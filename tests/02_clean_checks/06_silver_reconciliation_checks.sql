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
-- 06_silver_reconciliation_checks.sql
-- Assessment + Student Assessment Silver Reconciliation
--
-- Expected:
-- assessment rows = 206
-- student assessment rows = 173,912
-- missing/extra keys = 0
-- missing scores = 173
-- score reconciliation = PASS
-- ============================================================


-- ============================================================
-- 1. Assessment row-count reconciliation
-- ============================================================

WITH assessment_counts AS (
    SELECT
        (
            SELECT COUNT(*)
            FROM open_university.oulad_bronze.assessment_raw
        ) AS bronze_count,

        (
            SELECT COUNT(*)
            FROM open_university.oulad_silver.assessment_clean
        ) AS silver_count
),


-- ============================================================
-- 2. Student assessment row-count reconciliation
-- ============================================================

student_assessment_counts AS (
    SELECT
        (
            SELECT COUNT(*)
            FROM open_university.oulad_bronze.student_assessment_raw
        ) AS bronze_count,

        (
            SELECT COUNT(*)
            FROM open_university.oulad_silver.student_assessment_clean
        ) AS silver_count
),


-- ============================================================
-- 3. Assessment Bronze -> Silver key coverage
-- Expected: 0 missing keys
-- ============================================================

assessment_missing AS (
    SELECT COUNT(*) AS count
    FROM open_university.oulad_bronze.assessment_raw b
    LEFT JOIN open_university.oulad_silver.assessment_clean s
        ON TRY_CAST(b.id_assessment AS BIGINT) = s.id_assessment
    WHERE s.id_assessment IS NULL
),


-- ============================================================
-- 4. Assessment Silver -> Bronze key coverage
-- Expected: 0 extra keys
-- ============================================================

assessment_extra AS (
    SELECT COUNT(*) AS count
    FROM open_university.oulad_silver.assessment_clean s
    LEFT JOIN open_university.oulad_bronze.assessment_raw b
        ON s.id_assessment = TRY_CAST(b.id_assessment AS BIGINT)
    WHERE b.id_assessment IS NULL
),


-- ============================================================
-- 5. Student Assessment Bronze -> Silver key coverage
-- Expected: 0 missing keys
-- Key = id_assessment + id_student
-- ============================================================

student_assessment_missing AS (
    SELECT COUNT(*) AS count
    FROM open_university.oulad_bronze.student_assessment_raw b
    LEFT JOIN open_university.oulad_silver.student_assessment_clean s
        ON TRY_CAST(b.id_assessment AS BIGINT) = s.id_assessment
       AND TRY_CAST(b.id_student AS BIGINT) = s.id_student
    WHERE s.id_assessment IS NULL
),


-- ============================================================
-- 6. Student Assessment Silver -> Bronze key coverage
-- Expected: 0 extra keys
-- ============================================================

student_assessment_extra AS (
    SELECT COUNT(*) AS count
    FROM open_university.oulad_silver.student_assessment_clean s
    LEFT JOIN open_university.oulad_bronze.student_assessment_raw b
        ON s.id_assessment = TRY_CAST(b.id_assessment AS BIGINT)
       AND s.id_student = TRY_CAST(b.id_student AS BIGINT)
    WHERE b.id_assessment IS NULL
),


-- ============================================================
-- 7. Score reconciliation
--
-- Bronze:
-- ?, '', NA, N/A, NULL = missing
--
-- Silver:
-- missing scores should be SQL NULL
--
-- Expected:
-- scored Bronze = scored Silver
-- missing Bronze = missing Silver
-- score SUM = same
-- ============================================================

score_reconciliation AS (
    SELECT

        -- --------------------------------------------
        -- Bronze scored rows
        -- --------------------------------------------
        (
            SELECT COUNT(*)
            FROM open_university.oulad_bronze.student_assessment_raw
            WHERE TRIM(score) NOT IN (
                '?',
                '',
                'NA',
                'N/A',
                'NULL'
            )
            AND score IS NOT NULL
        ) AS bronze_scored_count,


        -- --------------------------------------------
        -- Silver scored rows
        -- --------------------------------------------
        (
            SELECT COUNT(score)
            FROM open_university.oulad_silver.student_assessment_clean
        ) AS silver_scored_count,


        -- --------------------------------------------
        -- Bronze missing scores
        -- IMPORTANT:
        -- Count placeholders as missing
        -- --------------------------------------------
        (
            SELECT COUNT(*)
            FROM open_university.oulad_bronze.student_assessment_raw
            WHERE score IS NULL
               OR TRIM(score) IN (
                    '?',
                    '',
                    'NA',
                    'N/A',
                    'NULL'
               )
        ) AS bronze_missing_score_count,


        -- --------------------------------------------
        -- Silver missing scores
        -- --------------------------------------------
        (
            SELECT COUNT(*)
            FROM open_university.oulad_silver.student_assessment_clean
            WHERE score IS NULL
        ) AS silver_missing_score_count,


        -- --------------------------------------------
        -- Bronze score sum
        -- Exclude known missing placeholders
        -- --------------------------------------------
        (
            SELECT SUM(
                TRY_CAST(score AS DECIMAL(5,2))
            )
            FROM open_university.oulad_bronze.student_assessment_raw
            WHERE score IS NOT NULL
              AND TRIM(score) NOT IN (
                    '?',
                    '',
                    'NA',
                    'N/A',
                    'NULL'
              )
        ) AS bronze_score_sum,


        -- --------------------------------------------
        -- Silver score sum
        -- --------------------------------------------
        (
            SELECT SUM(score)
            FROM open_university.oulad_silver.student_assessment_clean
        ) AS silver_score_sum
),


