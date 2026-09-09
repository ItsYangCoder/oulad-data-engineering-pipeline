-- ============================================================
-- Silver: Assessment Clean
-- Source: open_university.oulad_bronze.assessment_raw
-- Target: open_university.oulad_silver.assessment_clean
--
-- Grain: one row per assessment
-- Business key: id_assessment
-- ============================================================


-- ============================================================
-- 1. Create target table if it does not exist
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


-- ============================================================
-- 2. Validate required business key
--
-- id_assessment is required for the Silver business key.
-- Expected result: 0
-- ============================================================

SELECT
    COUNT(*) AS invalid_assessment_keys
FROM open_university.oulad_bronze.assessment_raw
WHERE TRY_CAST(id_assessment AS BIGINT) IS NULL;


-- ============================================================
-- 3. Prepare cleaned source and load into Silver
-- ============================================================

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

            -- ------------------------------------------------
            -- code_module
            -- Normalize placeholders to SQL NULL
            -- ------------------------------------------------

            CASE
                WHEN code_module IS NULL
                     OR TRIM(code_module) IN (
                        '?',
                        '',
                        'NA',
                        'N/A',
                        'NULL'
                     )
                THEN NULL
                ELSE TRIM(code_module)
            END AS normalized_code_module,


            -- ------------------------------------------------
            -- code_presentation
            -- Normalize placeholders to SQL NULL
            -- ------------------------------------------------

            CASE
                WHEN code_presentation IS NULL
                     OR TRIM(code_presentation) IN (
                        '?',
                        '',
                        'NA',
                        'N/A',
                        'NULL'
                     )
                THEN NULL
                ELSE TRIM(code_presentation)
            END AS normalized_code_presentation,


            -- ------------------------------------------------
            -- id_assessment
            -- Required business key
            -- ------------------------------------------------

            TRY_CAST(id_assessment AS BIGINT)
                AS cleaned_id_assessment,


            -- ------------------------------------------------
            -- assessment_type
            -- Normalize placeholders to SQL NULL
            -- ------------------------------------------------

            CASE
                WHEN assessment_type IS NULL
                     OR TRIM(assessment_type) IN (
                        '?',
                        '',
                        'NA',
                        'N/A',
                        'NULL'
                     )
                THEN NULL
                ELSE TRIM(assessment_type)
            END AS normalized_assessment_type,


            -- ------------------------------------------------
            -- date
            -- Normalize placeholders before casting
            --
            -- Expected:
            -- 11 missing Exam dates remain NULL
            -- ------------------------------------------------

            CASE
                WHEN date IS NULL
                     OR TRIM(date) IN (
                        '?',
                        '',
                        'NA',
                        'N/A',
                        'NULL'
                     )
                THEN NULL
                ELSE TRY_CAST(date AS INT)
            END AS cleaned_date,


            -- ------------------------------------------------
            -- weight
            -- Normalize placeholders before casting
            -- ------------------------------------------------

            CASE
                WHEN weight IS NULL
                     OR TRIM(CAST(weight AS STRING)) IN (
                        '?',
                        '',
                        'NA',
                        'N/A',
                        'NULL'
                     )
                THEN NULL
                ELSE TRY_CAST(weight AS DECIMAL(5,2))
            END AS cleaned_weight


        FROM open_university.oulad_bronze.assessment_raw

    ) prepared


    -- --------------------------------------------------------
    -- Required business-key protection
    --
    -- Invalid id_assessment values are excluded from MERGE.
    -- They are separately reported by the validation query above.
    -- --------------------------------------------------------

    WHERE cleaned_id_assessment IS NOT NULL

) AS source


-- ============================================================
-- 4. Match using business key
-- ============================================================

ON target.id_assessment = source.id_assessment


-- ============================================================
-- 5. Update existing records
-- ============================================================

WHEN MATCHED THEN UPDATE SET
    target.code_module = source.code_module,
    target.code_presentation = source.code_presentation,
    target.assessment_type = source.assessment_type,
    target.date = source.date,
    target.weight = source.weight,
    target.clean_load_timestamp = source.clean_load_timestamp,
    target.clean_load_date = source.clean_load_date


-- ============================================================
-- 6. Insert new records
-- ============================================================

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

