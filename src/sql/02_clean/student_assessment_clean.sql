-- ============================================================
-- Silver: Student Assessment Clean
-- Source: open_university.oulad_bronze.student_assessment_raw
-- Target: open_university.oulad_silver.student_assessment_clean
--
-- Grain:
-- one student result per assessment
--
-- Business key:
-- (id_assessment, id_student)
-- ============================================================


-- ============================================================
-- 1. Create target table if it does not exist
-- ============================================================

CREATE TABLE IF NOT EXISTS
    open_university.oulad_silver.student_assessment_clean
(
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


-- ============================================================
-- 2. Validate required business keys
--
-- Invalid keys must not enter the Silver table.
-- Expected result: 0
-- ============================================================

SELECT COUNT(*) AS invalid_student_assessment_keys
FROM open_university.oulad_bronze.student_assessment_raw
WHERE TRY_CAST(id_assessment AS BIGINT) IS NULL
   OR TRY_CAST(id_student AS BIGINT) IS NULL;


-- ============================================================
-- 3. Clean source and merge into Silver
-- ============================================================

MERGE INTO
    open_university.oulad_silver.student_assessment_clean AS target

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

            -- --------------------------------------------
            -- Assessment ID
            -- --------------------------------------------

            TRY_CAST(id_assessment AS BIGINT)
                AS cleaned_id_assessment,


            -- --------------------------------------------
            -- Student ID
            -- --------------------------------------------

            TRY_CAST(id_student AS BIGINT)
                AS cleaned_id_student,


            -- --------------------------------------------
            -- Relative submission date
            -- --------------------------------------------

            CASE
                WHEN date_submitted IS NULL
                     OR TRIM(CAST(date_submitted AS STRING)) IN (
                        '?',
                        '',
                        'NA',
                        'N/A',
                        'NULL'
                     )
                THEN NULL
                ELSE TRY_CAST(date_submitted AS INT)
            END AS cleaned_date_submitted,


            -- --------------------------------------------
            -- Banked flag
            -- --------------------------------------------

            CASE
                WHEN is_banked IS NULL
                     OR TRIM(CAST(is_banked AS STRING)) IN (
                        '?',
                        '',
                        'NA',
                        'N/A',
                        'NULL'
                     )
                THEN NULL
                ELSE TRY_CAST(is_banked AS INT)
            END AS cleaned_is_banked,


            -- --------------------------------------------
            -- Score
            --
            -- Unknown scores become SQL NULL.
            -- They must NOT become 0.
            -- --------------------------------------------

            CASE
                WHEN score IS NULL
                     OR TRIM(score) IN (
                        '?',
                        '',
                        'NA',
                        'N/A',
                        'NULL'
                     )
                THEN NULL
                ELSE TRY_CAST(score AS DECIMAL(5,2))
            END AS cleaned_score

        FROM open_university.oulad_bronze.student_assessment_raw

    ) prepared

    -- --------------------------------------------------------
    -- Required composite business key protection
    --
    -- Prevents NULL business keys from being inserted.
    -- This also makes the MERGE repeat-load safe for invalid keys.
    -- --------------------------------------------------------

    WHERE cleaned_id_assessment IS NOT NULL
      AND cleaned_id_student IS NOT NULL

) AS source


-- ============================================================
-- 4. Match using the complete business key
-- ============================================================

ON target.id_assessment = source.id_assessment
AND target.id_student = source.id_student


-- ============================================================
-- 5. Update existing result
-- ============================================================

WHEN MATCHED THEN UPDATE SET
    target.date_submitted = source.date_submitted,
    target.is_banked = source.is_banked,
    target.score = source.score,
    target.cleaned_at = source.cleaned_at,
    target.clean_load_timestamp = source.clean_load_timestamp,
    target.clean_load_date = source.clean_load_date


-- ============================================================
-- 6. Insert new result
-- ============================================================

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
