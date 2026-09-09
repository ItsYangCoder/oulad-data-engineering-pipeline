-- File: 03_silver_null_checks.sql
-- Suggested branch: feature/add-silver-checks
-- For checks tied to one transformation, use that transformation's branch instead.
-- Purpose: Separate valid missing optional values from unexpected missing data.
-- Status: Implementation pending. Replace this guide with the finished code.
-- Input: All Silver tables, plus the documented source missing-value results.
-- Output: Read-only validation queries with failure counts/details and stated expected results; no data
--    changes.
--
-- What to put in this file:
-- 1. Check required keys, clean_load_timestamp and clean_load_date for NULL; compare typed values
--    against non-missing Bronze inputs to detect failed conversions.
-- 2. Report expected optional NULLs: 1,111 imd_band; 45 date_registration; 22,521 date_unregistration;
--    5,243 each week_from/week_to.
-- 3. Report 11 assessment dates missing only for Exam and 173 scores missing only for TMA.
-- 4. Join the proper assessment/enrollment context using full keys; do not fail a table merely because
--    these documented optional values are NULL.
--
-- Use this file for manual Databricks checks. A runner must explicitly fail on violations; a displayed
--    result alone is not an automated test.
--
-- Done when: No unexpected required NULLs or unexplained conversion losses; optional NULL counts match
--    the current-batch baseline.
-- Read: docs/pipeline_plan.md and docs/assumptions.md.

-- File: 03_silver_null_checks.sql
-- Purpose: Validate required NULLs, expected optional NULLs, and conversion losses
--          for vle_clean and student_vle_clean.
-- Input:
--   open_university.oulad_bronze.vle_raw
--   open_university.oulad_bronze.student_vle_raw
--   open_university.oulad_silver.vle_clean
--   open_university.oulad_silver.student_vle_clean
-- Output: Read-only validation queries only; no data changes.
--
-- Expected:
--   No unexpected required NULLs
--   No failed numeric conversions from non-missing Bronze values
--   vle_clean preserves documented optional week NULLs

-- =============================================================================
-- SECTION A: VLE_CLEAN NULL / CONVERSION CHECKS
-- =============================================================================

-- File: 03_silver_null_checks_vle.sql
-- Purpose: Separate expected optional NULLs from unexpected missing/failed values in vle_clean.
-- Inputs:
--   open_university.oulad_bronze.vle_raw
--   open_university.oulad_silver.vle_clean
-- Output: Read-only validation queries only; no data changes.
--
-- Expected current-batch baseline:
--   Required business-key NULLs = 0
--   Audit-column NULLs = 0
--   Failed numeric conversions from non-missing Bronze inputs = 0
--   week_from NULL count = 5243
--   week_to NULL count = 5243
--
-- Important:
--   NULL week_from/week_to values are valid optional values.
--   They mean the source does not specify an availability period.


-- =============================================================================
-- 1. REQUIRED SILVER VALUES AND AUDIT COLUMNS
-- Expected: all failure_rows = 0
-- =============================================================================

SELECT 'code_module NULL' AS check_name, COUNT(*) AS failure_rows
FROM open_university.oulad_silver.vle_clean
WHERE code_module IS NULL

UNION ALL

SELECT 'code_presentation NULL' AS check_name, COUNT(*) AS failure_rows
FROM open_university.oulad_silver.vle_clean
WHERE code_presentation IS NULL

UNION ALL

SELECT 'id_site NULL' AS check_name, COUNT(*) AS failure_rows
FROM open_university.oulad_silver.vle_clean
WHERE id_site IS NULL

UNION ALL

SELECT 'clean_load_timestamp NULL' AS check_name, COUNT(*) AS failure_rows
FROM open_university.oulad_silver.vle_clean
WHERE clean_load_timestamp IS NULL

UNION ALL

SELECT 'clean_load_date NULL' AS check_name, COUNT(*) AS failure_rows
FROM open_university.oulad_silver.vle_clean
WHERE clean_load_date IS NULL;


