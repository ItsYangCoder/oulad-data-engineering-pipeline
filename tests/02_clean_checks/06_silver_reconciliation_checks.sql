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

-- ================================================================================================
-- File: 06_silver_reconciliation_checks.sql
-- Suggested branch: feature/add-silver-checks
--
-- Purpose:
--   Prove that Silver cleaning preserves required VLE records and recorded clicks.
--
-- Input:
--   open_university.oulad_bronze.student_vle_raw
--   open_university.oulad_bronze.vle_raw
--   open_university.oulad_silver.student_vle_clean
--   open_university.oulad_silver.vle_clean
--
-- Output:
--   Read-only reconciliation queries with expected results.
--
-- Important assumptions:
--   1. student_vle_raw is treated as a complete current-source snapshot.
--   2. student_vle_clean aggregates repeated Bronze records to one:
--
--        (code_module,
--         code_presentation,
--         id_student,
--         id_site,
--         date)
--
--   3. Repeated student_vle rows are combined with SUM(sum_click).
--   4. Negative relative dates are valid and must be preserved.
--   5. Invalid required keys / failed casts / negative clicks are excluded from
--      student_vle_clean and reviewed separately.
--   6. vle_clean should retain the valid Bronze VLE business-key population.
--
-- Expected OULAD student_vle benchmark:
--   Bronze rows:                     10,655,280
--   Silver daily interaction rows:   8,459,320
--   Expected row reduction:           2,195,960
--
-- A reduction in row count is expected for student_vle because repeated daily
-- interactions are aggregated. Recorded clicks must NOT be reduced.
--
-- This file performs no INSERT, UPDATE, DELETE, MERGE or table creation.
-- ================================================================================================



-- ================================================================================================
-- 1. STUDENT_VLE — GLOBAL RECONCILIATION
-- ================================================================================================
-- Compare:
--   raw Bronze rows
--   valid typed Bronze rows
--   unique valid daily interaction keys
--   Silver rows
--   Bronze clicks
--   Silver clicks
--
-- Expected:
--   silver_rows = valid_unique_daily_keys
--   click_difference = 0
--
-- For the documented current OULAD source:
--   raw_bronze_rows              = 10,655,280
--   silver_rows                  =  8,459,320
--   raw_to_silver_row_reduction  =  2,195,960
-- ================================================================================================

WITH bronze_normalized AS (
  SELECT
    CASE
      WHEN code_module IS NULL
        OR UPPER(TRIM(CAST(code_module AS STRING))) IN ('', '?', 'NA', 'N/A', 'NULL')
        THEN NULL
      ELSE UPPER(TRIM(CAST(code_module AS STRING)))
    END AS code_module,

    CASE
      WHEN code_presentation IS NULL
        OR UPPER(TRIM(CAST(code_presentation AS STRING))) IN ('', '?', 'NA', 'N/A', 'NULL')
        THEN NULL
      ELSE UPPER(TRIM(CAST(code_presentation AS STRING)))
    END AS code_presentation,

    CASE
      WHEN id_student IS NULL
        OR UPPER(TRIM(CAST(id_student AS STRING))) IN ('', '?', 'NA', 'N/A', 'NULL')
        THEN NULL
      ELSE TRIM(CAST(id_student AS STRING))
    END AS id_student_normalized,

    CASE
      WHEN id_site IS NULL
        OR UPPER(TRIM(CAST(id_site AS STRING))) IN ('', '?', 'NA', 'N/A', 'NULL')
        THEN NULL
      ELSE TRIM(CAST(id_site AS STRING))
    END AS id_site_normalized,

    CASE
      WHEN date IS NULL
        OR UPPER(TRIM(CAST(date AS STRING))) IN ('', '?', 'NA', 'N/A', 'NULL')
        THEN NULL
      ELSE TRIM(CAST(date AS STRING))
    END AS date_normalized,

    CASE
      WHEN sum_click IS NULL
        OR UPPER(TRIM(CAST(sum_click AS STRING))) IN ('', '?', 'NA', 'N/A', 'NULL')
        THEN NULL
      ELSE TRIM(CAST(sum_click AS STRING))
    END AS sum_click_normalized

  FROM open_university.oulad_bronze.student_vle_raw
),

bronze_typed AS (
  SELECT
    code_module,
    code_presentation,
    TRY_CAST(id_student_normalized AS BIGINT) AS id_student,
    TRY_CAST(id_site_normalized AS BIGINT) AS id_site,
    TRY_CAST(date_normalized AS INT) AS date,
    TRY_CAST(sum_click_normalized AS BIGINT) AS sum_click,

    CASE
      WHEN code_module IS NULL THEN 'MISSING_CODE_MODULE'
      WHEN code_presentation IS NULL THEN 'MISSING_CODE_PRESENTATION'
      WHEN id_student_normalized IS NULL THEN 'MISSING_ID_STUDENT'
      WHEN TRY_CAST(id_student_normalized AS BIGINT) IS NULL THEN 'INVALID_ID_STUDENT'
      WHEN id_site_normalized IS NULL THEN 'MISSING_ID_SITE'
      WHEN TRY_CAST(id_site_normalized AS BIGINT) IS NULL THEN 'INVALID_ID_SITE'
      WHEN date_normalized IS NULL THEN 'MISSING_DATE'
      WHEN TRY_CAST(date_normalized AS INT) IS NULL THEN 'INVALID_DATE'
      WHEN sum_click_normalized IS NULL THEN 'MISSING_SUM_CLICK'
      WHEN TRY_CAST(sum_click_normalized AS BIGINT) IS NULL THEN 'INVALID_SUM_CLICK'
      WHEN TRY_CAST(sum_click_normalized AS BIGINT) < 0 THEN 'NEGATIVE_SUM_CLICK'
      ELSE NULL
    END AS rejection_reason

  FROM bronze_normalized
),

