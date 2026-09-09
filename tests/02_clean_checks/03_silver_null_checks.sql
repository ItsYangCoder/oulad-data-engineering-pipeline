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

-- ============================================================
-- 1. assessment_clean
-- Required fields:
-- id_assessment
-- code_module
-- code_presentation
-- assessment_type
-- clean_load_timestamp
-- clean_load_date
--
-- Expected optional NULL:
-- date = 11 NULLs, all for Exam assessments
-- ============================================================

SELECT
    COUNT(*) AS unexpected_null_count
FROM open_university.oulad_silver.assessment_clean
WHERE id_assessment IS NULL
   OR TRIM(code_module) IS NULL
   OR TRIM(code_module) = ''
   OR TRIM(code_presentation) IS NULL
   OR TRIM(code_presentation) = ''
   OR TRIM(assessment_type) IS NULL
   OR TRIM(assessment_type) = ''
   OR clean_load_timestamp IS NULL
   OR clean_load_date IS NULL;


-- Check the documented 11 missing assessment dates
-- Expected: 11 rows, all assessment_type = 'Exam'

SELECT
    assessment_type,
    COUNT(*) AS null_date_count
FROM open_university.oulad_silver.assessment_clean
WHERE date IS NULL
GROUP BY assessment_type
ORDER BY assessment_type;


-- ============================================================
-- 2. student_assessment_clean
-- Required fields:
-- id_assessment
-- id_student
-- clean_load_timestamp
-- clean_load_date
--
-- Expected optional NULL:
-- score = 173 NULLs, all for TMA assessments
-- ============================================================

SELECT
    COUNT(*) AS unexpected_null_count
FROM open_university.oulad_silver.student_assessment_clean
WHERE id_assessment IS NULL
   OR id_student IS NULL
   OR clean_load_timestamp IS NULL
   OR clean_load_date IS NULL;


-- Check the documented 173 missing scores
-- Expected: 173 rows, all assessment_type = 'TMA'

SELECT
    a.assessment_type,
    COUNT(*) AS null_score_count
FROM open_university.oulad_silver.student_assessment_clean sa
JOIN open_university.oulad_silver.assessment_clean a
    ON sa.id_assessment = a.id_assessment
WHERE sa.score IS NULL
GROUP BY a.assessment_type
ORDER BY a.assessment_type;