-- =============================================================================
-- 2. DETAILS: UNEXPECTED REQUIRED NULLS
-- Expected: 0 rows
-- =============================================================================

SELECT *
FROM open_university.oulad_silver.vle_clean
WHERE code_module IS NULL
   OR code_presentation IS NULL
   OR id_site IS NULL
   OR clean_load_timestamp IS NULL
   OR clean_load_date IS NULL
ORDER BY code_module, code_presentation, id_site;


-- =============================================================================
-- 3. EXPECTED OPTIONAL NULLS IN SILVER
-- Expected:
--   week_from_null_rows = 5243
--   week_to_null_rows   = 5243
--   both_weeks_null_rows = 5243
-- =============================================================================

SELECT
    SUM(CASE WHEN week_from IS NULL THEN 1 ELSE 0 END) AS week_from_null_rows,
    SUM(CASE WHEN week_to IS NULL THEN 1 ELSE 0 END) AS week_to_null_rows,
    SUM(
        CASE
            WHEN week_from IS NULL AND week_to IS NULL THEN 1
            ELSE 0
        END
    ) AS both_weeks_null_rows
FROM open_university.oulad_silver.vle_clean;


-- =============================================================================
-- 4. BRONZE NUMERIC-CONVERSION CHECK
-- Detect non-missing source text that TRY_CAST cannot convert.
-- Expected: all failure_rows = 0
-- =============================================================================

WITH bronze_standardized AS (
    SELECT
        CASE
            WHEN TRIM(CAST(id_site AS STRING)) IS NULL
              OR UPPER(TRIM(CAST(id_site AS STRING))) IN ('?', '', 'NA', 'N/A', 'NULL')
            THEN NULL
            ELSE TRIM(CAST(id_site AS STRING))
        END AS id_site_text,

        CASE
            WHEN TRIM(CAST(week_from AS STRING)) IS NULL
              OR UPPER(TRIM(CAST(week_from AS STRING))) IN ('?', '', 'NA', 'N/A', 'NULL')
            THEN NULL
            ELSE TRIM(CAST(week_from AS STRING))
        END AS week_from_text,

        CASE
            WHEN TRIM(CAST(week_to AS STRING)) IS NULL
              OR UPPER(TRIM(CAST(week_to AS STRING))) IN ('?', '', 'NA', 'N/A', 'NULL')
            THEN NULL
            ELSE TRIM(CAST(week_to AS STRING))
        END AS week_to_text
    FROM open_university.oulad_bronze.vle_raw
)

SELECT
    'id_site failed BIGINT conversion' AS check_name,
    COUNT(*) AS failure_rows
FROM bronze_standardized
WHERE id_site_text IS NOT NULL
  AND TRY_CAST(id_site_text AS BIGINT) IS NULL

UNION ALL

SELECT
    'week_from failed INT conversion' AS check_name,
    COUNT(*) AS failure_rows
FROM bronze_standardized
WHERE week_from_text IS NOT NULL
  AND TRY_CAST(week_from_text AS INT) IS NULL

UNION ALL

SELECT
    'week_to failed INT conversion' AS check_name,
    COUNT(*) AS failure_rows
FROM bronze_standardized
WHERE week_to_text IS NOT NULL
  AND TRY_CAST(week_to_text AS INT) IS NULL;


-- =============================================================================
-- 5. DETAILS: BRONZE VALUES THAT WOULD FAIL NUMERIC CONVERSION
-- Expected: 0 rows
-- =============================================================================