bronze_summary AS (
  SELECT
    COUNT(*) AS raw_bronze_rows,

    COUNT_IF(rejection_reason IS NULL)
      AS valid_bronze_rows,

    COUNT_IF(rejection_reason IS NOT NULL)
      AS invalid_bronze_rows,

    COUNT(
      DISTINCT CASE
        WHEN rejection_reason IS NULL THEN
          STRUCT(
            code_module,
            code_presentation,
            id_student,
            id_site,
            date
          )
      END
    ) AS valid_unique_daily_keys,

    SUM(
      CASE
        WHEN rejection_reason IS NULL THEN sum_click
        ELSE 0
      END
    ) AS valid_bronze_clicks

  FROM bronze_typed
),

silver_summary AS (
  SELECT
    COUNT(*) AS silver_rows,
    SUM(sum_click) AS silver_clicks
  FROM open_university.oulad_silver.student_vle_clean
)

SELECT
  b.raw_bronze_rows,
  b.valid_bronze_rows,
  b.invalid_bronze_rows,
  b.valid_unique_daily_keys,

  s.silver_rows,

  b.raw_bronze_rows - s.silver_rows
    AS raw_to_silver_row_reduction,

  b.valid_bronze_rows - b.valid_unique_daily_keys
    AS aggregation_row_reduction,

  b.valid_bronze_clicks,
  s.silver_clicks,

  s.silver_rows - b.valid_unique_daily_keys
    AS row_count_difference,

  s.silver_clicks - b.valid_bronze_clicks
    AS click_difference

FROM bronze_summary b
CROSS JOIN silver_summary s;


-- Expected:
--
-- row_count_difference = 0
-- click_difference     = 0
--
-- Current documented benchmark, assuming no invalid Bronze records:
--
-- raw_bronze_rows             = 10,655,280
-- silver_rows                 =  8,459,320
-- raw_to_silver_row_reduction =  2,195,960



-- ================================================================================================
-- 2. STUDENT_VLE — CLASSIFY INVALID BRONZE RECORDS
-- ================================================================================================
-- This separates genuine invalid conversions from the intentional aggregation reduction.
--
-- Expected:
--   Ideally 0 invalid records.
--
-- If rows are returned, they must be explained separately and must NOT be mistaken
-- for rows removed by daily aggregation.
-- ================================================================================================

WITH normalized AS (
  SELECT
    CASE
      WHEN code_module IS NULL
        OR UPPER(TRIM(CAST(code_module AS STRING))) IN ('', '?', 'NA', 'N/A', 'NULL')
        THEN NULL
      ELSE UPPER(TRIM(CAST(code_module AS STRING)))
    END AS code_module,

    CASE
      WHEN code_presentation IS NULL
        OR UPPER(TRIM(CAST(code_presentation AS STRING))) IN ('', '?', 'NA', 'N/A', 'NULL')
        THEN NULL
      ELSE UPPER(TRIM(CAST(code_presentation AS STRING)))
    END AS code_presentation,

    CASE
      WHEN id_student IS NULL
        OR UPPER(TRIM(CAST(id_student AS STRING))) IN ('', '?', 'NA', 'N/A', 'NULL')
        THEN NULL
      ELSE TRIM(CAST(id_student AS STRING))
    END AS id_student_value,

    CASE
      WHEN id_site IS NULL
        OR UPPER(TRIM(CAST(id_site AS STRING))) IN ('', '?', 'NA', 'N/A', 'NULL')
        THEN NULL
      ELSE TRIM(CAST(id_site AS STRING))
    END AS id_site_value,

    CASE
      WHEN date IS NULL
        OR UPPER(TRIM(CAST(date AS STRING))) IN ('', '?', 'NA', 'N/A', 'NULL')
        THEN NULL
      ELSE TRIM(CAST(date AS STRING))
    END AS date_value,

    CASE
      WHEN sum_click IS NULL
        OR UPPER(TRIM(CAST(sum_click AS STRING))) IN ('', '?', 'NA', 'N/A', 'NULL')
        THEN NULL
      ELSE TRIM(CAST(sum_click AS STRING))
    END AS sum_click_value

  FROM open_university.oulad_bronze.student_vle_raw
),

classified AS (
  SELECT
    CASE
      WHEN code_module IS NULL THEN 'MISSING_CODE_MODULE'
      WHEN code_presentation IS NULL THEN 'MISSING_CODE_PRESENTATION'

      WHEN id_student_value IS NULL THEN 'MISSING_ID_STUDENT'
      WHEN TRY_CAST(id_student_value AS BIGINT) IS NULL THEN 'INVALID_ID_STUDENT'

      WHEN id_site_value IS NULL THEN 'MISSING_ID_SITE'
      WHEN TRY_CAST(id_site_value AS BIGINT) IS NULL THEN 'INVALID_ID_SITE'

      WHEN date_value IS NULL THEN 'MISSING_DATE'
      WHEN TRY_CAST(date_value AS INT) IS NULL THEN 'INVALID_DATE'

      WHEN sum_click_value IS NULL THEN 'MISSING_SUM_CLICK'
      WHEN TRY_CAST(sum_click_value AS BIGINT) IS NULL THEN 'INVALID_SUM_CLICK'
      WHEN TRY_CAST(sum_click_value AS BIGINT) < 0 THEN 'NEGATIVE_SUM_CLICK'

      ELSE NULL
    END AS rejection_reason

  FROM normalized
)

