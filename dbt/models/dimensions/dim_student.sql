{{ config(enabled=true) }}

-- dbt/models/dimensions/dim_student.sql
-- Grain: one row per id_student
-- Source: open_university.oulad_silver.student_info_clean
-- Key method: md5 of id_student
-- Result: open_university.oulad_gold.dim_student
-- Note: only student identity is kept at this grain. Enrollment-dependent
-- attributes (final_result, studied_credits, num_of_prev_attempts, and
-- demographic profile) are intentionally excluded — they can vary per
-- enrollment and belong in fact_student_enrollment, not this dimension.

with source_students as (

    select distinct
        id_student

    from {{ source('oulad_silver', 'student_info_clean') }}

    where id_student is not null

)

select
    md5(cast(id_student as string)) as student_key,
    id_student,
    current_timestamp()             as mart_load_timestamp,
    current_date()                  as mart_load_date

from source_students