WITH bronze_standardized AS (
    SELECT
        TRIM(CAST(code_module AS STRING)) AS code_module_raw,
        TRIM(CAST(code_presentation AS STRING)) AS code_presentation_raw,
        TRIM(CAST(id_site AS STRING)) AS id_site_raw,
        TRIM(CAST(week_from AS STRING)) AS week_from_raw,
        TRIM(CAST(week_to AS STRING)) AS week_to_raw,

        CASE
            WHEN TRIM(CAST(id_site AS STRING)) IS NULL
              OR UPPER(TRIM(CAST(id_site AS STRING))) IN ('?', '', 'NA', 'N/A', 'NULL')
            THEN NULL
            ELSE TRIM(CAST(id_site AS STRING))
        END AS id_site_text,

        CASE
            WHEN TRIM(CAST(week_from AS STRING)) IS NULL
              OR UPPER(TRIM(CAST(week_from AS STRING))) IN ('?', '', 'NA', 'N/A', 'NULL')
            THEN NULL
            ELSE TRIM(CAST(week_from AS STRING))
        END AS week_from_text,

        CASE
            WHEN TRIM(CAST(week_to AS STRING)) IS NULL
              OR UPPER(TRIM(CAST(week_to AS STRING))) IN ('?', '', 'NA', 'N/A', 'NULL')
            THEN NULL
            ELSE TRIM(CAST(week_to AS STRING))
        END AS week_to_text
    FROM open_university.oulad_bronze.vle_raw
)

SELECT
    code_module_raw,
    code_presentation_raw,
    id_site_raw,
    week_from_raw,
    week_to_raw,
    CASE
        WHEN id_site_text IS NOT NULL
         AND TRY_CAST(id_site_text AS BIGINT) IS NULL
        THEN 'INVALID_ID_SITE'
        WHEN week_from_text IS NOT NULL
         AND TRY_CAST(week_from_text AS INT) IS NULL
        THEN 'INVALID_WEEK_FROM'
        WHEN week_to_text IS NOT NULL
         AND TRY_CAST(week_to_text AS INT) IS NULL
        THEN 'INVALID_WEEK_TO'
    END AS conversion_issue
FROM bronze_standardized
WHERE (id_site_text IS NOT NULL AND TRY_CAST(id_site_text AS BIGINT) IS NULL)
   OR (week_from_text IS NOT NULL AND TRY_CAST(week_from_text AS INT) IS NULL)
   OR (week_to_text IS NOT NULL AND TRY_CAST(week_to_text AS INT) IS NULL)
ORDER BY code_module_raw, code_presentation_raw, id_site_raw;


-- =============================================================================
-- 6. OPTIONAL NULL BASELINE PASS/FAIL SUMMARY
-- Expected: PASS
-- =============================================================================

SELECT
    CASE
        WHEN SUM(CASE WHEN week_from IS NULL THEN 1 ELSE 0 END) = 5243
         AND SUM(CASE WHEN week_to IS NULL THEN 1 ELSE 0 END) = 5243
        THEN 'PASS'
        ELSE 'FAIL'
    END AS optional_null_baseline_status,
    SUM(CASE WHEN week_from IS NULL THEN 1 ELSE 0 END) AS actual_week_from_nulls,
    SUM(CASE WHEN week_to IS NULL THEN 1 ELSE 0 END) AS actual_week_to_nulls,
    5243 AS expected_week_from_nulls,
    5243 AS expected_week_to_nulls
FROM open_university.oulad_silver.vle_clean;


-- =============================================================================
-- SECTION B: STUDENT_VLE_CLEAN NULL / CONVERSION CHECKS
-- =============================================================================

-- File: 03_silver_null_checks_student_vle.sql
-- Purpose: Find unexpected missing values and failed numeric conversions for student_vle_clean.
-- Inputs:
--   open_university.oulad_bronze.student_vle_raw
--   open_university.oulad_silver.student_vle_clean
-- Output: Read-only validation queries only; no data changes.
--
-- Required Silver values:
--   code_module
--   code_presentation
--   id_student
--   id_site
--   date
--   sum_click
--   clean_load_timestamp
--   clean_load_date
--
-- Note:
--   Negative date values are valid relative days.
--
-- Expected:
--   Required-column NULLs = 0
--   Audit-column NULLs = 0
--   Failed numeric conversions from non-missing Bronze inputs = 0


-- =============================================================================
-- 1. REQUIRED SILVER VALUES AND AUDIT COLUMNS
-- Expected: all failure_rows = 0
-- =============================================================================

