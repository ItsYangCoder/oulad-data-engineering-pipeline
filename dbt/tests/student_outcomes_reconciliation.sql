-- Returns a row when the reporting view loses or duplicates enrollments.
with source_count as (
    select count(*) as row_count
    from {{ source('oulad_silver', 'student_info_clean') }}
),

view_count as (
    select count(*) as row_count
    from {{ ref('vw_student_outcomes') }}
)

select s.row_count as source_rows, v.row_count as view_rows
from source_count s
cross join view_count v
where s.row_count <> v.row_count
