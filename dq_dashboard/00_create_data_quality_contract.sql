-- =============================================================================
-- OULAD DATA QUALITY RESULT CONTRACT
-- Databricks SQL / Delta Lake
-- Suggested branch: feature/data-quality-results
--
-- Purpose:
--   1. Store one result for every check executed in a run.
--   2. Store the failed rows or failed business keys behind those results.
--   3. Supply dashboard-ready views for Overview -> Dataset -> Check -> Failure.
--
-- Safe to rerun:
--   CREATE SCHEMA/TABLE IF NOT EXISTS and CREATE OR REPLACE VIEW are idempotent.
-- =============================================================================

USE CATALOG open_university;

CREATE SCHEMA IF NOT EXISTS oulad_dq
COMMENT 'Shared data-quality results, failed records, and dashboard views for all OULAD layers';

-- One row per dataset check per execution run.
CREATE TABLE IF NOT EXISTS oulad_dq.data_quality_results (
    check_result_id       STRING            NOT NULL COMMENT 'Unique result identifier, normally uuid()',
    run_id                STRING            NOT NULL COMMENT 'Shared identifier for every check in one pipeline or test run',
    run_started_at        TIMESTAMP         NOT NULL COMMENT 'UTC timestamp when the data-quality run started',
    run_completed_at      TIMESTAMP                  COMMENT 'UTC timestamp when the data-quality run completed; NULL while running',
    executed_at           TIMESTAMP         NOT NULL COMMENT 'UTC timestamp when this individual check executed',

    dataset_catalog       STRING            NOT NULL COMMENT 'Catalog containing the checked dataset, for example open_university',
    dataset_schema        STRING            NOT NULL COMMENT 'Schema containing the checked dataset, for example oulad_silver',
    dataset_table         STRING            NOT NULL COMMENT 'Table or view checked, for example student_vle_clean',
    dataset_layer         STRING            NOT NULL COMMENT 'Pipeline layer: BRONZE, SILVER, GOLD, or OTHER',

    check_id              STRING            NOT NULL COMMENT 'Stable machine-readable check identifier',
    check_name            STRING            NOT NULL COMMENT 'Short dashboard label describing what is checked',
    check_type            STRING            NOT NULL COMMENT 'NULL, UNIQUE, RANGE, ACCEPTED_VALUES, REFERENTIAL_INTEGRITY, or VOLUME',
    check_description     STRING            NOT NULL COMMENT 'WHAT: plain-language definition of the check',
    expectation           STRING            NOT NULL COMMENT 'EXPECTATION: the acceptable outcome',
    threshold_operator    STRING            NOT NULL COMMENT 'Comparison operator such as =, <=, <, >=, >, BETWEEN, or IN',
    threshold_value       STRING            NOT NULL COMMENT 'THRESHOLD represented as text so counts, percentages, ranges, and sets are supported',

    status                STRING            NOT NULL COMMENT 'PASS, WARN, FAIL, or NOT_APPLICABLE',
    severity              STRING            NOT NULL COMMENT 'WARN, FAIL, or CRITICAL; action to take when the expectation is breached',
    stop_pipeline         BOOLEAN           NOT NULL COMMENT 'True only when status is FAIL and severity is CRITICAL',
    check_owner           STRING            NOT NULL COMMENT 'Person or team responsible for investigation',

    expected_result       STRING            NOT NULL COMMENT 'Human-readable expected result',
    actual_result         STRING            NOT NULL COMMENT 'Human-readable observed result',
    total_count           BIGINT                     COMMENT 'Number of evaluated records; NULL only for non-row-based checks',
    fail_count            BIGINT            NOT NULL COMMENT 'Number of failed records or keys; use 0 for PASS and NOT_APPLICABLE',
    fail_pct              DECIMAL(9,6)               COMMENT 'Failure percentage from 0 to 100; NULL when no denominator exists',
    message               STRING            NOT NULL COMMENT 'Short result explanation suitable for the dashboard',
    query_reference       STRING                     COMMENT 'SQL file, dbt test, notebook, or job that produced the result',
    result_metadata       MAP<STRING, STRING>         COMMENT 'Optional extensible metadata without changing the contract'
)
USING DELTA
COMMENT 'One row per data-quality check per run across every OULAD dataset'
TBLPROPERTIES (
    'delta.enableChangeDataFeed' = 'true',
    'quality' = 'gold'
);

