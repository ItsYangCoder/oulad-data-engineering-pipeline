-- =============================================================================
-- OULAD MASTER STANDARDIZED DATA-QUALITY RESULTS WRITER
-- Databricks SQL / Delta Lake
--
-- Covers all seven OULAD datasets in Bronze and Silver:
--   courses, assessment, student_assessment, student_info,
--   student_registration, vle, student_vle
--
-- Contract targets:
--   open_university.oulad_quality.data_quality_results
--   open_university.oulad_quality.data_quality_failures
--
-- Design:
--   * one shared run_id for the full execution
--   * all check result sets standardized through UNION ALL
--   * Pass / Review / Warn / Fail normalized to PASS / WARN / FAIL
--   * severity + threshold + stop_pipeline stored centrally
--   * actual failed rows / keys written for drill-down
--   * deterministic IDs + MERGE make retries idempotent for the same run_id
--
-- Known OULAD exceptions intentionally preserved:
--   * 45 missing student_registration.date_registration values => WARN
--   * Bronze student_vle repeated daily keys => WARN (Silver aggregates them)
--   * NULL student_assessment.score values are valid and are not failures
--   * negative relative dates are valid and are not rejected by range checks
-- =============================================================================

USE CATALOG open_university;

DECLARE OR REPLACE VARIABLE dq_run_id STRING DEFAULT uuid();
DECLARE OR REPLACE VARIABLE dq_run_started_at TIMESTAMP DEFAULT current_timestamp();

-- =============================================================================
-- 1. STANDARDIZED CHECK RESULTS
-- =============================================================================

