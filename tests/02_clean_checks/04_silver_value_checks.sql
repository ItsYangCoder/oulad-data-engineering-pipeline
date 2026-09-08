-- File: 04_silver_value_checks.sql
-- Suggested branch: feature/add-silver-checks
-- For checks tied to one transformation, use that transformation's branch instead.
-- Purpose: Find invalid types, unconverted placeholders and out-of-range values.
-- Status: Implementation pending. Replace this guide with the finished code.
-- Input: All seven Silver tables and column metadata.
-- Output: Read-only validation queries with failure counts/details and stated expected results; no data
--    changes.
--
-- What to put in this file:
-- 1. Check data types through metadata and confirm source placeholders (?, blank, NA, N/A, NULL text)
--    were normalized.
-- 2. Check scores and weights within 0..100 when present, is_banked in (0,1), positive presentation
--    lengths and nonnegative clicks/attempts/credits.
-- 3. Check agreed categories such as CMA/TMA/Exam and Distinction/Fail/Pass/Withdrawn.
-- 4. Check week_from <= week_to only when both exist; keep NULL optional weeks and valid negative
--    relative dates.
--
-- Use this file for manual Databricks checks. A runner must explicitly fail on violations; a displayed
--    result alone is not an automated test.
--
-- Done when: No unexpected placeholders, invalid categories/types or documented range violations.
-- Read: docs/pipeline_plan.md and docs/assumptions.md.

-- ============================================================
-- 1. assessment_clean
-- ============================================================

-- Check assessment_type categories
-- Expected: only TMA, CMA, Exam

SELECT
    assessment_type,
    COUNT(*) AS row_count
FROM open_university.oulad_silver.assessment_clean
GROUP BY assessment_type
ORDER BY assessment_type;


-- Check invalid assessment_type values
-- Expected: No rows returned

SELECT DISTINCT
    assessment_type
FROM open_university.oulad_silver.assessment_clean
WHERE assessment_type NOT IN ('TMA', 'CMA', 'Exam')
   OR assessment_type IS NULL;


-- Check assessment weight range
-- Expected: No rows returned
-- Weight should be between 0 and 100 when present

SELECT
    id_assessment,
    weight
FROM open_university.oulad_silver.assessment_clean
WHERE weight IS NOT NULL
  AND (weight < 0 OR weight > 100);


-- Check unconverted placeholders in assessment fields
-- Expected: No rows returned

SELECT *
FROM open_university.oulad_silver.assessment_clean
WHERE TRIM(code_module) IN ('?', '', 'NA', 'N/A', 'NULL')
   OR TRIM(code_presentation) IN ('?', '', 'NA', 'N/A', 'NULL')
   OR TRIM(assessment_type) IN ('?', '', 'NA', 'N/A', 'NULL');


-- ============================================================
-- 2. student_assessment_clean
-- ============================================================

-- Check score range
-- Expected: No rows returned
-- Missing scores are allowed and should remain NULL.

SELECT
    id_assessment,
    id_student,
    score
FROM open_university.oulad_silver.student_assessment_clean
WHERE score IS NOT NULL
  AND (score < 0 OR score > 100);


-- Check is_banked values
-- Expected: No rows returned
-- Valid values are 0 and 1.

SELECT DISTINCT
    is_banked
FROM open_university.oulad_silver.student_assessment_clean
WHERE is_banked IS NOT NULL
  AND is_banked NOT IN (0, 1);


-- Check unconverted placeholders
-- Expected: No rows returned

SELECT *
FROM open_university.oulad_silver.student_assessment_clean
WHERE CAST(id_assessment AS STRING) IN ('?', '', 'NA', 'N/A', 'NULL')
   OR CAST(id_student AS STRING) IN ('?', '', 'NA', 'N/A', 'NULL')
   OR CAST(date_submitted AS STRING) IN ('?', '', 'NA', 'N/A', 'NULL')
   OR CAST(is_banked AS STRING) IN ('?', '', 'NA', 'N/A', 'NULL')
   OR CAST(score AS STRING) IN ('?', '', 'NA', 'N/A', 'NULL');