SELECT 'code_module NULL' AS check_name, COUNT(*) AS failure_rows
FROM open_university.oulad_silver.student_vle_clean
WHERE code_module IS NULL

UNION ALL

SELECT 'code_presentation NULL' AS check_name, COUNT(*) AS failure_rows
FROM open_university.oulad_silver.student_vle_clean
WHERE code_presentation IS NULL

UNION ALL

SELECT 'id_student NULL' AS check_name, COUNT(*) AS failure_rows
FROM open_university.oulad_silver.student_vle_clean
WHERE id_student IS NULL

UNION ALL

SELECT 'id_site NULL' AS check_name, COUNT(*) AS failure_rows
FROM open_university.oulad_silver.student_vle_clean
WHERE id_site IS NULL

UNION ALL

SELECT 'date NULL' AS check_name, COUNT(*) AS failure_rows
FROM open_university.oulad_silver.student_vle_clean
WHERE date IS NULL

UNION ALL

SELECT 'sum_click NULL' AS check_name, COUNT(*) AS failure_rows
FROM open_university.oulad_silver.student_vle_clean
WHERE sum_click IS NULL

UNION ALL

SELECT 'clean_load_timestamp NULL' AS check_name, COUNT(*) AS failure_rows
FROM open_university.oulad_silver.student_vle_clean
WHERE clean_load_timestamp IS NULL

UNION ALL

SELECT 'clean_load_date NULL' AS check_name, COUNT(*) AS failure_rows
FROM open_university.oulad_silver.student_vle_clean
WHERE clean_load_date IS NULL;


-- =============================================================================
-- 2. DETAILS: UNEXPECTED REQUIRED NULLS
-- Expected: 0 rows
-- =============================================================================

SELECT *
FROM open_university.oulad_silver.student_vle_clean
WHERE code_module IS NULL
   OR code_presentation IS NULL
   OR id_student IS NULL
   OR id_site IS NULL
   OR date IS NULL
   OR sum_click IS NULL
   OR clean_load_timestamp IS NULL
   OR clean_load_date IS NULL
ORDER BY
    code_module,
    code_presentation,
    id_student,
    id_site,
    date;


-- =============================================================================
-- 3. BRONZE NUMERIC-CONVERSION CHECK
-- Detect non-missing source text that TRY_CAST cannot convert.
-- Expected: all failure_rows = 0
--
-- Negative relative dates are valid, so this checks conversion only;
-- it does NOT require date >= 0.
-- =============================================================================

WITH bronze_standardized AS (
    SELECT
        CASE
            WHEN TRIM(CAST(id_student AS STRING)) IS NULL
              OR UPPER(TRIM(CAST(id_student AS STRING))) IN ('?', '', 'NA', 'N/A', 'NULL')
            THEN NULL
            ELSE TRIM(CAST(id_student AS STRING))
        END AS id_student_text,

        CASE
            WHEN TRIM(CAST(id_site AS STRING)) IS NULL
              OR UPPER(TRIM(CAST(id_site AS STRING))) IN ('?', '', 'NA', 'N/A', 'NULL')
            THEN NULL
            ELSE TRIM(CAST(id_site AS STRING))
        END AS id_site_text,

        CASE
            WHEN TRIM(CAST(date AS STRING)) IS NULL
              OR UPPER(TRIM(CAST(date AS STRING))) IN ('?', '', 'NA', 'N/A', 'NULL')
            THEN NULL
            ELSE TRIM(CAST(date AS STRING))
        END AS date_text,

        CASE
            WHEN TRIM(CAST(sum_click AS STRING)) IS NULL
              OR UPPER(TRIM(CAST(sum_click AS STRING))) IN ('?', '', 'NA', 'N/A', 'NULL')
            THEN NULL
            ELSE TRIM(CAST(sum_click AS STRING))
        END AS sum_click_text
    FROM open_university.oulad_bronze.student_vle_raw
)