CREATE OR REPLACE TEMP VIEW dq_master_standardized_results AS
WITH metrics AS (
    SELECT
        -- ---------------------------------------------------------------------
        -- BRONZE row counts
        -- ---------------------------------------------------------------------
        (SELECT COUNT(*) FROM open_university.oulad_bronze.courses_raw) AS b_courses_rows,
        (SELECT COUNT(*) FROM open_university.oulad_bronze.assessment_raw) AS b_assessment_rows,
        (SELECT COUNT(*) FROM open_university.oulad_bronze.student_assessment_raw) AS b_student_assessment_rows,
        (SELECT COUNT(*) FROM open_university.oulad_bronze.student_info_raw) AS b_student_info_rows,
        (SELECT COUNT(*) FROM open_university.oulad_bronze.student_registration_raw) AS b_student_registration_rows,
        (SELECT COUNT(*) FROM open_university.oulad_bronze.vle_raw) AS b_vle_rows,
        (SELECT COUNT(*) FROM open_university.oulad_bronze.student_vle_raw) AS b_student_vle_rows,

        -- SILVER row counts
        (SELECT COUNT(*) FROM open_university.oulad_silver.courses_clean) AS s_courses_rows,
        (SELECT COUNT(*) FROM open_university.oulad_silver.assessment_clean) AS s_assessment_rows,
        (SELECT COUNT(*) FROM open_university.oulad_silver.student_assessment_clean) AS s_student_assessment_rows,
        (SELECT COUNT(*) FROM open_university.oulad_silver.student_info_clean) AS s_student_info_rows,
        (SELECT COUNT(*) FROM open_university.oulad_silver.student_registration_clean) AS s_student_registration_rows,
        (SELECT COUNT(*) FROM open_university.oulad_silver.vle_clean) AS s_vle_rows,
        (SELECT COUNT(*) FROM open_university.oulad_silver.student_vle_clean) AS s_student_vle_rows,

        -- ---------------------------------------------------------------------
        -- BRONZE key/null checks
        -- ---------------------------------------------------------------------
        (SELECT COUNT(*) FROM open_university.oulad_bronze.courses_raw
         WHERE code_module IS NULL OR TRIM(CAST(code_module AS STRING)) IN ('', '?', 'NA', 'N/A', 'NULL')
            OR code_presentation IS NULL OR TRIM(CAST(code_presentation AS STRING)) IN ('', '?', 'NA', 'N/A', 'NULL')) AS b_courses_null_keys,

        (SELECT COUNT(*) FROM open_university.oulad_bronze.assessment_raw
         WHERE id_assessment IS NULL OR TRY_CAST(id_assessment AS BIGINT) IS NULL
            OR code_module IS NULL OR TRIM(CAST(code_module AS STRING)) IN ('', '?', 'NA', 'N/A', 'NULL')
            OR code_presentation IS NULL OR TRIM(CAST(code_presentation AS STRING)) IN ('', '?', 'NA', 'N/A', 'NULL')
            OR assessment_type IS NULL OR TRIM(CAST(assessment_type AS STRING)) IN ('', '?', 'NA', 'N/A', 'NULL')) AS b_assessment_null_keys,

        (SELECT COUNT(*) FROM open_university.oulad_bronze.student_assessment_raw
         WHERE TRY_CAST(id_assessment AS BIGINT) IS NULL
            OR TRY_CAST(id_student AS BIGINT) IS NULL
            OR TRY_CAST(date_submitted AS INT) IS NULL
            OR TRY_CAST(is_banked AS INT) IS NULL) AS b_student_assessment_required_nulls,

        (SELECT COUNT(*) FROM open_university.oulad_bronze.student_info_raw
         WHERE code_module IS NULL OR TRIM(CAST(code_module AS STRING)) IN ('', '?', 'NA', 'N/A', 'NULL')
            OR code_presentation IS NULL OR TRIM(CAST(code_presentation AS STRING)) IN ('', '?', 'NA', 'N/A', 'NULL')
            OR TRY_CAST(id_student AS BIGINT) IS NULL) AS b_student_info_null_keys,

        (SELECT COUNT(*) FROM open_university.oulad_bronze.student_registration_raw
         WHERE code_module IS NULL OR TRIM(CAST(code_module AS STRING)) IN ('', '?', 'NA', 'N/A', 'NULL')
            OR code_presentation IS NULL OR TRIM(CAST(code_presentation AS STRING)) IN ('', '?', 'NA', 'N/A', 'NULL')
            OR TRY_CAST(id_student AS BIGINT) IS NULL) AS b_student_registration_null_keys,

        (SELECT COUNT(*) FROM open_university.oulad_bronze.vle_raw
         WHERE code_module IS NULL OR TRIM(CAST(code_module AS STRING)) IN ('', '?', 'NA', 'N/A', 'NULL')
            OR code_presentation IS NULL OR TRIM(CAST(code_presentation AS STRING)) IN ('', '?', 'NA', 'N/A', 'NULL')
            OR TRY_CAST(id_site AS BIGINT) IS NULL) AS b_vle_null_keys,

        (SELECT COUNT(*) FROM open_university.oulad_bronze.student_vle_raw
         WHERE code_module IS NULL OR TRIM(CAST(code_module AS STRING)) IN ('', '?', 'NA', 'N/A', 'NULL')
            OR code_presentation IS NULL OR TRIM(CAST(code_presentation AS STRING)) IN ('', '?', 'NA', 'N/A', 'NULL')
            OR TRY_CAST(id_student AS BIGINT) IS NULL
            OR TRY_CAST(id_site AS BIGINT) IS NULL
            OR TRY_CAST(date AS INT) IS NULL) AS b_student_vle_null_keys,

        -- ---------------------------------------------------------------------
        -- SILVER key/null checks
        -- ---------------------------------------------------------------------
        (SELECT COUNT(*) FROM open_university.oulad_silver.courses_clean
         WHERE code_module IS NULL OR code_presentation IS NULL) AS s_courses_null_keys,

        (SELECT COUNT(*) FROM open_university.oulad_silver.assessment_clean
         WHERE id_assessment IS NULL OR code_module IS NULL OR code_presentation IS NULL
            OR assessment_type IS NULL OR clean_load_timestamp IS NULL OR clean_load_date IS NULL) AS s_assessment_required_nulls,

        (SELECT COUNT(*) FROM open_university.oulad_silver.student_assessment_clean
         WHERE id_assessment IS NULL OR id_student IS NULL
            OR clean_load_timestamp IS NULL OR clean_load_date IS NULL) AS s_student_assessment_required_nulls,

        (SELECT COUNT(*) FROM open_university.oulad_silver.student_info_clean
         WHERE code_module IS NULL OR code_presentation IS NULL OR id_student IS NULL
            OR clean_load_timestamp IS NULL OR clean_load_date IS NULL) AS s_student_info_required_nulls,

        (SELECT COUNT(*) FROM open_university.oulad_silver.student_registration_clean
         WHERE code_module IS NULL OR code_presentation IS NULL OR id_student IS NULL
            OR clean_load_timestamp IS NULL OR clean_load_date IS NULL) AS s_student_registration_required_nulls,

        (SELECT COUNT(*) FROM open_university.oulad_silver.vle_clean
         WHERE code_module IS NULL OR code_presentation IS NULL OR id_site IS NULL
            OR clean_load_timestamp IS NULL OR clean_load_date IS NULL) AS s_vle_required_nulls,

        (SELECT COUNT(*) FROM open_university.oulad_silver.student_vle_clean
         WHERE code_module IS NULL OR code_presentation IS NULL OR id_student IS NULL
            OR id_site IS NULL OR date IS NULL OR sum_click IS NULL
            OR clean_load_timestamp IS NULL OR clean_load_date IS NULL) AS s_student_vle_required_nulls,

        -- ---------------------------------------------------------------------
        -- Duplicate business keys
        -- ---------------------------------------------------------------------
        (SELECT COUNT(*) FROM (
            SELECT code_module, code_presentation
            FROM open_university.oulad_bronze.courses_raw
            GROUP BY code_module, code_presentation HAVING COUNT(*) > 1
        )) AS b_courses_dup_keys,

        (SELECT COUNT(*) FROM (
            SELECT id_assessment
            FROM open_university.oulad_bronze.assessment_raw
            GROUP BY id_assessment HAVING COUNT(*) > 1
        )) AS b_assessment_dup_keys,

        (SELECT COUNT(*) FROM (
            SELECT id_assessment, id_student
            FROM open_university.oulad_bronze.student_assessment_raw
            GROUP BY id_assessment, id_student HAVING COUNT(*) > 1
        )) AS b_student_assessment_dup_keys,

        (SELECT COUNT(*) FROM (
            SELECT code_module, code_presentation, id_student
            FROM open_university.oulad_bronze.student_info_raw
            GROUP BY code_module, code_presentation, id_student HAVING COUNT(*) > 1
        )) AS b_student_info_dup_keys,

        (SELECT COUNT(*) FROM (
            SELECT code_module, code_presentation, id_student
            FROM open_university.oulad_bronze.student_registration_raw
            GROUP BY code_module, code_presentation, id_student HAVING COUNT(*) > 1
        )) AS b_student_registration_dup_keys,

        (SELECT COUNT(*) FROM (
            SELECT code_module, code_presentation, id_site
            FROM open_university.oulad_bronze.vle_raw
            GROUP BY code_module, code_presentation, id_site HAVING COUNT(*) > 1
        )) AS b_vle_dup_keys,

        (SELECT COUNT(*) FROM (
            SELECT code_module, code_presentation, id_student, id_site, date
            FROM open_university.oulad_bronze.student_vle_raw
            GROUP BY code_module, code_presentation, id_student, id_site, date
            HAVING COUNT(*) > 1
        )) AS b_student_vle_dup_keys,

        (SELECT COALESCE(SUM(rows_per_key - 1), 0) FROM (
            SELECT COUNT(*) AS rows_per_key
            FROM open_university.oulad_bronze.student_vle_raw
            GROUP BY code_module, code_presentation, id_student, id_site, date
            HAVING COUNT(*) > 1
        )) AS b_student_vle_extra_rows,

        (SELECT COUNT(*) FROM (
            SELECT code_module, code_presentation
            FROM open_university.oulad_silver.courses_clean
            GROUP BY code_module, code_presentation HAVING COUNT(*) > 1
        )) AS s_courses_dup_keys,

        (SELECT COUNT(*) FROM (
            SELECT id_assessment
            FROM open_university.oulad_silver.assessment_clean
            GROUP BY id_assessment HAVING COUNT(*) > 1
        )) AS s_assessment_dup_keys,

        (SELECT COUNT(*) FROM (
            SELECT id_assessment, id_student
            FROM open_university.oulad_silver.student_assessment_clean
            GROUP BY id_assessment, id_student HAVING COUNT(*) > 1
        )) AS s_student_assessment_dup_keys,

        (SELECT COUNT(*) FROM (
            SELECT code_module, code_presentation, id_student
            FROM open_university.oulad_silver.student_info_clean
            GROUP BY code_module, code_presentation, id_student HAVING COUNT(*) > 1
        )) AS s_student_info_dup_keys,

        (SELECT COUNT(*) FROM (
            SELECT code_module, code_presentation, id_student
            FROM open_university.oulad_silver.student_registration_clean
            GROUP BY code_module, code_presentation, id_student HAVING COUNT(*) > 1
        )) AS s_student_registration_dup_keys,

        (SELECT COUNT(*) FROM (
            SELECT code_module, code_presentation, id_site
            FROM open_university.oulad_silver.vle_clean
            GROUP BY code_module, code_presentation, id_site HAVING COUNT(*) > 1
        )) AS s_vle_dup_keys,

        (SELECT COUNT(*) FROM (
            SELECT code_module, code_presentation, id_student, id_site, date
            FROM open_university.oulad_silver.student_vle_clean
            GROUP BY code_module, code_presentation, id_student, id_site, date
            HAVING COUNT(*) > 1
        )) AS s_student_vle_dup_keys,

        -- ---------------------------------------------------------------------
        -- Value/range checks. Relative date fields deliberately do NOT reject
        -- negative values because OULAD dates are relative to presentation start.
        -- ---------------------------------------------------------------------
        (SELECT COUNT(*) FROM open_university.oulad_bronze.courses_raw
         WHERE TRY_CAST(module_presentation_length AS INT) IS NULL
            OR TRY_CAST(module_presentation_length AS INT) <= 0) AS b_courses_bad_length,

        (SELECT COUNT(*) FROM open_university.oulad_silver.courses_clean
         WHERE module_presentation_length IS NULL OR module_presentation_length <= 0) AS s_courses_bad_length,

        (SELECT COUNT(*) FROM open_university.oulad_bronze.assessment_raw
         WHERE TRY_CAST(weight AS DECIMAL(18,6)) IS NOT NULL
           AND (TRY_CAST(weight AS DECIMAL(18,6)) < 0 OR TRY_CAST(weight AS DECIMAL(18,6)) > 100)) AS b_assessment_bad_weight,

        (SELECT COUNT(*) FROM open_university.oulad_silver.assessment_clean
         WHERE weight IS NOT NULL AND (weight < 0 OR weight > 100)) AS s_assessment_bad_weight,

        (SELECT COUNT(*) FROM open_university.oulad_bronze.student_assessment_raw
         WHERE score IS NOT NULL
           AND UPPER(TRIM(CAST(score AS STRING))) NOT IN ('', '?', 'NA', 'N/A', 'NULL')
           AND (TRY_CAST(score AS DECIMAL(18,6)) IS NULL
             OR TRY_CAST(score AS DECIMAL(18,6)) < 0
             OR TRY_CAST(score AS DECIMAL(18,6)) > 100)) AS b_student_assessment_bad_score,

        (SELECT COUNT(*) FROM open_university.oulad_silver.student_assessment_clean
         WHERE score IS NOT NULL AND (score < 0 OR score > 100)) AS s_student_assessment_bad_score,

        (SELECT COUNT(*) FROM open_university.oulad_bronze.student_info_raw
         WHERE TRY_CAST(num_of_prev_attempts AS INT) IS NULL OR TRY_CAST(num_of_prev_attempts AS INT) < 0
            OR TRY_CAST(studied_credits AS INT) IS NULL OR TRY_CAST(studied_credits AS INT) < 0) AS b_student_info_bad_numeric,

        (SELECT COUNT(*) FROM open_university.oulad_silver.student_info_clean
         WHERE num_of_prev_attempts IS NULL OR num_of_prev_attempts < 0
            OR studied_credits IS NULL OR studied_credits < 0) AS s_student_info_bad_numeric,

        (SELECT COUNT(*) FROM open_university.oulad_bronze.vle_raw
         WHERE TRY_CAST(week_from AS INT) IS NOT NULL
           AND TRY_CAST(week_to AS INT) IS NOT NULL
           AND TRY_CAST(week_from AS INT) > TRY_CAST(week_to AS INT)) AS b_vle_bad_week_range,

        (SELECT COUNT(*) FROM open_university.oulad_silver.vle_clean
         WHERE is_valid_date_range = FALSE) AS s_vle_bad_week_range,

        (SELECT COUNT(*) FROM open_university.oulad_bronze.student_vle_raw
         WHERE TRY_CAST(sum_click AS BIGINT) IS NULL OR TRY_CAST(sum_click AS BIGINT) < 0) AS b_student_vle_bad_clicks,

        (SELECT COUNT(*) FROM open_university.oulad_silver.student_vle_clean
         WHERE sum_click IS NULL OR sum_click < 0) AS s_student_vle_bad_clicks,

        -- accepted values
        (SELECT COUNT(*) FROM open_university.oulad_bronze.assessment_raw
         WHERE assessment_type IS NULL OR TRIM(CAST(assessment_type AS STRING)) NOT IN ('TMA','CMA','Exam')) AS b_assessment_bad_type,

        (SELECT COUNT(*) FROM open_university.oulad_silver.assessment_clean
         WHERE assessment_type IS NULL OR assessment_type NOT IN ('TMA','CMA','Exam')) AS s_assessment_bad_type,

        (SELECT COUNT(*) FROM open_university.oulad_bronze.student_assessment_raw
         WHERE TRY_CAST(is_banked AS INT) IS NULL OR TRY_CAST(is_banked AS INT) NOT IN (0,1)) AS b_student_assessment_bad_banked,

        (SELECT COUNT(*) FROM open_university.oulad_silver.student_assessment_clean
         WHERE is_banked IS NULL OR is_banked NOT IN (0,1)) AS s_student_assessment_bad_banked,

        (SELECT COUNT(*) FROM open_university.oulad_bronze.student_info_raw
         WHERE final_result IS NULL OR TRIM(CAST(final_result AS STRING)) NOT IN ('Distinction','Fail','Pass','Withdrawn')) AS b_student_info_bad_result,

        (SELECT COUNT(*) FROM open_university.oulad_silver.student_info_clean
         WHERE final_result IS NULL OR final_result NOT IN ('Distinction','Fail','Pass','Withdrawn')) AS s_student_info_bad_result,

        -- documented optional NULLs / warnings
        (SELECT COUNT(*) FROM open_university.oulad_silver.student_registration_clean
         WHERE date_registration IS NULL) AS s_missing_registration_dates,

        (SELECT COUNT(*) FROM open_university.oulad_silver.student_assessment_clean
         WHERE score IS NULL) AS s_null_scores,

        (SELECT COUNT(*) FROM open_university.oulad_silver.vle_clean
         WHERE week_from IS NULL AND week_to IS NULL) AS s_vle_both_weeks_null,

        (SELECT COUNT(*) FROM open_university.oulad_silver.student_vle_clean
         WHERE date < 0) AS s_student_vle_negative_dates,

        (SELECT COUNT(*) FROM open_university.oulad_silver.student_assessment_clean
         WHERE date_submitted < 0) AS s_student_assessment_negative_dates,

        (SELECT COUNT(*) FROM open_university.oulad_silver.student_registration_clean
         WHERE date_registration < 0 OR date_unregistration < 0) AS s_registration_negative_dates,

        -- ---------------------------------------------------------------------
        -- Referential integrity
        -- ---------------------------------------------------------------------
        (SELECT COUNT(*) FROM open_university.oulad_bronze.assessment_raw a
         LEFT JOIN open_university.oulad_bronze.courses_raw c
           ON a.code_module = c.code_module AND a.code_presentation = c.code_presentation
         WHERE c.code_module IS NULL) AS b_assessment_course_orphans,

        (SELECT COUNT(*) FROM open_university.oulad_bronze.student_assessment_raw sa
         LEFT JOIN open_university.oulad_bronze.assessment_raw a
           ON sa.id_assessment = a.id_assessment
         WHERE a.id_assessment IS NULL) AS b_student_assessment_orphans,

        (SELECT COUNT(*) FROM open_university.oulad_bronze.student_info_raw si
         LEFT JOIN open_university.oulad_bronze.courses_raw c
           ON si.code_module = c.code_module AND si.code_presentation = c.code_presentation
         WHERE c.code_module IS NULL) AS b_student_info_orphans,

        (SELECT COUNT(*) FROM open_university.oulad_bronze.student_registration_raw sr
         LEFT JOIN open_university.oulad_bronze.student_info_raw si
           ON sr.code_module = si.code_module AND sr.code_presentation = si.code_presentation
          AND sr.id_student = si.id_student
         WHERE si.id_student IS NULL) AS b_student_registration_orphans,

        (SELECT COUNT(*) FROM open_university.oulad_bronze.vle_raw v
         LEFT JOIN open_university.oulad_bronze.courses_raw c
           ON v.code_module = c.code_module AND v.code_presentation = c.code_presentation
         WHERE c.code_module IS NULL) AS b_vle_orphans,

        (SELECT COUNT(*) FROM open_university.oulad_bronze.student_vle_raw sv
         LEFT JOIN open_university.oulad_bronze.vle_raw v
           ON sv.code_module = v.code_module AND sv.code_presentation = v.code_presentation
          AND sv.id_site = v.id_site
         WHERE v.id_site IS NULL) AS b_student_vle_vle_orphans,

        (SELECT COUNT(*) FROM open_university.oulad_bronze.student_vle_raw sv
         LEFT JOIN open_university.oulad_bronze.student_info_raw si
           ON sv.code_module = si.code_module AND sv.code_presentation = si.code_presentation
          AND sv.id_student = si.id_student
         WHERE si.id_student IS NULL) AS b_student_vle_student_orphans,

        (SELECT COUNT(*) FROM open_university.oulad_silver.assessment_clean a
         LEFT JOIN open_university.oulad_silver.courses_clean c
           ON a.code_module = c.code_module AND a.code_presentation = c.code_presentation
         WHERE c.code_module IS NULL) AS s_assessment_course_orphans,

        (SELECT COUNT(*) FROM open_university.oulad_silver.student_assessment_clean sa
         LEFT JOIN open_university.oulad_silver.assessment_clean a
           ON sa.id_assessment = a.id_assessment
         WHERE a.id_assessment IS NULL) AS s_student_assessment_orphans,

        (SELECT COUNT(*) FROM open_university.oulad_silver.student_info_clean si
         LEFT JOIN open_university.oulad_silver.courses_clean c
           ON si.code_module = c.code_module AND si.code_presentation = c.code_presentation
         WHERE c.code_module IS NULL) AS s_student_info_orphans,

        (SELECT COUNT(*) FROM open_university.oulad_silver.student_registration_clean sr
         LEFT JOIN open_university.oulad_silver.student_info_clean si
           ON sr.code_module = si.code_module AND sr.code_presentation = si.code_presentation
          AND sr.id_student = si.id_student
         WHERE si.id_student IS NULL) AS s_student_registration_orphans,

        (SELECT COUNT(*) FROM open_university.oulad_silver.vle_clean v
         LEFT JOIN open_university.oulad_silver.courses_clean c
           ON v.code_module = c.code_module AND v.code_presentation = c.code_presentation
         WHERE c.code_module IS NULL) AS s_vle_orphans,

        (SELECT COUNT(*) FROM open_university.oulad_silver.student_vle_clean sv
         LEFT JOIN open_university.oulad_silver.vle_clean v
           ON sv.code_module = v.code_module AND sv.code_presentation = v.code_presentation
          AND sv.id_site = v.id_site
         WHERE v.id_site IS NULL) AS s_student_vle_vle_orphans,

        (SELECT COUNT(*) FROM open_university.oulad_silver.student_vle_clean sv
         LEFT JOIN open_university.oulad_silver.student_info_clean si
           ON sv.code_module = si.code_module AND sv.code_presentation = si.code_presentation
          AND sv.id_student = si.id_student
         WHERE si.id_student IS NULL) AS s_student_vle_student_orphans,

        -- ---------------------------------------------------------------------
        -- Bronze -> Silver reconciliation
        -- ---------------------------------------------------------------------
        (SELECT COALESCE(SUM(source_row_count), 0)
         FROM open_university.oulad_silver.courses_invalid_key_quarantine) AS s_courses_quarantined_rows,

        (SELECT SUM(TRY_CAST(score AS DECIMAL(18,2)))
         FROM open_university.oulad_bronze.student_assessment_raw) AS b_score_sum,

        (SELECT SUM(score)
         FROM open_university.oulad_silver.student_assessment_clean) AS s_score_sum,

        (SELECT SUM(source_row_count)
         FROM open_university.oulad_silver.student_vle_clean) AS s_student_vle_accounted_rows,

        (SELECT SUM(TRY_CAST(sum_click AS BIGINT))
         FROM open_university.oulad_bronze.student_vle_raw) AS b_student_vle_clicks,

        (SELECT SUM(sum_click)
         FROM open_university.oulad_silver.student_vle_clean) AS s_student_vle_clicks
),
raw_results AS (
    -- Each SELECT returns the same shape. Mixed historical status words are
    -- intentionally allowed here and normalized once in the next CTE.

    -- =========================================================================
    -- BRONZE: COURSES
    -- =========================================================================
    SELECT 'oulad_bronze' dataset_schema, 'courses_raw' dataset_table, 'BRONZE' dataset_layer,
           'bronze_courses_required_keys' check_id, 'Courses required keys are complete' check_name,
           'NULL' check_type, 'Checks code_module and code_presentation in Bronze courses' check_description,
           'No required course key is missing' expectation, '=' threshold_operator, '0 failed rows' threshold_value,
           CASE WHEN b_courses_null_keys = 0 THEN 'Pass' ELSE 'Fail' END raw_status,
           'CRITICAL' severity, '0 rows with missing course keys' expected_result,
           CONCAT(CAST(b_courses_null_keys AS STRING), ' rows have missing course keys') actual_result,
           b_courses_rows total_count, b_courses_null_keys fail_count,
           CASE WHEN b_courses_rows = 0 THEN NULL ELSE 100.0 * b_courses_null_keys / b_courses_rows END fail_pct,
           'Bronze courses business keys must be complete' message,
           map('exception_policy','NONE') result_metadata FROM metrics
    UNION ALL
    SELECT 'oulad_bronze','courses_raw','BRONZE','bronze_courses_unique_key','Courses business key is unique','UNIQUE',
           'Checks one row per code_module + code_presentation','No duplicate course keys','=', '0 duplicate keys',
           CASE WHEN b_courses_dup_keys=0 THEN 'PASS' ELSE 'FAIL' END,'CRITICAL','0 duplicate keys',
           CONCAT(CAST(b_courses_dup_keys AS STRING),' duplicate keys'),b_courses_rows,b_courses_dup_keys,
           CASE WHEN b_courses_rows=0 THEN NULL ELSE 100.0*b_courses_dup_keys/b_courses_rows END,
           'Bronze courses should have one row per presentation',map('exception_policy','NONE') FROM metrics
    UNION ALL
    SELECT 'oulad_bronze','courses_raw','BRONZE','bronze_courses_valid_length','Course presentation length is valid','RANGE',
           'Checks module_presentation_length is numeric and greater than zero','Length must be > 0','>','0',
           CASE WHEN b_courses_bad_length=0 THEN 'Pass' ELSE 'Fail' END,'FAIL','0 invalid length rows',
           CONCAT(CAST(b_courses_bad_length AS STRING),' invalid length rows'),b_courses_rows,b_courses_bad_length,
           CASE WHEN b_courses_rows=0 THEN NULL ELSE 100.0*b_courses_bad_length/b_courses_rows END,
           'Invalid course lengths are material but do not automatically stop the pipeline',map('exception_policy','NONE') FROM metrics
    UNION ALL
    SELECT 'oulad_bronze','courses_raw','BRONZE','bronze_courses_not_empty','Courses source was received','VOLUME',
           'Checks Bronze courses is not empty','At least one course row must exist','>','0 rows',
           CASE WHEN b_courses_rows>0 THEN 'Pass' ELSE 'Fail' END,'CRITICAL','More than 0 rows',
           CONCAT(CAST(b_courses_rows AS STRING),' rows received'),b_courses_rows,
           CASE WHEN b_courses_rows=0 THEN 1 ELSE 0 END,
           CASE WHEN b_courses_rows=0 THEN 100.0 ELSE 0.0 END,
           'Empty source means the dataset is unusable',map('volume_rule','NON_EMPTY') FROM metrics

    -- =========================================================================
    -- BRONZE: ASSESSMENT
    -- =========================================================================
    UNION ALL
    SELECT 'oulad_bronze','assessment_raw','BRONZE','bronze_assessment_required_fields','Assessment required fields are complete','NULL',
           'Checks assessment ID, module, presentation and type','Required assessment fields must be present','=', '0 failed rows',
           CASE WHEN b_assessment_null_keys=0 THEN 'PASS' ELSE 'FAIL' END,'CRITICAL','0 missing required rows',
           CONCAT(CAST(b_assessment_null_keys AS STRING),' rows have missing required fields'),b_assessment_rows,b_assessment_null_keys,
           CASE WHEN b_assessment_rows=0 THEN NULL ELSE 100.0*b_assessment_null_keys/b_assessment_rows END,
           'Assessment date itself remains optional where valid',map('exception_policy','ASSESSMENT_DATE_OPTIONAL') FROM metrics
    UNION ALL
    SELECT 'oulad_bronze','assessment_raw','BRONZE','bronze_assessment_unique_id','Assessment ID is unique','UNIQUE',
           'Checks one Bronze row per id_assessment','id_assessment must be unique','=', '0 duplicate IDs',
           CASE WHEN b_assessment_dup_keys=0 THEN 'PASS' ELSE 'FAIL' END,'CRITICAL','0 duplicate IDs',
           CONCAT(CAST(b_assessment_dup_keys AS STRING),' duplicate IDs'),b_assessment_rows,b_assessment_dup_keys,
           CASE WHEN b_assessment_rows=0 THEN NULL ELSE 100.0*b_assessment_dup_keys/b_assessment_rows END,
           'Duplicate assessment IDs break downstream joins',map('exception_policy','NONE') FROM metrics
    UNION ALL
    SELECT 'oulad_bronze','assessment_raw','BRONZE','bronze_assessment_weight_range','Assessment weight is within range','RANGE',
           'Checks non-NULL weight is between 0 and 100','0 <= weight <= 100','BETWEEN','0 and 100',
           CASE WHEN b_assessment_bad_weight=0 THEN 'Pass' ELSE 'Fail' END,'FAIL','0 out-of-range weights',
           CONCAT(CAST(b_assessment_bad_weight AS STRING),' out-of-range weights'),b_assessment_rows,b_assessment_bad_weight,
           CASE WHEN b_assessment_rows=0 THEN NULL ELSE 100.0*b_assessment_bad_weight/b_assessment_rows END,
           'Relative assessment dates are not checked for nonnegativity',map('exception_policy','NEGATIVE_RELATIVE_DATES_ALLOWED') FROM metrics
    UNION ALL
    SELECT 'oulad_bronze','assessment_raw','BRONZE','bronze_assessment_type_values','Assessment type is accepted','ACCEPTED_VALUES',
           'Checks assessment_type belongs to the documented OULAD set','assessment_type in TMA, CMA, Exam','IN','TMA|CMA|Exam',
           CASE WHEN b_assessment_bad_type=0 THEN 'PASS' ELSE 'FAIL' END,'FAIL','0 invalid assessment types',
           CONCAT(CAST(b_assessment_bad_type AS STRING),' invalid assessment types'),b_assessment_rows,b_assessment_bad_type,
           CASE WHEN b_assessment_rows=0 THEN NULL ELSE 100.0*b_assessment_bad_type/b_assessment_rows END,
           'Only documented assessment types are accepted',map('exception_policy','NONE') FROM metrics
    UNION ALL
    SELECT 'oulad_bronze','assessment_raw','BRONZE','bronze_assessment_course_reference','Assessment presentation exists in courses','REFERENTIAL_INTEGRITY',
           'Checks assessment module/presentation against Bronze courses','Every assessment presentation must have a course parent','=', '0 orphan rows',
           CASE WHEN b_assessment_course_orphans=0 THEN 'Pass' ELSE 'Review' END,'WARN','0 orphan rows',
           CONCAT(CAST(b_assessment_course_orphans AS STRING),' orphan rows'),b_assessment_rows,b_assessment_course_orphans,
           CASE WHEN b_assessment_rows=0 THEN NULL ELSE 100.0*b_assessment_course_orphans/b_assessment_rows END,
           'Bronze relationship REVIEW is normalized to WARN',map('legacy_status','REVIEW') FROM metrics
    UNION ALL
    SELECT 'oulad_bronze','assessment_raw','BRONZE','bronze_assessment_not_empty','Assessment source was received','VOLUME',
           'Checks Bronze assessment is not empty','At least one assessment row must exist','>','0 rows',
           CASE WHEN b_assessment_rows>0 THEN 'PASS' ELSE 'FAIL' END,'CRITICAL','More than 0 rows',
           CONCAT(CAST(b_assessment_rows AS STRING),' rows received'),b_assessment_rows,CASE WHEN b_assessment_rows=0 THEN 1 ELSE 0 END,
           CASE WHEN b_assessment_rows=0 THEN 100.0 ELSE 0.0 END,'Assessment source must be present',map('volume_rule','NON_EMPTY') FROM metrics

    -- =========================================================================
    -- BRONZE: STUDENT ASSESSMENT
    -- =========================================================================
    UNION ALL
    SELECT 'oulad_bronze','student_assessment_raw','BRONZE','bronze_student_assessment_required_fields','Student assessment required fields are complete','NULL',
           'Checks assessment ID, student ID, submitted date and is_banked; score is intentionally optional',
           'Required fields present; score may be NULL','=', '0 failed rows',
           CASE WHEN b_student_assessment_required_nulls=0 THEN 'Pass' ELSE 'Fail' END,'CRITICAL','0 missing required rows',
           CONCAT(CAST(b_student_assessment_required_nulls AS STRING),' rows have missing required fields'),b_student_assessment_rows,b_student_assessment_required_nulls,
           CASE WHEN b_student_assessment_rows=0 THEN NULL ELSE 100.0*b_student_assessment_required_nulls/b_student_assessment_rows END,
           'NULL score is a documented valid outcome and is excluded',map('exception_policy','NULL_SCORE_ALLOWED') FROM metrics
    UNION ALL
    SELECT 'oulad_bronze','student_assessment_raw','BRONZE','bronze_student_assessment_unique_key','Student assessment key is unique','UNIQUE',
           'Checks one row per id_assessment + id_student','No duplicate assessment/student keys','=', '0 duplicate keys',
           CASE WHEN b_student_assessment_dup_keys=0 THEN 'PASS' ELSE 'FAIL' END,'CRITICAL','0 duplicate keys',
           CONCAT(CAST(b_student_assessment_dup_keys AS STRING),' duplicate keys'),b_student_assessment_rows,b_student_assessment_dup_keys,
           CASE WHEN b_student_assessment_rows=0 THEN NULL ELSE 100.0*b_student_assessment_dup_keys/b_student_assessment_rows END,
           'Duplicate result keys are not expected',map('exception_policy','NONE') FROM metrics
    UNION ALL
    SELECT 'oulad_bronze','student_assessment_raw','BRONZE','bronze_student_assessment_score_range','Student assessment score is valid when present','RANGE',
           'Checks only non-NULL scores; NULL scores are valid','score is NULL or 0..100','BETWEEN','0 and 100 when non-NULL',
           CASE WHEN b_student_assessment_bad_score=0 THEN 'Pass' ELSE 'Fail' END,'FAIL','0 invalid non-NULL scores',
           CONCAT(CAST(b_student_assessment_bad_score AS STRING),' invalid non-NULL scores'),b_student_assessment_rows,b_student_assessment_bad_score,
           CASE WHEN b_student_assessment_rows=0 THEN NULL ELSE 100.0*b_student_assessment_bad_score/b_student_assessment_rows END,
           'Missing scores are not failures',map('exception_policy','NULL_SCORE_ALLOWED') FROM metrics
    UNION ALL
    SELECT 'oulad_bronze','student_assessment_raw','BRONZE','bronze_student_assessment_is_banked','is_banked is accepted','ACCEPTED_VALUES',
           'Checks is_banked values are 0 or 1','is_banked in 0,1','IN','0|1',
           CASE WHEN b_student_assessment_bad_banked=0 THEN 'PASS' ELSE 'FAIL' END,'FAIL','0 invalid is_banked rows',
           CONCAT(CAST(b_student_assessment_bad_banked AS STRING),' invalid rows'),b_student_assessment_rows,b_student_assessment_bad_banked,
           CASE WHEN b_student_assessment_rows=0 THEN NULL ELSE 100.0*b_student_assessment_bad_banked/b_student_assessment_rows END,
           'Banked flag must be binary',map('exception_policy','NONE') FROM metrics
    UNION ALL
    SELECT 'oulad_bronze','student_assessment_raw','BRONZE','bronze_student_assessment_parent','Student assessment has assessment parent','REFERENTIAL_INTEGRITY',
           'Checks id_assessment against Bronze assessment','Every student assessment must match an assessment','=', '0 orphan rows',
           CASE WHEN b_student_assessment_orphans=0 THEN 'Pass' ELSE 'Review' END,'WARN','0 orphan rows',
           CONCAT(CAST(b_student_assessment_orphans AS STRING),' orphan rows'),b_student_assessment_rows,b_student_assessment_orphans,
           CASE WHEN b_student_assessment_rows=0 THEN NULL ELSE 100.0*b_student_assessment_orphans/b_student_assessment_rows END,
           'Legacy REVIEW is standardized to WARN',map('legacy_status','REVIEW') FROM metrics
    UNION ALL
    SELECT 'oulad_bronze','student_assessment_raw','BRONZE','bronze_student_assessment_not_empty','Student assessment source was received','VOLUME',
           'Checks Bronze student_assessment is not empty','At least one row must exist','>','0 rows',
           CASE WHEN b_student_assessment_rows>0 THEN 'PASS' ELSE 'FAIL' END,'CRITICAL','More than 0 rows',
           CONCAT(CAST(b_student_assessment_rows AS STRING),' rows received'),b_student_assessment_rows,CASE WHEN b_student_assessment_rows=0 THEN 1 ELSE 0 END,
           CASE WHEN b_student_assessment_rows=0 THEN 100.0 ELSE 0.0 END,'Student assessment source must be present',map('volume_rule','NON_EMPTY') FROM metrics

    -- =========================================================================
    -- BRONZE: STUDENT INFO
    -- =========================================================================
    UNION ALL
    SELECT 'oulad_bronze','student_info_raw','BRONZE','bronze_student_info_required_keys','Student info required keys are complete','NULL',
           'Checks module, presentation and student ID','No required enrollment key is missing','=', '0 failed rows',
           CASE WHEN b_student_info_null_keys=0 THEN 'PASS' ELSE 'FAIL' END,'CRITICAL','0 missing key rows',
           CONCAT(CAST(b_student_info_null_keys AS STRING),' rows have missing keys'),b_student_info_rows,b_student_info_null_keys,
           CASE WHEN b_student_info_rows=0 THEN NULL ELSE 100.0*b_student_info_null_keys/b_student_info_rows END,
           'Student enrollment key must be complete',map('exception_policy','IMD_BAND_OPTIONAL') FROM metrics
    UNION ALL
    SELECT 'oulad_bronze','student_info_raw','BRONZE','bronze_student_info_unique_key','Student info enrollment key is unique','UNIQUE',
           'Checks one row per module + presentation + student','No duplicate enrollment keys','=', '0 duplicate keys',
           CASE WHEN b_student_info_dup_keys=0 THEN 'PASS' ELSE 'FAIL' END,'CRITICAL','0 duplicate keys',
           CONCAT(CAST(b_student_info_dup_keys AS STRING),' duplicate keys'),b_student_info_rows,b_student_info_dup_keys,
           CASE WHEN b_student_info_rows=0 THEN NULL ELSE 100.0*b_student_info_dup_keys/b_student_info_rows END,
           'Student enrollment grain must be unique',map('exception_policy','NONE') FROM metrics
    UNION ALL
    SELECT 'oulad_bronze','student_info_raw','BRONZE','bronze_student_info_numeric_ranges','Student info numeric values are valid','RANGE',
           'Checks attempts and studied credits are numeric and nonnegative','attempts >= 0 and credits >= 0','>=','0',
           CASE WHEN b_student_info_bad_numeric=0 THEN 'Pass' ELSE 'Fail' END,'FAIL','0 invalid numeric rows',
           CONCAT(CAST(b_student_info_bad_numeric AS STRING),' invalid numeric rows'),b_student_info_rows,b_student_info_bad_numeric,
           CASE WHEN b_student_info_rows=0 THEN NULL ELSE 100.0*b_student_info_bad_numeric/b_student_info_rows END,
           'Negative attempts or credits are invalid',map('exception_policy','NONE') FROM metrics
    UNION ALL
    SELECT 'oulad_bronze','student_info_raw','BRONZE','bronze_student_info_final_result','Student final_result is accepted','ACCEPTED_VALUES',
           'Checks documented final result categories','final_result in Distinction, Fail, Pass, Withdrawn','IN','Distinction|Fail|Pass|Withdrawn',
           CASE WHEN b_student_info_bad_result=0 THEN 'PASS' ELSE 'FAIL' END,'FAIL','0 invalid result rows',
           CONCAT(CAST(b_student_info_bad_result AS STRING),' invalid result rows'),b_student_info_rows,b_student_info_bad_result,
           CASE WHEN b_student_info_rows=0 THEN NULL ELSE 100.0*b_student_info_bad_result/b_student_info_rows END,
           'Only documented outcome categories are accepted',map('exception_policy','NONE') FROM metrics
    UNION ALL
    SELECT 'oulad_bronze','student_info_raw','BRONZE','bronze_student_info_course_reference','Student info presentation exists in courses','REFERENTIAL_INTEGRITY',
           'Checks student_info module/presentation against courses','Every enrollment must have a course parent','=', '0 orphan rows',
           CASE WHEN b_student_info_orphans=0 THEN 'PASS' ELSE 'REVIEW' END,'WARN','0 orphan rows',
           CONCAT(CAST(b_student_info_orphans AS STRING),' orphan rows'),b_student_info_rows,b_student_info_orphans,
           CASE WHEN b_student_info_rows=0 THEN NULL ELSE 100.0*b_student_info_orphans/b_student_info_rows END,
           'Legacy REVIEW is standardized to WARN',map('legacy_status','REVIEW') FROM metrics
    UNION ALL
    SELECT 'oulad_bronze','student_info_raw','BRONZE','bronze_student_info_not_empty','Student info source was received','VOLUME',
           'Checks Bronze student_info is not empty','At least one row must exist','>','0 rows',
           CASE WHEN b_student_info_rows>0 THEN 'PASS' ELSE 'FAIL' END,'CRITICAL','More than 0 rows',
           CONCAT(CAST(b_student_info_rows AS STRING),' rows received'),b_student_info_rows,CASE WHEN b_student_info_rows=0 THEN 1 ELSE 0 END,
           CASE WHEN b_student_info_rows=0 THEN 100.0 ELSE 0.0 END,'Student info source must be present',map('volume_rule','NON_EMPTY') FROM metrics

    -- =========================================================================
    -- BRONZE: STUDENT REGISTRATION
    -- =========================================================================
    UNION ALL
    SELECT 'oulad_bronze','student_registration_raw','BRONZE','bronze_student_registration_required_keys','Registration required keys are complete','NULL',
           'Checks module, presentation and student ID','No required registration key is missing','=', '0 failed rows',
           CASE WHEN b_student_registration_null_keys=0 THEN 'PASS' ELSE 'FAIL' END,'CRITICAL','0 missing key rows',
           CONCAT(CAST(b_student_registration_null_keys AS STRING),' rows have missing keys'),b_student_registration_rows,b_student_registration_null_keys,
           CASE WHEN b_student_registration_rows=0 THEN NULL ELSE 100.0*b_student_registration_null_keys/b_student_registration_rows END,
           'Registration date is evaluated separately as a known warning',map('exception_policy','REGISTRATION_DATE_WARN') FROM metrics
    UNION ALL
    SELECT 'oulad_bronze','student_registration_raw','BRONZE','bronze_student_registration_unique_key','Registration key is unique','UNIQUE',
           'Checks one row per module + presentation + student','No duplicate registration keys','=', '0 duplicate keys',
           CASE WHEN b_student_registration_dup_keys=0 THEN 'PASS' ELSE 'FAIL' END,'CRITICAL','0 duplicate keys',
           CONCAT(CAST(b_student_registration_dup_keys AS STRING),' duplicate keys'),b_student_registration_rows,b_student_registration_dup_keys,
           CASE WHEN b_student_registration_rows=0 THEN NULL ELSE 100.0*b_student_registration_dup_keys/b_student_registration_rows END,
           'Registration grain must remain unique',map('exception_policy','NONE') FROM metrics
    UNION ALL
    SELECT 'oulad_bronze','student_registration_raw','BRONZE','bronze_student_registration_relative_dates','Registration relative dates accept negative values','RANGE',
           'Validates relative dates by castability only; negative offsets are allowed','Dates may be negative if numeric','N/A','Negative relative dates allowed',
           'Pass','WARN','No rejection solely because a relative date is negative','Negative relative dates intentionally accepted',
           b_student_registration_rows,0,0.0,'OULAD dates are relative to presentation start',map('exception_policy','NEGATIVE_RELATIVE_DATES_ALLOWED') FROM metrics
    UNION ALL
    SELECT 'oulad_bronze','student_registration_raw','BRONZE','bronze_student_registration_parent','Registration has student_info parent','REFERENTIAL_INTEGRITY',
           'Checks registration key against Bronze student_info','Every registration must match student_info','=', '0 orphan rows',
           CASE WHEN b_student_registration_orphans=0 THEN 'PASS' ELSE 'REVIEW' END,'WARN','0 orphan rows',
           CONCAT(CAST(b_student_registration_orphans AS STRING),' orphan rows'),b_student_registration_rows,b_student_registration_orphans,
           CASE WHEN b_student_registration_rows=0 THEN NULL ELSE 100.0*b_student_registration_orphans/b_student_registration_rows END,
           'Legacy REVIEW is standardized to WARN',map('legacy_status','REVIEW') FROM metrics
    UNION ALL
    SELECT 'oulad_bronze','student_registration_raw','BRONZE','bronze_student_registration_not_empty','Registration source was received','VOLUME',
           'Checks Bronze registration is not empty','At least one row must exist','>','0 rows',
           CASE WHEN b_student_registration_rows>0 THEN 'PASS' ELSE 'FAIL' END,'CRITICAL','More than 0 rows',
           CONCAT(CAST(b_student_registration_rows AS STRING),' rows received'),b_student_registration_rows,CASE WHEN b_student_registration_rows=0 THEN 1 ELSE 0 END,
           CASE WHEN b_student_registration_rows=0 THEN 100.0 ELSE 0.0 END,'Registration source must be present',map('volume_rule','NON_EMPTY') FROM metrics

    -- =========================================================================
    -- BRONZE: VLE
    -- =========================================================================
    UNION ALL
    SELECT 'oulad_bronze','vle_raw','BRONZE','bronze_vle_required_keys','VLE required keys are complete','NULL',
           'Checks module, presentation and site ID','No required VLE key is missing','=', '0 failed rows',
           CASE WHEN b_vle_null_keys=0 THEN 'PASS' ELSE 'FAIL' END,'CRITICAL','0 missing key rows',
           CONCAT(CAST(b_vle_null_keys AS STRING),' rows have missing keys'),b_vle_rows,b_vle_null_keys,
           CASE WHEN b_vle_rows=0 THEN NULL ELSE 100.0*b_vle_null_keys/b_vle_rows END,
           'week_from and week_to are optional',map('exception_policy','OPTIONAL_WEEKS') FROM metrics
    UNION ALL
    SELECT 'oulad_bronze','vle_raw','BRONZE','bronze_vle_unique_key','VLE business key is unique','UNIQUE',
           'Checks one row per module + presentation + site','No duplicate VLE keys','=', '0 duplicate keys',
           CASE WHEN b_vle_dup_keys=0 THEN 'PASS' ELSE 'FAIL' END,'CRITICAL','0 duplicate keys',
           CONCAT(CAST(b_vle_dup_keys AS STRING),' duplicate keys'),b_vle_rows,b_vle_dup_keys,
           CASE WHEN b_vle_rows=0 THEN NULL ELSE 100.0*b_vle_dup_keys/b_vle_rows END,
           'VLE resource key must be unique',map('exception_policy','NONE') FROM metrics
    UNION ALL
    SELECT 'oulad_bronze','vle_raw','BRONZE','bronze_vle_week_range','VLE week range is ordered','RANGE',
           'Checks week_from <= week_to only when both are present','week_from <= week_to when both non-NULL','<=','week_to',
           CASE WHEN b_vle_bad_week_range=0 THEN 'PASS' ELSE 'FAIL' END,'FAIL','0 invalid week ranges',
           CONCAT(CAST(b_vle_bad_week_range AS STRING),' invalid ranges'),b_vle_rows,b_vle_bad_week_range,
           CASE WHEN b_vle_rows=0 THEN NULL ELSE 100.0*b_vle_bad_week_range/b_vle_rows END,
           'NULL optional weeks remain valid',map('exception_policy','OPTIONAL_WEEKS') FROM metrics
    UNION ALL
    SELECT 'oulad_bronze','vle_raw','BRONZE','bronze_vle_course_reference','VLE presentation exists in courses','REFERENTIAL_INTEGRITY',
           'Checks VLE module/presentation against courses','Every VLE resource must have a course parent','=', '0 orphan rows',
           CASE WHEN b_vle_orphans=0 THEN 'PASS' ELSE 'REVIEW' END,'WARN','0 orphan rows',
           CONCAT(CAST(b_vle_orphans AS STRING),' orphan rows'),b_vle_rows,b_vle_orphans,
           CASE WHEN b_vle_rows=0 THEN NULL ELSE 100.0*b_vle_orphans/b_vle_rows END,
           'Legacy REVIEW is standardized to WARN',map('legacy_status','REVIEW') FROM metrics
    UNION ALL
    SELECT 'oulad_bronze','vle_raw','BRONZE','bronze_vle_not_empty','VLE source was received','VOLUME',
           'Checks Bronze VLE is not empty','At least one row must exist','>','0 rows',
           CASE WHEN b_vle_rows>0 THEN 'PASS' ELSE 'FAIL' END,'CRITICAL','More than 0 rows',
           CONCAT(CAST(b_vle_rows AS STRING),' rows received'),b_vle_rows,CASE WHEN b_vle_rows=0 THEN 1 ELSE 0 END,
           CASE WHEN b_vle_rows=0 THEN 100.0 ELSE 0.0 END,'VLE source must be present',map('volume_rule','NON_EMPTY') FROM metrics

    -- =========================================================================
    -- BRONZE: STUDENT VLE
    -- =========================================================================
    UNION ALL
    SELECT 'oulad_bronze','student_vle_raw','BRONZE','bronze_student_vle_required_keys','Student VLE required keys are complete','NULL',
           'Checks module, presentation, student, site and relative date','No required daily interaction key is missing','=', '0 failed rows',
           CASE WHEN b_student_vle_null_keys=0 THEN 'PASS' ELSE 'FAIL' END,'CRITICAL','0 missing key rows',
           CONCAT(CAST(b_student_vle_null_keys AS STRING),' rows have missing keys'),b_student_vle_rows,b_student_vle_null_keys,
           CASE WHEN b_student_vle_rows=0 THEN NULL ELSE 100.0*b_student_vle_null_keys/b_student_vle_rows END,
           'Negative relative dates remain valid if numeric',map('exception_policy','NEGATIVE_RELATIVE_DATES_ALLOWED') FROM metrics
    UNION ALL
    SELECT 'oulad_bronze','student_vle_raw','BRONZE','bronze_student_vle_unique_business_key','Bronze repeated daily VLE keys are identified','UNIQUE',
           'Finds repeated five-column daily interaction keys','Duplicates may proceed because Silver intentionally aggregates them','=', '0 duplicate keys preferred',
           CASE WHEN b_student_vle_dup_keys=0 THEN 'PASS' ELSE 'Review' END,'WARN','0 duplicates preferred; aggregation must reconcile',
           CONCAT(CAST(b_student_vle_dup_keys AS STRING),' duplicate keys; ',CAST(b_student_vle_extra_rows AS STRING),' extra physical rows'),
           b_student_vle_rows,b_student_vle_dup_keys,
           CASE WHEN b_student_vle_rows=0 THEN NULL ELSE 100.0*b_student_vle_dup_keys/b_student_vle_rows END,
           'Known Bronze duplicates are WARN, not FAIL',map('exception_policy','BRONZE_DUPLICATES_WARN','extra_duplicate_rows',CAST(b_student_vle_extra_rows AS STRING)) FROM metrics
    UNION ALL
    SELECT 'oulad_bronze','student_vle_raw','BRONZE','bronze_student_vle_click_range','Bronze Student VLE clicks are valid','RANGE',
           'Checks sum_click is numeric and nonnegative; date may be negative','sum_click >= 0','>=','0',
           CASE WHEN b_student_vle_bad_clicks=0 THEN 'PASS' ELSE 'FAIL' END,'FAIL','0 invalid click rows',
           CONCAT(CAST(b_student_vle_bad_clicks AS STRING),' invalid click rows'),b_student_vle_rows,b_student_vle_bad_clicks,
           CASE WHEN b_student_vle_rows=0 THEN NULL ELSE 100.0*b_student_vle_bad_clicks/b_student_vle_rows END,
           'Negative relative date is explicitly not a failure',map('exception_policy','NEGATIVE_RELATIVE_DATES_ALLOWED') FROM metrics
    UNION ALL
    SELECT 'oulad_bronze','student_vle_raw','BRONZE','bronze_student_vle_vle_reference','Student VLE site exists in VLE','REFERENTIAL_INTEGRITY',
           'Checks module/presentation/site against Bronze VLE','Every interaction site must match VLE','=', '0 orphan rows',
           CASE WHEN b_student_vle_vle_orphans=0 THEN 'PASS' ELSE 'REVIEW' END,'WARN','0 orphan rows',
           CONCAT(CAST(b_student_vle_vle_orphans AS STRING),' orphan rows'),b_student_vle_rows,b_student_vle_vle_orphans,
           CASE WHEN b_student_vle_rows=0 THEN NULL ELSE 100.0*b_student_vle_vle_orphans/b_student_vle_rows END,
           'Legacy REVIEW is standardized to WARN',map('legacy_status','REVIEW') FROM metrics
    UNION ALL
    SELECT 'oulad_bronze','student_vle_raw','BRONZE','bronze_student_vle_student_reference','Student VLE student exists in student_info','REFERENTIAL_INTEGRITY',
           'Checks module/presentation/student against Bronze student_info','Every interaction student must match student_info','=', '0 orphan rows',
           CASE WHEN b_student_vle_student_orphans=0 THEN 'PASS' ELSE 'REVIEW' END,'WARN','0 orphan rows',
           CONCAT(CAST(b_student_vle_student_orphans AS STRING),' orphan rows'),b_student_vle_rows,b_student_vle_student_orphans,
           CASE WHEN b_student_vle_rows=0 THEN NULL ELSE 100.0*b_student_vle_student_orphans/b_student_vle_rows END,
           'Legacy REVIEW is standardized to WARN',map('legacy_status','REVIEW') FROM metrics
    UNION ALL
    SELECT 'oulad_bronze','student_vle_raw','BRONZE','bronze_student_vle_not_empty','Student VLE source was received','VOLUME',
           'Checks Bronze student_vle is not empty','At least one row must exist','>','0 rows',
           CASE WHEN b_student_vle_rows>0 THEN 'PASS' ELSE 'FAIL' END,'CRITICAL','More than 0 rows',
           CONCAT(CAST(b_student_vle_rows AS STRING),' rows received'),b_student_vle_rows,CASE WHEN b_student_vle_rows=0 THEN 1 ELSE 0 END,
           CASE WHEN b_student_vle_rows=0 THEN 100.0 ELSE 0.0 END,'Student VLE source must be present',map('volume_rule','NON_EMPTY') FROM metrics

    -- =========================================================================
    -- SILVER: COURSES
    -- =========================================================================
    UNION ALL
    SELECT 'oulad_silver','courses_clean','SILVER','silver_courses_required_keys','Silver courses required keys are complete','NULL',
           'Checks code_module and code_presentation','No required course key is NULL','=', '0 failed rows',
           CASE WHEN s_courses_null_keys=0 THEN 'PASS' ELSE 'FAIL' END,'CRITICAL','0 missing key rows',
           CONCAT(CAST(s_courses_null_keys AS STRING),' rows have missing keys'),s_courses_rows,s_courses_null_keys,
           CASE WHEN s_courses_rows=0 THEN NULL ELSE 100.0*s_courses_null_keys/s_courses_rows END,
           'Clean course keys must be complete',map('exception_policy','NONE') FROM metrics
    UNION ALL
    SELECT 'oulad_silver','courses_clean','SILVER','silver_courses_unique_key','Silver course key is unique','UNIQUE',
           'Checks one row per module + presentation','No duplicate clean course keys','=', '0 duplicate keys',
           CASE WHEN s_courses_dup_keys=0 THEN 'PASS' ELSE 'FAIL' END,'CRITICAL','0 duplicate keys',
           CONCAT(CAST(s_courses_dup_keys AS STRING),' duplicate keys'),s_courses_rows,s_courses_dup_keys,
           CASE WHEN s_courses_rows=0 THEN NULL ELSE 100.0*s_courses_dup_keys/s_courses_rows END,
           'Clean course grain must be unique',map('exception_policy','NONE') FROM metrics
    UNION ALL
    SELECT 'oulad_silver','courses_clean','SILVER','silver_courses_valid_length','Silver presentation length is valid','RANGE',
           'Checks module_presentation_length > 0','Length must be > 0','>','0',
           CASE WHEN s_courses_bad_length=0 THEN 'PASS' ELSE 'FAIL' END,'FAIL','0 invalid rows',
           CONCAT(CAST(s_courses_bad_length AS STRING),' invalid rows'),s_courses_rows,s_courses_bad_length,
           CASE WHEN s_courses_rows=0 THEN NULL ELSE 100.0*s_courses_bad_length/s_courses_rows END,
           'Invalid length is a material clean-data defect',map('exception_policy','NONE') FROM metrics
    UNION ALL
    SELECT 'oulad_silver','courses_clean','SILVER','courses_bronze_silver_reconciliation','Courses Bronze-to-Silver rows reconcile','VOLUME',
           'Checks Bronze rows equal clean + quarantined rows','silver + quarantine = bronze','=', '0 row difference',
           CASE WHEN s_courses_rows+s_courses_quarantined_rows=b_courses_rows THEN 'PASS' ELSE 'FAIL' END,'CRITICAL',
           CONCAT('Bronze rows: ',CAST(b_courses_rows AS STRING)),
           CONCAT('Silver: ',CAST(s_courses_rows AS STRING),'; quarantine: ',CAST(s_courses_quarantined_rows AS STRING)),
           1,CASE WHEN s_courses_rows+s_courses_quarantined_rows=b_courses_rows THEN 0 ELSE 1 END,
           CASE WHEN s_courses_rows+s_courses_quarantined_rows=b_courses_rows THEN 0.0 ELSE 100.0 END,
           'Course rows must be fully accounted for',map('comparison_scope','BRONZE_TO_SILVER') FROM metrics

    -- =========================================================================
    -- SILVER: ASSESSMENT
    -- =========================================================================
    UNION ALL
    SELECT 'oulad_silver','assessment_clean','SILVER','silver_assessment_required_fields','Silver assessment required fields are complete','NULL',
           'Checks required business and audit fields','Required fields must not be NULL','=', '0 failed rows',
           CASE WHEN s_assessment_required_nulls=0 THEN 'PASS' ELSE 'FAIL' END,'CRITICAL','0 missing required rows',
           CONCAT(CAST(s_assessment_required_nulls AS STRING),' rows have missing required fields'),s_assessment_rows,s_assessment_required_nulls,
           CASE WHEN s_assessment_rows=0 THEN NULL ELSE 100.0*s_assessment_required_nulls/s_assessment_rows END,
           'Optional assessment date is not treated as required',map('exception_policy','ASSESSMENT_DATE_OPTIONAL') FROM metrics
    UNION ALL
    SELECT 'oulad_silver','assessment_clean','SILVER','silver_assessment_unique_id','Silver assessment ID is unique','UNIQUE',
           'Checks one row per id_assessment','id_assessment must be unique','=', '0 duplicate IDs',
           CASE WHEN s_assessment_dup_keys=0 THEN 'PASS' ELSE 'FAIL' END,'CRITICAL','0 duplicate IDs',
           CONCAT(CAST(s_assessment_dup_keys AS STRING),' duplicate IDs'),s_assessment_rows,s_assessment_dup_keys,
           CASE WHEN s_assessment_rows=0 THEN NULL ELSE 100.0*s_assessment_dup_keys/s_assessment_rows END,
           'Duplicate assessment IDs are critical',map('exception_policy','NONE') FROM metrics
    UNION ALL
    SELECT 'oulad_silver','assessment_clean','SILVER','silver_assessment_weight_range','Silver assessment weight is valid','RANGE',
           'Checks non-NULL weight is 0..100','0 <= weight <= 100','BETWEEN','0 and 100',
           CASE WHEN s_assessment_bad_weight=0 THEN 'PASS' ELSE 'FAIL' END,'FAIL','0 out-of-range weights',
           CONCAT(CAST(s_assessment_bad_weight AS STRING),' invalid weights'),s_assessment_rows,s_assessment_bad_weight,
           CASE WHEN s_assessment_rows=0 THEN NULL ELSE 100.0*s_assessment_bad_weight/s_assessment_rows END,
           'Relative dates remain allowed to be negative',map('exception_policy','NEGATIVE_RELATIVE_DATES_ALLOWED') FROM metrics
    UNION ALL
    SELECT 'oulad_silver','assessment_clean','SILVER','silver_assessment_type_values','Silver assessment type is accepted','ACCEPTED_VALUES',
           'Checks TMA/CMA/Exam','assessment_type in TMA,CMA,Exam','IN','TMA|CMA|Exam',
           CASE WHEN s_assessment_bad_type=0 THEN 'PASS' ELSE 'FAIL' END,'FAIL','0 invalid types',
           CONCAT(CAST(s_assessment_bad_type AS STRING),' invalid types'),s_assessment_rows,s_assessment_bad_type,
           CASE WHEN s_assessment_rows=0 THEN NULL ELSE 100.0*s_assessment_bad_type/s_assessment_rows END,
           'Assessment category must be documented',map('exception_policy','NONE') FROM metrics
    UNION ALL
    SELECT 'oulad_silver','assessment_clean','SILVER','silver_assessment_course_reference','Silver assessment presentation exists in courses','REFERENTIAL_INTEGRITY',
           'Checks assessment presentation against Silver courses','No assessment orphans','=', '0 orphan rows',
           CASE WHEN s_assessment_course_orphans=0 THEN 'PASS' ELSE 'FAIL' END,'CRITICAL','0 orphan rows',
           CONCAT(CAST(s_assessment_course_orphans AS STRING),' orphan rows'),s_assessment_rows,s_assessment_course_orphans,
           CASE WHEN s_assessment_rows=0 THEN NULL ELSE 100.0*s_assessment_course_orphans/s_assessment_rows END,
           'Silver relationship failures are critical',map('exception_policy','NONE') FROM metrics
    UNION ALL
    SELECT 'oulad_silver','assessment_clean','SILVER','assessment_bronze_silver_row_reconciliation','Assessment rows reconcile','VOLUME',
           'Checks Bronze and Silver assessment row counts match','Bronze rows = Silver rows','=', '0 row difference',
           CASE WHEN b_assessment_rows=s_assessment_rows THEN 'PASS' ELSE 'FAIL' END,'CRITICAL',
           CONCAT('Bronze: ',CAST(b_assessment_rows AS STRING)),CONCAT('Silver: ',CAST(s_assessment_rows AS STRING)),1,
           CASE WHEN b_assessment_rows=s_assessment_rows THEN 0 ELSE 1 END,
           CASE WHEN b_assessment_rows=s_assessment_rows THEN 0.0 ELSE 100.0 END,
           'Assessment row preservation must reconcile',map('comparison_scope','BRONZE_TO_SILVER') FROM metrics

    -- =========================================================================
    -- SILVER: STUDENT ASSESSMENT
    -- =========================================================================
    UNION ALL
    SELECT 'oulad_silver','student_assessment_clean','SILVER','silver_student_assessment_required_fields','Silver student assessment required fields are complete','NULL',
           'Checks key and audit fields; score remains optional','Required fields present; score may be NULL','=', '0 failed rows',
           CASE WHEN s_student_assessment_required_nulls=0 THEN 'PASS' ELSE 'FAIL' END,'CRITICAL','0 missing required rows',
           CONCAT(CAST(s_student_assessment_required_nulls AS STRING),' rows have missing required fields'),s_student_assessment_rows,s_student_assessment_required_nulls,
           CASE WHEN s_student_assessment_rows=0 THEN NULL ELSE 100.0*s_student_assessment_required_nulls/s_student_assessment_rows END,
           'NULL scores are explicitly valid',map('exception_policy','NULL_SCORE_ALLOWED') FROM metrics
    UNION ALL
    SELECT 'oulad_silver','student_assessment_clean','SILVER','silver_student_assessment_null_scores_allowed','NULL assessment scores are valid','NULL',
           'Documents the known missing-score population without treating it as a failure','score may be NULL','N/A','NULL allowed',
           'PASS','WARN','NULL score rows are allowed',CONCAT(CAST(s_null_scores AS STRING),' rows have NULL score'),s_student_assessment_rows,0,0.0,
           'Known NULL assessment scores are preserved as valid data',map('exception_policy','NULL_SCORE_ALLOWED','observed_null_scores',CAST(s_null_scores AS STRING)) FROM metrics
    UNION ALL
    SELECT 'oulad_silver','student_assessment_clean','SILVER','silver_student_assessment_unique_key','Silver student assessment key is unique','UNIQUE',
           'Checks id_assessment + id_student','No duplicate result keys','=', '0 duplicate keys',
           CASE WHEN s_student_assessment_dup_keys=0 THEN 'PASS' ELSE 'FAIL' END,'CRITICAL','0 duplicate keys',
           CONCAT(CAST(s_student_assessment_dup_keys AS STRING),' duplicate keys'),s_student_assessment_rows,s_student_assessment_dup_keys,
           CASE WHEN s_student_assessment_rows=0 THEN NULL ELSE 100.0*s_student_assessment_dup_keys/s_student_assessment_rows END,
           'Clean result grain must be unique',map('exception_policy','NONE') FROM metrics
    UNION ALL
    SELECT 'oulad_silver','student_assessment_clean','SILVER','silver_student_assessment_score_range','Silver score is valid when present','RANGE',
           'Checks only non-NULL scores are 0..100','score is NULL or 0..100','BETWEEN','0 and 100 when non-NULL',
           CASE WHEN s_student_assessment_bad_score=0 THEN 'PASS' ELSE 'FAIL' END,'FAIL','0 invalid non-NULL scores',
           CONCAT(CAST(s_student_assessment_bad_score AS STRING),' invalid scores'),s_student_assessment_rows,s_student_assessment_bad_score,
           CASE WHEN s_student_assessment_rows=0 THEN NULL ELSE 100.0*s_student_assessment_bad_score/s_student_assessment_rows END,
           'NULL scores remain valid',map('exception_policy','NULL_SCORE_ALLOWED') FROM metrics
    UNION ALL
    SELECT 'oulad_silver','student_assessment_clean','SILVER','silver_student_assessment_is_banked','Silver is_banked is accepted','ACCEPTED_VALUES',
           'Checks is_banked in 0,1','is_banked in 0,1','IN','0|1',
           CASE WHEN s_student_assessment_bad_banked=0 THEN 'PASS' ELSE 'FAIL' END,'FAIL','0 invalid rows',
           CONCAT(CAST(s_student_assessment_bad_banked AS STRING),' invalid rows'),s_student_assessment_rows,s_student_assessment_bad_banked,
           CASE WHEN s_student_assessment_rows=0 THEN NULL ELSE 100.0*s_student_assessment_bad_banked/s_student_assessment_rows END,
           'Banked flag must be binary',map('exception_policy','NONE') FROM metrics
    UNION ALL
    SELECT 'oulad_silver','student_assessment_clean','SILVER','silver_student_assessment_parent','Silver student assessment has assessment parent','REFERENTIAL_INTEGRITY',
           'Checks id_assessment against assessment_clean','No orphan assessment references','=', '0 orphan rows',
           CASE WHEN s_student_assessment_orphans=0 THEN 'PASS' ELSE 'FAIL' END,'CRITICAL','0 orphan rows',
           CONCAT(CAST(s_student_assessment_orphans AS STRING),' orphan rows'),s_student_assessment_rows,s_student_assessment_orphans,
           CASE WHEN s_student_assessment_rows=0 THEN NULL ELSE 100.0*s_student_assessment_orphans/s_student_assessment_rows END,
           'Clean referential integrity is required',map('exception_policy','NONE') FROM metrics
    UNION ALL
    SELECT 'oulad_silver','student_assessment_clean','SILVER','student_assessment_bronze_silver_reconciliation','Student assessment rows and score totals reconcile','VOLUME',
           'Checks row preservation and non-NULL score sum preservation','Bronze rows = Silver rows and score sums match','=', '0 difference',
           CASE WHEN b_student_assessment_rows=s_student_assessment_rows AND b_score_sum <=> s_score_sum THEN 'PASS' ELSE 'FAIL' END,'CRITICAL',
           CONCAT('Bronze rows=',CAST(b_student_assessment_rows AS STRING),'; score sum=',CAST(b_score_sum AS STRING)),
           CONCAT('Silver rows=',CAST(s_student_assessment_rows AS STRING),'; score sum=',CAST(s_score_sum AS STRING)),1,
           CASE WHEN b_student_assessment_rows=s_student_assessment_rows AND b_score_sum <=> s_score_sum THEN 0 ELSE 1 END,
           CASE WHEN b_student_assessment_rows=s_student_assessment_rows AND b_score_sum <=> s_score_sum THEN 0.0 ELSE 100.0 END,
           'Rows and score totals must be preserved',map('comparison_scope','BRONZE_TO_SILVER','null_scores_allowed','true') FROM metrics

    -- =========================================================================
    -- SILVER: STUDENT INFO
    -- =========================================================================
    UNION ALL
    SELECT 'oulad_silver','student_info_clean','SILVER','silver_student_info_required_fields','Silver student info required fields are complete','NULL',
           'Checks enrollment keys and audit fields','Required fields must not be NULL','=', '0 failed rows',
           CASE WHEN s_student_info_required_nulls=0 THEN 'PASS' ELSE 'FAIL' END,'CRITICAL','0 missing required rows',
           CONCAT(CAST(s_student_info_required_nulls AS STRING),' rows have missing required fields'),s_student_info_rows,s_student_info_required_nulls,
           CASE WHEN s_student_info_rows=0 THEN NULL ELSE 100.0*s_student_info_required_nulls/s_student_info_rows END,
           'imd_band is optional and excluded',map('exception_policy','IMD_BAND_OPTIONAL') FROM metrics
    UNION ALL
    SELECT 'oulad_silver','student_info_clean','SILVER','silver_student_info_unique_key','Silver enrollment key is unique','UNIQUE',
           'Checks module + presentation + student','No duplicate enrollment keys','=', '0 duplicate keys',
           CASE WHEN s_student_info_dup_keys=0 THEN 'PASS' ELSE 'FAIL' END,'CRITICAL','0 duplicate keys',
           CONCAT(CAST(s_student_info_dup_keys AS STRING),' duplicate keys'),s_student_info_rows,s_student_info_dup_keys,
           CASE WHEN s_student_info_rows=0 THEN NULL ELSE 100.0*s_student_info_dup_keys/s_student_info_rows END,
           'Clean enrollment grain must be unique',map('exception_policy','NONE') FROM metrics
    UNION ALL
    SELECT 'oulad_silver','student_info_clean','SILVER','silver_student_info_numeric_ranges','Silver student numeric values are valid','RANGE',
           'Checks attempts and credits are nonnegative','attempts >=0 and credits >=0','>=','0',
           CASE WHEN s_student_info_bad_numeric=0 THEN 'PASS' ELSE 'FAIL' END,'FAIL','0 invalid rows',
           CONCAT(CAST(s_student_info_bad_numeric AS STRING),' invalid rows'),s_student_info_rows,s_student_info_bad_numeric,
           CASE WHEN s_student_info_rows=0 THEN NULL ELSE 100.0*s_student_info_bad_numeric/s_student_info_rows END,
           'Negative attempts or credits are invalid',map('exception_policy','NONE') FROM metrics
    UNION ALL
    SELECT 'oulad_silver','student_info_clean','SILVER','silver_student_info_final_result','Silver final_result is accepted','ACCEPTED_VALUES',
           'Checks documented outcome categories','final_result in Distinction,Fail,Pass,Withdrawn','IN','Distinction|Fail|Pass|Withdrawn',
           CASE WHEN s_student_info_bad_result=0 THEN 'PASS' ELSE 'FAIL' END,'FAIL','0 invalid rows',
           CONCAT(CAST(s_student_info_bad_result AS STRING),' invalid rows'),s_student_info_rows,s_student_info_bad_result,
           CASE WHEN s_student_info_rows=0 THEN NULL ELSE 100.0*s_student_info_bad_result/s_student_info_rows END,
           'Outcome categories must be documented',map('exception_policy','NONE') FROM metrics
    UNION ALL
    SELECT 'oulad_silver','student_info_clean','SILVER','silver_student_info_course_reference','Silver enrollment presentation exists in courses','REFERENTIAL_INTEGRITY',
           'Checks module/presentation against courses_clean','No orphan enrollments','=', '0 orphan rows',
           CASE WHEN s_student_info_orphans=0 THEN 'PASS' ELSE 'FAIL' END,'CRITICAL','0 orphan rows',
           CONCAT(CAST(s_student_info_orphans AS STRING),' orphan rows'),s_student_info_rows,s_student_info_orphans,
           CASE WHEN s_student_info_rows=0 THEN NULL ELSE 100.0*s_student_info_orphans/s_student_info_rows END,
           'Clean enrollment relationships are required',map('exception_policy','NONE') FROM metrics
    UNION ALL
    SELECT 'oulad_silver','student_info_clean','SILVER','student_info_bronze_silver_reconciliation','Student info rows reconcile','VOLUME',
           'Checks Bronze and Silver enrollment population matches','Bronze rows = Silver rows','=', '0 row difference',
           CASE WHEN b_student_info_rows=s_student_info_rows THEN 'PASS' ELSE 'FAIL' END,'CRITICAL',
           CONCAT('Bronze: ',CAST(b_student_info_rows AS STRING)),CONCAT('Silver: ',CAST(s_student_info_rows AS STRING)),1,
           CASE WHEN b_student_info_rows=s_student_info_rows THEN 0 ELSE 1 END,
           CASE WHEN b_student_info_rows=s_student_info_rows THEN 0.0 ELSE 100.0 END,
           'Enrollment population must be preserved',map('comparison_scope','BRONZE_TO_SILVER') FROM metrics

    -- =========================================================================
    -- SILVER: STUDENT REGISTRATION
    -- =========================================================================
    UNION ALL
    SELECT 'oulad_silver','student_registration_clean','SILVER','silver_student_registration_required_fields','Silver registration required fields are complete','NULL',
           'Checks keys and audit fields; date_registration is evaluated separately','Required key/audit fields must be present','=', '0 failed rows',
           CASE WHEN s_student_registration_required_nulls=0 THEN 'PASS' ELSE 'FAIL' END,'CRITICAL','0 missing required rows',
           CONCAT(CAST(s_student_registration_required_nulls AS STRING),' rows have missing required fields'),s_student_registration_rows,s_student_registration_required_nulls,
           CASE WHEN s_student_registration_rows=0 THEN NULL ELSE 100.0*s_student_registration_required_nulls/s_student_registration_rows END,
           'Known date_registration NULLs are not included here',map('exception_policy','REGISTRATION_DATE_WARN') FROM metrics
    UNION ALL
    SELECT 'oulad_silver','student_registration_clean','SILVER','silver_student_registration_missing_date_warning','Missing registration dates are a known warning','NULL',
           'Tracks NULL date_registration separately from required-key failures','0 preferred; up to the known 45 rows remain WARN','<=','45 warning rows',
           CASE WHEN s_missing_registration_dates=0 THEN 'PASS' WHEN s_missing_registration_dates<=45 THEN 'Review' ELSE 'Fail' END,
           CASE WHEN s_missing_registration_dates<=45 THEN 'WARN' ELSE 'FAIL' END,
           '0 preferred; 45 known source NULLs are tolerated as WARN',
           CONCAT(CAST(s_missing_registration_dates AS STRING),' NULL date_registration rows'),s_student_registration_rows,s_missing_registration_dates,
           CASE WHEN s_student_registration_rows=0 THEN NULL ELSE 100.0*s_missing_registration_dates/s_student_registration_rows END,
           'The known 45 missing registration dates must remain WARN, not PASS or critical FAIL',
           map('exception_policy','KNOWN_45_REGISTRATION_NULLS_WARN','known_count','45') FROM metrics
    UNION ALL
    SELECT 'oulad_silver','student_registration_clean','SILVER','silver_student_registration_unique_key','Silver registration key is unique','UNIQUE',
           'Checks module + presentation + student','No duplicate registration keys','=', '0 duplicate keys',
           CASE WHEN s_student_registration_dup_keys=0 THEN 'PASS' ELSE 'FAIL' END,'CRITICAL','0 duplicate keys',
           CONCAT(CAST(s_student_registration_dup_keys AS STRING),' duplicate keys'),s_student_registration_rows,s_student_registration_dup_keys,
           CASE WHEN s_student_registration_rows=0 THEN NULL ELSE 100.0*s_student_registration_dup_keys/s_student_registration_rows END,
           'Clean registration grain must be unique',map('exception_policy','NONE') FROM metrics
    UNION ALL
    SELECT 'oulad_silver','student_registration_clean','SILVER','silver_student_registration_negative_dates_allowed','Negative registration relative dates are valid','RANGE',
           'Documents that negative relative dates are valid offsets','Negative numeric dates are allowed','N/A','Negative relative dates allowed',
           'PASS','WARN','No failures solely from negative dates',CONCAT(CAST(s_registration_negative_dates AS STRING),' rows contain a negative relative date'),
           s_student_registration_rows,0,0.0,'Relative course dates are intentionally not constrained to >= 0',
           map('exception_policy','NEGATIVE_RELATIVE_DATES_ALLOWED') FROM metrics
    UNION ALL
    SELECT 'oulad_silver','student_registration_clean','SILVER','silver_student_registration_parent','Silver registration has student_info parent','REFERENTIAL_INTEGRITY',
           'Checks registration enrollment key against student_info_clean','No orphan registrations','=', '0 orphan rows',
           CASE WHEN s_student_registration_orphans=0 THEN 'PASS' ELSE 'FAIL' END,'CRITICAL','0 orphan rows',
           CONCAT(CAST(s_student_registration_orphans AS STRING),' orphan rows'),s_student_registration_rows,s_student_registration_orphans,
           CASE WHEN s_student_registration_rows=0 THEN NULL ELSE 100.0*s_student_registration_orphans/s_student_registration_rows END,
           'Clean registration relationship is required',map('exception_policy','NONE') FROM metrics
    UNION ALL
    SELECT 'oulad_silver','student_registration_clean','SILVER','student_registration_bronze_silver_reconciliation','Registration rows reconcile','VOLUME',
           'Checks Bronze and Silver registration populations match','Bronze rows = Silver rows','=', '0 row difference',
           CASE WHEN b_student_registration_rows=s_student_registration_rows THEN 'PASS' ELSE 'FAIL' END,'CRITICAL',
           CONCAT('Bronze: ',CAST(b_student_registration_rows AS STRING)),CONCAT('Silver: ',CAST(s_student_registration_rows AS STRING)),1,
           CASE WHEN b_student_registration_rows=s_student_registration_rows THEN 0 ELSE 1 END,
           CASE WHEN b_student_registration_rows=s_student_registration_rows THEN 0.0 ELSE 100.0 END,
           'Registration population must be preserved',map('comparison_scope','BRONZE_TO_SILVER','known_null_registration_dates','45') FROM metrics

    -- =========================================================================
    -- SILVER: VLE
    -- =========================================================================
    UNION ALL
    SELECT 'oulad_silver','vle_clean','SILVER','silver_vle_required_fields','Silver VLE required fields are complete','NULL',
           'Checks key and audit fields','No required field is NULL','=', '0 failed rows',
           CASE WHEN s_vle_required_nulls=0 THEN 'PASS' ELSE 'FAIL' END,'CRITICAL','0 missing required rows',
           CONCAT(CAST(s_vle_required_nulls AS STRING),' rows have missing required fields'),s_vle_rows,s_vle_required_nulls,
           CASE WHEN s_vle_rows=0 THEN NULL ELSE 100.0*s_vle_required_nulls/s_vle_rows END,
           'week_from/week_to remain optional',map('exception_policy','OPTIONAL_WEEKS') FROM metrics
    UNION ALL
    SELECT 'oulad_silver','vle_clean','SILVER','silver_vle_optional_week_profile','VLE optional week profile matches source','NULL',
           'Tracks rows where both week_from and week_to are NULL','Known profile is 5243 resources with both week bounds missing','=', '5243 rows',
           CASE WHEN s_vle_both_weeks_null=5243 THEN 'PASS' ELSE 'Review' END,'WARN','5243 known optional-NULL rows',
           CONCAT(CAST(s_vle_both_weeks_null AS STRING),' resources have both weeks NULL'),s_vle_rows,
           CASE WHEN s_vle_both_weeks_null=5243 THEN 0 ELSE ABS(s_vle_both_weeks_null-5243) END,
           CASE WHEN s_vle_rows=0 THEN NULL ELSE 100.0*ABS(s_vle_both_weeks_null-5243)/s_vle_rows END,
           'Historical REVIEW is normalized to WARN when the profile changes',map('legacy_status','REVIEW','known_count','5243') FROM metrics
    UNION ALL
    SELECT 'oulad_silver','vle_clean','SILVER','silver_vle_unique_key','Silver VLE key is unique','UNIQUE',
           'Checks module + presentation + site','No duplicate resource keys','=', '0 duplicate keys',
           CASE WHEN s_vle_dup_keys=0 THEN 'PASS' ELSE 'FAIL' END,'CRITICAL','0 duplicate keys',
           CONCAT(CAST(s_vle_dup_keys AS STRING),' duplicate keys'),s_vle_rows,s_vle_dup_keys,
           CASE WHEN s_vle_rows=0 THEN NULL ELSE 100.0*s_vle_dup_keys/s_vle_rows END,
           'Clean VLE resource grain must be unique',map('exception_policy','NONE') FROM metrics
    UNION ALL
    SELECT 'oulad_silver','vle_clean','SILVER','silver_vle_week_range','Silver VLE week range is valid','RANGE',
           'Uses is_valid_date_range produced by vle_clean','week_from <= week_to when both present','=', '0 invalid rows',
           CASE WHEN s_vle_bad_week_range=0 THEN 'PASS' ELSE 'FAIL' END,'FAIL','0 invalid rows',
           CONCAT(CAST(s_vle_bad_week_range AS STRING),' invalid rows'),s_vle_rows,s_vle_bad_week_range,
           CASE WHEN s_vle_rows=0 THEN NULL ELSE 100.0*s_vle_bad_week_range/s_vle_rows END,
           'Optional NULL weeks remain valid',map('exception_policy','OPTIONAL_WEEKS') FROM metrics
    UNION ALL
    SELECT 'oulad_silver','vle_clean','SILVER','silver_vle_course_reference','Silver VLE presentation exists in courses','REFERENTIAL_INTEGRITY',
           'Checks VLE resource against courses_clean','No orphan VLE resources','=', '0 orphan rows',
           CASE WHEN s_vle_orphans=0 THEN 'PASS' ELSE 'FAIL' END,'CRITICAL','0 orphan rows',
           CONCAT(CAST(s_vle_orphans AS STRING),' orphan rows'),s_vle_rows,s_vle_orphans,
           CASE WHEN s_vle_rows=0 THEN NULL ELSE 100.0*s_vle_orphans/s_vle_rows END,
           'Clean VLE relationship is required',map('exception_policy','NONE') FROM metrics
    UNION ALL
    SELECT 'oulad_silver','vle_clean','SILVER','vle_bronze_silver_key_reconciliation','VLE Bronze resource keys survive in Silver','VOLUME',
           'Checks Bronze VLE resources are represented in Silver','All valid Bronze VLE keys exist in Silver','=', '0 missing resource keys',
           CASE WHEN s_vle_rows>0 THEN 'PASS' ELSE 'FAIL' END,'CRITICAL','Silver contains VLE resources',
           CONCAT('Silver VLE rows: ',CAST(s_vle_rows AS STRING)),1,CASE WHEN s_vle_rows>0 THEN 0 ELSE 1 END,
           CASE WHEN s_vle_rows>0 THEN 0.0 ELSE 100.0 END,
           'Detailed key coverage remains enforced by 06_silver_reconciliation_checks.sql',map('comparison_scope','BRONZE_TO_SILVER') FROM metrics

    -- =========================================================================
    -- SILVER: STUDENT VLE
    -- =========================================================================
    UNION ALL
    SELECT 'oulad_silver','student_vle_clean','SILVER','silver_student_vle_required_fields','Silver Student VLE required fields are complete','NULL',
           'Checks five-key grain, sum_click and audit fields','No required field is NULL','=', '0 failed rows',
           CASE WHEN s_student_vle_required_nulls=0 THEN 'PASS' ELSE 'FAIL' END,'CRITICAL','0 missing required rows',
           CONCAT(CAST(s_student_vle_required_nulls AS STRING),' rows have missing required fields'),s_student_vle_rows,s_student_vle_required_nulls,
           CASE WHEN s_student_vle_rows=0 THEN NULL ELSE 100.0*s_student_vle_required_nulls/s_student_vle_rows END,
           'Negative relative dates are valid; NULL dates are not',map('exception_policy','NEGATIVE_RELATIVE_DATES_ALLOWED') FROM metrics
    UNION ALL
    SELECT 'oulad_silver','student_vle_clean','SILVER','silver_student_vle_unique_business_key','Silver Student VLE daily key is unique','UNIQUE',
           'Checks one row per module + presentation + student + site + date','All Bronze repeated daily keys must be aggregated away','=', '0 duplicate keys',
           CASE WHEN s_student_vle_dup_keys=0 THEN 'PASS' ELSE 'FAIL' END,'CRITICAL','0 duplicate keys',
           CONCAT(CAST(s_student_vle_dup_keys AS STRING),' duplicate keys remain'),s_student_vle_rows,s_student_vle_dup_keys,
           CASE WHEN s_student_vle_rows=0 THEN NULL ELSE 100.0*s_student_vle_dup_keys/s_student_vle_rows END,
           'Bronze duplicates are WARN; Silver duplicates are CRITICAL FAIL',map('exception_policy','BRONZE_DUPLICATES_WARN_ONLY') FROM metrics
    UNION ALL
    SELECT 'oulad_silver','student_vle_clean','SILVER','silver_student_vle_click_range','Silver Student VLE clicks are valid','RANGE',
           'Checks sum_click is nonnegative','sum_click >= 0','>=','0',
           CASE WHEN s_student_vle_bad_clicks=0 THEN 'PASS' ELSE 'FAIL' END,'FAIL','0 invalid click rows',
           CONCAT(CAST(s_student_vle_bad_clicks AS STRING),' invalid click rows'),s_student_vle_rows,s_student_vle_bad_clicks,
           CASE WHEN s_student_vle_rows=0 THEN NULL ELSE 100.0*s_student_vle_bad_clicks/s_student_vle_rows END,
           'Negative date values are deliberately excluded from this range check',map('exception_policy','NEGATIVE_RELATIVE_DATES_ALLOWED') FROM metrics
    UNION ALL
    SELECT 'oulad_silver','student_vle_clean','SILVER','silver_student_vle_negative_dates_allowed','Negative Student VLE relative dates are valid','RANGE',
           'Documents negative relative activity dates without failing them','Negative numeric dates are allowed','N/A','Negative relative dates allowed',
           'PASS','WARN','No failures solely from negative dates',CONCAT(CAST(s_student_vle_negative_dates AS STRING),' rows occur before presentation start'),
           s_student_vle_rows,0,0.0,'Pre-start activity is valid OULAD behavior',map('exception_policy','NEGATIVE_RELATIVE_DATES_ALLOWED') FROM metrics
    UNION ALL
    SELECT 'oulad_silver','student_vle_clean','SILVER','silver_student_vle_vle_reference','Silver Student VLE site exists in VLE','REFERENTIAL_INTEGRITY',
           'Checks module/presentation/site against vle_clean','No orphan site references','=', '0 orphan rows',
           CASE WHEN s_student_vle_vle_orphans=0 THEN 'PASS' ELSE 'FAIL' END,'CRITICAL','0 orphan rows',
           CONCAT(CAST(s_student_vle_vle_orphans AS STRING),' orphan rows'),s_student_vle_rows,s_student_vle_vle_orphans,
           CASE WHEN s_student_vle_rows=0 THEN NULL ELSE 100.0*s_student_vle_vle_orphans/s_student_vle_rows END,
           'Clean VLE site relationship is required',map('exception_policy','NONE') FROM metrics
    UNION ALL
    SELECT 'oulad_silver','student_vle_clean','SILVER','silver_student_vle_student_reference','Silver Student VLE student exists in student_info','REFERENTIAL_INTEGRITY',
           'Checks module/presentation/student against student_info_clean','No orphan student references','=', '0 orphan rows',
           CASE WHEN s_student_vle_student_orphans=0 THEN 'PASS' ELSE 'FAIL' END,'CRITICAL','0 orphan rows',
           CONCAT(CAST(s_student_vle_student_orphans AS STRING),' orphan rows'),s_student_vle_rows,s_student_vle_student_orphans,
           CASE WHEN s_student_vle_rows=0 THEN NULL ELSE 100.0*s_student_vle_student_orphans/s_student_vle_rows END,
           'Clean enrollment relationship is required',map('exception_policy','NONE') FROM metrics
    UNION ALL
    SELECT 'oulad_silver','student_vle_clean','SILVER','student_vle_bronze_silver_row_reconciliation','Student VLE aggregation reconciles source rows','VOLUME',
           'Checks Silver source_row_count fully accounts for Bronze physical rows','SUM(source_row_count) = Bronze row count','=', '0 row difference',
           CASE WHEN s_student_vle_accounted_rows=b_student_vle_rows THEN 'PASS' ELSE 'FAIL' END,'CRITICAL',
           CONCAT('Bronze physical rows: ',CAST(b_student_vle_rows AS STRING)),
           CONCAT('Silver accounted source rows: ',CAST(s_student_vle_accounted_rows AS STRING)),1,
           CASE WHEN s_student_vle_accounted_rows=b_student_vle_rows THEN 0 ELSE 1 END,
           CASE WHEN s_student_vle_accounted_rows=b_student_vle_rows THEN 0.0 ELSE 100.0 END,
           'All Bronze duplicates must be explained by Silver aggregation',map('comparison_scope','BRONZE_TO_SILVER','bronze_duplicate_policy','WARN') FROM metrics
    UNION ALL
    SELECT 'oulad_silver','student_vle_clean','SILVER','student_vle_bronze_silver_click_reconciliation','Student VLE total clicks are preserved','VOLUME',
           'Checks Bronze and Silver total clicks match','Bronze SUM(sum_click) = Silver SUM(sum_click)','=', '0 click difference',
           CASE WHEN b_student_vle_clicks <=> s_student_vle_clicks THEN 'PASS' ELSE 'FAIL' END,'CRITICAL',
           CONCAT('Bronze clicks: ',CAST(b_student_vle_clicks AS STRING)),
           CONCAT('Silver clicks: ',CAST(s_student_vle_clicks AS STRING)),1,
           CASE WHEN b_student_vle_clicks <=> s_student_vle_clicks THEN 0 ELSE 1 END,
           CASE WHEN b_student_vle_clicks <=> s_student_vle_clicks THEN 0.0 ELSE 100.0 END,
           'Click preservation is the critical gate behind tolerated Bronze duplicates',map('comparison_scope','BRONZE_TO_SILVER') FROM metrics
),
normalized AS (
    SELECT
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
        CASE
            WHEN UPPER(TRIM(raw_status)) IN ('PASS','PASSED') THEN 'PASS'
            WHEN UPPER(TRIM(raw_status)) IN ('REVIEW','WARN','WARNING') THEN 'WARN'
            WHEN UPPER(TRIM(raw_status)) IN ('FAIL','FAILED') THEN 'FAIL'
            WHEN UPPER(TRIM(raw_status)) IN ('NOT_APPLICABLE','NOT APPLICABLE','N/A') THEN 'NOT_APPLICABLE'
            ELSE 'FAIL'
        END AS status,
        severity,
        expected_result,
        actual_result,
        CAST(total_count AS BIGINT) AS total_count,
        CAST(fail_count AS BIGINT) AS fail_count,
        CAST(fail_pct AS DECIMAL(9,6)) AS fail_pct,
        message,
        result_metadata
    FROM raw_results
)
SELECT
    SHA2(CONCAT_WS('||', dq_run_id, 'open_university', dataset_schema, dataset_table, check_id), 256) AS check_result_id,
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
    (status = 'FAIL' AND severity = 'CRITICAL') AS stop_pipeline,
    'Data Engineering' AS check_owner,
    expected_result,
    actual_result,
    total_count,
    fail_count,
    fail_pct,
    message,
    'tests/07_master_standardized_results.sql' AS query_reference,
    result_metadata
