-- Each query should return zero rows.
select student_key, count(*) as row_count
from open_university.oulad_gold.dim_student
group by student_key
having student_key is null or count(*) <> 1;

select course_key, count(*) as row_count
from open_university.oulad_gold.dim_course
group by course_key
having course_key is null or count(*) <> 1;

select code_module, code_presentation, count(*) as row_count
from open_university.oulad_gold.dim_module_presentation
group by code_module, code_presentation
having code_module is null or code_presentation is null or count(*) <> 1;

select date_key, count(*) as row_count
from open_university.oulad_gold.dim_date
group by date_key
having date_key is null or count(*) <> 1;

-- The date dimension must contain exactly one Unknown record.
select count(*) as unknown_row_count
from open_university.oulad_gold.dim_date
where date_key = 'UNKNOWN' and relative_day is null
having count(*) <> 1;

select demographics_key, count(*) as row_count
from open_university.oulad_gold.dim_demographics
group by demographics_key
having demographics_key is null or count(*) <> 1;
