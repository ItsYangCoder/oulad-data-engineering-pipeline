{{ config(enabled=true) }}

-- dbt/models/dimensions/dim_demographics.sql
-- Grain: one row per distinct combination of gender, region, highest_education,
-- imd_band, age_band, disability
-- Source: open_university.oulad_silver.student_info_clean
-- Key method: md5 of the six attributes, each null-safe-coalesced to a
-- placeholder token before hashing (same pattern used in courses_clean.sql's
-- quarantine_id generation) so two enrollments with an identical NULL imd_band
-- resolve to the same demographics_key rather than two different keys.
-- Result: open_university.oulad_gold.dim_demographics
-- Note: NULL imd_band is preserved as-is in the stored profile (requirement #4);
-- only the key generation coalesces NULLs to a placeholder, the actual column
-- values are not modified. Reporting layers may choose to display "Unknown"
-- without altering this stored value.
-- Note: final_result, studied_credits, num_of_prev_attempts deliberately
-- excluded — these are enrollment outcomes, not demographic attributes.
-- Note: student_info_clean grain is one row per enrollment (code_module,
-- code_presentation, id_student), so the same demographic profile can and
-- will repeat across many enrollments — select distinct is required here to
-- collapse those repeats into one profile row.

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