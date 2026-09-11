-- =============================================================================
-- STUDENT VLE STANDARDIZED DATA-QUALITY WRITER
-- Databricks SQL / Delta Lake
--
-- Purpose:
--   1. Reuse the validated Bronze Student VLE diagnostics.
--   2. Reuse the validated Silver Student VLE diagnostics.
--   3. Reconcile Bronze to Silver row aggregation and total clicks.
--   4. Write one standardized result row per check.
--   5. Write one detail row per failed key.
--
-- Required objects:
--   open_university.oulad_bronze.student_vle_raw
--   open_university.oulad_bronze.vle_raw
--   open_university.oulad_silver.student_vle_clean
--   open_university.oulad_silver.vle_clean
--   open_university.oulad_quality.data_quality_results
--   open_university.oulad_quality.data_quality_failures
--
-- Safe retry:
--   Result and failure writes use MERGE with deterministic identifiers.
-- =============================================================================

USE CATALOG open_university;

DECLARE OR REPLACE VARIABLE dq_run_id STRING DEFAULT uuid();
DECLARE OR REPLACE VARIABLE dq_run_started_at TIMESTAMP DEFAULT current_timestamp();

-- Normalize raw placeholders only for comparison and validation. Bronze data is
-- not changed by this script.
CREATE OR REPLACE TEMP VIEW dq_sv_bronze AS
SELECT
    CASE WHEN UPPER(TRIM(CAST(code_module AS STRING))) IN ('', '?', 'NA', 'N/A', 'NULL')
        THEN NULL ELSE TRIM(CAST(code_module AS STRING)) END AS code_module,
    CASE WHEN UPPER(TRIM(CAST(code_presentation AS STRING))) IN ('', '?', 'NA', 'N/A', 'NULL')
        THEN NULL ELSE TRIM(CAST(code_presentation AS STRING)) END AS code_presentation,
    CASE WHEN UPPER(TRIM(CAST(id_student AS STRING))) IN ('', '?', 'NA', 'N/A', 'NULL')
        THEN NULL ELSE TRIM(CAST(id_student AS STRING)) END AS id_student,
    CASE WHEN UPPER(TRIM(CAST(id_site AS STRING))) IN ('', '?', 'NA', 'N/A', 'NULL')
        THEN NULL ELSE TRIM(CAST(id_site AS STRING)) END AS id_site,
    CASE WHEN UPPER(TRIM(CAST(date AS STRING))) IN ('', '?', 'NA', 'N/A', 'NULL')
        THEN NULL ELSE TRIM(CAST(date AS STRING)) END AS activity_date,
    CASE WHEN UPPER(TRIM(CAST(sum_click AS STRING))) IN ('', '?', 'NA', 'N/A', 'NULL')
        THEN NULL ELSE TRIM(CAST(sum_click AS STRING)) END AS sum_click
FROM open_university.oulad_bronze.student_vle_raw;

CREATE OR REPLACE TEMP VIEW dq_sv_bronze_vle_keys AS
SELECT DISTINCT
    CASE WHEN UPPER(TRIM(CAST(code_module AS STRING))) IN ('', '?', 'NA', 'N/A', 'NULL')
        THEN NULL ELSE TRIM(CAST(code_module AS STRING)) END AS code_module,
    CASE WHEN UPPER(TRIM(CAST(code_presentation AS STRING))) IN ('', '?', 'NA', 'N/A', 'NULL')
        THEN NULL ELSE TRIM(CAST(code_presentation AS STRING)) END AS code_presentation,
    CASE WHEN UPPER(TRIM(CAST(id_site AS STRING))) IN ('', '?', 'NA', 'N/A', 'NULL')
        THEN NULL ELSE TRIM(CAST(id_site AS STRING)) END AS id_site
FROM open_university.oulad_bronze.vle_raw;

CREATE OR REPLACE TEMP VIEW dq_sv_silver AS
SELECT
    code_module,
    code_presentation,
    id_student,
    id_site,
    date AS activity_date,
    sum_click
FROM open_university.oulad_silver.student_vle_clean;

CREATE OR REPLACE TEMP VIEW dq_sv_silver_vle_keys AS
SELECT DISTINCT
    code_module,
    code_presentation,
    id_site
FROM open_university.oulad_silver.vle_clean;

-- Diagnostic failure sets. These preserve the validated check logic and are
-- reused by both the summary and failure-detail writers.
CREATE OR REPLACE TEMP VIEW dq_sv_bronze_null_failures AS
SELECT DISTINCT *
FROM dq_sv_bronze
WHERE code_module IS NULL
   OR code_presentation IS NULL
   OR id_student IS NULL
   OR id_site IS NULL
   OR activity_date IS NULL;

CREATE OR REPLACE TEMP VIEW dq_sv_bronze_duplicate_keys AS
SELECT
    code_module,
    code_presentation,
    id_student,
    id_site,
    activity_date,
    COUNT(*) AS rows_per_key
