# OULAD Data Engineering Pipeline Plan

**Suggested branch:** `docs/update-pipeline-plan`

## 1. Project Purpose

This document defines how the Open University Learning Analytics Dataset (OULAD) will be processed from Raw to Clean to Mart.

The plan is based on:

* Completed Bronze ingestion
* Bronze validation results
* Source profiling findings
* Documented project assumptions
* Expected analytics requirements

The final pipeline should support analysis of:

* Student assessment performance
* Student withdrawal and completion
* Demographic patterns
* Virtual Learning Environment engagement
* Relationship between engagement and academic performance

---

## 2. Pipeline Architecture

The project follows a medallion-style architecture:

**Source CSV → Raw/Bronze → Clean/Silver → Mart/Gold → Analytics**

| Layer        | Databricks schema               | Main responsibility                            |
| ------------ | ------------------------------- | ---------------------------------------------- |
| Source       | Unity Catalog Volume            | Store the delivered CSV files                  |
| Raw/Bronze   | `open_university.oulad_bronze`  | Preserve source records and ingestion metadata |
| Clean/Silver | `open_university.oulad_silver`  | Standardize, cast, clean, and aggregate data   |
| Mart/Gold    | `open_university.oulad_gold`    | Build dimensions and fact tables               |
| Quality      | `open_university.oulad_quality` | Store or execute validation checks             |
| Analytics    | SQL files and dashboards        | Answer the project’s business questions        |

---

## 3. Source Files

The project contains seven source CSV files.

| Source file               | Bronze table               | Bronze rows |
| ------------------------- | -------------------------- | ----------: |
| `assessments.csv`         | `assessment_raw`           |         206 |
| `courses.csv`             | `courses_raw`              |          22 |
| `studentAssessment.csv`   | `student_assessment_raw`   |     173,912 |
| `studentInfo.csv`         | `student_info_raw`         |      32,593 |
| `studentRegistration.csv` | `student_registration_raw` |      32,593 |
| `studentVle.csv`          | `student_vle_raw`          |  10,655,280 |
| `vle.csv`                 | `vle_raw`                  |       6,364 |

Every Bronze table contains:

* `ingestion_timestamp`
* `ingestion_date`

Bronze preserves the original source values. Cleaning and business-rule application must not happen in Bronze.

---

## 4. Confirmed Source Findings

Bronze validation confirmed the following:

* All seven source files were loaded with the expected row counts.
* All ingestion metadata columns are complete.
* All tested parent-child relationships contain zero orphan rows.
* Source placeholders such as `?` are used instead of physical SQL NULL values.
* The `student_vle_raw` table contains repeated daily interaction keys.

### Missing values

| Source table               | Column                | Missing rows |
| -------------------------- | --------------------- | -----------: |
| `student_info_raw`         | `imd_band`            |        1,111 |
| `student_registration_raw` | `date_registration`   |           45 |
| `student_registration_raw` | `date_unregistration` |       22,521 |
| `vle_raw`                  | `week_from`           |        5,243 |
| `vle_raw`                  | `week_to`             |        5,243 |
| `assessment_raw`           | `date`                |           11 |
| `student_assessment_raw`   | `score`               |          173 |

The 11 missing assessment dates all belong to Exam records.

The 173 missing scores all belong to TMA assessment records.

### Student VLE repeated keys

The candidate key for a daily student VLE interaction is:

* `code_module`
* `code_presentation`
* `id_student`
* `id_site`
* `date`

Profiling results:

| Metric                  |       Rows |
| ----------------------- | ---------: |
| Bronze source rows      | 10,655,280 |
| Unique daily keys       |  8,459,320 |
| Repeated key groups     |  1,614,505 |
| Repeated or excess rows |  2,195,960 |

Bronze will keep every source row. Clean will combine repeated daily keys and calculate the total number of clicks.

---

## 5. Raw-to-Clean Mapping

| Raw input                  | Clean output                 | Expected Clean rows |
| -------------------------- | ---------------------------- | ------------------: |
| `courses_raw`              | `courses_clean`              |                  22 |
| `assessment_raw`           | `assessment_clean`           |                 206 |
| `student_assessment_raw`   | `student_assessment_clean`   |             173,912 |
| `student_info_raw`         | `student_info_clean`         |              32,593 |
| `student_registration_raw` | `student_registration_clean` |              32,593 |
| `vle_raw`                  | `vle_clean`                  |               6,364 |
| `student_vle_raw`          | `student_vle_clean`          |           8,459,320 |

