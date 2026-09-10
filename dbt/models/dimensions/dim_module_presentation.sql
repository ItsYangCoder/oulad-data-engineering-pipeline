{{ config(enabled=true) }}

-- dbt/models/dimensions/dim_module_presentation.sql
-- Grain: one row per distinct code_module + code_presentation pair
-- Source: open_university.oulad_silver.courses_clean, ref('dim_course')
-- Key method: md5 of code_module + delimiter + code_presentation
-- Expected current-batch rows: 22
-- Note on is_valid_key: no filter needed. courses_clean.sql only merges
-- is_valid_key = TRUE rows; invalid keys are quarantined upstream.
-- Note: is_valid_length intentionally excluded from output per requirement #2
-- (spec lists exactly presentation_key, course_key, code_module,
-- code_presentation, module_presentation_length).

with source_presentations as (

    select distinct
        code_module,
        code_presentation,
        module_presentation_length

    from {{ source('oulad_silver', 'courses_clean') }}

),

presentation_with_course as (

    select
        sp.code_module,
        sp.code_presentation,
        sp.module_presentation_length,
        dc.course_key

    from source_presentations sp

    inner join {{ ref('dim_course') }} dc
        on sp.code_module = dc.code_module

)

select
    md5(concat(code_module, '||', code_presentation)) as presentation_key,
    course_key,
    code_module,
    code_presentation,
    module_presentation_length,
    current_timestamp() as mart_load_timestamp,
    current_date() as mart_load_date

from presentation_with_course