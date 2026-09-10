{{ config(enabled=true) }}

-- Grain: one row per module.
-- course_key is generated from code_module.

with source_courses as (

    select distinct
        code_module

    from {{ source('oulad_silver', 'courses_clean') }}

)

select
    md5(code_module)      as course_key,
    code_module,
    current_timestamp()   as mart_load_timestamp,
    current_date()        as mart_load_date

from source_courses