SELECT
  rejection_reason,
  COUNT(*) AS failure_count
FROM classified
WHERE rejection_reason IS NOT NULL
GROUP BY rejection_reason
ORDER BY failure_count DESC;


-- Expected:
--   0 rows unless documented source-quality exceptions exist.



-- ================================================================================================
-- 3. STUDENT_VLE — CLICK RECONCILIATION BY MODULE / PRESENTATION
-- ================================================================================================
-- Proves that aggregation does not change the number of recorded clicks within
-- any module presentation.
--
-- Expected:
--   0 rows.
-- ================================================================================================

WITH bronze_normalized AS (
  SELECT
    CASE
      WHEN code_module IS NULL
        OR UPPER(TRIM(CAST(code_module AS STRING))) IN ('', '?', 'NA', 'N/A', 'NULL')
        THEN NULL
      ELSE UPPER(TRIM(CAST(code_module AS STRING)))
    END AS code_module,

    CASE
      WHEN code_presentation IS NULL
        OR UPPER(TRIM(CAST(code_presentation AS STRING))) IN ('', '?', 'NA', 'N/A', 'NULL')
        THEN NULL
      ELSE UPPER(TRIM(CAST(code_presentation AS STRING)))
    END AS code_presentation,

    TRY_CAST(
      CASE
        WHEN id_student IS NULL
          OR UPPER(TRIM(CAST(id_student AS STRING))) IN ('', '?', 'NA', 'N/A', 'NULL')
          THEN NULL
        ELSE TRIM(CAST(id_student AS STRING))
      END AS BIGINT
    ) AS id_student,

    TRY_CAST(
      CASE
        WHEN id_site IS NULL
          OR UPPER(TRIM(CAST(id_site AS STRING))) IN ('', '?', 'NA', 'N/A', 'NULL')
          THEN NULL
        ELSE TRIM(CAST(id_site AS STRING))
      END AS BIGINT
    ) AS id_site,

    TRY_CAST(
      CASE
        WHEN date IS NULL
          OR UPPER(TRIM(CAST(date AS STRING))) IN ('', '?', 'NA', 'N/A', 'NULL')
          THEN NULL
        ELSE TRIM(CAST(date AS STRING))
      END AS INT
    ) AS date,

    TRY_CAST(
      CASE
        WHEN sum_click IS NULL
          OR UPPER(TRIM(CAST(sum_click AS STRING))) IN ('', '?', 'NA', 'N/A', 'NULL')
          THEN NULL
        ELSE TRIM(CAST(sum_click AS STRING))
      END AS BIGINT
    ) AS sum_click

  FROM open_university.oulad_bronze.student_vle_raw
),

bronze_valid AS (
  SELECT *
  FROM bronze_normalized
  WHERE code_module IS NOT NULL
    AND code_presentation IS NOT NULL
    AND id_student IS NOT NULL
    AND id_site IS NOT NULL
    AND date IS NOT NULL
    AND sum_click IS NOT NULL
    AND sum_click >= 0
),

bronze_totals AS (
  SELECT
    code_module,
    code_presentation,
    SUM(sum_click) AS bronze_clicks
  FROM bronze_valid
  GROUP BY
    code_module,
    code_presentation
),

silver_totals AS (
  SELECT
    code_module,
    code_presentation,
    SUM(sum_click) AS silver_clicks
  FROM open_university.oulad_silver.student_vle_clean
  GROUP BY
    code_module,
    code_presentation
)

SELECT
  COALESCE(b.code_module, s.code_module) AS code_module,
  COALESCE(b.code_presentation, s.code_presentation) AS code_presentation,

  b.bronze_clicks,
  s.silver_clicks,

  COALESCE(s.silver_clicks, 0)
    - COALESCE(b.bronze_clicks, 0)
    AS click_difference

FROM bronze_totals b
FULL OUTER JOIN silver_totals s
  ON b.code_module = s.code_module
 AND b.code_presentation = s.code_presentation

WHERE COALESCE(b.bronze_clicks, 0)
   <> COALESCE(s.silver_clicks, 0)

ORDER BY
  code_module,
  code_presentation;


-- Expected:
--   0 rows.



-- ================================================================================================
-- 4. STUDENT_VLE — COMPLETE DAILY KEY RECONCILIATION
-- ================================================================================================
-- Bronze is first aggregated to the EXACT Silver grain:
--
--   code_module
--   code_presentation
--   id_student
--   id_site
--   date
--
-- Then both key coverage and sum_click are compared.
--
-- Expected:
--   0 rows.
-- ================================================================================================

