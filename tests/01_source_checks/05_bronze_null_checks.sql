
-- ASSESSMENT NULL CHECKS
SELECT
    COUNT(*) AS total_rows,
    SUM(CASE WHEN assessment_type IS NULL THEN 1 ELSE 0 END)
        AS missing_assessment_type,
    SUM(CASE WHEN date IS NULL THEN 1 ELSE 0 END)
        AS missing_assessment_date,
    SUM(CASE WHEN weight IS NULL THEN 1 ELSE 0 END)
        AS missing_weight
FROM open_university.oulad_bronze.assessment_raw;



-- STUDENT ASSESSMENT NULL CHECKS
SELECT
    COUNT(*) AS total_rows,
    SUM(CASE WHEN date_submitted IS NULL THEN 1 ELSE 0 END)
        AS missing_date_submitted,
    SUM(CASE WHEN is_banked IS NULL THEN 1 ELSE 0 END)
        AS missing_is_banked,
    SUM(CASE WHEN score IS NULL THEN 1 ELSE 0 END)
        AS missing_score
FROM open_university.oulad_bronze.student_assessment_raw;



-- STUDENT INFORMATION NULL CHECKS
SELECT
    COUNT(*) AS total_rows,
    SUM(CASE WHEN gender IS NULL THEN 1 ELSE 0 END)
        AS missing_gender,
    SUM(CASE WHEN region IS NULL THEN 1 ELSE 0 END)
        AS missing_region,
    SUM(CASE WHEN highest_education IS NULL THEN 1 ELSE 0 END)
        AS missing_highest_education,
    SUM(CASE WHEN imd_band IS NULL THEN 1 ELSE 0 END)
        AS missing_imd_band,
    SUM(CASE WHEN age_band IS NULL THEN 1 ELSE 0 END)
        AS missing_age_band,
    SUM(CASE WHEN final_result IS NULL THEN 1 ELSE 0 END)
        AS missing_final_result
FROM open_university.oulad_bronze.student_info_raw;

-- STUDENT REGISTRATION NULL CHECKS
SELECT
    COUNT(*) AS total_rows,
    SUM(CASE WHEN date_registration IS NULL THEN 1 ELSE 0 END)
        AS missing_date_registration,
    SUM(CASE WHEN date_unregistration IS NULL THEN 1 ELSE 0 END)
        AS missing_date_unregistration
FROM open_university.oulad_bronze.student_registration_raw;


-- VLE RESOURCE NULL CHECKS
SELECT
    COUNT(*) AS total_rows,
    SUM(CASE WHEN activity_type IS NULL THEN 1 ELSE 0 END)
        AS missing_activity_type,
    SUM(CASE WHEN week_from IS NULL THEN 1 ELSE 0 END)
        AS missing_week_from,
    SUM(CASE WHEN week_to IS NULL THEN 1 ELSE 0 END)
        AS missing_week_to
FROM open_university.oulad_bronze.vle_raw;

-- STUDENT VLE NULL CHECKS
SELECT
    COUNT(*) AS total_rows,
    SUM(CASE WHEN sum_click IS NULL THEN 1 ELSE 0 END)
        AS missing_sum_click
FROM open_university.oulad_bronze.student_vle_raw;