-- ============================================================
-- 8. Expected NULL score count
-- Expected: 173
-- ============================================================

null_scores AS (
    SELECT COUNT(*) AS count
    FROM open_university.oulad_silver.student_assessment_clean
    WHERE score IS NULL
)


-- ============================================================
-- FINAL RECONCILIATION RESULT
-- ============================================================

SELECT

    -- --------------------------------------------
    -- Row counts
    -- --------------------------------------------

    a.bronze_count AS assessment_bronze_rows,
    a.silver_count AS assessment_silver_rows,

    sa.bronze_count AS student_assessment_bronze_rows,
    sa.silver_count AS student_assessment_silver_rows,


    -- --------------------------------------------
    -- Assessment key coverage
    -- --------------------------------------------

    am.count AS missing_assessment_keys,
    ae.count AS extra_assessment_keys,


    -- --------------------------------------------
    -- Student Assessment key coverage
    -- --------------------------------------------

    sam.count AS missing_student_assessment_keys,
    sae.count AS extra_student_assessment_keys,


    -- --------------------------------------------
    -- Score reconciliation
    -- --------------------------------------------

    sr.bronze_scored_count,
    sr.silver_scored_count,

    sr.bronze_missing_score_count,
    sr.silver_missing_score_count,

    sr.bronze_score_sum,
    sr.silver_score_sum,


    -- --------------------------------------------
    -- Expected NULL scores
    -- --------------------------------------------

    ns.count AS expected_null_scores,


    -- --------------------------------------------
    -- FINAL STATUS
    -- --------------------------------------------

    CASE
        WHEN a.bronze_count = 206
         AND a.silver_count = 206

         AND sa.bronze_count = 173912
         AND sa.silver_count = 173912

         AND am.count = 0
         AND ae.count = 0

         AND sam.count = 0
         AND sae.count = 0

         AND sr.bronze_scored_count = sr.silver_scored_count

         AND sr.bronze_missing_score_count
             = sr.silver_missing_score_count

         AND sr.bronze_score_sum
             = sr.silver_score_sum

         AND ns.count = 173

        THEN 'PASS'

        ELSE 'FAIL'
    END AS reconciliation_status


FROM assessment_counts a

CROSS JOIN student_assessment_counts sa

CROSS JOIN assessment_missing am

CROSS JOIN assessment_extra ae

CROSS JOIN student_assessment_missing sam

CROSS JOIN student_assessment_extra sae

CROSS JOIN score_reconciliation sr

CROSS JOIN null_scores ns;

-- VLE reconciliation
WITH bronze AS (
  SELECT
    COUNT(*) AS source_rows,
    SUM(TRY_CAST(sum_click AS BIGINT)) AS click_total
  FROM open_university.oulad_bronze.student_vle_raw
),
silver AS (
  SELECT
    COUNT(*) AS daily_rows,
    SUM(source_row_count) AS accounted_source_rows,
    SUM(sum_click) AS click_total
  FROM open_university.oulad_silver.student_vle_clean
),
resources AS (
  SELECT COUNT(*) AS resource_rows
  FROM open_university.oulad_silver.vle_clean
)
SELECT
  resources.resource_rows,
  bronze.source_rows AS bronze_interaction_rows,
  silver.daily_rows AS silver_daily_rows,
  silver.accounted_source_rows,
  bronze.click_total AS bronze_click_total,
  silver.click_total AS silver_click_total,
  CASE
    WHEN resources.resource_rows = 6364
     AND silver.daily_rows = 8459320
     AND bronze.source_rows = silver.accounted_source_rows
     AND bronze.click_total = silver.click_total
    THEN 'PASS' ELSE 'FAIL'
  END AS vle_reconciliation_status
FROM bronze
CROSS JOIN silver
CROSS JOIN resources;