WITH bronze_typed AS (
  SELECT
    CASE
      WHEN code_module IS NULL
        OR UPPER(TRIM(CAST(code_module AS STRING))) IN ('', '?', 'NA', 'N/A', 'NULL')
        THEN NULL
      ELSE UPPER(TRIM(CAST(code_module AS STRING)))
    END AS code_module,

    CASE
      WHEN code_presentation IS NULL
        OR UPPER(TRIM(CAST(code_presentation AS STRING))) IN ('', '?', 'NA', 'N/A', 'NULL')
        THEN NULL
      ELSE UPPER(TRIM(CAST(code_presentation AS STRING)))
    END AS code_presentation,

    TRY_CAST(
      NULLIF(
        CASE
          WHEN UPPER(TRIM(CAST(id_student AS STRING))) IN ('?', 'NA', 'N/A', 'NULL')
            THEN ''
          ELSE TRIM(CAST(id_student AS STRING))
        END,
        ''
      ) AS BIGINT
    ) AS id_student,

    TRY_CAST(
      NULLIF(
        CASE
          WHEN UPPER(TRIM(CAST(id_site AS STRING))) IN ('?', 'NA', 'N/A', 'NULL')
            THEN ''
          ELSE TRIM(CAST(id_site AS STRING))
        END,
        ''
      ) AS BIGINT
    ) AS id_site,

    TRY_CAST(
      NULLIF(
        CASE
          WHEN UPPER(TRIM(CAST(date AS STRING))) IN ('?', 'NA', 'N/A', 'NULL')
            THEN ''
          ELSE TRIM(CAST(date AS STRING))
        END,
        ''
      ) AS INT
    ) AS date,

    TRY_CAST(
      NULLIF(
        CASE
          WHEN UPPER(TRIM(CAST(sum_click AS STRING))) IN ('?', 'NA', 'N/A', 'NULL')
            THEN ''
          ELSE TRIM(CAST(sum_click AS STRING))
        END,
        ''
      ) AS BIGINT
    ) AS sum_click

  FROM open_university.oulad_bronze.student_vle_raw
),

bronze_daily AS (
  SELECT
    code_module,
    code_presentation,
    id_student,
    id_site,
    date,
    SUM(sum_click) AS bronze_sum_click,
    COUNT(*) AS bronze_source_row_count

  FROM bronze_typed

  WHERE code_module IS NOT NULL
    AND code_presentation IS NOT NULL
    AND id_student IS NOT NULL
    AND id_site IS NOT NULL
    AND date IS NOT NULL
    AND sum_click IS NOT NULL
    AND sum_click >= 0

  GROUP BY
    code_module,
    code_presentation,
    id_student,
    id_site,
    date
)

SELECT
  COALESCE(b.code_module, s.code_module) AS code_module,
  COALESCE(b.code_presentation, s.code_presentation) AS code_presentation,
  COALESCE(b.id_student, s.id_student) AS id_student,
  COALESCE(b.id_site, s.id_site) AS id_site,
  COALESCE(b.date, s.date) AS date,

  b.bronze_sum_click,
  s.sum_click AS silver_sum_click,

  b.bronze_source_row_count,
  s.source_row_count AS silver_source_row_count,

  CASE
    WHEN b.code_module IS NULL THEN 'EXTRA_IN_SILVER'
    WHEN s.code_module IS NULL THEN 'MISSING_FROM_SILVER'
    WHEN b.bronze_sum_click <> s.sum_click THEN 'CLICK_MISMATCH'
    WHEN b.bronze_source_row_count <> s.source_row_count THEN 'SOURCE_ROW_COUNT_MISMATCH'
  END AS reconciliation_failure

FROM bronze_daily b

FULL OUTER JOIN open_university.oulad_silver.student_vle_clean s

  ON  b.code_module = s.code_module
  AND b.code_presentation = s.code_presentation
  AND b.id_student = s.id_student
  AND b.id_site = s.id_site
  AND b.date = s.date

WHERE b.code_module IS NULL
   OR s.code_module IS NULL
   OR b.bronze_sum_click <> s.sum_click
   OR b.bronze_source_row_count <> s.source_row_count

ORDER BY
  code_module,
  code_presentation,
  id_student,
  id_site,
  date;


-- Expected:
--   0 rows.



-- ================================================================================================
-- 5. STUDENT_VLE — DAILY RECONCILIATION FAILURE COUNTS
-- ================================================================================================
-- Compact version of the previous check.
--
-- Expected:
--
--   missing_from_silver          = 0
--   extra_in_silver              = 0
--   click_mismatches             = 0
--   source_row_count_mismatches  = 0
-- ================================================================================================

WITH bronze_typed AS (
  SELECT
    CASE
      WHEN code_module IS NULL
        OR UPPER(TRIM(CAST(code_module AS STRING))) IN ('', '?', 'NA', 'N/A', 'NULL')
        THEN NULL
      ELSE UPPER(TRIM(CAST(code_module AS STRING)))
    END AS code_module,

    CASE
      WHEN code_presentation IS NULL
        OR UPPER(TRIM(CAST(code_presentation AS STRING))) IN ('', '?', 'NA', 'N/A', 'NULL')
        THEN NULL
      ELSE UPPER(TRIM(CAST(code_presentation AS STRING)))
    END AS code_presentation,

    TRY_CAST(TRIM(CAST(id_student AS STRING)) AS BIGINT) AS id_student,
    TRY_CAST(TRIM(CAST(id_site AS STRING)) AS BIGINT) AS id_site,
    TRY_CAST(TRIM(CAST(date AS STRING)) AS INT) AS date,
    TRY_CAST(TRIM(CAST(sum_click AS STRING)) AS BIGINT) AS sum_click

  FROM open_university.oulad_bronze.student_vle_raw
),

bronze_daily AS (
  SELECT
    code_module,
    code_presentation,
    id_student,
    id_site,
    date,
    SUM(sum_click) AS sum_click,
    COUNT(*) AS source_row_count

  FROM bronze_typed

  WHERE code_module IS NOT NULL
    AND code_presentation IS NOT NULL
    AND id_student IS NOT NULL
    AND id_site IS NOT NULL
    AND date IS NOT NULL
    AND sum_click IS NOT NULL
    AND sum_click >= 0

  GROUP BY
    code_module,
    code_presentation,
    id_student,
    id_site,
    date
),

