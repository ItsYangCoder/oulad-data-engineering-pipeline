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

-- ================================================================================================
-- File: 04_silver_value_checks.sql
-- Suggested branch: feature/add-silver-checks
-- Purpose: Find invalid types, unconverted placeholders and out-of-range values.
--
-- Input:
--   open_university.oulad_silver.student_vle_clean
--   open_university.oulad_silver.vle_clean
--
-- Output:
--   Read-only validation queries.
--
-- Expected:
--   Every failure query below should return 0 rows / 0 failures unless otherwise stated.
--
-- Notes:
--   - Negative relative dates in student_vle_clean are VALID and must not be rejected.
--   - week_from and week_to are optional in vle_clean and may remain NULL.
--   - week_from must only be <= week_to when BOTH values are present.
--   - Assessment-specific value checks such as CMA/TMA/Exam, score, weight and is_banked
--     do not apply to these two tables.
-- ================================================================================================


-- ================================================================================================
-- 1. DATA TYPE CHECKS
-- ================================================================================================

-- ------------------------------------------------------------------------------------------------
-- 1A. student_vle_clean expected data types
--
-- Expected result:
--   0 rows.
--
-- Any returned row means a column is missing or has an unexpected data type.
-- ------------------------------------------------------------------------------------------------

WITH expected_types AS (
  SELECT * FROM VALUES
    ('code_module',          'STRING'),
    ('code_presentation',    'STRING'),
    ('id_student',           'BIGINT'),
    ('id_site',              'BIGINT'),
    ('date',                 'INT'),
    ('sum_click',            'BIGINT'),
    ('source_row_count',     'BIGINT'),
    ('clean_load_timestamp', 'TIMESTAMP'),
    ('clean_load_date',      'DATE')
  AS expected(column_name, expected_data_type)
),

actual_types AS (
  SELECT
    column_name,
    UPPER(data_type) AS actual_data_type
  FROM open_university.information_schema.columns
  WHERE table_schema = 'oulad_silver'
    AND table_name = 'student_vle_clean'
)

SELECT
  e.column_name,
  e.expected_data_type,
  a.actual_data_type
FROM expected_types e
LEFT JOIN actual_types a
  ON e.column_name = a.column_name
WHERE a.column_name IS NULL
   OR a.actual_data_type <> e.expected_data_type;


-- ------------------------------------------------------------------------------------------------
-- 1B. vle_clean expected data types
--
-- Expected result:
--   0 rows.
--
-- OULAD VLE fields:
--   id_site
--   code_module
--   code_presentation
--   activity_type
--   week_from
--   week_to
-- ------------------------------------------------------------------------------------------------

WITH expected_types AS (
  SELECT * FROM VALUES
    ('id_site',              'BIGINT'),
    ('code_module',          'STRING'),
    ('code_presentation',    'STRING'),
    ('activity_type',        'STRING'),
    ('week_from',            'INT'),
    ('week_to',              'INT'),
    ('clean_load_timestamp', 'TIMESTAMP'),
    ('clean_load_date',      'DATE')
  AS expected(column_name, expected_data_type)
),

actual_types AS (
  SELECT
    column_name,
    UPPER(data_type) AS actual_data_type
  FROM open_university.information_schema.columns
  WHERE table_schema = 'oulad_silver'
    AND table_name = 'vle_clean'
)

SELECT
  e.column_name,
  e.expected_data_type,
  a.actual_data_type
FROM expected_types e
LEFT JOIN actual_types a
  ON e.column_name = a.column_name
WHERE a.column_name IS NULL
   OR a.actual_data_type <> e.expected_data_type;



-- ================================================================================================
-- 2. UNCONVERTED PLACEHOLDER CHECKS
-- ================================================================================================
-- Source placeholders:
--   ?
--   blank
--   NA
--   N/A
--   NULL text
--
-- These should already have been converted to SQL NULL during Silver cleaning.
--
-- Expected result for each query:
--   0 rows.
-- ================================================================================================


-- ------------------------------------------------------------------------------------------------
-- 2A. student_vle_clean string placeholders
-- ------------------------------------------------------------------------------------------------

SELECT
  *
FROM open_university.oulad_silver.student_vle_clean
WHERE UPPER(TRIM(code_module)) IN ('', '?', 'NA', 'N/A', 'NULL')
   OR UPPER(TRIM(code_presentation)) IN ('', '?', 'NA', 'N/A', 'NULL');


