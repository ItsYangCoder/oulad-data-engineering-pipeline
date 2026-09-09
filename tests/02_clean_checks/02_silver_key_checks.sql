-- File: 02_silver_key_checks.sql
-- Suggested branch: feature/add-silver-checks
-- For checks tied to one transformation, use that transformation's branch instead.
-- Purpose: Find missing or repeated Silver business keys.
-- Status: Implementation pending. Replace this guide with the finished code.
-- Input: All seven Silver tables.
-- Output: Read-only validation queries with failure counts/details and stated expected results; no data
--    changes.
--
-- What to put in this file:
-- 1. Check assessment by id_assessment; courses by code_module + code_presentation.
-- 2. Check student_assessment by id_assessment + id_student; student_info and registration by
--    code_module + code_presentation + id_student.
-- 3. Check vle by code_module + code_presentation + id_site; student_vle by those codes plus id_student
--    + id_site + date.
-- 4. Test each key component for NULL/blank separately, then GROUP BY the full key and HAVING COUNT(*)
--    > 1.
--
-- Use this file for manual Databricks checks. A runner must explicitly fail on violations; a displayed
--    result alone is not an automated test.
--
-- Done when: No missing required key components and no repeated full business keys.
-- Read: docs/pipeline_plan.md and docs/assumptions.md.


-- File: 02_silver_key_checks.sql
-- Purpose: Validate required and unique business keys for vle_clean and student_vle_clean.
-- Input:
--   open_university.oulad_silver.vle_clean
--   open_university.oulad_silver.student_vle_clean
-- Output: Read-only validation queries only; no data changes.
--
-- Expected:
--   No missing/blank required business-key components
--   No repeated full business keys

-- =============================================================================
-- SECTION A: VLE_CLEAN KEY CHECKS
-- =============================================================================

-- File: 02_silver_key_checks_vle.sql
-- Purpose: Validate required and unique business keys for vle_clean.
-- Input: open_university.oulad_silver.vle_clean
-- Output: Read-only validation queries only; no data changes.
--
-- Business key:
--   (code_module, code_presentation, id_site)
--
-- Expected:
--   0 missing/blank key components
--   0 repeated full business keys


-- =============================================================================
-- 1. SUMMARY: MISSING / BLANK BUSINESS KEY COMPONENTS
-- Expected: all failure_rows = 0
-- =============================================================================

SELECT 'code_module is NULL' AS check_name, COUNT(*) AS failure_rows
FROM open_university.oulad_silver.vle_clean
WHERE code_module IS NULL

UNION ALL

SELECT 'code_module is blank' AS check_name, COUNT(*) AS failure_rows
FROM open_university.oulad_silver.vle_clean
WHERE code_module IS NOT NULL
  AND TRIM(code_module) = ''

UNION ALL

SELECT 'code_presentation is NULL' AS check_name, COUNT(*) AS failure_rows
FROM open_university.oulad_silver.vle_clean
WHERE code_presentation IS NULL

UNION ALL

SELECT 'code_presentation is blank' AS check_name, COUNT(*) AS failure_rows
FROM open_university.oulad_silver.vle_clean
WHERE code_presentation IS NOT NULL
  AND TRIM(code_presentation) = ''

UNION ALL

SELECT 'id_site is NULL' AS check_name, COUNT(*) AS failure_rows
FROM open_university.oulad_silver.vle_clean
WHERE id_site IS NULL;


-- =============================================================================
-- 2. DETAILS: ROWS WITH MISSING / BLANK BUSINESS KEY COMPONENTS
-- Expected: 0 rows
-- =============================================================================

SELECT *
FROM open_university.oulad_silver.vle_clean
WHERE code_module IS NULL
   OR TRIM(code_module) = ''
   OR code_presentation IS NULL
   OR TRIM(code_presentation) = ''
   OR id_site IS NULL
ORDER BY code_module, code_presentation, id_site;


-- =============================================================================
-- 3. SUMMARY: DUPLICATE FULL BUSINESS KEYS
-- Expected: duplicate_key_groups = 0
-- =============================================================================

SELECT COUNT(*) AS duplicate_key_groups
FROM (
    SELECT
        code_module,
        code_presentation,
        id_site
    FROM open_university.oulad_silver.vle_clean
    GROUP BY
        code_module,
        code_presentation,
        id_site
    HAVING COUNT(*) > 1
) d;


-- =============================================================================
-- 4. DETAILS: DUPLICATE FULL BUSINESS KEYS
-- Expected: 0 rows
-- =============================================================================

SELECT
    code_module,
    code_presentation,
    id_site,
    COUNT(*) AS row_count
FROM open_university.oulad_silver.vle_clean
GROUP BY
    code_module,
    code_presentation,
    id_site
HAVING COUNT(*) > 1
ORDER BY row_count DESC, code_module, code_presentation, id_site;


