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


-- --------------------------------------------------------------------------------------------------------
-- 1. Required key-component checks
-- --------------------------------------------------------------------------------------------------------
SELECT 'vle_clean' AS table_name,
       'missing_or_blank_code_module' AS check_name,
       COUNT(*) AS failure_count
FROM open_university.oulad_silver.vle_clean
WHERE code_module IS NULL OR TRIM(code_module) = ''

UNION ALL

SELECT 'vle_clean',
       'missing_or_blank_code_presentation',
       COUNT(*)
FROM open_university.oulad_silver.vle_clean
WHERE code_presentation IS NULL OR TRIM(code_presentation) = ''

UNION ALL

SELECT 'vle_clean',
       'missing_id_site',
       COUNT(*)
FROM open_university.oulad_silver.vle_clean
WHERE id_site IS NULL

UNION ALL

SELECT 'student_vle_clean',
       'missing_or_blank_code_module',
       COUNT(*)
FROM open_university.oulad_silver.student_vle_clean
WHERE code_module IS NULL OR TRIM(code_module) = ''

UNION ALL

SELECT 'student_vle_clean',
       'missing_or_blank_code_presentation',
       COUNT(*)
FROM open_university.oulad_silver.student_vle_clean
WHERE code_presentation IS NULL OR TRIM(code_presentation) = ''

UNION ALL

SELECT 'student_vle_clean',
       'missing_id_student',
       COUNT(*)
FROM open_university.oulad_silver.student_vle_clean
WHERE id_student IS NULL

UNION ALL

SELECT 'student_vle_clean',
       'missing_id_site',
       COUNT(*)
FROM open_university.oulad_silver.student_vle_clean
WHERE id_site IS NULL

UNION ALL

SELECT 'student_vle_clean',
       'missing_date',
       COUNT(*)
FROM open_university.oulad_silver.student_vle_clean
WHERE date IS NULL;

-- --------------------------------------------------------------------------------------------------------
-- 2. Duplicate-key summary
-- duplicate_groups counts repeated business keys. duplicate_excess_rows counts rows beyond the one
-- permitted row per key. Both metrics must be 0.
-- --------------------------------------------------------------------------------------------------------
WITH vle_duplicate_keys AS (
  SELECT
    code_module,
    code_presentation,
    id_site,
    COUNT(*) AS rows_for_key
  FROM open_university.oulad_silver.vle_clean
  GROUP BY code_module, code_presentation, id_site
  HAVING COUNT(*) > 1
),

student_vle_duplicate_keys AS (
  SELECT
    code_module,
    code_presentation,
    id_student,
    id_site,
    date,
    COUNT(*) AS rows_for_key
  FROM open_university.oulad_silver.student_vle_clean
  GROUP BY code_module, code_presentation, id_student, id_site, date
  HAVING COUNT(*) > 1
)

SELECT
  'vle_clean' AS table_name,
  COUNT(*) AS duplicate_groups,
  COALESCE(SUM(rows_for_key - 1), 0) AS duplicate_excess_rows
FROM vle_duplicate_keys

UNION ALL

SELECT
  'student_vle_clean',
  COUNT(*),
  COALESCE(SUM(rows_for_key - 1), 0)
FROM student_vle_duplicate_keys;

-- --------------------------------------------------------------------------------------------------------
-- 3. VLE resource duplicate-key details
-- Expected result: no rows.
-- --------------------------------------------------------------------------------------------------------
SELECT
  code_module,
  code_presentation,
  id_site,
  COUNT(*) AS rows_for_key
FROM open_university.oulad_silver.vle_clean
GROUP BY code_module, code_presentation, id_site
HAVING COUNT(*) > 1
ORDER BY rows_for_key DESC, code_module, code_presentation, id_site;

-- --------------------------------------------------------------------------------------------------------
-- 4. Student VLE daily duplicate-key details
-- Expected result: no rows.
-- --------------------------------------------------------------------------------------------------------
SELECT
  code_module,
  code_presentation,
  id_student,
  id_site,
  date,
  COUNT(*) AS rows_for_key
FROM open_university.oulad_silver.student_vle_clean
GROUP BY code_module, code_presentation, id_student, id_site, date
HAVING COUNT(*) > 1
ORDER BY rows_for_key DESC, code_module, code_presentation, id_student, id_site, date;

-- --------------------------------------------------------------------------------------------------------
-- 5. Rejected Bronze records caused by invalid required key values
-- Expected result for the documented current batch: no rows.
-- --------------------------------------------------------------------------------------------------------
SELECT
  rejection_reason,
  COUNT(*) AS rejected_rows
FROM open_university.oulad_silver.student_vle_rejected
WHERE rejection_reason IN (
  'MISSING_CODE_MODULE',
  'MISSING_CODE_PRESENTATION',
  'MISSING_ID_STUDENT',
  'INVALID_ID_STUDENT',
  'MISSING_ID_SITE',
  'INVALID_ID_SITE',
  'MISSING_DATE',
  'INVALID_DATE'
)
GROUP BY rejection_reason
ORDER BY rejection_reason;
