{{ config(enabled=true) }}

-- dbt/models/dimensions/dim_course.sql
-- Grain: one row per distinct code_module, across all presentations
-- Source: open_university.oulad_silver.courses_clean
-- Key method: md5 of code_module
-- Result: open_university.oulad_gold.dim_course
-- Note on is_valid_key: no filter needed. courses_clean.sql only merges
-- is_valid_key = TRUE rows; invalid keys are quarantined upstream.
-- Note: is_valid_length not applicable — this model does not select
-- module_presentation_length (that belongs to dim_module_presentation).

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