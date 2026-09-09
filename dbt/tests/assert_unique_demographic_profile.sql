-- Fails when more than one row exists for the same six-attribute demographic profile.
-- SQL GROUP BY treats matching NULL values as one group, which preserves the
-- dimension's intended null-safe business grain.
select
    gender,
    region,
    highest_education,
    imd_band,
    age_band,
    disability,
    count(*) as row_count
from {{ ref('dim_demographics') }}
group by
    gender,
    region,
    highest_education,
    imd_band,
    age_band,
    disability
having count(*) > 1
