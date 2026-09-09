-- Final cross-table Silver reconciliation
-- Each result returns PASS only when the current-batch baseline and relationships agree.

-- Course coverage
WITH course_counts AS (
  SELECT
    (SELECT COUNT(*) FROM open_university.oulad_bronze.courses_raw) AS bronze_rows,
    (SELECT COUNT(*) FROM open_university.oulad_silver.courses_clean) AS silver_rows,
    (SELECT COALESCE(SUM(source_row_count), 0) FROM open_university.oulad_silver.courses_invalid_key_quarantine) AS quarantined_rows
)
SELECT *,
  CASE
    WHEN bronze_rows = 22
     AND silver_rows + quarantined_rows = bronze_rows
    THEN 'PASS' ELSE 'FAIL'
  END AS course_reconciliation_status
FROM course_counts;

-- Assessment coverage and score preservation
WITH metrics AS (
  SELECT
    (SELECT COUNT(*) FROM open_university.oulad_bronze.assessment_raw) AS assessment_bronze_rows,
    (SELECT COUNT(*) FROM open_university.oulad_silver.assessment_clean) AS assessment_silver_rows,
    (SELECT COUNT(*) FROM open_university.oulad_bronze.student_assessment_raw) AS result_bronze_rows,
    (SELECT COUNT(*) FROM open_university.oulad_silver.student_assessment_clean) AS result_silver_rows,
    (SELECT COUNT(*) FROM open_university.oulad_silver.student_assessment_clean WHERE score IS NULL) AS missing_scores,
    (SELECT SUM(TRY_CAST(score AS DECIMAL(18,2))) FROM open_university.oulad_bronze.student_assessment_raw) AS bronze_score_sum,
    (SELECT SUM(score) FROM open_university.oulad_silver.student_assessment_clean) AS silver_score_sum
)
SELECT *,
  CASE
    WHEN assessment_bronze_rows = 206
     AND assessment_silver_rows = 206
     AND result_bronze_rows = 173912
     AND result_silver_rows = 173912
     AND missing_scores = 173
     AND bronze_score_sum = silver_score_sum
    THEN 'PASS' ELSE 'FAIL'
  END AS assessment_reconciliation_status
FROM metrics;

-- Enrollment and registration coverage
WITH enrollment_metrics AS (
  SELECT
    (SELECT COUNT(*) FROM open_university.oulad_bronze.student_info_raw) AS info_bronze_rows,
    (SELECT COUNT(*) FROM open_university.oulad_silver.student_info_clean) AS info_silver_rows,
    (SELECT COUNT(*) FROM open_university.oulad_bronze.student_registration_raw) AS registration_bronze_rows,
    (SELECT COUNT(*) FROM open_university.oulad_silver.student_registration_clean) AS registration_silver_rows,
    (
      SELECT COUNT(*)
      FROM open_university.oulad_silver.student_registration_clean r
      LEFT JOIN open_university.oulad_silver.student_info_clean i
        ON r.code_module = i.code_module
       AND r.code_presentation = i.code_presentation
       AND r.id_student = i.id_student
      WHERE i.id_student IS NULL
    ) AS registration_orphans
)
SELECT *,
  CASE
    WHEN info_bronze_rows = 32593
     AND info_silver_rows = 32593
     AND registration_bronze_rows = 32593
     AND registration_silver_rows = 32593
     AND registration_orphans = 0
    THEN 'PASS' ELSE 'FAIL'
  END AS enrollment_reconciliation_status
FROM enrollment_metrics;

-- VLE reduction is expected because repeated source rows are aggregated to one daily business key.
WITH vle_metrics AS (
  SELECT
    (SELECT COUNT(*) FROM open_university.oulad_silver.vle_clean) AS resource_rows,
    (SELECT COUNT(*) FROM open_university.oulad_bronze.student_vle_raw) AS bronze_interaction_rows,
    (SELECT COUNT(*) FROM open_university.oulad_silver.student_vle_clean) AS silver_daily_rows,
    (SELECT SUM(source_row_count) FROM open_university.oulad_silver.student_vle_clean) AS accounted_source_rows,
    (SELECT SUM(TRY_CAST(sum_click AS BIGINT)) FROM open_university.oulad_bronze.student_vle_raw) AS bronze_click_total,
    (SELECT SUM(sum_click) FROM open_university.oulad_silver.student_vle_clean) AS silver_click_total
)
SELECT *,
  bronze_interaction_rows - silver_daily_rows AS rows_combined_by_daily_aggregation,
  CASE
    WHEN resource_rows = 6364
     AND bronze_interaction_rows = 10655280
     AND silver_daily_rows = 8459320
     AND accounted_source_rows = bronze_interaction_rows
     AND bronze_click_total = silver_click_total
    THEN 'PASS' ELSE 'FAIL'
  END AS vle_reconciliation_status
FROM vle_metrics;
