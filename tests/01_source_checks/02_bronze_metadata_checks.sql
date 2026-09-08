-- Suggested branch: test/bronze-checks
-- For checks tied to one transformation, use that transformation's branch instead.

-- Checks whether every Bronze record has ingestion metadata.

SELECT
    'assessment_raw' AS table_name,
    COUNT(*) AS total_rows,
    SUM(CASE WHEN ingestion_timestamp IS NULL THEN 1 ELSE 0 END)
        AS missing_ingestion_timestamp,
    SUM(CASE WHEN ingestion_date IS NULL THEN 1 ELSE 0 END)
        AS missing_ingestion_date
FROM open_university.oulad_bronze.assessment_raw

UNION ALL

SELECT
    'courses_raw',
    COUNT(*),
    SUM(CASE WHEN ingestion_timestamp IS NULL THEN 1 ELSE 0 END),
    SUM(CASE WHEN ingestion_date IS NULL THEN 1 ELSE 0 END)
FROM open_university.oulad_bronze.courses_raw

UNION ALL

SELECT
    'student_assessment_raw',
    COUNT(*),
    SUM(CASE WHEN ingestion_timestamp IS NULL THEN 1 ELSE 0 END),
    SUM(CASE WHEN ingestion_date IS NULL THEN 1 ELSE 0 END)
FROM open_university.oulad_bronze.student_assessment_raw

UNION ALL

SELECT
    'student_info_raw',
    COUNT(*),
    SUM(CASE WHEN ingestion_timestamp IS NULL THEN 1 ELSE 0 END),
    SUM(CASE WHEN ingestion_date IS NULL THEN 1 ELSE 0 END)
FROM open_university.oulad_bronze.student_info_raw

UNION ALL

SELECT
    'student_registration_raw',
    COUNT(*),
    SUM(CASE WHEN ingestion_timestamp IS NULL THEN 1 ELSE 0 END),
    SUM(CASE WHEN ingestion_date IS NULL THEN 1 ELSE 0 END)
FROM open_university.oulad_bronze.student_registration_raw

UNION ALL

SELECT
    'student_vle_raw',
    COUNT(*),
    SUM(CASE WHEN ingestion_timestamp IS NULL THEN 1 ELSE 0 END),
    SUM(CASE WHEN ingestion_date IS NULL THEN 1 ELSE 0 END)
FROM open_university.oulad_bronze.student_vle_raw

UNION ALL

SELECT
    'vle_raw',
    COUNT(*),
    SUM(CASE WHEN ingestion_timestamp IS NULL THEN 1 ELSE 0 END),
    SUM(CASE WHEN ingestion_date IS NULL THEN 1 ELSE 0 END)
FROM open_university.oulad_bronze.vle_raw

ORDER BY table_name;