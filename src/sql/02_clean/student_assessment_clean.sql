-- ============================================================
-- Silver: Student Assessment Clean
-- Source: open_university.oulad_bronze.student_assessment_raw
-- Target: open_university.oulad_silver.student_assessment_clean
--
-- Grain: one student result per assessment
-- Business key: (id_assessment, id_student)
-- ============================================================

CREATE TABLE IF NOT EXISTS open_university.oulad_silver.student_assessment_clean (
    id_assessment BIGINT,
    id_student BIGINT,
    date_submitted INT,
    is_banked INT,
    score DECIMAL(5,2),
    clean_load_timestamp TIMESTAMP,
    clean_load_date DATE
)
USING DELTA;

-- Validate required composite business keys before MERGE.
-- Invalid keys are reported and excluded from the load below.
SELECT COUNT(*) AS invalid_student_assessment_keys
FROM open_university.oulad_bronze.student_assessment_raw
WHERE TRY_CAST(id_assessment AS BIGINT) IS NULL
   OR TRY_CAST(id_student AS BIGINT) IS NULL;

MERGE INTO open_university.oulad_silver.student_assessment_clean AS target
USING (
    SELECT
        cleaned_id_assessment AS id_assessment,
        cleaned_id_student AS id_student,
        cleaned_date_submitted AS date_submitted,
        cleaned_is_banked AS is_banked,
        cleaned_score AS score,
        current_timestamp() AS clean_load_timestamp,
        current_date() AS clean_load_date
    FROM (
        SELECT
            TRY_CAST(id_assessment AS BIGINT) AS cleaned_id_assessment,
            TRY_CAST(id_student AS BIGINT) AS cleaned_id_student,

            CASE
                WHEN date_submitted IS NULL
                     OR UPPER(TRIM(CAST(date_submitted AS STRING))) IN ('?', '', 'NA', 'N/A', 'NULL')
                THEN NULL
                ELSE TRY_CAST(date_submitted AS INT)
            END AS cleaned_date_submitted,

            CASE
                WHEN is_banked IS NULL
                     OR UPPER(TRIM(CAST(is_banked AS STRING))) IN ('?', '', 'NA', 'N/A', 'NULL')
                THEN NULL
                ELSE TRY_CAST(is_banked AS INT)
            END AS cleaned_is_banked,

            CASE
                WHEN score IS NULL
                     OR UPPER(TRIM(score)) IN ('?', '', 'NA', 'N/A', 'NULL')
                THEN NULL
                ELSE TRY_CAST(score AS DECIMAL(5,2))
            END AS cleaned_score
        FROM open_university.oulad_bronze.student_assessment_raw
    ) prepared
    WHERE cleaned_id_assessment IS NOT NULL
      AND cleaned_id_student IS NOT NULL
) AS source
ON target.id_assessment = source.id_assessment
AND target.id_student = source.id_student
WHEN MATCHED THEN UPDATE SET
    target.date_submitted = source.date_submitted,
    target.is_banked = source.is_banked,
    target.score = source.score,
    target.clean_load_timestamp = source.clean_load_timestamp,
    target.clean_load_date = source.clean_load_date
WHEN NOT MATCHED THEN INSERT (
    id_assessment,
    id_student,
    date_submitted,
    is_banked,
    score,
    clean_load_timestamp,
    clean_load_date
)
VALUES (
    source.id_assessment,
    source.id_student,
    source.date_submitted,
    source.is_banked,
    source.score,
    source.clean_load_timestamp,
    source.clean_load_date
);