-- One row per failed source record or failed business key.
CREATE TABLE IF NOT EXISTS oulad_dq.data_quality_failures (
    failure_id            STRING            NOT NULL COMMENT 'Unique failure identifier, normally uuid()',
    check_result_id       STRING            NOT NULL COMMENT 'Links to data_quality_results.check_result_id',
    run_id                STRING            NOT NULL COMMENT 'Links the failure to its data-quality run',
    detected_at           TIMESTAMP         NOT NULL COMMENT 'UTC timestamp when the failure was captured',

    dataset_catalog       STRING            NOT NULL COMMENT 'Catalog containing the failed dataset',
    dataset_schema        STRING            NOT NULL COMMENT 'Schema containing the failed dataset',
    dataset_table         STRING            NOT NULL COMMENT 'Table or view containing the failure',
    dataset_layer         STRING            NOT NULL COMMENT 'Pipeline layer: BRONZE, SILVER, GOLD, or OTHER',

    check_id              STRING            NOT NULL COMMENT 'Stable check identifier matching the parent result',
    check_type            STRING            NOT NULL COMMENT 'One of the six standard check categories',
    severity              STRING            NOT NULL COMMENT 'WARN, FAIL, or CRITICAL copied from the parent result',
    failed_key            STRING            NOT NULL COMMENT 'Readable business key; use a deterministic JSON object for composite keys',
    failed_record_json    STRING                     COMMENT 'Complete failed row serialized with to_json(named_struct(...)) when allowed',
    failed_column         STRING                     COMMENT 'Column that failed; NULL for row, key, relationship, or volume failures',
    expected_value        STRING                     COMMENT 'Expected value, range, set, relationship, or condition',
    actual_value          STRING                     COMMENT 'Observed failing value',
    failure_message       STRING            NOT NULL COMMENT 'Plain-language explanation of this failed row or key',
    failure_metadata      MAP<STRING, STRING>         COMMENT 'Optional source location, parent key, batch, or other drill-down fields'
)
USING DELTA
COMMENT 'Failed records and failed keys supporting check-level dashboard drill-down'
TBLPROPERTIES (
    'delta.enableChangeDataFeed' = 'true',
    'quality' = 'gold'
);

-- Latest completed run. If the latest run is still active, it becomes visible
-- only after run_completed_at is populated for its result rows.
CREATE OR REPLACE VIEW oulad_dq.vw_dq_latest_run_results
COMMENT 'All check results from the most recently completed data-quality run'
AS
WITH completed_runs AS (
    SELECT
        run_id,
        MAX(run_completed_at) AS completed_at
    FROM oulad_dq.data_quality_results
    WHERE run_completed_at IS NOT NULL
    GROUP BY run_id
),
latest_run AS (
    SELECT run_id
    FROM completed_runs
    QUALIFY ROW_NUMBER() OVER (ORDER BY completed_at DESC, run_id DESC) = 1
)
SELECT r.*
FROM oulad_dq.data_quality_results r
INNER JOIN latest_run l
    ON r.run_id = l.run_id;

-- Dashboard landing page: answers health, pass rate, failures, stop decision,
-- affected datasets, and recency in one row.
CREATE OR REPLACE VIEW oulad_dq.vw_dq_dashboard_overview
COMMENT 'Single-row summary for the latest completed run'
AS
SELECT
    MAX(run_id) AS run_id,
    CASE
        WHEN COUNT_IF(status = 'FAIL') > 0 THEN 'FAIL'
        WHEN COUNT_IF(status = 'WARN') > 0 THEN 'WARN'
        WHEN COUNT_IF(status <> 'NOT_APPLICABLE') = 0 THEN 'WARN'
        ELSE 'PASS'
    END AS overall_health,
    COUNT_IF(status = 'PASS') AS checks_passed,
    COUNT_IF(status <> 'NOT_APPLICABLE') AS applicable_checks,
    ROUND(
        100.0 * COUNT_IF(status = 'PASS')
        / NULLIF(COUNT_IF(status <> 'NOT_APPLICABLE'), 0),
        2
    ) AS pass_rate_pct,
    COUNT_IF(status = 'WARN') AS warning_checks,
    COUNT_IF(status = 'FAIL') AS failed_checks,
    COUNT_IF(stop_pipeline) AS critical_failures,
    COUNT(DISTINCT CASE
        WHEN status IN ('WARN', 'FAIL')
        THEN CONCAT_WS('.', dataset_catalog, dataset_schema, dataset_table)
    END) AS datasets_affected,
    MAX(run_completed_at) AS last_checked,
    COUNT_IF(stop_pipeline) > 0 AS stop_pipeline