The expected `student_vle_clean` count is lower than the Bronze count because repeated daily keys will be aggregated.

---

## 6. General Clean-Layer Rules

Every Clean transformation must:

* Trim unnecessary spaces from text values.
* Standardize text categories where appropriate.
* Convert source placeholders to SQL NULL.
* Use `TRY_CAST` for safe type conversion.
* Preserve records with missing optional values.
* Avoid inventing missing dates or values.
* Apply the documented candidate keys.
* Remove or aggregate repeated business keys when required.
* Add `clean_load_timestamp`.
* Add `clean_load_date`.
* Produce repeatable results when the pipeline is rerun.
* Include a corresponding validation file.

The following source representations are treated as missing values:

* `?`
* Empty string
* `NA`
* `N/A`
* Text value `NULL`

Missing numeric values must not automatically be replaced with zero.

---

## 7. Clean Table Specifications

## 7.1 `courses_clean`

**Source:** `courses_raw`

**Grain:** One row per module presentation.

**Candidate key:**

* `code_module`
* `code_presentation`

**Transformations:**

* Trim `code_module`.
* Trim and standardize `code_presentation`.
* Cast `module_presentation_length` to INTEGER.
* Validate that the candidate key is complete and unique.
* Add Clean audit columns.
* Preserve all 22 source rows.

---

## 7.2 `assessment_clean`

**Source:** `assessment_raw`

**Grain:** One row per assessment.

**Candidate key:**

* `id_assessment`

**Transformations:**

* Trim and standardize module and presentation codes.
* Cast `id_assessment` to BIGINT.
* Standardize `assessment_type`.
* Convert the assessment date placeholder to NULL.
* Cast valid assessment dates to INTEGER.
* Cast `weight` to DECIMAL.
* Preserve the 11 Exam records with missing assessment dates.
* Do not invent examination deadlines.
* Add Clean audit columns.
* Preserve all 206 source rows.

---

## 7.3 `student_assessment_clean`

**Source:** `student_assessment_raw`

**Grain:** One student result for one assessment.

**Candidate key:**

* `id_assessment`
* `id_student`

**Transformations:**

* Cast `id_assessment` to BIGINT.
* Cast `id_student` to BIGINT.
* Cast `date_submitted` to INTEGER.
* Cast `is_banked` to INTEGER or another agreed Boolean-compatible type.
* Convert missing score placeholders to NULL.
* Cast valid scores to DECIMAL.
* Validate that scores are between 0 and 100.
* Preserve all 173 records with missing TMA scores.
* Do not replace missing scores with zero.
* Add Clean audit columns.
* Preserve all 173,912 source rows.

---

## 7.4 `student_info_clean`

**Source:** `student_info_raw`

**Grain:** One student enrollment in one module presentation.

**Candidate key:**

* `code_module`
* `code_presentation`
* `id_student`

**Transformations:**

* Standardize module and presentation codes.
* Cast `id_student` to BIGINT.
* Standardize `gender`.
* Trim and standardize `region`.
* Standardize `highest_education`.
* Convert missing `imd_band` placeholders to NULL.
* Standardize `age_band`.
* Cast `num_of_prev_attempts` to INTEGER.
* Cast `studied_credits` to INTEGER.
* Standardize `disability`.
* Standardize `final_result`.
* Preserve all 1,111 records with missing `imd_band`.
* Add Clean audit columns.
* Preserve all 32,593 source rows.

---

## 7.5 `student_registration_clean`

**Source:** `student_registration_raw`

**Grain:** One student registration in one module presentation.

**Candidate key:**

* `code_module`
* `code_presentation`
* `id_student`

**Transformations:**

* Standardize module and presentation codes.
* Cast `id_student` to BIGINT.
* Convert missing date placeholders to NULL.
* Cast valid `date_registration` values to INTEGER.
* Cast valid `date_unregistration` values to INTEGER.
* Preserve all 45 missing registration dates.
* Preserve all 93 Withdrawn records with missing unregistration dates.
* Do not invent missing dates.
* Add Clean audit columns.
* Preserve all 32,593 source rows.

