-- ============================================================
-- Silver: Assessment Clean
-- Source: open_university.oulad_bronze.assessment_raw
-- Target: open_university.oulad_silver.assessment_clean
--
-- Grain: one row per assessment
-- Business key: id_assessment
-- ============================================================

CREATE TABLE IF NOT EXISTS open_university.oulad_silver.assessment_clean (
    code_module STRING,
    code_presentation STRING,
    id_assessment BIGINT,
    assessment_type STRING,
    date INT,
    weight DECIMAL(5,2),
    clean_load_timestamp TIMESTAMP,
    clean_load_date DATE
)
USING DELTA;

-- Validate required business key before MERGE.
-- Invalid keys are reported and excluded from the load below.
SELECT COUNT(*) AS invalid_assessment_keys
FROM open_university.oulad_bronze.assessment_raw
WHERE TRY_CAST(id_assessment AS BIGINT) IS NULL;

MERGE INTO open_university.oulad_silver.assessment_clean AS target
USING (
    SELECT
        normalized_code_module AS code_module,
        normalized_code_presentation AS code_presentation,
        cleaned_id_assessment AS id_assessment,
        normalized_assessment_type AS assessment_type,
        cleaned_date AS date,
        cleaned_weight AS weight,
        current_timestamp() AS clean_load_timestamp,
        current_date() AS clean_load_date
    FROM (
        SELECT
            CASE
                WHEN code_module IS NULL
                     OR UPPER(TRIM(code_module)) IN ('?', '', 'NA', 'N/A', 'NULL')
                THEN NULL
                ELSE TRIM(code_module)
            END AS normalized_code_module,

            CASE
                WHEN code_presentation IS NULL
                     OR UPPER(TRIM(code_presentation)) IN ('?', '', 'NA', 'N/A', 'NULL')
                THEN NULL
                ELSE TRIM(code_presentation)
            END AS normalized_code_presentation,

            TRY_CAST(id_assessment AS BIGINT) AS cleaned_id_assessment,

            CASE
                WHEN assessment_type IS NULL
                     OR UPPER(TRIM(assessment_type)) IN ('?', '', 'NA', 'N/A', 'NULL')
                THEN NULL
                WHEN UPPER(TRIM(assessment_type)) = 'EXAM' THEN 'Exam'
                WHEN UPPER(TRIM(assessment_type)) = 'TMA' THEN 'TMA'
                WHEN UPPER(TRIM(assessment_type)) = 'CMA' THEN 'CMA'
                ELSE NULL
            END AS normalized_assessment_type,

            CASE
                WHEN date IS NULL
                     OR UPPER(TRIM(date)) IN ('?', '', 'NA', 'N/A', 'NULL')
                THEN NULL
                ELSE TRY_CAST(date AS INT)
            END AS cleaned_date,

            CASE
                WHEN weight IS NULL
                     OR UPPER(TRIM(CAST(weight AS STRING))) IN ('?', '', 'NA', 'N/A', 'NULL')
                THEN NULL
                ELSE TRY_CAST(weight AS DECIMAL(5,2))
            END AS cleaned_weight

        FROM open_university.oulad_bronze.assessment_raw
    ) prepared
    WHERE cleaned_id_assessment IS NOT NULL
) AS source
ON target.id_assessment = source.id_assessment
WHEN MATCHED THEN UPDATE SET
    target.code_module = source.code_module,
    target.code_presentation = source.code_presentation,
    target.assessment_type = source.assessment_type,
    target.date = source.date,
    target.weight = source.weight,
    target.clean_load_timestamp = source.clean_load_timestamp,
    target.clean_load_date = source.clean_load_date
WHEN NOT MATCHED THEN INSERT (
    code_module,
    code_presentation,
    id_assessment,
    assessment_type,
    date,
    weight,
    clean_load_timestamp,
    clean_load_date
)
VALUES (
    source.code_module,
    source.code_presentation,
    source.id_assessment,
    source.assessment_type,
    source.date,
    source.weight,
    source.clean_load_timestamp,
    source.clean_load_date
);
