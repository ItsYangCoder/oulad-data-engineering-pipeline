-- File: 01_silver_row_count_checks.sql
-- Suggested branch: feature/add-silver-checks
-- For checks tied to one transformation, use that transformation's branch instead.
-- Purpose: Explain every Bronze-to-Silver row-count difference.
-- Status: Implementation pending. Replace this guide with the finished code.
-- Input: All seven Bronze and matching Silver tables.
-- Output: Read-only validation queries with failure counts/details and stated expected results; no data
--    changes.
--
-- What to put in this file:
-- 1. Return table_name, bronze_count, silver_count, expected_count, difference and a clear status for
--    the current batch.
-- 2. Expect assessment 206; courses 22; student_assessment 173,912; student_info and
--    student_registration 32,593 each; vle 6,364.
-- 3. Expect student_vle to change from 10,655,280 source rows to 8,459,320 complete daily keys after
--    aggregation.
-- 4. Compare with live Bronze counts and document any new-batch baseline changes; fixed counts are not
--    universal thresholds.
--
-- Use this file for manual Databricks checks. A runner must explicitly fail on violations; a displayed
--    result alone is not an automated test.
--
-- Done when: All differences are explained by the documented transformation, with no unexpected loss.
-- Read: docs/pipeline_plan.md and docs/assumptions.md.

-- ============================================================
-- File: 01_silver_row_count_checks.sql
-- Branch: feature/clean-assessments
--
-- Purpose:
-- Validate Bronze-to-Silver row counts for the assessment
-- transformations.
--
-- Expected current-batch counts:
--   assessment_clean          = 206
--   student_assessment_clean  = 173,912
--
-- This is a read-only validation check.
-- ============================================================


WITH row_counts AS (

    -- Assessment
    SELECT
        'assessment_clean' AS table_name,
        (
            SELECT COUNT(*)
            FROM open_university.oulad_bronze.assessment_raw
        ) AS bronze_count,
        (
            SELECT COUNT(*)
            FROM open_university.oulad_silver.assessment_clean
        ) AS silver_count,
        206 AS expected_count

    UNION ALL

    -- Student Assessment
    SELECT
        'student_assessment_clean' AS table_name,
        (
            SELECT COUNT(*)
            FROM open_university.oulad_bronze.student_assessment_raw
        ) AS bronze_count,
        (
            SELECT COUNT(*)
            FROM open_university.oulad_silver.student_assessment_clean
        ) AS silver_count,
        173912 AS expected_count
)

SELECT
    table_name,
    bronze_count,
    silver_count,
    expected_count,
    silver_count - bronze_count AS difference,

    CASE
        WHEN silver_count = expected_count
             AND silver_count = bronze_count
        THEN 'PASS'

        WHEN silver_count = expected_count
             AND silver_count <> bronze_count
        THEN 'REVIEW - documented transformation difference'

        ELSE 'FAIL'
    END AS status

FROM row_counts
ORDER BY table_name;