A missing `date_unregistration` does not automatically indicate a source error. It is expected for students who did not withdraw.

The primary dropout rule is:

**`final_result = 'Withdrawn'`**

---

## 7.6 `vle_clean`

**Source:** `vle_raw`

**Grain:** One VLE resource in one module presentation.

**Candidate key:**

* `code_module`
* `code_presentation`
* `id_site`

**Transformations:**

* Standardize module and presentation codes.
* Cast `id_site` to BIGINT.
* Standardize `activity_type`.
* Convert missing `week_from` values to NULL.
* Convert missing `week_to` values to NULL.
* Cast valid week values to INTEGER.
* Preserve the 5,243 resources with unspecified availability weeks.
* Add Clean audit columns.
* Preserve all 6,364 source rows.

---

## 7.7 `student_vle_clean`

**Source:** `student_vle_raw`

**Grain:** One student’s interaction with one VLE resource during one module presentation on one relative date.

**Candidate key:**

* `code_module`
* `code_presentation`
* `id_student`
* `id_site`
* `date`

**Transformations:**

* Standardize module and presentation codes.
* Cast `id_student` to BIGINT.
* Cast `id_site` to BIGINT.
* Cast `date` to INTEGER.
* Cast `sum_click` to BIGINT.
* Validate that `sum_click` is not negative.
* Group records using the complete candidate key.
* Calculate `SUM(sum_click)` for repeated daily keys.
* Add Clean audit columns.
* Produce an expected 8,459,320 rows.

The total number of clicks before and after aggregation must remain equal.

---

## 8. Clean Validation Requirements

Every Clean table must be tested for:

* Expected row count
* Missing candidate-key values
* Duplicate candidate keys
* Invalid data types
* Unconverted source placeholders
* Invalid numeric ranges
* Missing audit columns
* Missing parent records
* Unexpected record loss

Important expected results:

| Clean table                  | Expected rows |
| ---------------------------- | ------------: |
| `courses_clean`              |            22 |
| `assessment_clean`           |           206 |
| `student_assessment_clean`   |       173,912 |
| `student_info_clean`         |        32,593 |
| `student_registration_clean` |        32,593 |
| `vle_clean`                  |         6,364 |
| `student_vle_clean`          |     8,459,320 |

The following values are expected and must not automatically fail the pipeline:

* 1,111 missing `imd_band` values
* 45 missing registration dates
* 22,521 missing unregistration dates
* 5,243 missing VLE availability ranges
* 11 missing Exam dates
* 173 missing TMA scores

---

## 9. Mart Model

Gold transformations are implemented with dbt in `dbt/models/`, targeting
`open_university.oulad_gold`. Use `source()` for Silver tables and `ref()`
for other dbt models.

The agreed professor-aligned scope contains exactly five dimensions and two
facts, plus one supporting reporting view.

### Dimensions

| Model | Grain | Main source |
| --- | --- | --- |
| `dim_student` | One row per student | `student_info_clean` |
| `dim_course` | One row per module | `courses_clean` |
| `dim_module_presentation` | One row per module presentation | `courses_clean` |
| `dim_date` | One row per relative day | Clean relative-day fields |
| `dim_demographics` | One row per distinct demographic profile | `student_info_clean` |

### Facts

| Model | Grain | Main source |
| --- | --- | --- |
| `fact_assessments` | One student result for one assessment | Student assessment and assessment context |
| `fact_vle_interactions` | One student-resource-day per module presentation | Clean student VLE interactions |

### Supporting reporting view

`vw_student_outcomes` has one row per student-module-presentation enrollment.
It provides the complete population for cohort, dropout and enrollment-level
reporting, including students without recorded assessment or VLE activity.

Do not add `fact_student_enrollment`, `dim_assessment` or
`dim_vle_resource` to the required scope. Assessment and resource context
belongs directly in the respective facts. The required relative-day dimension
is named `dim_date`.

---

## 10. Dimension Specifications

Use consistent, repeatable keys and document the chosen key method. Planned
Gold audit fields are `mart_load_timestamp` and `mart_load_date`; keep the
implemented names consistent across models and tests.

### 10.1 `dim_course`

- Grain/business key: one `code_module`.
- Fields: `course_key`, `code_module` and audit fields.
- Take distinct modules from `courses_clean`; do not invent module names.

