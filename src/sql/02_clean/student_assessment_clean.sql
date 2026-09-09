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
    cleaned_at TIMESTAMP,
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
        current_timestamp() AS cleaned_at,
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
    target.cleaned_at = source.cleaned_at,
    target.clean_load_timestamp = source.clean_load_timestamp,
    target.clean_load_date = source.clean_load_date
WHEN NOT MATCHED THEN INSERT (
    id_assessment,
    id_student,
    date_submitted,
    is_banked,
    score,
    cleaned_at,
    clean_load_timestamp,
    clean_load_date
)
VALUES (
    source.id_assessment,
    source.id_student,
    source.date_submitted,
    source.is_banked,
    source.score,
    source.cleaned_at,
    source.clean_load_timestamp,
    source.clean_load_date
);

-- Validation: row count. Expected: 173,912.
SELECT COUNT(*) AS total_rows
FROM open_university.oulad_silver.student_assessment_clean;

-- Validation: required keys. Expected: 0 NULL IDs.
SELECT COUNT(*) AS null_id_assessment
FROM open_university.oulad_silver.student_assessment_clean
WHERE id_assessment IS NULL;

SELECT COUNT(*) AS null_id_student
FROM open_university.oulad_silver.student_assessment_clean
WHERE id_student IS NULL;

-- Validation: duplicate composite keys. Expected: no rows.
SELECT id_assessment, id_student, COUNT(*) AS row_count
FROM open_university.oulad_silver.student_assessment_clean
GROUP BY id_assessment, id_student
HAVING COUNT(*) > 1;

-- Validation: expected NULL scores. Expected: 173.
SELECT COUNT(*) AS null_scores
FROM open_university.oulad_silver.student_assessment_clean
WHERE score IS NULL;

-- Validation: score range. Expected: 0 <= score <= 100 when present.
SELECT MIN(score) AS min_score, MAX(score) AS max_score
FROM open_university.oulad_silver.student_assessment_clean
WHERE score IS NOT NULL;

-- Validation: invalid scores. Expected: no rows.
SELECT id_assessment, id_student, score
FROM open_university.oulad_silver.student_assessment_clean
WHERE score IS NOT NULL AND (score < 0 OR score > 100);

-- Validation: parent assessment relationship. Expected: 0 unmatched.
SELECT COUNT(*) AS unmatched_assessments
FROM open_university.oulad_silver.student_assessment_clean AS sa
LEFT JOIN open_university.oulad_silver.assessment_clean AS a
    ON sa.id_assessment = a.id_assessment
WHERE a.id_assessment IS NULL;

-- Validation: audit fields. Expected: 0 NULL values.
SELECT COUNT(*) AS null_cleaned_at
FROM open_university.oulad_silver.student_assessment_clean
WHERE cleaned_at IS NULL;

SELECT COUNT(*) AS null_clean_load_timestamp
FROM open_university.oulad_silver.student_assessment_clean
WHERE clean_load_timestamp IS NULL;

SELECT COUNT(*) AS null_clean_load_date
FROM open_university.oulad_silver.student_assessment_clean
WHERE clean_load_date IS NULL;
