{{ config(enabled=true) }}

-- Grain: one distinct demographic profile.
-- Missing demographic values are standardized in Silver before this dimension is built.

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
            gender,
            region,
            highest_education,
            imd_band,
            age_band,
            disability
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
