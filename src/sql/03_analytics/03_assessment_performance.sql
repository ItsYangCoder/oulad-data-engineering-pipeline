-- File: 03_assessment_performance.sql
-- Suggested branch: feature/assessment-analysis
-- Purpose: Summarize assessment performance, score coverage and submission patterns.
-- Input: open_university.oulad_gold.fact_assessments.
-- Output: Read-only result set for Metabase; no CREATE, MERGE, INSERT or table rebuild.
-- Grain / business key: One output row per module-presentation and assessment type.
--
-- Metric definitions / business rules:
-- * result_count = all assessment-result rows, including rows with a missing score.
-- * scored_result_count = COUNT(score); NULL scores are excluded from score metrics.
-- * missing_score_count = result_count - scored_result_count.
-- * avg_score = AVG(score), which ignores NULL scores by SQL semantics.
-- * Assessment types remain separate: Exam, TMA and CMA.
-- * The current source batch has 173 missing TMA scores. Missing scores stay visible
--   in coverage and are not converted to zero or an automatic failure.
-- * No pass threshold is defined in pipeline_plan.md or assumptions.md, so no pass
--   rate is calculated here.
-- * assessment weight is retained as avg_assessment_weight for context only. No
--   weighted score is calculated because no approved weighted-score business rule
--   is documented.
-- * late_result_count uses date_submitted > assessment_date only when both relative
--   days are non-NULL. Unknown deadline/submission dates are not treated as late.
-- * banked_result_count reports is_banked = 1 but does not exclude or alter those
--   results because no banked-result exclusion rule is documented.

WITH fact_results AS (
    -- Gold source function:
    -- Reads the validated fact table as the single source of truth for
    -- assessment analytics. No source data is modified in this layer.
    SELECT
        id_assessment,
        id_student,
        code_module,
        code_presentation,
        assessment_type,
        assessment_date,
        date_submitted,
        weight,
        score,
        is_banked
    FROM open_university.oulad_gold.fact_assessments
),

assessment_performance AS (
    -- Aggregation function:
    -- Groups results by module, presentation and assessment type, then
    -- calculates coverage, score and submission-behavior metrics.
    -- COUNT(*) keeps all result rows, while COUNT(score) excludes NULL scores.
    -- AVG(score) calculates the average using only known scores.
    SELECT
        code_module,
        code_presentation,
        assessment_type,
        COUNT(*) AS result_count,
        COUNT(score) AS scored_result_count,
        COUNT(*) - COUNT(score) AS missing_score_count,
        AVG(score) AS avg_score,
        AVG(weight) AS avg_assessment_weight,
        SUM(CASE WHEN is_banked = 1 THEN 1 ELSE 0 END) AS banked_result_count,
        SUM(
            CASE
                WHEN date_submitted IS NOT NULL
                 AND assessment_date IS NOT NULL
                THEN 1
                ELSE 0
            END
        ) AS lateness_eligible_count,
        SUM(
            CASE
                WHEN date_submitted IS NOT NULL
                 AND assessment_date IS NOT NULL
                 AND date_submitted > assessment_date
                THEN 1
                ELSE 0
            END
        ) AS late_result_count
    FROM fact_results
    GROUP BY
        code_module,
        code_presentation,
        assessment_type
)

-- Reporting function:
-- Returns the analytics-ready metrics for dashboarding and interpretation.
-- The late-result rate uses only records with known submission and assessment
-- dates. Unknown dates remain outside the rate instead of being classified as late.
SELECT
    code_module,
    code_presentation,
    assessment_type,
    result_count,
    scored_result_count,
    missing_score_count,
    avg_score,
    avg_assessment_weight,
    banked_result_count,
    lateness_eligible_count,
    late_result_count,
    CASE
        -- Rate function: avoids division by zero when no date pair is eligible.
        WHEN lateness_eligible_count = 0 THEN NULL
        ELSE late_result_count * 100.0 / lateness_eligible_count
    END AS late_result_rate_pct
FROM assessment_performance
ORDER BY
    code_module,
    code_presentation,
    -- Display function: keeps assessment types in a consistent business order.
    CASE assessment_type
        WHEN 'Exam' THEN 1
        WHEN 'TMA' THEN 2
        WHEN 'CMA' THEN 3
        ELSE 4
    END;