comparison AS (
  SELECT
    b.code_module AS bronze_code_module,
    s.code_module AS silver_code_module,

    b.sum_click AS bronze_sum_click,
    s.sum_click AS silver_sum_click,

    b.source_row_count AS bronze_source_row_count,
    s.source_row_count AS silver_source_row_count

  FROM bronze_daily b

  FULL OUTER JOIN open_university.oulad_silver.student_vle_clean s

    ON  b.code_module = s.code_module
    AND b.code_presentation = s.code_presentation
    AND b.id_student = s.id_student
    AND b.id_site = s.id_site
    AND b.date = s.date
)

SELECT
  COUNT_IF(
    bronze_code_module IS NOT NULL
    AND silver_code_module IS NULL
  ) AS missing_from_silver,

  COUNT_IF(
    bronze_code_module IS NULL
    AND silver_code_module IS NOT NULL
  ) AS extra_in_silver,

  COUNT_IF(
    bronze_code_module IS NOT NULL
    AND silver_code_module IS NOT NULL
    AND bronze_sum_click <> silver_sum_click
  ) AS click_mismatches,

  COUNT_IF(
    bronze_code_module IS NOT NULL
    AND silver_code_module IS NOT NULL
    AND bronze_source_row_count <> silver_source_row_count
  ) AS source_row_count_mismatches

FROM comparison;



-- ================================================================================================
-- 6. STUDENT_VLE — PROVE THE 2,195,960 ROW REDUCTION IS AGGREGATION
-- ================================================================================================
-- This explicitly distinguishes:
--
--   Bronze physical rows
--       versus
--   unique complete daily interaction keys
--
-- Expected current dataset:
--
--   bronze_rows               = 10,655,280
--   silver_rows               =  8,459,320
--   rows_combined             =  2,195,960
--   click_difference          =  0
--
-- If invalid Bronze records exist, review them separately because the exact raw
-- reduction may include rejected rows as well as aggregation.
-- ================================================================================================

WITH typed_bronze AS (
  SELECT
    CASE
      WHEN code_module IS NULL
        OR UPPER(TRIM(CAST(code_module AS STRING))) IN ('', '?', 'NA', 'N/A', 'NULL')
        THEN NULL
      ELSE UPPER(TRIM(CAST(code_module AS STRING)))
    END AS code_module,

    CASE
      WHEN code_presentation IS NULL
        OR UPPER(TRIM(CAST(code_presentation AS STRING))) IN ('', '?', 'NA', 'N/A', 'NULL')
        THEN NULL
      ELSE UPPER(TRIM(CAST(code_presentation AS STRING)))
    END AS code_presentation,

    TRY_CAST(TRIM(CAST(id_student AS STRING)) AS BIGINT) AS id_student,
    TRY_CAST(TRIM(CAST(id_site AS STRING)) AS BIGINT) AS id_site,
    TRY_CAST(TRIM(CAST(date AS STRING)) AS INT) AS date,
    TRY_CAST(TRIM(CAST(sum_click AS STRING)) AS BIGINT) AS sum_click

  FROM open_university.oulad_bronze.student_vle_raw
),

valid_bronze AS (
  SELECT *
  FROM typed_bronze
  WHERE code_module IS NOT NULL
    AND code_presentation IS NOT NULL
    AND id_student IS NOT NULL
    AND id_site IS NOT NULL
    AND date IS NOT NULL
    AND sum_click IS NOT NULL
    AND sum_click >= 0
),

bronze_counts AS (
  SELECT
    COUNT(*) AS valid_bronze_rows,

    COUNT(
      DISTINCT STRUCT(
        code_module,
        code_presentation,
        id_student,
        id_site,
        date
      )
    ) AS unique_daily_keys,

    SUM(sum_click) AS bronze_clicks

  FROM valid_bronze
),

raw_count AS (
  SELECT
    COUNT(*) AS raw_bronze_rows
  FROM open_university.oulad_bronze.student_vle_raw
),

silver_counts AS (
  SELECT
    COUNT(*) AS silver_rows,
    SUM(sum_click) AS silver_clicks
  FROM open_university.oulad_silver.student_vle_clean
)

SELECT
  r.raw_bronze_rows,
  b.valid_bronze_rows,
  b.unique_daily_keys,
  s.silver_rows,

  b.valid_bronze_rows - b.unique_daily_keys
    AS rows_combined_by_aggregation,

  r.raw_bronze_rows - s.silver_rows
    AS total_raw_to_silver_reduction,

  b.bronze_clicks,
  s.silver_clicks,

  s.silver_clicks - b.bronze_clicks
    AS click_difference

FROM raw_count r
CROSS JOIN bronze_counts b
CROSS JOIN silver_counts s;


-- Expected:
--
-- unique_daily_keys = silver_rows
-- click_difference  = 0
--
-- With the documented clean OULAD snapshot:
--
-- raw_bronze_rows              = 10,655,280
-- silver_rows                  =  8,459,320
-- total_raw_to_silver_reduction = 2,195,960



-- ================================================================================================
-- 7. VLE_CLEAN — BRONZE -> SILVER BUSINESS-KEY COVERAGE
-- ================================================================================================
-- Expected VLE business key:
--
--   (code_module, code_presentation, id_site)
--
-- This finds valid Bronze VLE keys that disappeared during cleaning.
--
-- Expected:
--   0 rows.
-- ================================================================================================