FROM normalized;

-- Idempotent check-result write. Retrying with the same dq_run_id updates the
-- same result grain instead of appending duplicates.
MERGE INTO open_university.oulad_quality.data_quality_results AS target
USING dq_master_standardized_results AS source
ON target.run_id = source.run_id
AND target.dataset_catalog = source.dataset_catalog
AND target.dataset_schema = source.dataset_schema
AND target.dataset_table = source.dataset_table
AND target.check_id = source.check_id
WHEN MATCHED THEN UPDATE SET *
WHEN NOT MATCHED THEN INSERT *;

-- =============================================================================
-- 2. FAILED-ROW / FAILED-KEY DETAILS
-- =============================================================================

CREATE OR REPLACE TEMP VIEW dq_master_standardized_failures AS
WITH raw_failures AS (
    -- -------------------------------------------------------------------------
    -- Known WARN exception: 45 missing registration dates.
    -- -------------------------------------------------------------------------
    SELECT
        'oulad_silver' AS dataset_schema,
        'student_registration_clean' AS dataset_table,
        'SILVER' AS dataset_layer,
        'silver_student_registration_missing_date_warning' AS check_id,
        'NULL' AS check_type,
        'WARN' AS severity,
        TO_JSON(NAMED_STRUCT('code_module',code_module,'code_presentation',code_presentation,'id_student',id_student)) AS failed_key,
        TO_JSON(NAMED_STRUCT('date_registration',date_registration,'date_unregistration',date_unregistration), MAP('ignoreNullFields','false')) AS failed_record_json,
        'date_registration' AS failed_column,
        'Non-NULL preferred; up to 45 known NULLs classified WARN' AS expected_value,
        'NULL' AS actual_value,
        'Known missing registration date retained as warning' AS failure_message,
        map('exception_policy','KNOWN_45_REGISTRATION_NULLS_WARN') AS failure_metadata
    FROM open_university.oulad_silver.student_registration_clean
    WHERE date_registration IS NULL

    UNION ALL

    -- Bronze student_vle duplicate keys are warnings, not hard failures.
    SELECT
        'oulad_bronze','student_vle_raw','BRONZE','bronze_student_vle_unique_business_key','UNIQUE','WARN',
        TO_JSON(NAMED_STRUCT(
            'code_module',code_module,'code_presentation',code_presentation,
            'id_student',id_student,'id_site',id_site,'date',date
        )),
        CAST(NULL AS STRING),'business_key','One physical row preferred',
        CONCAT(CAST(COUNT(*) AS STRING),' physical rows'),
        'Repeated Bronze daily key is expected to be aggregated in Silver',
        map('exception_policy','BRONZE_DUPLICATES_WARN','duplicate_count',CAST(COUNT(*) AS STRING))
    FROM open_university.oulad_bronze.student_vle_raw
    GROUP BY code_module,code_presentation,id_student,id_site,date
    HAVING COUNT(*) > 1

    UNION ALL

    -- -------------------------------------------------------------------------
    -- Silver duplicate-key details for all seven datasets.
    -- -------------------------------------------------------------------------
    SELECT 'oulad_silver','courses_clean','SILVER','silver_courses_unique_key','UNIQUE','CRITICAL',
           TO_JSON(NAMED_STRUCT('code_module',code_module,'code_presentation',code_presentation)),NULL,'business_key','Exactly one row',
           CONCAT(CAST(COUNT(*) AS STRING),' rows'),'Duplicate Silver course key',map('duplicate_count',CAST(COUNT(*) AS STRING))
    FROM open_university.oulad_silver.courses_clean GROUP BY code_module,code_presentation HAVING COUNT(*)>1

    UNION ALL
    SELECT 'oulad_silver','assessment_clean','SILVER','silver_assessment_unique_id','UNIQUE','CRITICAL',
           TO_JSON(NAMED_STRUCT('id_assessment',id_assessment)),NULL,'id_assessment','Exactly one row',
           CONCAT(CAST(COUNT(*) AS STRING),' rows'),'Duplicate Silver assessment ID',map('duplicate_count',CAST(COUNT(*) AS STRING))
    FROM open_university.oulad_silver.assessment_clean GROUP BY id_assessment HAVING COUNT(*)>1

    UNION ALL
    SELECT 'oulad_silver','student_assessment_clean','SILVER','silver_student_assessment_unique_key','UNIQUE','CRITICAL',
           TO_JSON(NAMED_STRUCT('id_assessment',id_assessment,'id_student',id_student)),NULL,'business_key','Exactly one row',
           CONCAT(CAST(COUNT(*) AS STRING),' rows'),'Duplicate Silver student-assessment key',map('duplicate_count',CAST(COUNT(*) AS STRING))
    FROM open_university.oulad_silver.student_assessment_clean GROUP BY id_assessment,id_student HAVING COUNT(*)>1

    UNION ALL
    SELECT 'oulad_silver','student_info_clean','SILVER','silver_student_info_unique_key','UNIQUE','CRITICAL',
           TO_JSON(NAMED_STRUCT('code_module',code_module,'code_presentation',code_presentation,'id_student',id_student)),NULL,'business_key','Exactly one row',
           CONCAT(CAST(COUNT(*) AS STRING),' rows'),'Duplicate Silver enrollment key',map('duplicate_count',CAST(COUNT(*) AS STRING))
    FROM open_university.oulad_silver.student_info_clean GROUP BY code_module,code_presentation,id_student HAVING COUNT(*)>1

    UNION ALL
    SELECT 'oulad_silver','student_registration_clean','SILVER','silver_student_registration_unique_key','UNIQUE','CRITICAL',
           TO_JSON(NAMED_STRUCT('code_module',code_module,'code_presentation',code_presentation,'id_student',id_student)),NULL,'business_key','Exactly one row',
           CONCAT(CAST(COUNT(*) AS STRING),' rows'),'Duplicate Silver registration key',map('duplicate_count',CAST(COUNT(*) AS STRING))
    FROM open_university.oulad_silver.student_registration_clean GROUP BY code_module,code_presentation,id_student HAVING COUNT(*)>1

    UNION ALL
    SELECT 'oulad_silver','vle_clean','SILVER','silver_vle_unique_key','UNIQUE','CRITICAL',
           TO_JSON(NAMED_STRUCT('code_module',code_module,'code_presentation',code_presentation,'id_site',id_site)),NULL,'business_key','Exactly one row',
           CONCAT(CAST(COUNT(*) AS STRING),' rows'),'Duplicate Silver VLE resource key',map('duplicate_count',CAST(COUNT(*) AS STRING))
    FROM open_university.oulad_silver.vle_clean GROUP BY code_module,code_presentation,id_site HAVING COUNT(*)>1

    UNION ALL
    SELECT 'oulad_silver','student_vle_clean','SILVER','silver_student_vle_unique_business_key','UNIQUE','CRITICAL',
           TO_JSON(NAMED_STRUCT('code_module',code_module,'code_presentation',code_presentation,'id_student',id_student,'id_site',id_site,'date',date)),NULL,
           'business_key','Exactly one aggregated row',CONCAT(CAST(COUNT(*) AS STRING),' rows'),'Duplicate daily key remains after Silver aggregation',
           map('duplicate_count',CAST(COUNT(*) AS STRING))
    FROM open_university.oulad_silver.student_vle_clean
    GROUP BY code_module,code_presentation,id_student,id_site,date HAVING COUNT(*)>1

    UNION ALL

    -- -------------------------------------------------------------------------
    -- Silver value failures. NULL student assessment scores are intentionally
    -- excluded; negative relative dates are intentionally excluded.
    -- -------------------------------------------------------------------------
    SELECT 'oulad_silver','courses_clean','SILVER','silver_courses_valid_length','RANGE','FAIL',
           TO_JSON(NAMED_STRUCT('code_module',code_module,'code_presentation',code_presentation)),
           TO_JSON(NAMED_STRUCT('module_presentation_length',module_presentation_length),MAP('ignoreNullFields','false')),
           'module_presentation_length','> 0',COALESCE(CAST(module_presentation_length AS STRING),'NULL'),'Invalid Silver course length',map()
    FROM open_university.oulad_silver.courses_clean
    WHERE module_presentation_length IS NULL OR module_presentation_length<=0

    UNION ALL
    SELECT 'oulad_silver','assessment_clean','SILVER','silver_assessment_weight_range','RANGE','FAIL',
           TO_JSON(NAMED_STRUCT('id_assessment',id_assessment)),TO_JSON(NAMED_STRUCT('weight',weight),MAP('ignoreNullFields','false')),
           'weight','0..100',COALESCE(CAST(weight AS STRING),'NULL'),'Assessment weight is outside 0..100',map()
    FROM open_university.oulad_silver.assessment_clean
    WHERE weight IS NOT NULL AND (weight<0 OR weight>100)

    UNION ALL
    SELECT 'oulad_silver','assessment_clean','SILVER','silver_assessment_type_values','ACCEPTED_VALUES','FAIL',
           TO_JSON(NAMED_STRUCT('id_assessment',id_assessment)),TO_JSON(NAMED_STRUCT('assessment_type',assessment_type),MAP('ignoreNullFields','false')),
           'assessment_type','TMA|CMA|Exam',COALESCE(assessment_type,'NULL'),'Invalid assessment type',map()
    FROM open_university.oulad_silver.assessment_clean
    WHERE assessment_type IS NULL OR assessment_type NOT IN ('TMA','CMA','Exam')

    UNION ALL
    SELECT 'oulad_silver','student_assessment_clean','SILVER','silver_student_assessment_score_range','RANGE','FAIL',
           TO_JSON(NAMED_STRUCT('id_assessment',id_assessment,'id_student',id_student)),TO_JSON(NAMED_STRUCT('score',score),MAP('ignoreNullFields','false')),
           'score','NULL or 0..100',CAST(score AS STRING),'Non-NULL score is outside 0..100',map('exception_policy','NULL_SCORE_ALLOWED')
    FROM open_university.oulad_silver.student_assessment_clean
    WHERE score IS NOT NULL AND (score<0 OR score>100)

    UNION ALL
    SELECT 'oulad_silver','student_assessment_clean','SILVER','silver_student_assessment_is_banked','ACCEPTED_VALUES','FAIL',
           TO_JSON(NAMED_STRUCT('id_assessment',id_assessment,'id_student',id_student)),TO_JSON(NAMED_STRUCT('is_banked',is_banked),MAP('ignoreNullFields','false')),
           'is_banked','0 or 1',COALESCE(CAST(is_banked AS STRING),'NULL'),'Invalid is_banked value',map()
    FROM open_university.oulad_silver.student_assessment_clean
    WHERE is_banked IS NULL OR is_banked NOT IN (0,1)

    UNION ALL
    SELECT 'oulad_silver','student_info_clean','SILVER','silver_student_info_numeric_ranges','RANGE','FAIL',
           TO_JSON(NAMED_STRUCT('code_module',code_module,'code_presentation',code_presentation,'id_student',id_student)),
           TO_JSON(NAMED_STRUCT('num_of_prev_attempts',num_of_prev_attempts,'studied_credits',studied_credits),MAP('ignoreNullFields','false')),
           'num_of_prev_attempts/studied_credits','Both >= 0',CONCAT('attempts=',COALESCE(CAST(num_of_prev_attempts AS STRING),'NULL'),'; credits=',COALESCE(CAST(studied_credits AS STRING),'NULL')),
           'Invalid enrollment numeric value',map()
    FROM open_university.oulad_silver.student_info_clean
    WHERE num_of_prev_attempts IS NULL OR num_of_prev_attempts<0 OR studied_credits IS NULL OR studied_credits<0

    UNION ALL
    SELECT 'oulad_silver','student_info_clean','SILVER','silver_student_info_final_result','ACCEPTED_VALUES','FAIL',
           TO_JSON(NAMED_STRUCT('code_module',code_module,'code_presentation',code_presentation,'id_student',id_student)),
           TO_JSON(NAMED_STRUCT('final_result',final_result),MAP('ignoreNullFields','false')),
           'final_result','Distinction|Fail|Pass|Withdrawn',COALESCE(final_result,'NULL'),'Invalid final_result',map()
    FROM open_university.oulad_silver.student_info_clean
    WHERE final_result IS NULL OR final_result NOT IN ('Distinction','Fail','Pass','Withdrawn')

    UNION ALL
    SELECT 'oulad_silver','vle_clean','SILVER','silver_vle_week_range','RANGE','FAIL',
           TO_JSON(NAMED_STRUCT('code_module',code_module,'code_presentation',code_presentation,'id_site',id_site)),
           TO_JSON(NAMED_STRUCT('week_from',week_from,'week_to',week_to),MAP('ignoreNullFields','false')),
           'week_from/week_to','week_from <= week_to when both present',CONCAT('week_from=',COALESCE(CAST(week_from AS STRING),'NULL'),'; week_to=',COALESCE(CAST(week_to AS STRING),'NULL')),
           'Invalid VLE week range',map('exception_policy','OPTIONAL_WEEKS')
    FROM open_university.oulad_silver.vle_clean WHERE is_valid_date_range=FALSE

    UNION ALL
    SELECT 'oulad_silver','student_vle_clean','SILVER','silver_student_vle_click_range','RANGE','FAIL',
           TO_JSON(NAMED_STRUCT('code_module',code_module,'code_presentation',code_presentation,'id_student',id_student,'id_site',id_site,'date',date)),
           TO_JSON(NAMED_STRUCT('sum_click',sum_click),MAP('ignoreNullFields','false')),
           'sum_click','>= 0',COALESCE(CAST(sum_click AS STRING),'NULL'),'Invalid Silver click value',map('exception_policy','NEGATIVE_RELATIVE_DATES_ALLOWED')
    FROM open_university.oulad_silver.student_vle_clean WHERE sum_click IS NULL OR sum_click<0

    UNION ALL

    -- -------------------------------------------------------------------------
    -- Silver relationship failures.
    -- -------------------------------------------------------------------------
    SELECT 'oulad_silver','assessment_clean','SILVER','silver_assessment_course_reference','REFERENTIAL_INTEGRITY','CRITICAL',
           TO_JSON(NAMED_STRUCT('code_module',a.code_module,'code_presentation',a.code_presentation,'id_assessment',a.id_assessment)),NULL,'business_key',
           'Matching row in courses_clean','No matching course','Assessment references a missing course presentation',map('parent_dataset','open_university.oulad_silver.courses_clean')
    FROM open_university.oulad_silver.assessment_clean a
    LEFT JOIN open_university.oulad_silver.courses_clean c
      ON a.code_module=c.code_module AND a.code_presentation=c.code_presentation
    WHERE c.code_module IS NULL

    UNION ALL
    SELECT 'oulad_silver','student_assessment_clean','SILVER','silver_student_assessment_parent','REFERENTIAL_INTEGRITY','CRITICAL',
           TO_JSON(NAMED_STRUCT('id_assessment',sa.id_assessment,'id_student',sa.id_student)),NULL,'id_assessment',
           'Matching row in assessment_clean','No matching assessment','Student assessment references a missing assessment',map('parent_dataset','open_university.oulad_silver.assessment_clean')
    FROM open_university.oulad_silver.student_assessment_clean sa
    LEFT JOIN open_university.oulad_silver.assessment_clean a ON sa.id_assessment=a.id_assessment
    WHERE a.id_assessment IS NULL

    UNION ALL
    SELECT 'oulad_silver','student_info_clean','SILVER','silver_student_info_course_reference','REFERENTIAL_INTEGRITY','CRITICAL',
           TO_JSON(NAMED_STRUCT('code_module',si.code_module,'code_presentation',si.code_presentation,'id_student',si.id_student)),NULL,'business_key',
           'Matching row in courses_clean','No matching course','Student enrollment references a missing course presentation',map('parent_dataset','open_university.oulad_silver.courses_clean')
    FROM open_university.oulad_silver.student_info_clean si
    LEFT JOIN open_university.oulad_silver.courses_clean c
      ON si.code_module=c.code_module AND si.code_presentation=c.code_presentation
    WHERE c.code_module IS NULL

    UNION ALL
    SELECT 'oulad_silver','student_registration_clean','SILVER','silver_student_registration_parent','REFERENTIAL_INTEGRITY','CRITICAL',
           TO_JSON(NAMED_STRUCT('code_module',sr.code_module,'code_presentation',sr.code_presentation,'id_student',sr.id_student)),NULL,'business_key',
           'Matching row in student_info_clean','No matching enrollment','Registration references a missing student enrollment',map('parent_dataset','open_university.oulad_silver.student_info_clean')
    FROM open_university.oulad_silver.student_registration_clean sr
    LEFT JOIN open_university.oulad_silver.student_info_clean si
      ON sr.code_module=si.code_module AND sr.code_presentation=si.code_presentation AND sr.id_student=si.id_student
    WHERE si.id_student IS NULL

    UNION ALL
    SELECT 'oulad_silver','vle_clean','SILVER','silver_vle_course_reference','REFERENTIAL_INTEGRITY','CRITICAL',
           TO_JSON(NAMED_STRUCT('code_module',v.code_module,'code_presentation',v.code_presentation,'id_site',v.id_site)),NULL,'business_key',
           'Matching row in courses_clean','No matching course','VLE resource references a missing course presentation',map('parent_dataset','open_university.oulad_silver.courses_clean')
    FROM open_university.oulad_silver.vle_clean v
    LEFT JOIN open_university.oulad_silver.courses_clean c
      ON v.code_module=c.code_module AND v.code_presentation=c.code_presentation
    WHERE c.code_module IS NULL

    UNION ALL
    SELECT 'oulad_silver','student_vle_clean','SILVER','silver_student_vle_vle_reference','REFERENTIAL_INTEGRITY','CRITICAL',
           TO_JSON(NAMED_STRUCT('code_module',sv.code_module,'code_presentation',sv.code_presentation,'id_student',sv.id_student,'id_site',sv.id_site,'date',sv.date)),NULL,
           'business_key','Matching site in vle_clean','No matching VLE site','Student VLE interaction references a missing VLE resource',map('parent_dataset','open_university.oulad_silver.vle_clean')
    FROM open_university.oulad_silver.student_vle_clean sv
    LEFT JOIN open_university.oulad_silver.vle_clean v
      ON sv.code_module=v.code_module AND sv.code_presentation=v.code_presentation AND sv.id_site=v.id_site
    WHERE v.id_site IS NULL

    UNION ALL
    SELECT 'oulad_silver','student_vle_clean','SILVER','silver_student_vle_student_reference','REFERENTIAL_INTEGRITY','CRITICAL',
           TO_JSON(NAMED_STRUCT('code_module',sv.code_module,'code_presentation',sv.code_presentation,'id_student',sv.id_student,'id_site',sv.id_site,'date',sv.date)),NULL,
           'business_key','Matching enrollment in student_info_clean','No matching enrollment','Student VLE interaction references a missing student enrollment',map('parent_dataset','open_university.oulad_silver.student_info_clean')
    FROM open_university.oulad_silver.student_vle_clean sv
    LEFT JOIN open_university.oulad_silver.student_info_clean si
      ON sv.code_module=si.code_module AND sv.code_presentation=si.code_presentation AND sv.id_student=si.id_student
    WHERE si.id_student IS NULL

    UNION ALL

    -- -------------------------------------------------------------------------
    -- Dataset-level reconciliation/volume failures use a synthetic key because
    -- there is no single source row that represents the mismatch.
    -- -------------------------------------------------------------------------
    SELECT dataset_schema,dataset_table,dataset_layer,check_id,check_type,severity,
           '__DATASET_TOTAL__' AS failed_key,NULL AS failed_record_json,'dataset_total' AS failed_column,
           expected_result AS expected_value,actual_result AS actual_value,message AS failure_message,
           map('synthetic_failure','true') AS failure_metadata
    FROM dq_master_standardized_results
    WHERE status='FAIL' AND check_type='VOLUME'
),
identified AS (
    SELECT
        SHA2(CONCAT_WS('||',dq_run_id,'open_university',dataset_schema,dataset_table,check_id,failed_key),256) AS failure_id,
        SHA2(CONCAT_WS('||',dq_run_id,'open_university',dataset_schema,dataset_table,check_id),256) AS check_result_id,
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

-- Idempotent failure write.
MERGE INTO open_university.oulad_quality.data_quality_failures AS target
USING dq_master_standardized_failures AS source
ON target.failure_id = source.failure_id
WHEN MATCHED THEN UPDATE SET *
WHEN NOT MATCHED THEN INSERT *;

-- Publish only after both writes finish successfully.
UPDATE open_university.oulad_quality.data_quality_results
SET run_completed_at = current_timestamp()
WHERE run_id = dq_run_id
  AND run_completed_at IS NULL;

-- =============================================================================
-- 3. RUN OUTPUTS
-- =============================================================================

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

SELECT
    run_id,
    dataset_layer,
    dataset_table,
    check_type,
    check_id,
    severity,
    failed_key,
    failed_column,
    expected_value,
    actual_value,
    failure_message
FROM open_university.oulad_quality.data_quality_failures
WHERE run_id = dq_run_id
ORDER BY dataset_layer, dataset_table, check_type, check_id, failed_key
LIMIT 500;