FROM dq_sv_bronze
WHERE code_module IS NOT NULL
  AND code_presentation IS NOT NULL
  AND id_student IS NOT NULL
  AND id_site IS NOT NULL
  AND activity_date IS NOT NULL
GROUP BY code_module, code_presentation, id_student, id_site, activity_date
HAVING COUNT(*) > 1;

CREATE OR REPLACE TEMP VIEW dq_sv_bronze_range_failures AS
SELECT DISTINCT *
FROM dq_sv_bronze
WHERE TRY_CAST(sum_click AS BIGINT) IS NULL
   OR TRY_CAST(sum_click AS BIGINT) < 0;

CREATE OR REPLACE TEMP VIEW dq_sv_bronze_orphan_sites AS
SELECT
    s.code_module,
    s.code_presentation,
    s.id_site,
    COUNT(*) AS affected_rows
FROM dq_sv_bronze s
LEFT ANTI JOIN dq_sv_bronze_vle_keys v
    ON s.code_module = v.code_module
   AND s.code_presentation = v.code_presentation
   AND s.id_site = v.id_site
WHERE s.code_module IS NOT NULL
  AND s.code_presentation IS NOT NULL
  AND s.id_site IS NOT NULL
GROUP BY s.code_module, s.code_presentation, s.id_site;

CREATE OR REPLACE TEMP VIEW dq_sv_silver_null_failures AS
SELECT DISTINCT *
FROM dq_sv_silver
WHERE code_module IS NULL
   OR code_presentation IS NULL
   OR id_student IS NULL
   OR id_site IS NULL
   OR activity_date IS NULL;

CREATE OR REPLACE TEMP VIEW dq_sv_silver_duplicate_keys AS
SELECT
    code_module,
    code_presentation,
    id_student,
    id_site,
    activity_date,
    COUNT(*) AS rows_per_key
FROM dq_sv_silver
WHERE code_module IS NOT NULL
  AND code_presentation IS NOT NULL
  AND id_student IS NOT NULL
  AND id_site IS NOT NULL
  AND activity_date IS NOT NULL
GROUP BY code_module, code_presentation, id_student, id_site, activity_date
HAVING COUNT(*) > 1;

CREATE OR REPLACE TEMP VIEW dq_sv_silver_range_failures AS
SELECT DISTINCT *
FROM dq_sv_silver
WHERE sum_click IS NULL
   OR sum_click < 0;

CREATE OR REPLACE TEMP VIEW dq_sv_silver_orphan_sites AS
SELECT
    s.code_module,
    s.code_presentation,
    s.id_site,
    COUNT(*) AS affected_rows
FROM dq_sv_silver s
LEFT ANTI JOIN dq_sv_silver_vle_keys v
    ON s.code_module = v.code_module
   AND s.code_presentation = v.code_presentation
   AND s.id_site = v.id_site
WHERE s.code_module IS NOT NULL
  AND s.code_presentation IS NOT NULL
  AND s.id_site IS NOT NULL
GROUP BY s.code_module, s.code_presentation, s.id_site;

