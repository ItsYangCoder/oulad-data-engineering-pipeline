{{ config(enabled=false) }}

-- File: fact_assessments_grain.sql
-- Purpose: Reject repeated or incomplete student-assessment keys.
-- Status: Implementation pending. Replace this guide with the finished code.
-- Input: ref('fact_assessments').
-- Output: A dbt singular test: one SELECT/CTE query returning failing rows only.
--
-- What to put in this file:
-- 1. Select rows with NULL id_assessment or id_student, and groups repeated on the pair.
-- 2. GROUP BY id_assessment, id_student and return groups with COUNT(*) > 1.
-- 3. Return failing keys/counts only; do not return a successful summary row.
-- 4. Remove enabled=false when the SQL and upstream model are ready, then run this test and verify it
--    catches a deliberate failing case in development.
--
--
-- Done when: Zero returned rows when the model has one record per result pair.
-- Read: docs/pipeline_plan.md and docs/assumptions.md.