WITH bronze_keys AS (
  SELECT DISTINCT

    CASE
      WHEN code_module IS NULL
        OR UPPER(TRIM(CAST(code_module AS STRING))) IN ('', '?', 'NA', 'N/A', 'NULL')
        THEN NULL
      ELSE UPPER(TRIM(CAST(code_module AS STRING)))
    END AS code_module,

    CASE
      WHEN code_presentation IS NULL
        OR UPPER(TRIM(CAST(code_presentation AS STRING))) IN ('', '?', 'NA', 'N/A', 'NULL')
        THEN NULL
      ELSE UPPER(TRIM(CAST(code_presentation AS STRING)))
    END AS code_presentation,

    TRY_CAST(
      CASE
        WHEN id_site IS NULL
          OR UPPER(TRIM(CAST(id_site AS STRING))) IN ('', '?', 'NA', 'N/A', 'NULL')
          THEN NULL
        ELSE TRIM(CAST(id_site AS STRING))
      END AS BIGINT
    ) AS id_site

  FROM open_university.oulad_bronze.vle_raw
),

valid_bronze_keys AS (
  SELECT *
  FROM bronze_keys
  WHERE code_module IS NOT NULL
    AND code_presentation IS NOT NULL
    AND id_site IS NOT NULL
)

SELECT
  b.code_module,
  b.code_presentation,
  b.id_site

FROM valid_bronze_keys b

LEFT ANTI JOIN open_university.oulad_silver.vle_clean s

  ON  b.code_module = s.code_module
  AND b.code_presentation = s.code_presentation
  AND b.id_site = s.id_site

ORDER BY
  b.code_module,
  b.code_presentation,
  b.id_site;


-- Expected:
--   0 rows.



-- ================================================================================================
-- 8. VLE_CLEAN — SILVER -> BRONZE BUSINESS-KEY COVERAGE
-- ================================================================================================
-- Finds Silver VLE keys that have no valid normalized Bronze source key.
--
-- Expected:
--   0 rows.
-- ================================================================================================

WITH bronze_keys AS (
  SELECT DISTINCT

    CASE
      WHEN code_module IS NULL
        OR UPPER(TRIM(CAST(code_module AS STRING))) IN ('', '?', 'NA', 'N/A', 'NULL')
        THEN NULL
      ELSE UPPER(TRIM(CAST(code_module AS STRING)))
    END AS code_module,

    CASE
      WHEN code_presentation IS NULL
        OR UPPER(TRIM(CAST(code_presentation AS STRING))) IN ('', '?', 'NA', 'N/A', 'NULL')
        THEN NULL
      ELSE UPPER(TRIM(CAST(code_presentation AS STRING)))
    END AS code_presentation,

    TRY_CAST(
      CASE
        WHEN id_site IS NULL
          OR UPPER(TRIM(CAST(id_site AS STRING))) IN ('', '?', 'NA', 'N/A', 'NULL')
          THEN NULL
        ELSE TRIM(CAST(id_site AS STRING))
      END AS BIGINT
    ) AS id_site

  FROM open_university.oulad_bronze.vle_raw
),

valid_bronze_keys AS (
  SELECT *
  FROM bronze_keys
  WHERE code_module IS NOT NULL
    AND code_presentation IS NOT NULL
    AND id_site IS NOT NULL
)

SELECT
  s.code_module,
  s.code_presentation,
  s.id_site

FROM open_university.oulad_silver.vle_clean s

LEFT ANTI JOIN valid_bronze_keys b

  ON  s.code_module = b.code_module
  AND s.code_presentation = b.code_presentation
  AND s.id_site = b.id_site

ORDER BY
  s.code_module,
  s.code_presentation,
  s.id_site;


-- Expected:
--   0 rows.



-- ================================================================================================
-- 9. VLE_CLEAN — BUSINESS-KEY COUNT RECONCILIATION
-- ================================================================================================
-- Compact coverage check.
--
-- Expected:
--
--   valid_bronze_business_keys = silver_business_rows
--   key_count_difference       = 0
-- ================================================================================================

WITH bronze_keys AS (
  SELECT DISTINCT

    CASE
      WHEN code_module IS NULL
        OR UPPER(TRIM(CAST(code_module AS STRING))) IN ('', '?', 'NA', 'N/A', 'NULL')
        THEN NULL
      ELSE UPPER(TRIM(CAST(code_module AS STRING)))
    END AS code_module,

    CASE
      WHEN code_presentation IS NULL
        OR UPPER(TRIM(CAST(code_presentation AS STRING))) IN ('', '?', 'NA', 'N/A', 'NULL')
        THEN NULL
      ELSE UPPER(TRIM(CAST(code_presentation AS STRING)))
    END AS code_presentation,

    TRY_CAST(TRIM(CAST(id_site AS STRING)) AS BIGINT) AS id_site

  FROM open_university.oulad_bronze.vle_raw
),

bronze_summary AS (
  SELECT
    COUNT(*) AS valid_bronze_business_keys
  FROM bronze_keys
  WHERE code_module IS NOT NULL
    AND code_presentation IS NOT NULL
    AND id_site IS NOT NULL
),

silver_summary AS (
  SELECT
    COUNT(*) AS silver_business_rows
  FROM open_university.oulad_silver.vle_clean
)

SELECT
  b.valid_bronze_business_keys,
  s.silver_business_rows,

  s.silver_business_rows
    - b.valid_bronze_business_keys
    AS key_count_difference

FROM bronze_summary b
CROSS JOIN silver_summary s;


