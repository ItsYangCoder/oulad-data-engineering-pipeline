-- VLE measures must reconcile and the reporting view must keep every enrollment.
select
    (select count(*) from open_university.oulad_silver.student_vle_clean) as silver_vle_rows,
    (select count(*) from open_university.oulad_gold.fact_vle_interactions) as gold_vle_rows,
    (select sum(sum_click) from open_university.oulad_silver.student_vle_clean) as silver_clicks,
    (select sum(sum_click) from open_university.oulad_gold.fact_vle_interactions) as gold_clicks,
    (select count(*) from open_university.oulad_silver.student_info_clean) as silver_enrollments,
    (select count(*) from open_university.oulad_gold.vw_student_outcomes) as reporting_enrollments;