-- One unified result set: six Bronze checks, six Silver checks, and two
-- Bronze-to-Silver reconciliation checks.
CREATE OR REPLACE TEMP VIEW dq_student_vle_results AS
WITH stats AS (
    SELECT
        (SELECT COUNT(*) FROM dq_sv_bronze) AS bronze_rows,
        (SELECT COUNT(*) FROM dq_sv_silver) AS silver_rows,
        (SELECT COUNT(*) FROM dq_sv_bronze_null_failures) AS bronze_nulls,
        (SELECT COUNT(*) FROM dq_sv_bronze_duplicate_keys) AS bronze_duplicate_keys,
        (SELECT COALESCE(SUM(rows_per_key - 1), 0) FROM dq_sv_bronze_duplicate_keys)
            AS bronze_extra_rows,
        (SELECT COUNT(*) FROM dq_sv_bronze_range_failures) AS bronze_range_failures,
        (SELECT COUNT(*) FROM dq_sv_bronze_orphan_sites) AS bronze_orphan_sites,
        (SELECT COUNT(*) FROM dq_sv_silver_null_failures) AS silver_nulls,
        (SELECT COUNT(*) FROM dq_sv_silver_duplicate_keys) AS silver_duplicate_keys,
        (SELECT COUNT(*) FROM dq_sv_silver_range_failures) AS silver_range_failures,
        (SELECT COUNT(*) FROM dq_sv_silver_orphan_sites) AS silver_orphan_sites,
        (SELECT SUM(TRY_CAST(sum_click AS BIGINT)) FROM dq_sv_bronze) AS bronze_clicks,
        (SELECT SUM(sum_click) FROM dq_sv_silver) AS silver_clicks
),
raw_results AS (
    -- BRONZE: NULL
    SELECT
        'oulad_bronze' AS dataset_schema, 'student_vle_raw' AS dataset_table,
        'BRONZE' AS dataset_layer, 'bronze_student_vle_required_keys' AS check_id,
        'Student VLE required keys are complete' AS check_name, 'NULL' AS check_type,
        'Checks the five required Bronze Student VLE business-key columns' AS check_description,
        'No required business-key column should be missing' AS expectation,
        '=' AS threshold_operator, '0 failed rows' AS threshold_value,
        CASE WHEN bronze_nulls = 0 THEN 'PASS' ELSE 'FAIL' END AS status,
        'CRITICAL' AS severity, bronze_nulls > 0 AS stop_pipeline,
        '0 rows with missing required keys' AS expected_result,
        CONCAT(CAST(bronze_nulls AS STRING), ' rows have missing required keys') AS actual_result,
        bronze_rows AS total_count, bronze_nulls AS fail_count,
        CASE WHEN bronze_rows = 0 THEN CAST(NULL AS DECIMAL(9,6))
            ELSE CAST(100.0 * bronze_nulls / bronze_rows AS DECIMAL(9,6)) END AS fail_pct,
        CASE WHEN bronze_nulls = 0 THEN 'All Bronze Student VLE keys are complete'
            ELSE 'Bronze Student VLE contains missing required keys' END AS message,
        map('comparison_scope', 'INTERNAL') AS result_metadata
    FROM stats

    UNION ALL

    -- BRONZE: UNIQUE. Repeated raw daily keys are a warning because Silver is
    -- explicitly responsible for aggregating them; reconciliation is critical.
    SELECT
        'oulad_bronze', 'student_vle_raw', 'BRONZE',
        'bronze_student_vle_unique_business_key',
        'Student VLE repeated daily keys are identified', 'UNIQUE',
        'Finds repeated five-column daily interaction keys in the raw source',
        'Repeated keys may proceed only when Silver aggregates them without losing clicks',
        '=', '0 duplicated keys preferred',
        CASE WHEN bronze_duplicate_keys = 0 THEN 'PASS' ELSE 'WARN' END,
        'WARN', FALSE,
        '0 duplicated keys preferred; all duplicates must reconcile in Silver',
        CONCAT(CAST(bronze_duplicate_keys AS STRING), ' duplicated keys; ',
            CAST(bronze_extra_rows AS STRING), ' extra physical rows'),
        bronze_rows, bronze_duplicate_keys,
        CASE WHEN bronze_rows = 0 THEN CAST(NULL AS DECIMAL(9,6))
            ELSE CAST(100.0 * bronze_duplicate_keys / bronze_rows AS DECIMAL(9,6)) END,
        CASE WHEN bronze_duplicate_keys = 0 THEN 'No repeated Bronze daily keys found'
            ELSE 'Repeated Bronze daily keys require Silver aggregation' END,
        map('comparison_scope', 'INTERNAL', 'extra_duplicate_rows', CAST(bronze_extra_rows AS STRING))
    FROM stats

    UNION ALL

    -- BRONZE: RANGE
    SELECT
        'oulad_bronze', 'student_vle_raw', 'BRONZE',
        'bronze_student_vle_valid_sum_click', 'Student VLE clicks are valid', 'RANGE',
        'Checks that Bronze sum_click is numeric and nonnegative',
        'sum_click should be numeric and greater than or equal to zero',
        '>=', '0',
        CASE WHEN bronze_range_failures = 0 THEN 'PASS' ELSE 'FAIL' END,
        'FAIL', FALSE,
        '0 invalid sum_click rows',
        CONCAT(CAST(bronze_range_failures AS STRING), ' rows contain invalid sum_click values'),
        bronze_rows, bronze_range_failures,
        CASE WHEN bronze_rows = 0 THEN CAST(NULL AS DECIMAL(9,6))
            ELSE CAST(100.0 * bronze_range_failures / bronze_rows AS DECIMAL(9,6)) END,
        CASE WHEN bronze_range_failures = 0 THEN 'All Bronze click values are valid'
            ELSE 'Bronze contains invalid click values' END,
        map('comparison_scope', 'INTERNAL')
    FROM stats

    UNION ALL

    -- BRONZE: ACCEPTED_VALUES
    SELECT
        'oulad_bronze', 'student_vle_raw', 'BRONZE',
        'bronze_student_vle_accepted_values', 'Student VLE accepted values',
        'ACCEPTED_VALUES', 'Determines whether an accepted-values check applies',
        'No applicable categorical business field exists in Student VLE',
        'N/A', 'Not applicable', 'NOT_APPLICABLE', 'WARN', FALSE,
        'No applicable categorical field', 'No applicable categorical field',
        bronze_rows, CAST(0 AS BIGINT), CAST(NULL AS DECIMAL(9,6)),
        'Accepted-values check is not applicable to Bronze Student VLE',
        map('comparison_scope', 'INTERNAL')
    FROM stats

    UNION ALL

    -- BRONZE: REFERENTIAL_INTEGRITY
    SELECT
        'oulad_bronze', 'student_vle_raw', 'BRONZE',
        'bronze_student_vle_site_reference', 'Student VLE sites exist in VLE',
        'REFERENTIAL_INTEGRITY',
        'Checks each complete Bronze module-presentation-site key against Bronze VLE',
        'Every complete Student VLE site key should match a VLE record',
        '=', '0 orphaned site keys',
        CASE WHEN bronze_orphan_sites = 0 THEN 'PASS' ELSE 'FAIL' END,
        'CRITICAL', bronze_orphan_sites > 0,
        '0 orphaned site keys',
        CONCAT(CAST(bronze_orphan_sites AS STRING), ' site keys have no Bronze VLE match'),
        bronze_rows, bronze_orphan_sites,
        CASE WHEN bronze_rows = 0 THEN CAST(NULL AS DECIMAL(9,6))
            ELSE CAST(100.0 * bronze_orphan_sites / bronze_rows AS DECIMAL(9,6)) END,
        CASE WHEN bronze_orphan_sites = 0 THEN 'All Bronze site keys have a VLE parent'
            ELSE 'Bronze contains orphaned site keys' END,
        map('comparison_scope', 'INTERNAL', 'parent_dataset', 'open_university.oulad_bronze.vle_raw')
    FROM stats

    UNION ALL

    -- BRONZE: VOLUME
    SELECT
        'oulad_bronze', 'student_vle_raw', 'BRONZE',
        'bronze_student_vle_not_empty', 'Student VLE source was received', 'VOLUME',
        'Checks that the Bronze Student VLE source is not empty',
        'Bronze Student VLE should contain at least one row', '>', '0 rows',
        CASE WHEN bronze_rows > 0 THEN 'PASS' ELSE 'FAIL' END,
        'CRITICAL', bronze_rows = 0,
        'More than 0 rows', CONCAT('Bronze contains ', CAST(bronze_rows AS STRING), ' rows'),
        bronze_rows, CASE WHEN bronze_rows = 0 THEN CAST(1 AS BIGINT) ELSE CAST(0 AS BIGINT) END,
        CASE WHEN bronze_rows = 0 THEN CAST(100 AS DECIMAL(9,6)) ELSE CAST(0 AS DECIMAL(9,6)) END,
        CASE WHEN bronze_rows > 0 THEN 'Bronze Student VLE source was received'
            ELSE 'Bronze Student VLE is empty' END,
        map('comparison_scope', 'INTERNAL', 'volume_rule', 'NON_EMPTY_PILOT')
    FROM stats

    UNION ALL

    -- SILVER: NULL
    SELECT
        'oulad_silver', 'student_vle_clean', 'SILVER',
        'silver_student_vle_required_keys',
        'Silver Student VLE required keys are complete', 'NULL',
        'Checks the five required Silver Student VLE business-key columns',
        'No required business-key column should be NULL', '=', '0 failed rows',
        CASE WHEN silver_nulls = 0 THEN 'PASS' ELSE 'FAIL' END,
        'CRITICAL', silver_nulls > 0,
        '0 rows with missing required keys',
        CONCAT(CAST(silver_nulls AS STRING), ' rows have missing required keys'),
        silver_rows, silver_nulls,
        CASE WHEN silver_rows = 0 THEN CAST(NULL AS DECIMAL(9,6))
            ELSE CAST(100.0 * silver_nulls / silver_rows AS DECIMAL(9,6)) END,
        CASE WHEN silver_nulls = 0 THEN 'All Silver Student VLE keys are complete'
            ELSE 'Silver Student VLE contains missing required keys' END,
        map('comparison_scope', 'INTERNAL')
    FROM stats

    UNION ALL

    -- SILVER: UNIQUE
    SELECT
        'oulad_silver', 'student_vle_clean', 'SILVER',
        'silver_student_vle_unique_business_key',
        'Silver Student VLE daily business key is unique', 'UNIQUE',
        'Checks one Silver row per module, presentation, student, site, and date',
        'No repeated five-column daily interaction keys should remain', '=', '0 duplicated keys',
        CASE WHEN silver_duplicate_keys = 0 THEN 'PASS' ELSE 'FAIL' END,
        'CRITICAL', silver_duplicate_keys > 0,
        '0 duplicated keys',
        CONCAT(CAST(silver_duplicate_keys AS STRING), ' duplicated Silver keys'),
        silver_rows, silver_duplicate_keys,
        CASE WHEN silver_rows = 0 THEN CAST(NULL AS DECIMAL(9,6))
            ELSE CAST(100.0 * silver_duplicate_keys / silver_rows AS DECIMAL(9,6)) END,
        CASE WHEN silver_duplicate_keys = 0 THEN 'Silver has one row per daily business key'
            ELSE 'Duplicate daily keys remain in Silver' END,
        map('comparison_scope', 'INTERNAL')
    FROM stats

    UNION ALL

    -- SILVER: RANGE
    SELECT
        'oulad_silver', 'student_vle_clean', 'SILVER',
        'silver_student_vle_valid_clicks', 'Silver Student VLE clicks are valid', 'RANGE',
        'Checks that Silver sum_click is present and nonnegative',
        'sum_click should be greater than or equal to zero', '>=', '0',
        CASE WHEN silver_range_failures = 0 THEN 'PASS' ELSE 'FAIL' END,
        'FAIL', FALSE,
        '0 NULL or negative sum_click rows',
        CONCAT(CAST(silver_range_failures AS STRING), ' rows have invalid sum_click values'),
        silver_rows, silver_range_failures,
        CASE WHEN silver_rows = 0 THEN CAST(NULL AS DECIMAL(9,6))
            ELSE CAST(100.0 * silver_range_failures / silver_rows AS DECIMAL(9,6)) END,
        CASE WHEN silver_range_failures = 0 THEN 'All Silver click values are valid'
            ELSE 'Silver contains invalid click values' END,
        map('comparison_scope', 'INTERNAL')
    FROM stats

    UNION ALL

    -- SILVER: ACCEPTED_VALUES
    SELECT
        'oulad_silver', 'student_vle_clean', 'SILVER',
        'silver_student_vle_accepted_values', 'Silver Student VLE accepted values',
        'ACCEPTED_VALUES', 'Determines whether an accepted-values check applies',
        'No applicable categorical business field exists in Student VLE',
        'N/A', 'Not applicable', 'NOT_APPLICABLE', 'WARN', FALSE,
        'No applicable categorical field', 'No applicable categorical field',
        silver_rows, CAST(0 AS BIGINT), CAST(NULL AS DECIMAL(9,6)),
        'Accepted-values check is not applicable to Silver Student VLE',
        map('comparison_scope', 'INTERNAL')
    FROM stats

    UNION ALL

    -- SILVER: REFERENTIAL_INTEGRITY
    SELECT
        'oulad_silver', 'student_vle_clean', 'SILVER',
        'silver_student_vle_site_reference', 'Silver Student VLE sites exist in VLE',
        'REFERENTIAL_INTEGRITY',
        'Checks each complete Silver module-presentation-site key against Silver VLE',
        'Every complete Student VLE site key should match a Silver VLE record',
        '=', '0 orphaned site keys',
        CASE WHEN silver_orphan_sites = 0 THEN 'PASS' ELSE 'FAIL' END,
        'CRITICAL', silver_orphan_sites > 0,
        '0 orphaned site keys',
        CONCAT(CAST(silver_orphan_sites AS STRING), ' site keys have no Silver VLE match'),
        silver_rows, silver_orphan_sites,
        CASE WHEN silver_rows = 0 THEN CAST(NULL AS DECIMAL(9,6))
            ELSE CAST(100.0 * silver_orphan_sites / silver_rows AS DECIMAL(9,6)) END,
        CASE WHEN silver_orphan_sites = 0 THEN 'All Silver site keys have a VLE parent'
            ELSE 'Silver contains orphaned site keys' END,
        map('comparison_scope', 'INTERNAL', 'parent_dataset', 'open_university.oulad_silver.vle_clean')
    FROM stats

    UNION ALL

    -- SILVER: VOLUME
    SELECT
        'oulad_silver', 'student_vle_clean', 'SILVER',
        'silver_student_vle_not_empty', 'Silver Student VLE contains records', 'VOLUME',
        'Checks that the Silver Student VLE table is not empty',
        'Silver Student VLE should contain at least one row', '>', '0 rows',
        CASE WHEN silver_rows > 0 THEN 'PASS' ELSE 'FAIL' END,
        'CRITICAL', silver_rows = 0,
        'More than 0 rows', CONCAT('Silver contains ', CAST(silver_rows AS STRING), ' rows'),
        silver_rows, CASE WHEN silver_rows = 0 THEN CAST(1 AS BIGINT) ELSE CAST(0 AS BIGINT) END,
        CASE WHEN silver_rows = 0 THEN CAST(100 AS DECIMAL(9,6)) ELSE CAST(0 AS DECIMAL(9,6)) END,
        CASE WHEN silver_rows > 0 THEN 'Silver Student VLE contains records'
            ELSE 'Silver Student VLE is empty' END,
        map('comparison_scope', 'INTERNAL', 'volume_rule', 'NON_EMPTY_PILOT')
    FROM stats

    UNION ALL

    -- BRONZE -> SILVER: expected row reduction
    SELECT
        'oulad_silver', 'student_vle_clean', 'SILVER',
        'student_vle_bronze_silver_row_reconciliation',
        'Bronze duplicate aggregation reconciles to Silver rows', 'VOLUME',
        'Compares Silver row count with Bronze rows minus extra duplicate rows',
        'Silver rows should equal Bronze rows minus extra repeated-key rows',
        '=', '0 row difference',
        CASE WHEN silver_rows = bronze_rows - bronze_extra_rows THEN 'PASS' ELSE 'FAIL' END,
        'CRITICAL', silver_rows <> bronze_rows - bronze_extra_rows,
        CONCAT('Expected Silver rows: ', CAST(bronze_rows - bronze_extra_rows AS STRING)),
        CONCAT('Actual Silver rows: ', CAST(silver_rows AS STRING),
            '; difference: ', CAST(silver_rows - (bronze_rows - bronze_extra_rows) AS STRING)),
        CAST(1 AS BIGINT),
        CASE WHEN silver_rows = bronze_rows - bronze_extra_rows
            THEN CAST(0 AS BIGINT) ELSE CAST(1 AS BIGINT) END,
        CASE WHEN silver_rows = bronze_rows - bronze_extra_rows
            THEN CAST(0 AS DECIMAL(9,6)) ELSE CAST(100 AS DECIMAL(9,6)) END,
        CASE WHEN silver_rows = bronze_rows - bronze_extra_rows
            THEN 'Silver row reduction is fully explained by Bronze duplicate aggregation'
            ELSE 'Silver row count does not reconcile to Bronze duplicate aggregation' END,
        map(
            'comparison_scope', 'BRONZE_TO_SILVER',
            'source_dataset', 'open_university.oulad_bronze.student_vle_raw',
            'target_dataset', 'open_university.oulad_silver.student_vle_clean',
            'bronze_extra_rows', CAST(bronze_extra_rows AS STRING)
        )
    FROM stats

    UNION ALL

    -- BRONZE -> SILVER: click preservation
    SELECT
        'oulad_silver', 'student_vle_clean', 'SILVER',
        'student_vle_bronze_silver_click_reconciliation',
        'Bronze total clicks are preserved in Silver', 'VOLUME',
        'Compares typed Bronze total clicks with aggregated Silver total clicks',
        'Bronze and Silver total clicks should match exactly', '=', '0 click difference',
        CASE WHEN silver_clicks = bronze_clicks THEN 'PASS' ELSE 'FAIL' END,
        'CRITICAL', NOT (silver_clicks <=> bronze_clicks),
        CONCAT('Bronze total clicks: ', CAST(bronze_clicks AS STRING)),
        CONCAT('Silver total clicks: ', CAST(silver_clicks AS STRING),
            '; difference: ', CAST(silver_clicks - bronze_clicks AS STRING)),
        CAST(1 AS BIGINT),
        CASE WHEN silver_clicks <=> bronze_clicks THEN CAST(0 AS BIGINT) ELSE CAST(1 AS BIGINT) END,
        CASE WHEN silver_clicks <=> bronze_clicks
            THEN CAST(0 AS DECIMAL(9,6)) ELSE CAST(100 AS DECIMAL(9,6)) END,
        CASE WHEN silver_clicks <=> bronze_clicks
            THEN 'All Bronze clicks are preserved in Silver'
            ELSE 'Bronze and Silver total clicks do not match' END,
        map(
            'comparison_scope', 'BRONZE_TO_SILVER',
            'source_dataset', 'open_university.oulad_bronze.student_vle_raw',
            'target_dataset', 'open_university.oulad_silver.student_vle_clean'
        )
    FROM stats
)
SELECT
    SHA2(CONCAT_WS('||', dq_run_id, dataset_schema, dataset_table, check_id), 256)
        AS check_result_id,
    dq_run_id AS run_id,
    dq_run_started_at AS run_started_at,
    CAST(NULL AS TIMESTAMP) AS run_completed_at,
    current_timestamp() AS executed_at,
    'open_university' AS dataset_catalog,
    dataset_schema,
    dataset_table,
    dataset_layer,
    check_id,
    check_name,
    check_type,
    check_description,
    expectation,
    threshold_operator,
    threshold_value,
    status,
    severity,
    stop_pipeline,
    'Data Engineering' AS check_owner,
    expected_result,
    actual_result,
    total_count,
    fail_count,
    fail_pct,
    message,
    'tests/02_clean_checks/07_student_vle_standardized_results.sql' AS query_reference,
    result_metadata
