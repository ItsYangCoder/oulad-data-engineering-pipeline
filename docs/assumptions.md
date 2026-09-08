# Project Assumptions

**Suggested branch:** `docs/update-assumptions`

This document records the agreed transformation and business rules for
the OULAD data engineering pipeline.

These assumptions are based on the completed Bronze source profiling.
They may be updated if new source batches or business requirements are
provided.

## 1. Bronze Data Preservation

Bronze tables preserve the original source records and values.

- No source rows will be deleted from Bronze.
- Text placeholders such as `?`, empty strings, `NA`, `N/A`, and `NULL`
  will remain unchanged in Bronze.
- Data cleaning will only be performed in the Clean layer.
- Ingestion metadata will be retained for audit purposes.

## 2. Missing-Value Handling

Source placeholders will be converted to SQL NULL values in the Clean
layer.

The pipeline will not guess or invent missing values unless an approved
business rule is provided.

## 3. Missing Demographic Information

The `student_info_raw` table contains 1,111 missing `imd_band` values.

These values will be converted to NULL. They will not be replaced with
a region average, mode, or default demographic category.

Analytics may display them as `Unknown` without modifying the stored
Clean value.

## 4. Missing Assessment Dates

The `assessment_raw` table contains 11 Exam records with missing dates.

These dates will remain NULL because no reliable examination deadline
is available. They will not be calculated or copied from another
assessment.

## 5. Missing Assessment Scores

The `student_assessment_raw` table contains 173 TMA records with missing
scores.

A missing score does not automatically mean a score of zero.

The pipeline will:

- Preserve the assessment record.
- Convert the placeholder to NULL.
- Exclude NULL scores from average-score calculations.
- Not treat a missing score as a failed assessment unless a business
  rule is later provided.

## 6. Registration and Withdrawal Dates

A missing `date_unregistration` usually means that the student did not
withdraw from the module presentation.

The primary dropout indicator will be:

`final_result = 'Withdrawn'`

The `date_unregistration` column will provide the withdrawal timing only
when a valid value is available.

The pipeline will preserve:

- 45 records with missing registration dates.
- 93 Withdrawn records with missing unregistration dates.
- 9 Fail records with recorded unregistration dates.

No missing registration or withdrawal dates will be invented.

## 7. VLE Availability Weeks

The `vle_raw` table contains 5,243 records where both `week_from` and
`week_to` are missing.

This is interpreted as an unspecified availability period.

Both values will remain NULL in the Clean layer. The records will not
be removed.

## 8. Student VLE Daily Aggregation

The Bronze table contains repeated student VLE daily keys.

The Clean table grain will be:

One student interacting with one VLE resource in one module presentation
on one relative date.

The candidate key is:

- `code_module`
- `code_presentation`
- `id_student`
- `id_site`
- `date`

Repeated records will be grouped using this key, and `sum_click` will be
summed.

The expected Clean output is 8,459,320 rows, assuming no additional
invalid records are discovered.

## 9. Assessment Fact Grain

One row in `fact_assessments` will represent:

One student's result for one assessment.

The expected business key is:

- `id_assessment`
- `id_student`

## 10. VLE Interaction Fact Grain

One row in `fact_vle_interactions` will represent:

One student's interaction with one VLE resource during one module
presentation on one relative date.

## 11. Relative Dates

Source date fields represent the number of days relative to the start
of a module presentation.

They will not be interpreted as calendar dates unless the actual module
presentation start date becomes available.

The project may use a relative-day dimension instead of inventing
calendar dates.

## 12. Source Relationships

The completed relationship tests returned zero orphan records.

The documented composite keys will be used when joining tables. Joining
only by `code_module` or `id_student` is not considered sufficient when
a module presentation is required.

## 13. Incremental Loading

The current source delivery is treated as the initial batch.

Incremental `COPY INTO` or `MERGE` logic will only be finalized when the
new batch location, delivery pattern, and update behavior are known.

Placeholder incremental commands will not be included in runnable Raw
scripts.

## 14. Assumption Review

These assumptions must be reviewed when:

- A new source batch arrives.
- The source schema changes.
- Business definitions are provided.
- A transformation produces unexpected row counts.
- A new data-quality issue is discovered.