### 10.2 `dim_module_presentation`

- Grain/business key: one `code_module + code_presentation` pair.
- Fields: `presentation_key`, `course_key`, both codes,
  `module_presentation_length` and audit fields.
- A presentation code alone is not unique across modules.
- Expected current-batch rows: 22.

### 10.3 `dim_student`

- Grain/business key: one `id_student`.
- Fields: `student_key`, `id_student` and audit fields.
- A student may have several enrollments. Keep presentation-dependent
  `final_result`, `studied_credits` and `num_of_prev_attempts` in
  `vw_student_outcomes`, not as permanent student attributes.
- Resolve demographics using the matching enrollment when building facts.

### 10.4 `dim_demographics`

- Grain: one distinct combination of `gender`, `region`,
  `highest_education`, `imd_band`, `age_band` and `disability`.
- Fields: `demographics_key`, those six attributes and audit fields.
- Use consistent NULL handling for keys and null-safe profile matching.
- Preserve missing stored values; reports may display `Unknown`.

### 10.5 `dim_date`

- Grain/business key: one non-null `relative_day`.
- Fields: `date_key`, `relative_day`, `is_before_presentation` and
  documented optional `relative_week`/`timing_group` fields, plus audit fields.
- Cover assessment deadlines, submission days, interaction days and registration/
  unregistration days from Silver.
- Day 0 means presentation start; negative days are valid.
- Unknown dates stay NULL and must not be replaced by day 0.
- Do not generate calendar dates/month names without actual supplied start dates.

---

## 11. Fact and Reporting Specifications

### 11.1 `fact_assessments`

Purpose: support assessment-performance analysis.

Business key: `id_assessment + id_student`.

Start from `student_assessment_clean`; resolve assessment context by
`id_assessment`, then enrollment context by all three enrollment-key columns.

Planned fields include:

- `id_assessment`, `id_student`, `code_module`, `code_presentation`
- `student_key`, `course_key`, `presentation_key`, `demographics_key`
- `date_key` for the submission day and the original `date_submitted`
- `assessment_type`, assessment relative date and assessment weight
- `score`, `is_banked` and audit fields

Preserve all 173 missing TMA scores as NULL. Unknown Exam deadlines stay NULL.
If implementing weighted scores or lateness, document the formula, missing-input
behavior and treatment of banked results. Do not mix assessment weights into an
undocumented overall grade.

Expected current-batch rows: 173,912.

### 11.2 `fact_vle_interactions`

Purpose: support engagement and resource-activity analysis.

Business key: `code_module + code_presentation + id_student + id_site + date`.

Start from the already aggregated `student_vle_clean`. Join resources on the
complete module-presentation-resource key and demographics through the complete
student enrollment key.

Planned fields include:

- The five business-key columns
- `student_key`, `course_key`, `presentation_key`, `demographics_key`
- `date_key` for the interaction day
- `activity_type`, optional resource availability weeks
- `sum_click` and audit fields

Dimension joins must not multiply daily rows or click totals.

Expected current-batch rows: 8,459,320.

### 11.3 `vw_student_outcomes`

Purpose: support cohort, dropout and enrollment-level reporting.

Business key: `code_module + code_presentation + id_student`.

Materialize this dbt model as a view.

1. Start with the complete `student_info_clean` enrollment population.
2. LEFT JOIN registration on the full enrollment key.
3. Include dimension keys, `final_result`, `studied_credits`,
   `num_of_prev_attempts`, `date_registration` and `date_unregistration`.
4. Derive `is_withdrawn` from `final_result = 'Withdrawn'`.
5. Aggregate each fact separately to enrollment grain before joining summaries.
6. Include counts/average scores and clicks/active-day measures with explicit
   definitions and denominators.
7. Keep zero-activity enrollments. Use zero for absent activity counts/totals,
   but keep unknown dates and unavailable average scores NULL.

Never join the two detailed facts directly; multiple rows on both sides can
multiply scores, clicks and enrollment counts.

Expected current-batch rows: 32,593, including 10,156 Withdrawn enrollments.

---

## 12. Mart Validation Requirements

Validate:

