
CREATE TABLE IF NOT EXISTS open_university.oulad_silver.student_vle_clean (
  code_module STRING,
  code_presentation STRING,
  id_student BIGINT,
  id_site BIGINT,
  date INT,
  sum_click BIGINT,
  source_row_count BIGINT,
  clean_load_timestamp TIMESTAMP,
  clean_load_date DATE
) USING DELTA;

CREATE TABLE IF NOT EXISTS open_university.oulad_silver.student_vle_rejected (
  code_module_raw STRING,
  code_presentation_raw STRING,
  id_student_raw STRING,
  id_site_raw STRING,
  date_raw STRING,
  sum_click_raw STRING,
  rejection_reason STRING,
  clean_load_timestamp TIMESTAMP,
  clean_load_date DATE
) USING DELTA;

-- Normalize the current batch and combine repeated daily keys.
CREATE OR REPLACE TEMP VIEW student_vle_typed_current_batch AS
WITH normalized AS (
  SELECT
    CAST(code_module AS STRING) AS code_module_raw,
    CAST(code_presentation AS STRING) AS code_presentation_raw,
    CAST(id_student AS STRING) AS id_student_raw,
    CAST(id_site AS STRING) AS id_site_raw,
    CAST(date AS STRING) AS date_raw,
    CAST(sum_click AS STRING) AS sum_click_raw,
    CASE
      WHEN code_module IS NULL
        OR UPPER(TRIM(CAST(code_module AS STRING))) IN ('', '?', 'NA', 'N/A', 'NULL') THEN NULL
      ELSE UPPER(TRIM(CAST(code_module AS STRING)))
    END AS code_module,
    CASE
      WHEN code_presentation IS NULL
        OR UPPER(TRIM(CAST(code_presentation AS STRING))) IN ('', '?', 'NA', 'N/A', 'NULL') THEN NULL
      ELSE UPPER(TRIM(CAST(code_presentation AS STRING)))
    END AS code_presentation,
    CASE
      WHEN id_student IS NULL
        OR UPPER(TRIM(CAST(id_student AS STRING))) IN ('', '?', 'NA', 'N/A', 'NULL') THEN NULL
      ELSE TRIM(CAST(id_student AS STRING))
    END AS id_student_normalized,
    CASE
      WHEN id_site IS NULL
        OR UPPER(TRIM(CAST(id_site AS STRING))) IN ('', '?', 'NA', 'N/A', 'NULL') THEN NULL
      ELSE TRIM(CAST(id_site AS STRING))
    END AS id_site_normalized,
    CASE
      WHEN date IS NULL
        OR UPPER(TRIM(CAST(date AS STRING))) IN ('', '?', 'NA', 'N/A', 'NULL') THEN NULL
      ELSE TRIM(CAST(date AS STRING))
    END AS date_normalized,
    CASE
      WHEN sum_click IS NULL
        OR UPPER(TRIM(CAST(sum_click AS STRING))) IN ('', '?', 'NA', 'N/A', 'NULL') THEN NULL
      ELSE TRIM(CAST(sum_click AS STRING))
    END AS sum_click_normalized
  FROM open_university.oulad_bronze.student_vle_raw
),

casted AS (
  SELECT
    code_module_raw,
    code_presentation_raw,
    id_student_raw,
    id_site_raw,
    date_raw,
    sum_click_raw,
    code_module,
    code_presentation,
    TRY_CAST(id_student_normalized AS BIGINT) AS id_student,
    TRY_CAST(id_site_normalized AS BIGINT) AS id_site,
    TRY_CAST(date_normalized AS INT) AS date,
    TRY_CAST(sum_click_normalized AS BIGINT) AS sum_click,
    id_student_normalized,
    id_site_normalized,
    date_normalized,
    sum_click_normalized
  FROM normalized
)

SELECT
  *,
  CASE
    WHEN code_module IS NULL THEN 'MISSING_CODE_MODULE'
    WHEN code_presentation IS NULL THEN 'MISSING_CODE_PRESENTATION'
    WHEN id_student_normalized IS NULL THEN 'MISSING_ID_STUDENT'
    WHEN id_student IS NULL THEN 'INVALID_ID_STUDENT'
    WHEN id_site_normalized IS NULL THEN 'MISSING_ID_SITE'
    WHEN id_site IS NULL THEN 'INVALID_ID_SITE'
    WHEN date_normalized IS NULL THEN 'MISSING_DATE'
    WHEN date IS NULL THEN 'INVALID_DATE'
    WHEN sum_click_normalized IS NULL THEN 'MISSING_SUM_CLICK'
    WHEN sum_click IS NULL THEN 'INVALID_SUM_CLICK'
    WHEN sum_click < 0 THEN 'NEGATIVE_SUM_CLICK'
    ELSE NULL
  END AS rejection_reason
