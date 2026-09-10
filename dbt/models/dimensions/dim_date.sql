{{ config(enabled=true) }}

-- dbt/models/dimensions/dim_date.sql
-- Grain: one row per non-null relative_day
-- Sources:
--   assessment_clean.date
--   student_assessment_clean.date_submitted
--   student_vle_clean.date
--   student_registration_clean.date_registration
--   student_registration_clean.date_unregistration
-- Key method: md5 of relative_day cast to string
-- Result: open_university.oulad_gold.dim_date
-- OULAD dates are relative day offsets from the module presentation start.
-- Day 0 means presentation start.
-- Negative values represent days before presentation start.
-- Positive values represent days after presentation start.
-- relative_week calculation:
-- floor(relative_day / 7.0)
--   days 0 to 6    = week 0
--   days 7 to 13   = week 1
--   days -1 to -7  = week -1
--   days -8 to -14 = week -2
-- This is relative-day bucketing only and does not represent calendar weeks.
-- timing_group calculation:
--   'Pre-Presentation' for relative_day < 0
--   'Presentation Period' for relative_day >= 0
-- No finer-grained timing groups are defined because no business rules
-- for those boundaries have been supplied.
-- Missing source dates are not converted to day 0.
-- NULL source dates remain unknown and are excluded from this lookup.
-- No actual calendar dates, months, or years are generated.

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

)

select
    md5(cast(relative_day as string)) as date_key,
    relative_day,
    cast(floor(relative_day / 7.0) as integer) as relative_week,

    case
        when relative_day < 0 then true
        else false
    end as is_before_presentation,

    case
        when relative_day < 0 then 'Pre-Presentation'
        else 'Presentation Period'
    end as timing_group,

    current_timestamp() as mart_load_timestamp,
    current_date() as mart_load_date

from distinct_days