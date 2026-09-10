
SELECT 'courses_clean_invalid_length_values' AS check_name, COUNT(*) AS invalid_rows,
       CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END AS check_status
FROM open_university.oulad_silver.courses_clean
WHERE module_presentation_length IS NOT NULL AND module_presentation_length <= 0;

SELECT 'courses_clean_flag_accuracy' AS check_name, COUNT(*) AS mismatch_rows,
       CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END AS check_status
FROM open_university.oulad_silver.courses_clean
WHERE (is_valid_length = TRUE AND (module_presentation_length IS NULL OR module_presentation_length <= 0))
   OR (is_valid_length = FALSE AND module_presentation_length IS NOT NULL AND module_presentation_length > 0);

SELECT 'courses_clean_is_valid_key_check' AS check_name, COUNT(*) AS invalid_key_flag_rows,
       CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END AS check_status
FROM open_university.oulad_silver.courses_clean
WHERE is_valid_key = FALSE;

SELECT assessment_type, COUNT(*) AS row_count
FROM open_university.oulad_silver.assessment_clean
GROUP BY assessment_type
ORDER BY assessment_type;

SELECT DISTINCT assessment_type
FROM open_university.oulad_silver.assessment_clean
WHERE assessment_type NOT IN ('TMA', 'CMA', 'Exam') OR assessment_type IS NULL;

SELECT id_assessment, weight
FROM open_university.oulad_silver.assessment_clean
WHERE weight IS NOT NULL AND (weight < 0 OR weight > 100);

SELECT *
FROM open_university.oulad_silver.assessment_clean
WHERE TRIM(code_module) IN ('?', '', 'NA', 'N/A', 'NULL')
   OR TRIM(code_presentation) IN ('?', '', 'NA', 'N/A', 'NULL')
   OR TRIM(assessment_type) IN ('?', '', 'NA', 'N/A', 'NULL');

SELECT id_assessment, id_student, score
FROM open_university.oulad_silver.student_assessment_clean
WHERE score IS NOT NULL AND (score < 0 OR score > 100);

SELECT DISTINCT is_banked
FROM open_university.oulad_silver.student_assessment_clean
WHERE is_banked IS NOT NULL AND is_banked NOT IN (0, 1);

SELECT *
FROM open_university.oulad_silver.student_assessment_clean
WHERE CAST(id_assessment AS STRING) IN ('?', '', 'NA', 'N/A', 'NULL')
   OR CAST(id_student AS STRING) IN ('?', '', 'NA', 'N/A', 'NULL')
   OR CAST(date_submitted AS STRING) IN ('?', '', 'NA', 'N/A', 'NULL')
   OR CAST(is_banked AS STRING) IN ('?', '', 'NA', 'N/A', 'NULL')
   OR CAST(score AS STRING) IN ('?', '', 'NA', 'N/A', 'NULL');

WITH expected_types AS (

    SELECT *
    FROM VALUES

        ('student_info_clean', 'code_module', 'string'),
        ('student_info_clean', 'code_presentation', 'string'),
        ('student_info_clean', 'id_student', 'bigint'),
        ('student_info_clean', 'gender', 'string'),
        ('student_info_clean', 'region', 'string'),
        ('student_info_clean', 'highest_education', 'string'),
        ('student_info_clean', 'imd_band', 'string'),
        ('student_info_clean', 'age_band', 'string'),
        ('student_info_clean', 'num_of_prev_attempts', 'int'),
        ('student_info_clean', 'studied_credits', 'int'),
        ('student_info_clean', 'disability', 'string'),
        ('student_info_clean', 'final_result', 'string'),
        ('student_info_clean', 'clean_load_timestamp', 'timestamp'),
        ('student_info_clean', 'clean_load_date', 'date'),

        ('student_registration_clean', 'code_module', 'string'),
        ('student_registration_clean', 'code_presentation', 'string'),
        ('student_registration_clean', 'id_student', 'bigint'),
        ('student_registration_clean', 'date_registration', 'int'),
        ('student_registration_clean', 'date_unregistration', 'int'),
        ('student_registration_clean', 'clean_load_timestamp', 'timestamp'),
        ('student_registration_clean', 'clean_load_date', 'date')

    AS t(table_name, column_name, expected_type)

),

type_mismatches AS (

    SELECT
        e.table_name,
        e.column_name,
        e.expected_type,
        LOWER(c.full_data_type) AS actual_type

    FROM expected_types AS e

    LEFT JOIN open_university.information_schema.columns AS c
        ON  c.table_schema = 'oulad_silver'
        AND c.table_name = e.table_name
        AND c.column_name = e.column_name

    WHERE c.column_name IS NULL
       OR LOWER(c.full_data_type) <> e.expected_type

)

SELECT
    'Student Silver schema' AS check_name,
    'student_info_clean + student_registration_clean' AS column_or_rule,

    COUNT(*) AS failure_count,

    0 AS expected_count,

    CASE
        WHEN COUNT(*) = 0 THEN 'Pass'
        ELSE 'Fail'
    END AS status

