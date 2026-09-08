{{ config(enabled=false) }}

-- Model: dim_student
-- Purpose: Store one record per student.
-- Grain: One row per unique student ID.
-- Source: Silver student and demographic tables.
-- Status: TODO - implementation pending