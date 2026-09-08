-- File: 06_silver_reconciliation_checks.sql
-- Suggested branch: feature/add-silver-checks
-- For checks tied to one transformation, use that transformation's branch instead.
-- Purpose: Prove cleaning preserves the required records, scores and clicks.
-- Status: Implementation pending. Replace this guide with the finished code.
-- Input: Bronze and Silver assessment, enrollment, registration and VLE data.
-- Output: Read-only validation queries with failure counts/details and stated expected results; no data
--    changes.
--
-- What to put in this file:
-- 1. Compare business-key coverage in both directions for the six tables that should retain their
--    source row grain.
-- 2. Compare normalized Bronze and Silver counts of scored/missing assessments and SUM(score); classify
--    invalid conversions separately.
-- 3. Compare typed Bronze SUM(sum_click) to Silver totals globally, per presentation and by the
--    complete daily interaction key.
-- 4. Confirm the 2,195,960-row VLE reduction is from aggregation, not dropped clicks.
-- 5. Compare outcome/registration populations and rerun the same source to verify stable business-row
--    counts and measures.
--
-- Use this file for manual Databricks checks. A runner must explicitly fail on violations; a displayed
--    result alone is not an automated test.
--
-- Done when: No unexplained missing/extra keys or changed measures; click differences are zero and
--    repeat loads do not inflate totals.
-- Read: docs/pipeline_plan.md and docs/assumptions.md.

-- ============================================================
-- 1. Assessment row-count reconciliation
-- Expected:
-- Bronze = Silver = 206
-- ============================================================

SELECT
    (SELECT COUNT(*)
     FROM open_university.oulad_bronze.assessment_raw) AS bronze_count,

    (SELECT COUNT(*)
     FROM open_university.oulad_silver.assessment_clean) AS silver_count,

    (SELECT COUNT(*)
     FROM open_university.oulad_silver.assessment_clean)
    -
    (SELECT COUNT(*)
     FROM open_university.oulad_bronze.assessment_raw) AS difference;


-- ============================================================
-- 2. Student assessment row-count reconciliation
-- Expected:
-- Bronze = Silver = 173,912
-- ============================================================

SELECT
    (SELECT COUNT(*)
     FROM open_university.oulad_bronze.student_assessment_raw) AS bronze_count,

    (SELECT COUNT(*)
     FROM open_university.oulad_silver.student_assessment_clean) AS silver_count,

    (SELECT COUNT(*)
     FROM open_university.oulad_silver.student_assessment_clean)
    -
    (SELECT COUNT(*)
     FROM open_university.oulad_bronze.student_assessment_raw) AS difference;


-- ============================================================
-- 3. Assessment business-key coverage
-- Check Bronze -> Silver
-- Expected: 0 missing keys
-- ============================================================

SELECT
    COUNT(*) AS missing_assessment_keys
FROM open_university.oulad_bronze.assessment_raw b
LEFT JOIN open_university.oulad_silver.assessment_clean s
    ON TRY_CAST(b.id_assessment AS BIGINT) = s.id_assessment
WHERE s.id_assessment IS NULL;


-- ============================================================
-- 4. Assessment business-key coverage
-- Check Silver -> Bronze
-- Expected: 0 extra keys
-- ============================================================

SELECT
    COUNT(*) AS extra_assessment_keys
FROM open_university.oulad_silver.assessment_clean s
LEFT JOIN open_university.oulad_bronze.assessment_raw b
    ON s.id_assessment = TRY_CAST(b.id_assessment AS BIGINT)
WHERE b.id_assessment IS NULL;


-- ============================================================
-- 5. Student assessment business-key coverage
-- Check Bronze -> Silver
-- Expected: 0 missing keys
-- ============================================================

SELECT
    COUNT(*) AS missing_student_assessment_keys
FROM open_university.oulad_bronze.student_assessment_raw b
LEFT JOIN open_university.oulad_silver.student_assessment_clean s
    ON TRY_CAST(b.id_assessment AS BIGINT) = s.id_assessment
   AND TRY_CAST(b.id_student AS BIGINT) = s.id_student
WHERE s.id_assessment IS NULL;


-- ============================================================
-- 6. Student assessment business-key coverage
-- Check Silver -> Bronze
-- Expected: 0 extra keys
-- ============================================================

SELECT
    COUNT(*) AS extra_student_assessment_keys
FROM open_university.oulad_silver.student_assessment_clean s
LEFT JOIN open_university.oulad_bronze.student_assessment_raw b
    ON s.id_assessment = TRY_CAST(b.id_assessment AS BIGINT)
   AND s.id_student = TRY_CAST(b.id_student AS BIGINT)
WHERE b.id_assessment IS NULL;


-- ============================================================
-- 7. Score reconciliation
--
-- Expected:
-- - Bronze and Silver scored-row counts match
-- - Bronze and Silver NULL-score counts match
-- - SUM(score) matches
--
-- NULL scores are expected and must remain NULL.
-- ============================================================

WITH bronze_scores AS (
    SELECT
        COUNT(score) AS scored_count,
        COUNT(*) - COUNT(score) AS missing_score_count,
        SUM(TRY_CAST(score AS DECIMAL(5,2))) AS score_sum
    FROM open_university.oulad_bronze.student_assessment_raw
    WHERE TRIM(score) NOT IN ('?', '', 'NA', 'N/A', 'NULL')
       OR score IS NULL
),

silver_scores AS (
    SELECT
        COUNT(score) AS scored_count,
        COUNT(*) - COUNT(score) AS missing_score_count,
        SUM(score) AS score_sum
    FROM open_university.oulad_silver.student_assessment_clean
)

SELECT
    b.scored_count AS bronze_scored_count,
    s.scored_count AS silver_scored_count,

    b.missing_score_count AS bronze_missing_score_count,
    s.missing_score_count AS silver_missing_score_count,

    b.score_sum AS bronze_score_sum,
    s.score_sum AS silver_score_sum,

    CASE
        WHEN b.scored_count = s.scored_count
         AND b.missing_score_count = s.missing_score_count
         AND b.score_sum = s.score_sum
        THEN 'PASS'
        ELSE 'FAIL'
    END AS status
FROM bronze_scores b
CROSS JOIN silver_scores s;


-- ============================================================
-- 8. Documented missing-score reconciliation
-- Expected:
-- 173 missing scores
-- ============================================================

SELECT
    COUNT(*) AS null_score_count
FROM open_university.oulad_silver.student_assessment_clean
WHERE score IS NULL;


