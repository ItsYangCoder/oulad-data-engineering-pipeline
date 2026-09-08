-- Suggested branch: test/bronze-checks
-- For checks tied to one transformation, use that transformation's branch instead.

-- Checks both actual NULL values and text placeholders.

-- Student information
SELECT
    COUNT(*) AS total_rows,

    SUM(
        CASE
            WHEN imd_band IS NULL
              OR TRIM(CAST(imd_band AS STRING))
                    IN ('', '?', 'NA', 'N/A', 'NULL')
            THEN 1 ELSE 0
        END
    ) AS missing_imd_band

FROM open_university.oulad_bronze.student_info_raw;


-- Student registration
SELECT
    COUNT(*) AS total_rows,

    SUM(
        CASE
            WHEN date_registration IS NULL
              OR TRIM(CAST(date_registration AS STRING))
                    IN ('', '?', 'NA', 'N/A', 'NULL')
            THEN 1 ELSE 0
        END
    ) AS missing_date_registration,

    SUM(
        CASE
            WHEN date_unregistration IS NULL
              OR TRIM(CAST(date_unregistration AS STRING))
                    IN ('', '?', 'NA', 'N/A', 'NULL')
            THEN 1 ELSE 0
        END
    ) AS missing_date_unregistration

FROM open_university.oulad_bronze.student_registration_raw;


-- VLE resources
SELECT
    COUNT(*) AS total_rows,

    SUM(
        CASE
            WHEN week_from IS NULL
              OR TRIM(CAST(week_from AS STRING))
                    IN ('', '?', 'NA', 'N/A', 'NULL')
            THEN 1 ELSE 0
        END
    ) AS missing_week_from,

    SUM(
        CASE
            WHEN week_to IS NULL
              OR TRIM(CAST(week_to AS STRING))
                    IN ('', '?', 'NA', 'N/A', 'NULL')
            THEN 1 ELSE 0
        END
    ) AS missing_week_to

FROM open_university.oulad_bronze.vle_raw;


-- Assessment information
SELECT
    COUNT(*) AS total_rows,

    SUM(
        CASE
            WHEN date IS NULL
              OR TRIM(CAST(date AS STRING))
                    IN ('', '?', 'NA', 'N/A', 'NULL')
            THEN 1 ELSE 0
        END
    ) AS missing_assessment_date,

    SUM(
        CASE
            WHEN weight IS NULL
              OR TRIM(CAST(weight AS STRING))
                    IN ('', '?', 'NA', 'N/A', 'NULL')
            THEN 1 ELSE 0
        END
    ) AS missing_weight

FROM open_university.oulad_bronze.assessment_raw;


-- Student assessment scores
SELECT
    COUNT(*) AS total_rows,

    SUM(
        CASE
            WHEN score IS NULL
              OR TRIM(CAST(score AS STRING))
                    IN ('', '?', 'NA', 'N/A', 'NULL')
            THEN 1 ELSE 0
        END
    ) AS missing_score

FROM open_university.oulad_bronze.student_assessment_raw;