-- Measures demographic differences in withdrawal using all enrollments as the denominator.
select
    coalesce(d.gender, 'Unknown') as gender,
    coalesce(d.age_band, 'Unknown') as age_band,
    coalesce(d.highest_education, 'Unknown') as highest_education,
    coalesce(d.imd_band, 'Unknown') as imd_band,
    count(*) as enrollment_count,
    sum(case when e.is_withdrawn then 1 else 0 end) as withdrawn_count,
    round(100.0 * sum(case when e.is_withdrawn then 1 else 0 end) / count(*), 2)
        as withdrawal_rate_pct
from open_university.oulad_gold.fact_student_enrollment e
inner join open_university.oulad_gold.dim_demographics d
    on e.demographics_key = d.demographics_key
group by
    coalesce(d.gender, 'Unknown'),
    coalesce(d.age_band, 'Unknown'),
    coalesce(d.highest_education, 'Unknown'),
    coalesce(d.imd_band, 'Unknown')
order by withdrawal_rate_pct desc, enrollment_count desc;
