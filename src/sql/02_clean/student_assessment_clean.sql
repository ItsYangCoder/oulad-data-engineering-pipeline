-- ============================================================
-- STUDENT ASSESSMENT CLEAN
-- Branch: feature/clean-assessments
--
-- Source:
--   open_university.oulad_bronze.student_assessment_raw
--
-- Target:
--   open_university.oulad_silver.student_assessment_clean
--
-- Grain:
--   One row per student per assessment
--
-- Key:
--   (id_assessment, id_student)
--
-- Expected rows:
--   173,912
--
-- Expected missing scores:
--   173 TMA scores
-- ============================================================


-- ============================================================
-- 1. CREATE SILVER TABLE
-- ============================================================

CREATE TABLE IF NOT EXISTS
    open_university.oulad_silver.student_assessment_clean
(
    id_assessment BIGINT,
    id_student BIGINT,
    date_submitted INT,
    is_banked INT,
    score DECIMAL(5,2),

    -- Audit fields
    cleaned_at TIMESTAMP,
    clean_load_timestamp TIMESTAMP,
    clean_load_date DATE
)
USING DELTA;


-- ============================================================
-- 2. CLEAN SOURCE DATA
-- ============================================================

MERGE INTO
    open_university.oulad_silver.student_assessment_clean AS target

USING
(
    SELECT
        -- IDs
        TRY_CAST(id_assessment AS BIGINT) AS id_assessment,
        TRY_CAST(id_student AS BIGINT) AS id_student,

        -- Relative submission date
        TRY_CAST(date_submitted AS INT) AS date_submitted,

        -- Banked flag
        TRY_CAST(is_banked AS INT) AS is_banked,

        -- Score
        -- Unknown / missing values are preserved as NULL.
        CASE
            WHEN score IS NULL THEN NULL
            WHEN TRIM(score) IN ('', '?', 'NA', 'N/A', 'NULL') THEN NULL
            ELSE TRY_CAST(score AS DECIMAL(5,2))
        END AS score,

        -- Audit fields
        current_timestamp() AS cleaned_at,
        current_timestamp() AS clean_load_timestamp,
        current_date() AS clean_load_date

    FROM open_university.oulad_bronze.student_assessment_raw
) AS source

ON target.id_assessment = source.id_assessment
AND target.id_student = source.id_student


-- ============================================================
-- 3. UPDATE EXISTING RECORDS
-- ============================================================

WHEN MATCHED THEN
UPDATE SET
    target.date_submitted = source.date_submitted,
    target.is_banked = source.is_banked,
    target.score = source.score,
    target.cleaned_at = source.cleaned_at,
    target.clean_load_timestamp = source.clean_load_timestamp,
    target.clean_load_date = source.clean_load_date


-- ============================================================
-- 4. INSERT NEW RECORDS
-- ============================================================

WHEN NOT MATCHED THEN
INSERT
(
    id_assessment,
    id_student,
    date_submitted,
    is_banked,
    score,
    cleaned_at,
    clean_load_timestamp,
    clean_load_date
)
VALUES
(
    source.id_assessment,
    source.id_student,
    source.date_submitted,
    source.is_banked,
    source.score,
    source.cleaned_at,
    source.clean_load_timestamp,
    source.clean_load_date
);


-- ============================================================
-- 5. VALIDATION: ROW COUNT
-- Expected: 173,912
-- ============================================================

SELECT
    COUNT(*) AS total_rows
FROM open_university.oulad_silver.student_assessment_clean;


-- ============================================================
-- 6. VALIDATION: REQUIRED KEYS
-- Expected: 0 NULL IDs
-- ============================================================

SELECT
    COUNT(*) AS null_id_assessment
FROM open_university.oulad_silver.student_assessment_clean
WHERE id_assessment IS NULL;


SELECT
    COUNT(*) AS null_id_student
FROM open_university.oulad_silver.student_assessment_clean
WHERE id_student IS NULL;


-- ============================================================
-- 7. VALIDATION: DUPLICATE COMPOSITE KEYS
-- Expected: NO ROWS
-- ============================================================

SELECT
    id_assessment,
    id_student,
    COUNT(*) AS row_count
FROM open_university.oulad_silver.student_assessment_clean
GROUP BY
    id_assessment,
    id_student
HAVING COUNT(*) > 1;


-- ============================================================
-- 8. VALIDATION: EXPECTED NULL SCORES
-- Expected: 173
--
-- These are known missing TMA scores and must remain NULL.
-- ============================================================

SELECT
    COUNT(*) AS null_scores
FROM open_university.oulad_silver.student_assessment_clean
WHERE score IS NULL;


-- ============================================================
-- 9. VALIDATION: SCORE RANGE
-- Expected: minimum >= 0
--           maximum <= 100
-- ============================================================

SELECT
    MIN(score) AS min_score,
    MAX(score) AS max_score
FROM open_university.oulad_silver.student_assessment_clean
WHERE score IS NOT NULL;


-- ============================================================
-- 10. VALIDATION: INVALID SCORES
-- Expected: NO ROWS
-- ============================================================

SELECT
    id_assessment,
    id_student,
    score
FROM open_university.oulad_silver.student_assessment_clean
WHERE score IS NOT NULL
  AND (score < 0 OR score > 100);


-- ============================================================
-- 11. VALIDATION: PARENT ASSESSMENT RELATIONSHIP
-- Expected: 0 unmatched records
-- ============================================================

SELECT
    COUNT(*) AS unmatched_assessments
FROM open_university.oulad_silver.student_assessment_clean AS sa
LEFT JOIN open_university.oulad_silver.assessment_clean AS a
    ON sa.id_assessment = a.id_assessment
WHERE a.id_assessment IS NULL;


-- ============================================================
-- 12. VALIDATION: AUDIT FIELDS
-- Expected: 0 NULL audit values
-- ============================================================

SELECT
    COUNT(*) AS null_cleaned_at
FROM open_university.oulad_silver.student_assessment_clean
WHERE cleaned_at IS NULL;


SELECT
    COUNT(*) AS null_clean_load_timestamp
FROM open_university.oulad_silver.student_assessment_clean
WHERE clean_load_timestamp IS NULL;


SELECT
    COUNT(*) AS null_clean_load_date
FROM open_university.oulad_silver.student_assessment_clean
WHERE clean_load_date IS NULL;