-- Expected:
--   key_count_difference = 0



-- ================================================================================================
-- 10. VLE_CLEAN — ATTRIBUTE RECONCILIATION
-- ================================================================================================
-- Beyond business-key coverage, confirm the main VLE attributes were preserved:
--
--   activity_type
--   week_from
--   week_to
--
-- Source placeholders are normalized before comparison.
--
-- Expected:
--   0 rows.
-- ================================================================================================

WITH bronze_typed AS (
  SELECT

    CASE
      WHEN code_module IS NULL
        OR UPPER(TRIM(CAST(code_module AS STRING))) IN ('', '?', 'NA', 'N/A', 'NULL')
        THEN NULL
      ELSE UPPER(TRIM(CAST(code_module AS STRING)))
    END AS code_module,

    CASE
      WHEN code_presentation IS NULL
        OR UPPER(TRIM(CAST(code_presentation AS STRING))) IN ('', '?', 'NA', 'N/A', 'NULL')
        THEN NULL
      ELSE UPPER(TRIM(CAST(code_presentation AS STRING)))
    END AS code_presentation,

    TRY_CAST(TRIM(CAST(id_site AS STRING)) AS BIGINT) AS id_site,

    CASE
      WHEN activity_type IS NULL
        OR UPPER(TRIM(CAST(activity_type AS STRING))) IN ('', '?', 'NA', 'N/A', 'NULL')
        THEN NULL
      ELSE TRIM(CAST(activity_type AS STRING))
    END AS activity_type,

    TRY_CAST(
      CASE
        WHEN week_from IS NULL
          OR UPPER(TRIM(CAST(week_from AS STRING))) IN ('', '?', 'NA', 'N/A', 'NULL')
          THEN NULL
        ELSE TRIM(CAST(week_from AS STRING))
      END AS INT
    ) AS week_from,

    TRY_CAST(
      CASE
        WHEN week_to IS NULL
          OR UPPER(TRIM(CAST(week_to AS STRING))) IN ('', '?', 'NA', 'N/A', 'NULL')
          THEN NULL
        ELSE TRIM(CAST(week_to AS STRING))
      END AS INT
    ) AS week_to

  FROM open_university.oulad_bronze.vle_raw
),

bronze_valid AS (
  SELECT *
  FROM bronze_typed
  WHERE code_module IS NOT NULL
    AND code_presentation IS NOT NULL
    AND id_site IS NOT NULL
)

SELECT
  b.code_module,
  b.code_presentation,
  b.id_site,

  b.activity_type AS bronze_activity_type,
  s.activity_type AS silver_activity_type,

  b.week_from AS bronze_week_from,
  s.week_from AS silver_week_from,

  b.week_to AS bronze_week_to,
  s.week_to AS silver_week_to

FROM bronze_valid b

INNER JOIN open_university.oulad_silver.vle_clean s

  ON  b.code_module = s.code_module
  AND b.code_presentation = s.code_presentation
  AND b.id_site = s.id_site

WHERE NOT (b.activity_type <=> s.activity_type)
   OR NOT (b.week_from <=> s.week_from)
   OR NOT (b.week_to <=> s.week_to)

ORDER BY
  b.code_module,
  b.code_presentation,
  b.id_site;


-- Expected:
--   0 rows.
--
-- `<=>` is Spark SQL's NULL-safe equality operator.
-- This is important because NULL optional week values may legitimately match NULL.



-- ================================================================================================
-- 11. COMBINED RECONCILIATION SUMMARY
-- ================================================================================================
-- Compact high-level result for manual Databricks QA.
--
-- Expected:
--
--   student_vle row difference   = 0
--   student_vle click difference = 0
--   vle key difference           = 0
-- ================================================================================================

WITH student_bronze AS (
  SELECT
    CASE
      WHEN code_module IS NULL
        OR UPPER(TRIM(CAST(code_module AS STRING))) IN ('', '?', 'NA', 'N/A', 'NULL')
        THEN NULL
      ELSE UPPER(TRIM(CAST(code_module AS STRING)))
    END AS code_module,

    CASE
      WHEN code_presentation IS NULL
        OR UPPER(TRIM(CAST(code_presentation AS STRING))) IN ('', '?', 'NA', 'N/A', 'NULL')
        THEN NULL
      ELSE UPPER(TRIM(CAST(code_presentation AS STRING)))
    END AS code_presentation,

    TRY_CAST(TRIM(CAST(id_student AS STRING)) AS BIGINT) AS id_student,
    TRY_CAST(TRIM(CAST(id_site AS STRING)) AS BIGINT) AS id_site,
    TRY_CAST(TRIM(CAST(date AS STRING)) AS INT) AS date,
    TRY_CAST(TRIM(CAST(sum_click AS STRING)) AS BIGINT) AS sum_click

  FROM open_university.oulad_bronze.student_vle_raw
),

student_valid AS (
  SELECT *
  FROM student_bronze
  WHERE code_module IS NOT NULL
    AND code_presentation IS NOT NULL
    AND id_student IS NOT NULL
    AND id_site IS NOT NULL
    AND date IS NOT NULL
    AND sum_click IS NOT NULL
    AND sum_click >= 0
),

student_daily AS (
  SELECT
    code_module,
    code_presentation,
    id_student,
    id_site,
    date,
    SUM(sum_click) AS sum_click
  FROM student_valid
  GROUP BY
    code_module,
    code_presentation,
    id_student,
    id_site,
    date
),

