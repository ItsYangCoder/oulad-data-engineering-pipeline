{{ config(enabled=true) }}

-- Grain: one row per student.
-- Enrollment-specific outcomes and demographics are stored outside this dimension.

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