-- =============================================================================
-- 5. OPTIONAL HIGH-LEVEL UNIQUENESS CHECK
-- Expected for current batch:
--   total_rows = 6364
--   distinct_business_keys = 6364
-- =============================================================================

SELECT
    COUNT(*) AS total_rows,
    COUNT(
        DISTINCT STRUCT(
            code_module,
            code_presentation,
            id_site
        )
    ) AS distinct_business_keys
FROM open_university.oulad_silver.vle_clean;


-- =============================================================================
-- SECTION B: STUDENT_VLE_CLEAN KEY CHECKS
-- =============================================================================

-- File: 02_silver_key_checks_student_vle.sql
-- Purpose: Validate required and unique business keys for student_vle_clean.
-- Input: open_university.oulad_silver.student_vle_clean
-- Output: Read-only validation queries only; no data changes.
--
-- Business key:
--   (code_module, code_presentation, id_student, id_site, date)
--
-- Note:
--   Negative date values are valid relative days and must not be treated as bad keys.
--
-- Expected:
--   0 missing/blank key components
--   0 repeated full business keys


-- =============================================================================
-- 1. SUMMARY: MISSING / BLANK BUSINESS KEY COMPONENTS
-- Expected: all failure_rows = 0
-- =============================================================================

SELECT 'code_module is NULL' AS check_name, COUNT(*) AS failure_rows
FROM open_university.oulad_silver.student_vle_clean
WHERE code_module IS NULL

UNION ALL

SELECT 'code_module is blank' AS check_name, COUNT(*) AS failure_rows
FROM open_university.oulad_silver.student_vle_clean
WHERE code_module IS NOT NULL
  AND TRIM(code_module) = ''

UNION ALL

SELECT 'code_presentation is NULL' AS check_name, COUNT(*) AS failure_rows
FROM open_university.oulad_silver.student_vle_clean
WHERE code_presentation IS NULL

UNION ALL

SELECT 'code_presentation is blank' AS check_name, COUNT(*) AS failure_rows
FROM open_university.oulad_silver.student_vle_clean
WHERE code_presentation IS NOT NULL
  AND TRIM(code_presentation) = ''

UNION ALL

SELECT 'id_student is NULL' AS check_name, COUNT(*) AS failure_rows
FROM open_university.oulad_silver.student_vle_clean
WHERE id_student IS NULL

UNION ALL

SELECT 'id_site is NULL' AS check_name, COUNT(*) AS failure_rows
FROM open_university.oulad_silver.student_vle_clean
WHERE id_site IS NULL

UNION ALL

SELECT 'date is NULL' AS check_name, COUNT(*) AS failure_rows
FROM open_university.oulad_silver.student_vle_clean
WHERE date IS NULL;


-- =============================================================================
-- 2. DETAILS: ROWS WITH MISSING / BLANK BUSINESS KEY COMPONENTS
-- Expected: 0 rows
-- =============================================================================

SELECT *
FROM open_university.oulad_silver.student_vle_clean
WHERE code_module IS NULL
   OR TRIM(code_module) = ''
   OR code_presentation IS NULL
   OR TRIM(code_presentation) = ''
   OR id_student IS NULL
   OR id_site IS NULL
   OR date IS NULL
ORDER BY
    code_module,
    code_presentation,
    id_student,
    id_site,
    date;


-- =============================================================================
-- 3. SUMMARY: DUPLICATE FULL BUSINESS KEYS
-- Expected: duplicate_key_groups = 0
-- =============================================================================

SELECT COUNT(*) AS duplicate_key_groups
FROM (
    SELECT
        code_module,
        code_presentation,
        id_student,
        id_site,
        date
    FROM open_university.oulad_silver.student_vle_clean
    GROUP BY
        code_module,
        code_presentation,
        id_student,
        id_site,
        date
    HAVING COUNT(*) > 1
) d;


-- =============================================================================
-- 4. DETAILS: DUPLICATE FULL BUSINESS KEYS
-- Expected: 0 rows
-- =============================================================================

SELECT
    code_module,
    code_presentation,
    id_student,
    id_site,
    date,
    COUNT(*) AS row_count
FROM open_university.oulad_silver.student_vle_clean
GROUP BY
    code_module,
    code_presentation,
    id_student,
    id_site,
    date
HAVING COUNT(*) > 1
ORDER BY
    row_count DESC,
    code_module,
    code_presentation,
    id_student,
    id_site,
    date;


-- =============================================================================
-- 5. OPTIONAL HIGH-LEVEL UNIQUENESS CHECK
-- Expected for current batch:
--   total_rows = 8459320
--   distinct_business_keys = 8459320
-- =============================================================================

SELECT
    COUNT(*) AS total_rows,
    COUNT(
        DISTINCT STRUCT(
            code_module,
            code_presentation,
            id_student,
            id_site,
            date
        )
    ) AS distinct_business_keys
FROM open_university.oulad_silver.student_vle_clean;