student_bronze_summary AS (
  SELECT
    COUNT(*) AS expected_rows,
    SUM(sum_click) AS expected_clicks
  FROM student_daily
),

student_silver_summary AS (
  SELECT
    COUNT(*) AS actual_rows,
    SUM(sum_click) AS actual_clicks
  FROM open_university.oulad_silver.student_vle_clean
),

vle_bronze_keys AS (
  SELECT DISTINCT
    CASE
      WHEN code_module IS NULL
        OR UPPER(TRIM(CAST(code_module AS STRING))) IN ('', '?', 'NA', 'N/A', 'NULL')
        THEN NULL
      ELSE UPPER(TRIM(CAST(code_module AS STRING)))
    END AS code_module,

    CASE
      WHEN code_presentation IS NULL
        OR UPPER(TRIM(CAST(code_presentation AS STRING))) IN ('', '?', 'NA', 'N/A', 'NULL')
        THEN NULL
      ELSE UPPER(TRIM(CAST(code_presentation AS STRING)))
    END AS code_presentation,

    TRY_CAST(TRIM(CAST(id_site AS STRING)) AS BIGINT) AS id_site

  FROM open_university.oulad_bronze.vle_raw
),

vle_bronze_summary AS (
  SELECT
    COUNT(*) AS expected_rows
  FROM vle_bronze_keys
  WHERE code_module IS NOT NULL
    AND code_presentation IS NOT NULL
    AND id_site IS NOT NULL
),

vle_silver_summary AS (
  SELECT
    COUNT(*) AS actual_rows
  FROM open_university.oulad_silver.vle_clean
)

SELECT
  'student_vle_clean' AS table_name,
  'business_row_count' AS check_name,
  sb.expected_rows AS expected_value,
  ss.actual_rows AS actual_value,
  ss.actual_rows - sb.expected_rows AS difference

FROM student_bronze_summary sb
CROSS JOIN student_silver_summary ss

UNION ALL

SELECT
  'student_vle_clean',
  'sum_click',
  sb.expected_clicks,
  ss.actual_clicks,
  ss.actual_clicks - sb.expected_clicks

FROM student_bronze_summary sb
CROSS JOIN student_silver_summary ss

UNION ALL

SELECT
  'vle_clean',
  'business_row_count',
  vb.expected_rows,
  vs.actual_rows,
  vs.actual_rows - vb.expected_rows

FROM vle_bronze_summary vb
CROSS JOIN vle_silver_summary vs

ORDER BY
  table_name,
  check_name;


-- Expected:
--   difference = 0 for every row.



-- ================================================================================================
-- 12. RERUN STABILITY CHECK
-- ================================================================================================
-- Rerun verification requires two observations:
--
--   1. Run this query BEFORE rerunning the same Bronze snapshot.
--   2. Run the Silver transformation again with unchanged Bronze.
--   3. Run this exact query again.
--
-- Expected:
--   The business-row counts and click totals must remain unchanged.
--
-- clean_load_timestamp is deliberately NOT included because a rerun may legitimately
-- refresh audit timestamps.
-- ================================================================================================

SELECT
  'student_vle_clean' AS table_name,

  COUNT(*) AS business_row_count,

  COUNT(
    DISTINCT STRUCT(
      code_module,
      code_presentation,
      id_student,
      id_site,
      date
    )
  ) AS distinct_business_keys,

  SUM(sum_click) AS total_measure

FROM open_university.oulad_silver.student_vle_clean

UNION ALL

SELECT
  'vle_clean',

  COUNT(*) AS business_row_count,

  COUNT(
    DISTINCT STRUCT(
      code_module,
      code_presentation,
      id_site
    )
  ) AS distinct_business_keys,

  CAST(NULL AS BIGINT) AS total_measure

FROM open_university.oulad_silver.vle_clean;


-- Expected after rerunning the SAME Bronze snapshot:
--
-- student_vle_clean
--   business_row_count   -> unchanged
--   distinct_business_keys -> unchanged
--   total_measure        -> unchanged
--
-- vle_clean
--   business_row_count     -> unchanged
--   distinct_business_keys -> unchanged
--
-- Most importantly:
--   student_vle_clean SUM(sum_click) must NOT increase after a rerun.



-- ================================================================================================
-- DONE WHEN
-- ================================================================================================
--
-- STUDENT_VLE
-- 1. Valid normalized Bronze daily-key count equals Silver row count.
-- 2. Global Bronze and Silver click totals are equal.
-- 3. Click difference by module/presentation is zero.
-- 4. Click difference by complete daily interaction key is zero.
-- 5. No valid Bronze daily keys are missing from Silver.
-- 6. No unexplained Silver daily keys exist outside Bronze.
-- 7. source_row_count agrees with the number of Bronze rows aggregated into each Silver row.
-- 8. Current documented source reduces from:
--
--        10,655,280 Bronze rows
--     to  8,459,320 Silver rows
--
--     giving:
--
--         2,195,960 combined rows
--
--     without losing clicks.
--
-- VLE
-- 9. Every valid normalized Bronze VLE business key exists in Silver.
-- 10. Every Silver VLE business key exists in normalized Bronze.
-- 11. VLE business-key counts agree.
-- 12. activity_type, week_from and week_to agree after normalization.
--
-- RERUN
-- 13. Reprocessing the same Bronze snapshot does not increase business-row counts.
-- 14. Reprocessing the same student_vle snapshot does not increase SUM(sum_click).
--
-- A displayed result does not automatically fail a Databricks job.
-- A runner must explicitly assert these expected values if automated failure behavior is required.
-- ================================================================================================