-- File: 05_silver_relationship_checks.sql
-- Suggested branch: feature/add-silver-checks
-- For checks tied to one transformation, use that transformation's branch instead.
-- Purpose: Find Silver child rows without their required parent.
-- Status: Implementation pending. Replace this guide with the finished code.
-- Input: All seven Silver tables.
-- Output: Read-only validation queries with failure counts/details and stated expected results; no data
--    changes.
--
-- What to put in this file:
-- 1. Check student_assessment -> assessment on id_assessment; assessment, student_info and vle ->
--    courses on both module/presentation codes.
-- 2. Check registration -> student_info on the complete enrollment key.
-- 3. Check student_vle -> vle on module + presentation + id_site, and -> student_info on module +
--    presentation + id_student.
-- 4. Use assessment context to validate student_assessment against the full enrollment key; never join
--    student_id alone for enrollment context.
-- 5. Return relationship name, orphan count and failing keys or detail queries.
--
-- Use this file for manual Databricks checks. A runner must explicitly fail on violations; a displayed
--    result alone is not an automated test.
--
-- Done when: Zero unexplained orphan rows using complete composite joins.
-- Read: docs/pipeline_plan.md and docs/assumptions.md.

-- ============================================================
-- 1. student_assessment_clean -> assessment_clean
-- Relationship:
-- student_assessment_clean.id_assessment
-- must exist in assessment_clean.id_assessment
--
-- Expected: 0 orphan rows
-- ============================================================

SELECT
    COUNT(*) AS orphan_count
FROM open_university.oulad_silver.student_assessment_clean sa
LEFT JOIN open_university.oulad_silver.assessment_clean a
    ON sa.id_assessment = a.id_assessment
WHERE a.id_assessment IS NULL;


-- Show orphan assessment keys if any exist
-- Expected: No rows returned

SELECT DISTINCT
    sa.id_assessment
FROM open_university.oulad_silver.student_assessment_clean sa
LEFT JOIN open_university.oulad_silver.assessment_clean a
    ON sa.id_assessment = a.id_assessment
WHERE a.id_assessment IS NULL
ORDER BY sa.id_assessment;


-- ============================================================
-- 2. assessment_clean -> courses_clean
-- Relationship:
-- assessment_clean.code_module + code_presentation
-- must exist in courses_clean
--
-- Expected: 0 orphan rows
-- ============================================================

SELECT
    COUNT(*) AS orphan_count
FROM open_university.oulad_silver.assessment_clean a
LEFT JOIN open_university.oulad_silver.courses_clean c
    ON a.code_module = c.code_module
   AND a.code_presentation = c.code_presentation
WHERE c.code_module IS NULL
   OR c.code_presentation IS NULL;


-- Show orphan course keys if any exist
-- Expected: No rows returned

SELECT DISTINCT
    a.code_module,
    a.code_presentation
FROM open_university.oulad_silver.assessment_clean a
LEFT JOIN open_university.oulad_silver.courses_clean c
    ON a.code_module = c.code_module
   AND a.code_presentation = c.code_presentation
WHERE c.code_module IS NULL
   OR c.code_presentation IS NULL
ORDER BY
    a.code_module,
    a.code_presentation;