FROM raw_results;

-- Idempotent result write for this run.
MERGE INTO open_university.oulad_quality.data_quality_results AS target
USING dq_student_vle_results AS source
ON target.run_id = source.run_id
AND target.dataset_catalog = source.dataset_catalog
AND target.dataset_schema = source.dataset_schema
AND target.dataset_table = source.dataset_table
AND target.check_id = source.check_id
WHEN MATCHED THEN UPDATE SET *
WHEN NOT MATCHED THEN INSERT *;

-- Standardized failure detail. Volume/reconciliation failures use a synthetic
-- dataset-level key because no individual source record represents the breach.
CREATE OR REPLACE TEMP VIEW dq_student_vle_failures AS
WITH raw_failures AS (
    SELECT
        'oulad_bronze' AS dataset_schema, 'student_vle_raw' AS dataset_table,
        'BRONZE' AS dataset_layer, 'bronze_student_vle_required_keys' AS check_id,
        'NULL' AS check_type, 'CRITICAL' AS severity,
        TO_JSON(NAMED_STRUCT(
            'code_module', code_module, 'code_presentation', code_presentation,
            'id_student', id_student, 'id_site', id_site, 'date', activity_date
        ), MAP('ignoreNullFields', 'false')) AS failed_key,
        TO_JSON(NAMED_STRUCT(
            'code_module', code_module, 'code_presentation', code_presentation,
            'id_student', id_student, 'id_site', id_site, 'date', activity_date,
            'sum_click', sum_click
        ), MAP('ignoreNullFields', 'false')) AS failed_record_json,
        'business_key' AS failed_column, 'All five key fields populated' AS expected_value,
        'One or more key fields missing' AS actual_value,
        'Bronze Student VLE required business key is incomplete' AS failure_message,
        map('comparison_scope', 'INTERNAL') AS failure_metadata
    FROM dq_sv_bronze_null_failures

    UNION ALL

    SELECT
        'oulad_bronze', 'student_vle_raw', 'BRONZE',
        'bronze_student_vle_unique_business_key', 'UNIQUE', 'WARN',
        TO_JSON(NAMED_STRUCT(
            'code_module', code_module, 'code_presentation', code_presentation,
            'id_student', id_student, 'id_site', id_site, 'date', activity_date
        )),
        CAST(NULL AS STRING), 'business_key', 'One row preferred',
        CONCAT(CAST(rows_per_key AS STRING), ' rows'),
        'Repeated Bronze daily key requires Silver aggregation',
        map('comparison_scope', 'INTERNAL', 'duplicate_count', CAST(rows_per_key AS STRING))
    FROM dq_sv_bronze_duplicate_keys

    UNION ALL

    SELECT
        'oulad_bronze', 'student_vle_raw', 'BRONZE',
        'bronze_student_vle_valid_sum_click', 'RANGE', 'FAIL',
        TO_JSON(NAMED_STRUCT(
            'code_module', code_module, 'code_presentation', code_presentation,
            'id_student', id_student, 'id_site', id_site, 'date', activity_date
        ), MAP('ignoreNullFields', 'false')),
        TO_JSON(NAMED_STRUCT('sum_click', sum_click), MAP('ignoreNullFields', 'false')),
        'sum_click', 'Numeric value >= 0', COALESCE(sum_click, 'NULL'),
        'Bronze sum_click is NULL, nonnumeric, or negative',
        map('comparison_scope', 'INTERNAL')
    FROM dq_sv_bronze_range_failures

    UNION ALL

    SELECT
        'oulad_bronze', 'student_vle_raw', 'BRONZE',
        'bronze_student_vle_site_reference', 'REFERENTIAL_INTEGRITY', 'CRITICAL',
        TO_JSON(NAMED_STRUCT(
            'code_module', code_module, 'code_presentation', code_presentation,
            'id_site', id_site
        )),
        CAST(NULL AS STRING), 'business_key', 'Matching key in Bronze VLE',
        'No matching Bronze VLE key', 'Bronze Student VLE site key is orphaned',
        map('comparison_scope', 'INTERNAL', 'affected_rows', CAST(affected_rows AS STRING))
    FROM dq_sv_bronze_orphan_sites

    UNION ALL

    SELECT
        'oulad_silver', 'student_vle_clean', 'SILVER',
        'silver_student_vle_required_keys', 'NULL', 'CRITICAL',
        TO_JSON(NAMED_STRUCT(
            'code_module', code_module, 'code_presentation', code_presentation,
            'id_student', id_student, 'id_site', id_site, 'date', activity_date
        ), MAP('ignoreNullFields', 'false')),
        TO_JSON(NAMED_STRUCT('sum_click', sum_click), MAP('ignoreNullFields', 'false')),
        'business_key', 'All five key fields populated', 'One or more key fields missing',
        'Silver Student VLE required business key is incomplete',
        map('comparison_scope', 'INTERNAL')
    FROM dq_sv_silver_null_failures

    UNION ALL

    SELECT
        'oulad_silver', 'student_vle_clean', 'SILVER',
        'silver_student_vle_unique_business_key', 'UNIQUE', 'CRITICAL',
        TO_JSON(NAMED_STRUCT(
            'code_module', code_module, 'code_presentation', code_presentation,
            'id_student', id_student, 'id_site', id_site, 'date', activity_date
        )),
        CAST(NULL AS STRING), 'business_key', 'Exactly one Silver row',
        CONCAT(CAST(rows_per_key AS STRING), ' rows'),
        'Duplicate daily business key remains in Silver',
        map('comparison_scope', 'INTERNAL', 'duplicate_count', CAST(rows_per_key AS STRING))
    FROM dq_sv_silver_duplicate_keys

    UNION ALL

    SELECT
        'oulad_silver', 'student_vle_clean', 'SILVER',
        'silver_student_vle_valid_clicks', 'RANGE', 'FAIL',
        TO_JSON(NAMED_STRUCT(
            'code_module', code_module, 'code_presentation', code_presentation,
            'id_student', id_student, 'id_site', id_site, 'date', activity_date
        ), MAP('ignoreNullFields', 'false')),
        TO_JSON(NAMED_STRUCT('sum_click', sum_click), MAP('ignoreNullFields', 'false')),
        'sum_click', 'Value >= 0', COALESCE(CAST(sum_click AS STRING), 'NULL'),
        'Silver sum_click is NULL or negative', map('comparison_scope', 'INTERNAL')
    FROM dq_sv_silver_range_failures

    UNION ALL

    SELECT
        'oulad_silver', 'student_vle_clean', 'SILVER',
        'silver_student_vle_site_reference', 'REFERENTIAL_INTEGRITY', 'CRITICAL',
        TO_JSON(NAMED_STRUCT(
            'code_module', code_module, 'code_presentation', code_presentation,
            'id_site', id_site
        )),
        CAST(NULL AS STRING), 'business_key', 'Matching key in Silver VLE',
        'No matching Silver VLE key', 'Silver Student VLE site key is orphaned',
        map('comparison_scope', 'INTERNAL', 'affected_rows', CAST(affected_rows AS STRING))
    FROM dq_sv_silver_orphan_sites

    UNION ALL

    SELECT
        'oulad_silver', 'student_vle_clean', 'SILVER',
        'student_vle_bronze_silver_row_reconciliation', 'VOLUME', 'CRITICAL',
        '__DATASET_TOTAL__', CAST(NULL AS STRING), 'row_count',
        expected_result, actual_result,
        'Bronze-to-Silver row aggregation does not reconcile',
        map('comparison_scope', 'BRONZE_TO_SILVER')
    FROM dq_student_vle_results
    WHERE check_id = 'student_vle_bronze_silver_row_reconciliation'
      AND status = 'FAIL'

    UNION ALL

    SELECT
        'oulad_silver', 'student_vle_clean', 'SILVER',
        'student_vle_bronze_silver_click_reconciliation', 'VOLUME', 'CRITICAL',
        '__DATASET_TOTAL__', CAST(NULL AS STRING), 'sum_click',
        expected_result, actual_result,
        'Bronze-to-Silver click totals do not reconcile',
        map('comparison_scope', 'BRONZE_TO_SILVER')
    FROM dq_student_vle_results
    WHERE check_id = 'student_vle_bronze_silver_click_reconciliation'
      AND status = 'FAIL'
),
identified AS (
    SELECT
        SHA2(CONCAT_WS('||', dq_run_id, dataset_schema, dataset_table, check_id, failed_key), 256)
            AS failure_id,
        SHA2(CONCAT_WS('||', dq_run_id, dataset_schema, dataset_table, check_id), 256)
            AS check_result_id,
        dq_run_id AS run_id,
        current_timestamp() AS detected_at,
        'open_university' AS dataset_catalog,
        dataset_schema,
        dataset_table,
        dataset_layer,
        check_id,
        check_type,
        severity,
        failed_key,
        failed_record_json,
        failed_column,
        expected_value,
        actual_value,
        failure_message,
        failure_metadata
    FROM raw_failures
)
SELECT * FROM identified;

