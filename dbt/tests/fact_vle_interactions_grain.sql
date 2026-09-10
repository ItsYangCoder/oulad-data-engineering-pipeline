-- Returns rows when the VLE business key is missing or duplicated.
with grouped as (
    select
        code_module,
        code_presentation,
        id_student,
        id_site,
        relative_day,
        count(*) as row_count
    from {{ ref('fact_vle_interactions') }}
    group by code_module, code_presentation, id_student, id_site, relative_day
)

select *
from grouped
where code_module is null
   or code_presentation is null
   or id_student is null
   or id_site is null
   or relative_day is null
   or row_count <> 1
