# Assessment Performance — Metabase Dashboard Specification

## Purpose

Provide the assessment-performance dashboard specification for the shared Metabase dashboard. The dashboard should use the read-only analytics query in `src/sql/03_analytics/03_assessment_performance.sql` and keep missing scores visible.

## Source

- Gold fact: `open_university.oulad_gold.fact_assessments`
- Analytics query: `src/sql/03_analytics/03_assessment_performance.sql`
- Business checks: `tests/04_business_checks/03_assessment_checks.sql`

## Recommended visuals

### 1. Assessment result coverage

**Visualization:** stacked bar or grouped bar

- Dimension: `assessment_type`
- Measures: `scored_result_count`, `missing_score_count`
- Filters: `code_module`, `code_presentation`

**Interpretation:** shows how many results have a known score versus a missing score. Missing values must remain visible and must not be treated as failures.

### 2. Average score by assessment type

**Visualization:** bar chart

- Dimension: `assessment_type`
- Measure: `avg_score`
- Filters: `code_module`, `code_presentation`

**Interpretation:** `avg_score` excludes NULL scores by SQL aggregation semantics.

### 3. Missing-score monitoring

**Visualization:** KPI/card

- Measure: `missing_score_count`
- Suggested filter: `assessment_type = TMA`

**Current-batch expectation:** 173 missing TMA scores.

### 4. Late submission rate

**Visualization:** bar chart or KPI

- Dimension: `assessment_type`
- Measure: `late_result_rate_pct`

**Interpretation:** only rows with both `assessment_date` and `date_submitted` known are eligible. Unknown dates are not classified as late.

### 5. Banked results

**Visualization:** bar chart or KPI

- Dimension: `assessment_type`
- Measure: `banked_result_count`

**Interpretation:** banked results remain in the reported population because no approved exclusion rule is documented.

## Dashboard filters

Recommended shared filters:

- `code_module`
- `code_presentation`
- `assessment_type`

## Business interpretation rules

- Total results = scored results + missing-score results.
- Missing scores remain NULL and are not converted to zero or automatic failures.
- No pass-rate metric is shown because no approved pass threshold is documented.
- Assessment weight is descriptive context only; no weighted score is calculated.
- Banked results are reported rather than excluded.

## Validation evidence to record in Metabase

Before marking the dashboard checklist complete, record the actual Databricks/Metabase result for:

1. total result count = 173,912
2. scored result count = 173,739
3. missing score count = 173
4. missing TMA score count = 173
5. analytics totals reconcile to `fact_assessments`
6. average score excludes NULL scores

A zero-row result from a failure-only business-check query is evidence that the corresponding check passed when executed. The repository cannot claim that result until the query has actually been run.