- Unique, non-null dimension keys and complete fact business keys
- Correct key coverage, foreign keys and module-presentation context
- Nullable optional dates/scores handled according to the assumptions
- No row multiplication from dimension or reporting joins
- Audit fields, numeric measures and source-to-target reconciliation
- Repeat loads that do not inflate business-row counts or measures

| Model | Expected current-batch rows |
| --- | ---: |
| `fact_assessments` | 173,912 |
| `fact_vle_interactions` | 8,459,320 |
| `vw_student_outcomes` (view) | 32,593 |

Assessment keys, scored/missing counts and score totals must reconcile with
Silver. VLE daily keys and click totals must reconcile with Silver and typed
Bronze totals. Enrollment outcomes/withdrawals must reconcile with
`student_info_clean`.

Use model YAML for documentation and reusable dbt data tests. Files in
`dbt/tests/` are singular tests returning failing rows only. Manual validation
SQL stays in `tests/03_gold_checks/` and `tests/04_business_checks/`; a result
display alone does not automatically fail a pipeline.

---

## 13. Recommended Build Order

1. Build `courses_clean` and `assessment_clean`.
2. Build `student_assessment_clean`, `student_info_clean` and
   `student_registration_clean`.
3. Build `vle_clean` and aggregate `student_vle_clean`.
4. Run the Silver validation and reconciliation checks.
5. Configure dbt connection settings and declare all seven Silver sources.
6. Build `dim_course`, `dim_module_presentation`, `dim_student`,
   `dim_demographics` and `dim_date` in dependency order.
7. Build `fact_assessments` and `fact_vle_interactions`.
8. Build `vw_student_outcomes` using separate fact summaries.
9. Run dbt tests and Gold reconciliation checks.
10. Implement analytics, business checks and Metabase dashboards.
11. Create the ERD and complete the project README.
12. Configure and validate orchestration and CI/CD when the relevant steps work.

dbt `ref()` dependencies define the model build order. Unfinished model/test
SQL currently keeps `enabled=false`; remove it as each model/test becomes
ready. A successful parse of disabled guides is not a completed pipeline.

---

## 14. Analytics Plan

The Mart layer should support the following questions:

### Dropout analysis

* Which module presentations have the highest withdrawal rates?
* How do demographics influence student withdrawal?
* When do students commonly withdraw?
* Do previous attempts affect withdrawal risk?
* Does the number of studied credits relate to withdrawal?

### Assessment analysis

* What are the average scores by module and presentation?
* Which assessment types have the highest and lowest scores?
* How many students receive a passing score?
* How do late submissions affect student performance?
* How do banked assessments affect results?

### VLE engagement analysis

* Which VLE resource types receive the most clicks?
* Which module presentations have the highest engagement?
* How does engagement change over relative time?
* Which students have low or declining engagement?
* How does engagement relate to assessment performance?
* Do Withdrawn students interact less with the VLE?

---

## 15. Incremental Loading Plan

The current source delivery is treated as the initial batch.

The final incremental implementation will depend on:

* New batch folder structure
* File naming convention
* Delivery frequency
* Whether files contain new or updated records
* Whether previously delivered records can change

When a new batch is provided:

* Raw ingestion should load only newly delivered files.
* Raw tables should preserve source-file and ingestion metadata.
* Clean tables should use documented business keys.
* Changed records may be processed with Delta `MERGE`.
* Append-only files may be ingested using `COPY INTO`.
* Student VLE records must be aggregated before merging into Clean.
* Reprocessing the same batch must not create duplicate Clean or Mart rows.
* Incremental row counts and aggregate totals must be validated.

Placeholder batch paths must not be included in runnable SQL files.

---

## 16. Repository File Plan

Transformation responsibilities:

- `src/sql/00_setup/`: catalog/schema initialization and source inspection
- `src/sql/01_raw/`: seven source-preserving Bronze ingestion scripts
- `src/sql/02_clean/`: seven Silver transformations
- `dbt/models/sources/silver_sources.yml`: the seven existing Silver inputs
- `dbt/models/dimensions/`: the five required dimensions and their YAML
- `dbt/models/facts/`: the two required facts and their YAML
- `dbt/models/reporting/`: the outcomes view and its YAML
- `src/sql/03_analytics/`: four read-only queries for Metabase

Validation responsibilities:

- `tests/01_source_checks/`: source/Bronze profiling
- `tests/02_clean_checks/`: Silver checks, including Bronze-to-Silver reconciliation
- `tests/03_gold_checks/`: manual Gold checks
- `tests/04_business_checks/`: analytics metric validation
- `dbt/tests/`: automated singular tests returning failing rows

The existing filename `dbt/tests/assessment_click_reconciliation.sql` refers
to assessment result/score reconciliation. It does not compare VLE clicks;
those belong in `vle_click_reconciliation.sql`.

Each unfinished file contains its purpose, inputs, intended output, steps to
implement and completion criteria. Assigned members should replace the guide
with code, retaining useful purpose/grain comments. Baseline counts describe
the current source delivery and must be reviewed for a new batch.

### Source-name validation

The seven live Bronze tables and their committed SQL references have been
verified and aligned:

- `assessment_raw`
- `courses_raw`
- `student_assessment_raw`
- `student_info_raw`
- `student_registration_raw`
- `student_vle_raw`
- `vle_raw`

All seven Bronze row counts reconcile with the current source delivery. Bronze
data was preserved; no substitute tables were created and no reload was
required.

---

## 17. Git and Pull Request Rules

Each group member must:

1. Pull the latest `main` branch.
2. Create a separate feature branch.
3. Work only on assigned files.
4. Add or update the related validation tests.
5. Run the SQL successfully in Databricks.
6. Record the expected and actual row counts.
7. Update documentation when a transformation rule changes.
8. Push the feature branch.
9. Open a pull request into `main`.
10. Request review before merging.

### Choosing a branch for an assigned task

Every file now shows a **Suggested branch** near the top. For the source-inspection
notebook, it is in the first Markdown cell. These are naming suggestions for future
work; adding the labels does not create the branches.

Use one branch for one task and keep its related SQL, YAML, tests and documentation
together. Files with the same suggested name can be worked on in that task branch;
you do not need to create another branch for each file.

| Task | Suggested branch |
| --- | --- |
| Clean assessment definitions and student results | `feature/clean-assessments` |
| Clean student information and registration | `feature/clean-students` |
| Clean VLE resources and daily interactions | `feature/clean-vle` |
| Build the five dimensions and their documentation | `feature/build-dimensions` |
| Build the assessment fact and its dbt tests | `feature/build-assessment-mart` |
| Build the VLE fact and its dbt tests | `feature/build-vle-mart` |
| Build the enrollment reporting view | `feature/build-student-outcomes` |
| Implement cohort analytics and its business checks | `feature/cohort-analysis` |

The other files carry their corresponding names directly in their headers.
For shared files such as `facts.yml`, update the relevant model entry on the same
branch as that model. General quality-check files have a suggested branch for a
standalone validation task; checks accompanying a transformation belong on that
transformation's branch.

Example: start an assessment-cleaning task from the latest `main`:

```bash
git switch main
git pull --ff-only origin main
git switch -c feature/clean-assessments
```

If that task branch already exists locally, switch to it instead of creating it
again. If two members work independently in the same area, use distinct names,
such as `feature/clean-assessments-rhea`, so their separate work does not share a
remote branch accidentally.

After implementing and validating the assigned work, commit it, push the task
branch, and open a pull request into `main` following the steps above.

Do not commit:

* Source CSV files
* Databricks credentials
* Access tokens
* Generated datasets
* Temporary query outputs
* Unfinished incremental paths

---

## 18. Definition of Done

A task is complete when:

* The SQL runs successfully.
* The expected table is created.
* Column names and data types are correct.
* Candidate keys are complete and unique at the intended grain.
* Expected missing values are handled according to `assumptions.md`.
* Source placeholders are no longer present in Clean.
* Row counts are validated.
* Parent-child relationships are valid.
* Audit columns are included.
* The related validation SQL is included.
* Documentation is updated when required.
* A pull request has been reviewed and approved.

---

## 19. Change Management

This plan must be reviewed when:

* A new source batch is delivered.
* The source schema changes.
* Business definitions are clarified.
* New data-quality issues are discovered.
* A transformation produces unexpected results.
* The fact-table grain changes.
* The team approves a different incremental-loading strategy.

Any change to table grain, candidate keys, or business rules must also be reflected in:

* `docs/source_assessment.md`
* `docs/assumptions.md`
* Clean validation tests
* Mart validation tests
* Project README
