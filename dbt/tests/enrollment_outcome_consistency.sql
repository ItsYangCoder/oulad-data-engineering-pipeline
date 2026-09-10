-- Returns rows when is_withdrawn disagrees with the documented final_result rule.
select *
from {{ ref('fact_student_enrollment') }}
where is_withdrawn <> (final_result = 'Withdrawn')