-- ------------------------------------------------------------------------------------------------
-- 2B. vle_clean string placeholders
-- ------------------------------------------------------------------------------------------------

SELECT
  *
FROM open_university.oulad_silver.vle_clean
WHERE UPPER(TRIM(code_module)) IN ('', '?', 'NA', 'N/A', 'NULL')
   OR UPPER(TRIM(code_presentation)) IN ('', '?', 'NA', 'N/A', 'NULL')
   OR UPPER(TRIM(activity_type)) IN ('', '?', 'NA', 'N/A', 'NULL');



-- ================================================================================================
-- 3. STUDENT_VLE_CLEAN VALUE / RANGE CHECKS
-- ================================================================================================


-- ------------------------------------------------------------------------------------------------
-- 3A. sum_click must be nonnegative.
--
-- Negative relative values in `date` are intentionally NOT checked because negative dates
-- before the official presentation start are valid in OULAD.
--
-- Expected result:
--   0 rows.
-- ------------------------------------------------------------------------------------------------

SELECT
  code_module,
  code_presentation,
  id_student,
  id_site,
  date,
  sum_click
FROM open_university.oulad_silver.student_vle_clean
WHERE sum_click < 0;


-- ------------------------------------------------------------------------------------------------
-- 3B. source_row_count must be positive.
--
-- Every Silver student-resource-day row must have come from at least one Bronze source row.
--
-- Expected result:
--   0 rows.
-- ------------------------------------------------------------------------------------------------

SELECT
  code_module,
  code_presentation,
  id_student,
  id_site,
  date,
  source_row_count
FROM open_university.oulad_silver.student_vle_clean
WHERE source_row_count <= 0;


-- ------------------------------------------------------------------------------------------------
-- 3C. Failure count for invalid student_vle values.
--
-- Expected:
--   invalid_sum_click_rows    = 0
--   invalid_source_row_count  = 0
-- ------------------------------------------------------------------------------------------------

SELECT
  COUNT_IF(sum_click < 0) AS invalid_sum_click_rows,
  COUNT_IF(source_row_count <= 0) AS invalid_source_row_count
FROM open_university.oulad_silver.student_vle_clean;



-- ================================================================================================
-- 4. VLE_CLEAN ACCEPTED VALUE CHECKS
-- ================================================================================================


-- ------------------------------------------------------------------------------------------------
-- 4A. activity_type must contain a recognized OULAD VLE activity category.
--
-- Expected result:
--   0 rows.
--
-- NULL is handled by the Silver null checks if activity_type is defined as required.
-- This query specifically finds populated but unexpected categories.
-- ------------------------------------------------------------------------------------------------

SELECT
  id_site,
  code_module,
  code_presentation,
  activity_type,
  week_from,
  week_to
FROM open_university.oulad_silver.vle_clean
WHERE activity_type IS NOT NULL
  AND LOWER(TRIM(activity_type)) NOT IN (
    'dataplus',
    'dualpane',
    'externalquiz',
    'folder',
    'forumng',
    'glossary',
    'homepage',
    'htmlactivity',
    'oucollaborate',
    'oucontent',
    'ouelluminate',
    'ouwiki',
    'page',
    'questionnaire',
    'quiz',
    'repeatactivity',
    'resource',
    'sharedsubpage',
    'subpage',
    'url'
  );


-- ------------------------------------------------------------------------------------------------
-- 4B. Summary of unexpected activity types.
--
-- This version is useful during manual Databricks investigation because it shows exactly
-- which unexpected values exist and how often they occur.
--
-- Expected result:
--   0 rows.
-- ------------------------------------------------------------------------------------------------

SELECT
  activity_type,
  COUNT(*) AS failure_count
FROM open_university.oulad_silver.vle_clean
WHERE activity_type IS NOT NULL
  AND LOWER(TRIM(activity_type)) NOT IN (
    'dataplus',
    'dualpane',
    'externalquiz',
    'folder',
    'forumng',
    'glossary',
    'homepage',
    'htmlactivity',
    'oucollaborate',
    'oucontent',
    'ouelluminate',
    'ouwiki',
    'page',
    'questionnaire',
    'quiz',
    'repeatactivity',
    'resource',
    'sharedsubpage',
    'subpage',
    'url'
  )
GROUP BY activity_type
ORDER BY failure_count DESC;



-- ================================================================================================
-- 5. VLE_CLEAN WEEK RANGE CHECK
-- ================================================================================================