SELECT
    'id_student failed BIGINT conversion' AS check_name,
    COUNT(*) AS failure_rows
FROM bronze_standardized
WHERE id_student_text IS NOT NULL
  AND TRY_CAST(id_student_text AS BIGINT) IS NULL

UNION ALL

SELECT
    'id_site failed BIGINT conversion' AS check_name,
    COUNT(*) AS failure_rows
FROM bronze_standardized
WHERE id_site_text IS NOT NULL
  AND TRY_CAST(id_site_text AS BIGINT) IS NULL

UNION ALL

SELECT
    'date failed INT conversion' AS check_name,
    COUNT(*) AS failure_rows
FROM bronze_standardized
WHERE date_text IS NOT NULL
  AND TRY_CAST(date_text AS INT) IS NULL

UNION ALL

SELECT
    'sum_click failed BIGINT conversion' AS check_name,
    COUNT(*) AS failure_rows
FROM bronze_standardized
WHERE sum_click_text IS NOT NULL
  AND TRY_CAST(sum_click_text AS BIGINT) IS NULL;


-- =============================================================================
-- 4. DETAILS: BRONZE VALUES THAT WOULD FAIL NUMERIC CONVERSION
-- Expected: 0 rows
-- =============================================================================

WITH bronze_standardized AS (
    SELECT
        TRIM(CAST(code_module AS STRING)) AS code_module_raw,
        TRIM(CAST(code_presentation AS STRING)) AS code_presentation_raw,
        TRIM(CAST(id_student AS STRING)) AS id_student_raw,
        TRIM(CAST(id_site AS STRING)) AS id_site_raw,
        TRIM(CAST(date AS STRING)) AS date_raw,
        TRIM(CAST(sum_click AS STRING)) AS sum_click_raw,

        CASE
            WHEN TRIM(CAST(id_student AS STRING)) IS NULL
              OR UPPER(TRIM(CAST(id_student AS STRING))) IN ('?', '', 'NA', 'N/A', 'NULL')
            THEN NULL
            ELSE TRIM(CAST(id_student AS STRING))
        END AS id_student_text,

        CASE
            WHEN TRIM(CAST(id_site AS STRING)) IS NULL
              OR UPPER(TRIM(CAST(id_site AS STRING))) IN ('?', '', 'NA', 'N/A', 'NULL')
            THEN NULL
            ELSE TRIM(CAST(id_site AS STRING))
        END AS id_site_text,

        CASE
            WHEN TRIM(CAST(date AS STRING)) IS NULL
              OR UPPER(TRIM(CAST(date AS STRING))) IN ('?', '', 'NA', 'N/A', 'NULL')
            THEN NULL
            ELSE TRIM(CAST(date AS STRING))
        END AS date_text,

        CASE
            WHEN TRIM(CAST(sum_click AS STRING)) IS NULL
              OR UPPER(TRIM(CAST(sum_click AS STRING))) IN ('?', '', 'NA', 'N/A', 'NULL')
            THEN NULL
            ELSE TRIM(CAST(sum_click AS STRING))
        END AS sum_click_text
    FROM open_university.oulad_bronze.student_vle_raw
)

SELECT
    code_module_raw,
    code_presentation_raw,
    id_student_raw,
    id_site_raw,
    date_raw,
    sum_click_raw,
    CASE
        WHEN id_student_text IS NOT NULL
         AND TRY_CAST(id_student_text AS BIGINT) IS NULL
        THEN 'INVALID_ID_STUDENT'
        WHEN id_site_text IS NOT NULL
         AND TRY_CAST(id_site_text AS BIGINT) IS NULL
        THEN 'INVALID_ID_SITE'
        WHEN date_text IS NOT NULL
         AND TRY_CAST(date_text AS INT) IS NULL
        THEN 'INVALID_DATE'
        WHEN sum_click_text IS NOT NULL
         AND TRY_CAST(sum_click_text AS BIGINT) IS NULL
        THEN 'INVALID_SUM_CLICK'
    END AS conversion_issue
