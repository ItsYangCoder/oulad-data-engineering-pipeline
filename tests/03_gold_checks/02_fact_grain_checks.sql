-- Both queries should return zero rows.
select code_module, code_presentation, id_student, count(*) as row_count
from open_university.oulad_gold.fact_student_enrollment
group by code_module, code_presentation, id_student
having count(*) <> 1;

select code_module, code_presentation, id_student, id_site, relative_day, count(*) as row_count
from open_university.oulad_gold.fact_vle_interactions
group by code_module, code_presentation, id_student, id_site, relative_day
having count(*) <> 1;