FROM type_mismatches

UNION ALL

SELECT
    'Source placeholder normalization',
    'student_info_clean text columns',

    COUNT(*),

    0,

    CASE
        WHEN COUNT(*) = 0 THEN 'Pass'
        ELSE 'Fail'
    END

FROM open_university.oulad_silver.student_info_clean

WHERE UPPER(TRIM(COALESCE(code_module, '')))
          IN ('?', 'NA', 'N/A', 'NULL')

   OR UPPER(TRIM(COALESCE(code_presentation, '')))
          IN ('?', 'NA', 'N/A', 'NULL')

   OR UPPER(TRIM(COALESCE(gender, '')))
          IN ('?', 'NA', 'N/A', 'NULL')

   OR UPPER(TRIM(COALESCE(region, '')))
          IN ('?', 'NA', 'N/A', 'NULL')

   OR UPPER(TRIM(COALESCE(highest_education, '')))
          IN ('?', 'NA', 'N/A', 'NULL')

   OR UPPER(TRIM(COALESCE(imd_band, '')))
          IN ('?', 'NA', 'N/A', 'NULL')

   OR UPPER(TRIM(COALESCE(age_band, '')))
          IN ('?', 'NA', 'N/A', 'NULL')

   OR UPPER(TRIM(COALESCE(disability, '')))
          IN ('?', 'NA', 'N/A', 'NULL')

   OR UPPER(TRIM(COALESCE(final_result, '')))
          IN ('?', 'NA', 'N/A', 'NULL')

UNION ALL

SELECT
    'Accepted values',
    'gender',

    COUNT(*),

    0,

    CASE
        WHEN COUNT(*) = 0 THEN 'Pass'
        ELSE 'Fail'
    END

FROM open_university.oulad_silver.student_info_clean

WHERE gender NOT IN ('F', 'M')
   OR gender IS NULL

UNION ALL

SELECT
    'Accepted values',
    'disability',

    COUNT(*),

    0,

    CASE
        WHEN COUNT(*) = 0 THEN 'Pass'
        ELSE 'Fail'
    END

FROM open_university.oulad_silver.student_info_clean

WHERE disability NOT IN ('Y', 'N')
   OR disability IS NULL

UNION ALL

SELECT
    'Accepted values',
    'final_result',

    COUNT(*),

    0,

    CASE
        WHEN COUNT(*) = 0 THEN 'Pass'
        ELSE 'Fail'
    END

FROM open_university.oulad_silver.student_info_clean

WHERE final_result NOT IN (
    'Distinction',
    'Fail',
    'Pass',
    'Withdrawn'
)
OR final_result IS NULL

UNION ALL

SELECT
    'Accepted values',
    'imd_band',

    COUNT(*),

    0,

    CASE
        WHEN COUNT(*) = 0 THEN 'Pass'
        ELSE 'Fail'
    END

FROM open_university.oulad_silver.student_info_clean

WHERE imd_band IS NOT NULL
  AND imd_band NOT IN (
        '0-10%',
        '10-20%',
        '20-30%',
        '30-40%',
        '40-50%',
        '50-60%',
        '60-70%',
        '70-80%',
        '80-90%',
        '90-100%'
  )

UNION ALL

SELECT
    'Numeric range',
    'num_of_prev_attempts',

    COUNT(*),

    0,

    CASE
        WHEN COUNT(*) = 0 THEN 'Pass'
        ELSE 'Fail'
    END

FROM open_university.oulad_silver.student_info_clean

WHERE num_of_prev_attempts IS NULL
   OR num_of_prev_attempts < 0

UNION ALL

SELECT
    'Numeric range',
    'studied_credits',

    COUNT(*),

    0,

    CASE
        WHEN COUNT(*) = 0 THEN 'Pass'
        ELSE 'Fail'
    END

FROM open_university.oulad_silver.student_info_clean

WHERE studied_credits IS NULL
   OR studied_credits < 0;

SELECT 'vle_invalid_week_ranges' AS check_name, COUNT(*) AS invalid_rows,
       CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END AS status
FROM open_university.oulad_silver.vle_clean
WHERE is_valid_date_range = FALSE;

SELECT 'vle_invalid_business_keys' AS check_name, COUNT(*) AS invalid_rows,
       CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END AS status
FROM open_university.oulad_silver.vle_clean
WHERE has_valid_business_keys = FALSE OR has_valid_business_keys IS NULL;

SELECT 'student_vle_negative_clicks' AS check_name, COUNT(*) AS invalid_rows,
       CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END AS status
FROM open_university.oulad_silver.student_vle_clean
WHERE sum_click < 0;
-- Checks Silver data types, accepted values and valid numeric ranges.
-- Expected result: every status is PASS and every failure count is zero.
