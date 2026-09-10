-- Fails when more than one row exists for a module/presentation business key.
select
    code_module,
    code_presentation,
    count(*) as row_count
from {{ ref('dim_module_presentation') }}
group by
    code_module,
    code_presentation
having count(*) > 1
