-- Returns rows when the enrollment business key is missing or duplicated.
with grouped as (
    select
        code_module,
        code_presentation,
        id_student,
        count(*) as row_count
    from {{ ref('fact_student_enrollment') }}
    group by code_module, code_presentation, id_student
)

select *
from grouped
where code_module is null
   or code_presentation is null
   or id_student is null
   or row_count <> 1