FROM oulad_dq.vw_dq_latest_run_results;

-- Dataset level: click from the overview into the affected table.
CREATE OR REPLACE VIEW oulad_dq.vw_dq_dataset_health
COMMENT 'Latest-run health and pass rate by dataset'
AS
SELECT
    run_id,
    dataset_catalog,
    dataset_schema,
    dataset_table,
    dataset_layer,
    CASE
        WHEN COUNT_IF(status = 'FAIL') > 0 THEN 'FAIL'
        WHEN COUNT_IF(status = 'WARN') > 0 THEN 'WARN'
        WHEN COUNT_IF(status <> 'NOT_APPLICABLE') = 0 THEN 'WARN'
        ELSE 'PASS'
    END AS dataset_health,
    COUNT_IF(status = 'PASS') AS checks_passed,
    COUNT_IF(status <> 'NOT_APPLICABLE') AS applicable_checks,
    ROUND(
        100.0 * COUNT_IF(status = 'PASS')
        / NULLIF(COUNT_IF(status <> 'NOT_APPLICABLE'), 0),
        2
    ) AS pass_rate_pct,
    COUNT_IF(status = 'WARN') AS warning_checks,
    COUNT_IF(status = 'FAIL') AS failed_checks,
    COUNT_IF(stop_pipeline) AS critical_failures,
    MAX(executed_at) AS last_checked,
    COUNT_IF(stop_pipeline) > 0 AS stop_pipeline
FROM oulad_dq.vw_dq_latest_run_results
GROUP BY
    run_id,
    dataset_catalog,
    dataset_schema,
    dataset_table,
    dataset_layer;

-- Check level: shows exactly what is broken and the associated rule.
CREATE OR REPLACE VIEW oulad_dq.vw_dq_problem_checks
COMMENT 'Latest-run WARN and FAIL checks for check-level drill-down'
AS
SELECT
    check_result_id,
    run_id,
    executed_at,
    run_completed_at,
    dataset_catalog,
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
    check_owner,
    expected_result,
    actual_result,
    total_count,
    fail_count,
    fail_pct,
    message,
    query_reference
FROM oulad_dq.vw_dq_latest_run_results
WHERE status IN ('WARN', 'FAIL');

-- Failure level: actual failed rows/keys linked to their check.
CREATE OR REPLACE VIEW oulad_dq.vw_dq_failure_detail
COMMENT 'Latest-run failed rows and failed keys for final dashboard drill-down'
AS
SELECT
    r.run_id,
    r.check_result_id,
    r.check_id,
    r.check_name,
    r.check_type,
    r.status,
    r.severity,
    r.stop_pipeline,
    r.check_owner,
    r.dataset_catalog,
    r.dataset_schema,
    r.dataset_table,
    r.dataset_layer,
    f.failure_id,
    f.detected_at,
    f.failed_key,
    f.failed_column,
    f.expected_value,
    f.actual_value,
    f.failure_message,
    f.failed_record_json,
    f.failure_metadata
FROM oulad_dq.vw_dq_latest_run_results r
INNER JOIN oulad_dq.data_quality_failures f
    ON r.check_result_id = f.check_result_id
    AND r.run_id = f.run_id
WHERE r.status IN ('WARN', 'FAIL');

-- Historical trend source: supports "when did it start?", "is it getting
-- worse?", and "which dataset fails most often?" without discarding history.
CREATE OR REPLACE VIEW oulad_dq.vw_dq_history
COMMENT 'Historical check results with dashboard-friendly dataset name'
AS
SELECT
    *,
    CONCAT_WS('.', dataset_catalog, dataset_schema, dataset_table) AS dataset
FROM oulad_dq.data_quality_results;