-- Idempotent failure-detail write for this run.
MERGE INTO open_university.oulad_quality.data_quality_failures AS target
USING dq_student_vle_failures AS source
ON target.failure_id = source.failure_id
WHEN MATCHED THEN UPDATE SET *
WHEN NOT MATCHED THEN INSERT *;

-- Publish the run only after both result and failure writes succeed.
UPDATE open_university.oulad_quality.data_quality_results
SET run_completed_at = current_timestamp()
WHERE run_id = dq_run_id
  AND run_completed_at IS NULL;

-- Final check-level output. Expected: 14 rows.
SELECT
    run_id,
    dataset_layer,
    dataset_table,
    check_type,
    check_id,
    status,
    severity,
    stop_pipeline,
    total_count,
    fail_count,
    fail_pct,
    actual_result,
    run_completed_at
FROM open_university.oulad_quality.data_quality_results
WHERE run_id = dq_run_id
ORDER BY dataset_layer, dataset_table, check_type, check_id;

-- Final failure-level output. With the validated OULAD data, the expected rows
-- are the known repeated Bronze daily keys classified as WARN.
SELECT
    run_id,
    dataset_layer,
    dataset_table,
    check_type,
    check_id,
    severity,
    failed_key,
    actual_value,
    failure_message
FROM open_university.oulad_quality.data_quality_failures
WHERE run_id = dq_run_id
ORDER BY dataset_layer, dataset_table, check_type, failed_key
LIMIT 100;
