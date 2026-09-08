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

-- ============================================================
-- 1. assessment_clean
-- Business key: id_assessment
-- Expected:
-- - No NULL id_assessment
-- - No duplicate id_assessment
-- ============================================================

-- Check for NULL assessment keys
SELECT
    COUNT(*) AS null_id_assessment_count
FROM open_university.oulad_silver.assessment_clean
WHERE id_assessment IS NULL;


-- Check for duplicate assessment keys
SELECT
    id_assessment,
    COUNT(*) AS row_count
FROM open_university.oulad_silver.assessment_clean
GROUP BY id_assessment
HAVING COUNT(*) > 1
ORDER BY row_count DESC;


-- ============================================================
-- 2. student_assessment_clean
-- Business key: id_assessment + id_student
-- Expected:
-- - No NULL id_assessment
-- - No NULL id_student
-- - No duplicate composite key
-- ============================================================

-- Check for NULL id_assessment
SELECT
    COUNT(*) AS null_id_assessment_count
FROM open_university.oulad_silver.student_assessment_clean
WHERE id_assessment IS NULL;


-- Check for NULL id_student
SELECT
    COUNT(*) AS null_id_student_count
FROM open_university.oulad_silver.student_assessment_clean
WHERE id_student IS NULL;


-- Check for duplicate composite keys
SELECT
    id_assessment,
    id_student,
    COUNT(*) AS row_count
FROM open_university.oulad_silver.student_assessment_clean
GROUP BY
    id_assessment,
    id_student
HAVING COUNT(*) > 1
ORDER BY row_count DESC;
