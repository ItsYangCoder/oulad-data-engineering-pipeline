{{ config(enabled=true) }}

-- File: fact_assessments.sql
-- Purpose: Build the Gold assessment fact at one row per (id_assessment, id_student).
-- Grain: One row per assessment result pair.
-- Function: Integrates Silver assessment/result data with enrollment context and
--            resolves the surrogate keys required by the Gold star schema.

with assessment_results as (
    -- Source function:
    -- Reads student assessment results from Silver.
    -- NULL scores are intentionally preserved because a missing score means
    -- the result is unknown and must not be treated as zero or as a failure.
    select
        id_assessment,
        id_student,
        date_submitted,
        is_banked,
        score
    from {{ source('oulad_silver', 'student_assessment_clean') }}
),

assessment_context as (
    -- Source function:
    -- Reads assessment-level metadata from Silver, including the module,
    -- presentation, assessment type, deadline and assessment weight.
    select
        id_assessment,
        code_module,
        code_presentation,
        assessment_type,
        date as assessment_date,
        weight
    from {{ source('oulad_silver', 'assessment_clean') }}
),

enrollment_context as (
    -- Source function:
    -- Reads enrollment-level student attributes used to identify the
    -- student's demographic profile for the demographics dimension.
    select
        code_module,
        code_presentation,
        id_student,
        gender,
        region,
        highest_education,
        imd_band,
        age_band,
        disability
    from {{ source('oulad_silver', 'student_info_clean') }}
),

student_dimension as (
    -- Dimension lookup function:
    -- Maps the source id_student to the Gold surrogate student_key.
    select
        id_student,
        student_key
    from {{ ref('dim_student') }}
),

course_dimension as (
    -- Dimension lookup function:
    -- Maps code_module to the Gold surrogate course_key.
    select
        code_module,
        course_key
    from {{ ref('dim_course') }}
),

presentation_dimension as (
    -- Dimension lookup function:
    -- Maps code_module + code_presentation to presentation_key.
    select
        code_module,
        code_presentation,
        presentation_key
    from {{ ref('dim_module_presentation') }}
),

date_dimension as (
    -- Dimension lookup function:
    -- Maps the OULAD relative submission day (date_submitted) to date_key.
    select
        relative_day,
        date_key
    from {{ ref('dim_date') }}
),

demographics_dimension as (
    -- Dimension lookup function:
    -- Maps the enrollment demographic attributes to demographics_key.
    select
        gender,
        region,
        highest_education,
        imd_band,
        age_band,
        disability,
        demographics_key
    from {{ ref('dim_demographics') }}
),

joined as (
    -- Integration function:
    -- Combines assessment results with assessment metadata, enrollment
    -- context, and all required Gold dimension keys.
    -- LEFT JOINs preserve assessment-result rows even when a related
    -- dimension lookup is unavailable.
    select
        r.id_assessment,
        r.id_student,
        a.code_module,
        a.code_presentation,
        a.assessment_type,
        a.assessment_date,
        r.date_submitted,
        a.weight,
        r.score,
        r.is_banked,
        s.student_key,
        c.course_key,
        p.presentation_key,
        d.date_key,
        g.demographics_key
    from assessment_results r
    left join assessment_context a
        on r.id_assessment = a.id_assessment
    left join enrollment_context e
        on r.id_student = e.id_student
        and a.code_module = e.code_module
        and a.code_presentation = e.code_presentation
    left join student_dimension s
        on r.id_student = s.id_student
    left join course_dimension c
        on a.code_module = c.code_module
    left join presentation_dimension p
        on a.code_module = p.code_module
        and a.code_presentation = p.code_presentation
    left join date_dimension d
        on r.date_submitted = d.relative_day
    left join demographics_dimension g
        on coalesce(e.gender, '__NULL__') = coalesce(g.gender, '__NULL__')
        and coalesce(e.region, '__NULL__') = coalesce(g.region, '__NULL__')
        and coalesce(e.highest_education, '__NULL__') = coalesce(g.highest_education, '__NULL__')
        and coalesce(e.imd_band, '__NULL__') = coalesce(g.imd_band, '__NULL__')
        and coalesce(e.age_band, '__NULL__') = coalesce(g.age_band, '__NULL__')
        and coalesce(e.disability, '__NULL__') = coalesce(g.disability, '__NULL__')
)

-- Final Gold output function:
-- Produces the analytics-ready fact containing business identifiers,
-- dimension foreign keys, assessment/result measures, and mart audit fields.
select
    id_assessment,
    id_student,
    code_module,
    code_presentation,
    student_key,
    course_key,
    presentation_key,
    date_key,
    demographics_key,
    assessment_type,
    assessment_date,
    date_submitted,
    weight,
    score,
    is_banked,
    current_timestamp() as mart_load_timestamp,
    current_date() as mart_load_date
from joined
