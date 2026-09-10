{{ config(enabled=true) }}

-- Grain: one distinct demographic profile.
-- NULL attributes remain NULL but are handled consistently when generating the key.

with source_demographics as (

    select distinct
        gender,
        region,
        highest_education,
        imd_band,
        age_band,
        disability

    from {{ source('oulad_silver', 'student_info_clean') }}

)

select
    md5(
        concat_ws(
            '||',
            coalesce(gender, '__NULL__'),
            coalesce(region, '__NULL__'),
            coalesce(highest_education, '__NULL__'),
            coalesce(imd_band, '__NULL__'),
            coalesce(age_band, '__NULL__'),
            coalesce(disability, '__NULL__')
        )
    )                    as demographics_key,
    gender,
    region,
    highest_education,
    imd_band,
    age_band,
    disability,
    current_timestamp()  as mart_load_timestamp,
    current_date()       as mart_load_date

from source_demographics
