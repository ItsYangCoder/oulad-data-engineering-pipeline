{{ config(enabled=true) }}

-- Grain: one observed relative day plus one Unknown record.
-- Negative days occur before the presentation; missing dates use the Unknown key.

with assessment_dates as (

    select
        cast(date as integer) as relative_day

    from {{ source('oulad_silver', 'assessment_clean') }}

),

student_assessment_dates as (

    select
        cast(date_submitted as integer) as relative_day

    from {{ source('oulad_silver', 'student_assessment_clean') }}

),

vle_dates as (

    select
        cast(date as integer) as relative_day

    from {{ source('oulad_silver', 'student_vle_clean') }}

),

registration_dates as (

    select
        cast(date_registration as integer) as relative_day

    from {{ source('oulad_silver', 'student_registration_clean') }}

),

unregistration_dates as (

    select
        cast(date_unregistration as integer) as relative_day

    from {{ source('oulad_silver', 'student_registration_clean') }}

),

all_dates as (

    select relative_day
    from assessment_dates

    union

    select relative_day
    from student_assessment_dates

    union

    select relative_day
    from vle_dates

    union

    select relative_day
    from registration_dates

    union

    select relative_day
    from unregistration_dates

),

distinct_days as (

    select distinct
        relative_day

    from all_dates

    where relative_day is not null

),

known_days as (
    select
        md5(cast(relative_day as string)) as date_key,
        relative_day,
        cast(floor(relative_day / 7.0) as integer) as relative_week,
        case when relative_day < 0 then true else false end as is_before_presentation,
        case
            when relative_day < 0 then 'Pre-Presentation'
            else 'Presentation Period'
        end as timing_group
    from distinct_days
)

select
    date_key,
    relative_day,
    relative_week,
    is_before_presentation,
    timing_group,
    current_timestamp() as mart_load_timestamp,
    current_date() as mart_load_date
from known_days

union all

select
    'UNKNOWN' as date_key,
    cast(null as integer) as relative_day,
    cast(null as integer) as relative_week,
    cast(null as boolean) as is_before_presentation,
    'Unknown' as timing_group,
    current_timestamp() as mart_load_timestamp,
    current_date() as mart_load_date