FROM casted;

-- Keep rejected records for review.
MERGE INTO open_university.oulad_silver.student_vle_rejected AS target
USING (
  SELECT DISTINCT
    code_module_raw,
    code_presentation_raw,
    id_student_raw,
    id_site_raw,
    date_raw,
    sum_click_raw,
    rejection_reason,
    CURRENT_TIMESTAMP() AS clean_load_timestamp,
    CURRENT_DATE() AS clean_load_date
  FROM student_vle_typed_current_batch
  WHERE rejection_reason IS NOT NULL
) AS source
ON  target.code_module_raw <=> source.code_module_raw
AND target.code_presentation_raw <=> source.code_presentation_raw
AND target.id_student_raw <=> source.id_student_raw
AND target.id_site_raw <=> source.id_site_raw
AND target.date_raw <=> source.date_raw
AND target.sum_click_raw <=> source.sum_click_raw
AND target.rejection_reason = source.rejection_reason
WHEN NOT MATCHED THEN INSERT (
  code_module_raw,
  code_presentation_raw,
  id_student_raw,
  id_site_raw,
  date_raw,
  sum_click_raw,
  rejection_reason,
  clean_load_timestamp,
  clean_load_date
)
VALUES (
  source.code_module_raw,
  source.code_presentation_raw,
  source.id_student_raw,
  source.id_site_raw,
  source.date_raw,
  source.sum_click_raw,
  source.rejection_reason,
  source.clean_load_timestamp,
  source.clean_load_date
);

SELECT assert_true(
  (
    SELECT COUNT(*)
    FROM (
      SELECT
        code_module,
        code_presentation,
        id_student,
        id_site,
        date,
        CAST(SUM(sum_click) AS BIGINT) AS sum_click,
        COUNT(*) AS source_row_count
      FROM student_vle_typed_current_batch
      WHERE rejection_reason IS NULL
      GROUP BY code_module, code_presentation, id_student, id_site, date
    ) AS source
    INNER JOIN open_university.oulad_silver.student_vle_clean AS target
      ON target.code_module = source.code_module
     AND target.code_presentation = source.code_presentation
     AND target.id_student = source.id_student
     AND target.id_site = source.id_site
     AND target.date = source.date
    WHERE source.source_row_count < target.source_row_count
       OR source.sum_click < target.sum_click
  ) = 0,
  'Student VLE source is smaller than stored totals for an existing key. Check for a partial or incomplete batch.'
);

-- Upsert valid daily interactions without deleting prior history.
MERGE INTO open_university.oulad_silver.student_vle_clean AS target
USING (
  SELECT
    code_module,
    code_presentation,
    id_student,
    id_site,
    date,
    CAST(SUM(sum_click) AS BIGINT) AS sum_click,
    COUNT(*) AS source_row_count,
    CURRENT_TIMESTAMP() AS clean_load_timestamp,
    CURRENT_DATE() AS clean_load_date
  FROM student_vle_typed_current_batch
  WHERE rejection_reason IS NULL
  GROUP BY
    code_module,
    code_presentation,
    id_student,
    id_site,
    date
) AS source
ON  target.code_module = source.code_module
AND target.code_presentation = source.code_presentation
AND target.id_student = source.id_student
AND target.id_site = source.id_site
AND target.date = source.date
WHEN MATCHED THEN UPDATE SET
  target.sum_click = source.sum_click,
  target.source_row_count = source.source_row_count,
  target.clean_load_timestamp = source.clean_load_timestamp,
  target.clean_load_date = source.clean_load_date
WHEN NOT MATCHED THEN INSERT (
  code_module,
  code_presentation,
  id_student,
  id_site,
  date,
  sum_click,
  source_row_count,
  clean_load_timestamp,
  clean_load_date
)
VALUES (
  source.code_module,
  source.code_presentation,
  source.id_student,
  source.id_site,
  source.date,
  source.sum_click,
  source.source_row_count,
  source.clean_load_timestamp,
  source.clean_load_date
);

DROP VIEW IF EXISTS student_vle_typed_current_batch;
-- Aggregates VLE clicks by student, presentation, resource and relative day.
-- Existing history is retained because an incremental batch may be partial.
