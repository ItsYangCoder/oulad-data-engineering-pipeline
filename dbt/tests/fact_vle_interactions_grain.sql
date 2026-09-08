{{ config(enabled=false) }}

-- File: fact_vle_interactions_grain.sql
-- Purpose: Reject repeated or incomplete daily interaction keys.
-- Status: Implementation pending. Replace this guide with the finished code.
-- Input: ref('fact_vle_interactions').
-- Output: A dbt singular test: one SELECT/CTE query returning failing rows only.
--
-- What to put in this file:
-- 1. Check every component of code_module + code_presentation + id_student + id_site + date for NULL.
-- 2. GROUP BY the complete five-column key and return groups with COUNT(*) > 1.
-- 3. Return failing keys/counts only; negative relative date values are valid.
-- 4. Remove enabled=false when the SQL and upstream model are ready, then run this test and verify it
--    catches a deliberate failing case in development.
--
--
-- Done when: Zero returned rows when each daily interaction key occurs once.
-- Read: docs/pipeline_plan.md and docs/assumptions.md.