FROM bronze_standardized
WHERE (id_student_text IS NOT NULL AND TRY_CAST(id_student_text AS BIGINT) IS NULL)
   OR (id_site_text IS NOT NULL AND TRY_CAST(id_site_text AS BIGINT) IS NULL)
   OR (date_text IS NOT NULL AND TRY_CAST(date_text AS INT) IS NULL)
   OR (sum_click_text IS NOT NULL AND TRY_CAST(sum_click_text AS BIGINT) IS NULL)
ORDER BY
    code_module_raw,
    code_presentation_raw,
    id_student_raw,
    id_site_raw,
    date_raw;


-- =============================================================================
-- 5. REQUIRED SOURCE PLACEHOLDER / NULL CHECK
-- These are required student-VLE fields. Any source placeholder converted to
-- NULL should be reported/rejected by the transformation rather than silently
-- entering the Silver business key.
--
-- Expected for the current valid source batch: 0 unexpected required missing
-- values. If nonzero, reconcile these rows with your reject/report output.
-- =============================================================================

WITH bronze_standardized AS (
    SELECT
        CASE
            WHEN TRIM(CAST(code_module AS STRING)) IS NULL
              OR UPPER(TRIM(CAST(code_module AS STRING))) IN ('?', '', 'NA', 'N/A', 'NULL')
            THEN NULL
            ELSE TRIM(CAST(code_module AS STRING))
        END AS code_module_clean,

        CASE
            WHEN TRIM(CAST(code_presentation AS STRING)) IS NULL
              OR UPPER(TRIM(CAST(code_presentation AS STRING))) IN ('?', '', 'NA', 'N/A', 'NULL')
            THEN NULL
            ELSE TRIM(CAST(code_presentation AS STRING))
        END AS code_presentation_clean,

        CASE
            WHEN TRIM(CAST(id_student AS STRING)) IS NULL
              OR UPPER(TRIM(CAST(id_student AS STRING))) IN ('?', '', 'NA', 'N/A', 'NULL')
            THEN NULL
            ELSE TRIM(CAST(id_student AS STRING))
        END AS id_student_clean,

        CASE
            WHEN TRIM(CAST(id_site AS STRING)) IS NULL
              OR UPPER(TRIM(CAST(id_site AS STRING))) IN ('?', '', 'NA', 'N/A', 'NULL')
            THEN NULL
            ELSE TRIM(CAST(id_site AS STRING))
        END AS id_site_clean,

        CASE
            WHEN TRIM(CAST(date AS STRING)) IS NULL
              OR UPPER(TRIM(CAST(date AS STRING))) IN ('?', '', 'NA', 'N/A', 'NULL')
            THEN NULL
            ELSE TRIM(CAST(date AS STRING))
        END AS date_clean,

        CASE
            WHEN TRIM(CAST(sum_click AS STRING)) IS NULL
              OR UPPER(TRIM(CAST(sum_click AS STRING))) IN ('?', '', 'NA', 'N/A', 'NULL')
            THEN NULL
            ELSE TRIM(CAST(sum_click AS STRING))
        END AS sum_click_clean
    FROM open_university.oulad_bronze.student_vle_raw
)

SELECT
    SUM(CASE WHEN code_module_clean IS NULL THEN 1 ELSE 0 END)
        AS missing_code_module_rows,
    SUM(CASE WHEN code_presentation_clean IS NULL THEN 1 ELSE 0 END)
        AS missing_code_presentation_rows,
    SUM(CASE WHEN id_student_clean IS NULL THEN 1 ELSE 0 END)
        AS missing_id_student_rows,
    SUM(CASE WHEN id_site_clean IS NULL THEN 1 ELSE 0 END)
        AS missing_id_site_rows,
    SUM(CASE WHEN date_clean IS NULL THEN 1 ELSE 0 END)
        AS missing_date_rows,
    SUM(CASE WHEN sum_click_clean IS NULL THEN 1 ELSE 0 END)
        AS missing_sum_click_rows
FROM bronze_standardized;