-- ------------------------------------------------------------------------------------------------
-- 5A. week_from must not be greater than week_to when both values exist.
--
-- IMPORTANT:
--   week_from IS NULL       -> allowed
--   week_to IS NULL         -> allowed
--   both NULL               -> allowed
--   week_from <= week_to    -> valid
--   week_from > week_to     -> invalid
--
-- Expected result:
--   0 rows.
-- ------------------------------------------------------------------------------------------------

SELECT
  id_site,
  code_module,
  code_presentation,
  activity_type,
  week_from,
  week_to
FROM open_university.oulad_silver.vle_clean
WHERE week_from IS NOT NULL
  AND week_to IS NOT NULL
  AND week_from > week_to;


-- ------------------------------------------------------------------------------------------------
-- 5B. Failure count for invalid week ranges.
--
-- Expected:
--   invalid_week_range_rows = 0
-- ------------------------------------------------------------------------------------------------

SELECT
  COUNT(*) AS invalid_week_range_rows
FROM open_university.oulad_silver.vle_clean
WHERE week_from IS NOT NULL
  AND week_to IS NOT NULL
  AND week_from > week_to;



-- ================================================================================================
-- 6. COMBINED VALUE-CHECK SUMMARY
-- ================================================================================================
-- Gives one compact manual QA result for the two Silver tables.
--
-- Expected:
--   Every failure_count = 0.
-- ================================================================================================

SELECT
  'student_vle_clean' AS table_name,
  'negative_sum_click' AS check_name,
  COUNT(*) AS failure_count
FROM open_university.oulad_silver.student_vle_clean
WHERE sum_click < 0

UNION ALL

SELECT
  'student_vle_clean',
  'invalid_source_row_count',
  COUNT(*)
FROM open_university.oulad_silver.student_vle_clean
WHERE source_row_count <= 0

UNION ALL

SELECT
  'student_vle_clean',
  'unconverted_placeholder',
  COUNT(*)
FROM open_university.oulad_silver.student_vle_clean
WHERE UPPER(TRIM(code_module)) IN ('', '?', 'NA', 'N/A', 'NULL')
   OR UPPER(TRIM(code_presentation)) IN ('', '?', 'NA', 'N/A', 'NULL')

UNION ALL

SELECT
  'vle_clean',
  'unconverted_placeholder',
  COUNT(*)
FROM open_university.oulad_silver.vle_clean
WHERE UPPER(TRIM(code_module)) IN ('', '?', 'NA', 'N/A', 'NULL')
   OR UPPER(TRIM(code_presentation)) IN ('', '?', 'NA', 'N/A', 'NULL')
   OR UPPER(TRIM(activity_type)) IN ('', '?', 'NA', 'N/A', 'NULL')

UNION ALL

SELECT
  'vle_clean',
  'invalid_activity_type',
  COUNT(*)
FROM open_university.oulad_silver.vle_clean
WHERE activity_type IS NOT NULL
  AND LOWER(TRIM(activity_type)) NOT IN (
    'dataplus',
    'dualpane',
    'externalquiz',
    'folder',
    'forumng',
    'glossary',
    'homepage',
    'htmlactivity',
    'oucollaborate',
    'oucontent',
    'ouelluminate',
    'ouwiki',
    'page',
    'questionnaire',
    'quiz',
    'repeatactivity',
    'resource',
    'sharedsubpage',
    'subpage',
    'url'
  )

UNION ALL

SELECT
  'vle_clean',
  'invalid_week_range',
  COUNT(*)
FROM open_university.oulad_silver.vle_clean
WHERE week_from IS NOT NULL
  AND week_to IS NOT NULL
  AND week_from > week_to

ORDER BY table_name, check_name;


-- ================================================================================================
-- DONE WHEN
-- ================================================================================================
--
-- 1. Metadata type checks return 0 rows.
-- 2. Placeholder checks return 0 rows.
-- 3. student_vle_clean contains no negative sum_click values.
-- 4. student_vle_clean source_row_count is always positive.
-- 5. vle_clean contains only recognized OULAD activity_type values.
-- 6. vle_clean has no rows where week_from > week_to when both values are present.
-- 7. NULL optional week_from / week_to values remain allowed.
-- 8. Negative student_vle relative dates remain allowed.
-- 9. The final combined summary reports failure_count = 0 for every check.
--
-- This file is read-only. It identifies violations but does not modify Silver data.
-- ================================================================================================
