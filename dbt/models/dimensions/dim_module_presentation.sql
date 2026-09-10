{{ config(materialized='table') }}

-- Grain: one module and presentation combination.
-- code_presentation is not unique without code_module.

with source_presentations as (
    select distinct code_module, code_presentation, module_presentation_length
    from {{ source('oulad_silver', 'courses_clean') }}
)

select
    md5(concat_ws('||', code_module, code_presentation)) as presentation_key,
    code_module,
    code_presentation,
    module_presentation_length,
    current_timestamp() as mart_load_timestamp,
    current_date() as mart_load_date
from source_presentations
