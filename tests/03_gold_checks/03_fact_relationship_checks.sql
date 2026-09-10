-- Each result should report zero unresolved foreign keys.
select
    sum(case when s.student_key is null then 1 else 0 end) as missing_student,
    sum(case when c.course_key is null then 1 else 0 end) as missing_course,
    sum(case when p.presentation_key is null then 1 else 0 end) as missing_presentation,
    sum(case when d.demographics_key is null then 1 else 0 end) as missing_demographics,
    sum(case when rd.date_key is null then 1 else 0 end) as missing_registration_date,
    sum(case when ud.date_key is null then 1 else 0 end) as missing_unregistration_date
from open_university.oulad_gold.fact_student_enrollment f
left join open_university.oulad_gold.dim_student s on f.student_key = s.student_key
left join open_university.oulad_gold.dim_course c on f.course_key = c.course_key
left join open_university.oulad_gold.dim_module_presentation p on f.presentation_key = p.presentation_key
left join open_university.oulad_gold.dim_demographics d on f.demographics_key = d.demographics_key
left join open_university.oulad_gold.dim_date rd on f.registration_date_key = rd.date_key
left join open_university.oulad_gold.dim_date ud on f.unregistration_date_key = ud.date_key;

select
    sum(case when s.student_key is null then 1 else 0 end) as missing_student,
    sum(case when c.course_key is null then 1 else 0 end) as missing_course,
    sum(case when p.presentation_key is null then 1 else 0 end) as missing_presentation,
    sum(case when d.demographics_key is null then 1 else 0 end) as missing_demographics,
    sum(case when dt.date_key is null then 1 else 0 end) as missing_date
from open_university.oulad_gold.fact_vle_interactions f
left join open_university.oulad_gold.dim_student s on f.student_key = s.student_key
left join open_university.oulad_gold.dim_course c on f.course_key = c.course_key
left join open_university.oulad_gold.dim_module_presentation p on f.presentation_key = p.presentation_key
left join open_university.oulad_gold.dim_demographics d on f.demographics_key = d.demographics_key
left join open_university.oulad_gold.dim_date dt on f.date_key = dt.date_key;
