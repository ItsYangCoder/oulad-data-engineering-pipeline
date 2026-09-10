-- Enrollment, outcome and assessment totals must reconcile to Silver.
select
    (select count(*) from open_university.oulad_silver.student_info_clean) as silver_enrollments,
    (select count(*) from open_university.oulad_gold.fact_student_enrollment) as gold_enrollments,
    (select count(*) from open_university.oulad_gold.vw_student_outcomes) as reporting_enrollments,
    (select count(*) from open_university.oulad_gold.fact_student_enrollment where is_withdrawn) as withdrawn_enrollments,
    (select sum(assessment_count) from open_university.oulad_gold.fact_student_enrollment) as summarized_assessments,
    (select count(*) from open_university.oulad_silver.student_assessment_clean) as silver_assessments;

-- VLE rows and clicks must reconcile to the already aggregated Silver table.
select
    (select count(*) from open_university.oulad_silver.student_vle_clean) as silver_rows,
    (select count(*) from open_university.oulad_gold.fact_vle_interactions) as gold_rows,
    (select sum(sum_click) from open_university.oulad_silver.student_vle_clean) as silver_clicks,
    (select sum(sum_click) from open_university.oulad_gold.fact_vle_interactions) as gold_clicks;
