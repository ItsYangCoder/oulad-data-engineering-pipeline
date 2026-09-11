-- Overall withdrawal baseline using all enrollments as the denominator.
select
    count(*) as enrollment_count,
    sum(case when final_result = 'Withdrawn' then 1 else 0 end) as withdrawn_count,
    round(
        100.0 * sum(case when final_result = 'Withdrawn' then 1 else 0 end)
        / nullif(count(*), 0),
        2
    ) as withdrawal_rate_pct,
    sum(
        case
            when final_result = 'Withdrawn'
                and date_unregistration is not null
            then 1
            else 0
        end
    ) as known_withdrawal_timing_count,
    sum(
        case
            when final_result = 'Withdrawn'
                and date_unregistration is null
            then 1
            else 0
        end
    ) as unknown_withdrawal_timing_count
from open_university.oulad_gold.fact_student_enrollment;


-- Separates Withdrawn enrollments by whether withdrawal timing is available.
with withdrawn as (
    select
        case
            when date_unregistration is null then 'Unknown'
            else 'Known'
        end as timing_availability
    from open_university.oulad_gold.fact_student_enrollment
    where final_result = 'Withdrawn'
),

timing_summary as (
    select
        timing_availability,
        count(*) as withdrawn_count
    from withdrawn
    group by timing_availability
),

withdrawn_total as (
    select count(*) as total_count
    from withdrawn
)

select
    s.timing_availability,
    s.withdrawn_count,
    round(
        100.0 * s.withdrawn_count / nullif(t.total_count, 0),
        2
    ) as share_of_withdrawn_pct
from timing_summary s
cross join withdrawn_total t
order by s.timing_availability;


-- Shows relative withdrawal timing only where a withdrawal date is known.
select
    d.timing_group,
    d.relative_week,
    count(*) as withdrawn_count
from open_university.oulad_gold.fact_student_enrollment e
inner join open_university.oulad_gold.dim_date d
    on e.unregistration_date_key = d.date_key
where e.final_result = 'Withdrawn'
  and e.date_unregistration is not null
group by
    d.timing_group,
    d.relative_week
order by
    d.relative_week;


-- Measures demographic differences in withdrawal using all enrollments as the denominator.
select
    d.gender,
    d.age_band,
    d.highest_education,
    d.imd_band,
    count(*) as enrollment_count,
    sum(case when e.final_result = 'Withdrawn' then 1 else 0 end) as withdrawn_count,
    round(
        100.0 * sum(case when e.final_result = 'Withdrawn' then 1 else 0 end)
        / nullif(count(*), 0),
        2
    ) as withdrawal_rate_pct
from open_university.oulad_gold.fact_student_enrollment e
inner join open_university.oulad_gold.dim_demographics d
    on e.demographics_key = d.demographics_key
group by
    d.gender,
    d.age_band,
    d.highest_education,
    d.imd_band
order by
    withdrawal_rate_pct desc,
    enrollment_count desc;
