-- Measures demographic differences in withdrawal using all enrollments as the denominator.
select
    d.gender,
    d.age_band,
    d.highest_education,
    d.imd_band,
    count(*) as enrollment_count,
    sum(case when e.is_withdrawn then 1 else 0 end) as withdrawn_count,
    round(100.0 * sum(case when e.is_withdrawn then 1 else 0 end) / count(*), 2)
        as withdrawal_rate_pct
from open_university.oulad_gold.fact_student_enrollment e
inner join open_university.oulad_gold.dim_demographics d
    on e.demographics_key = d.demographics_key
group by
    d.gender,
    d.age_band,
    d.highest_education,
    d.imd_band
order by withdrawal_rate_pct desc, enrollment_count desc;
