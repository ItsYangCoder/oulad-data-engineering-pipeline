# OULAD Data Engineering Pipeline Plan

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

The Mart layer will contain dimensions and fact tables for analytics.

### Dimensions

| Mart table                | Grain                                            | Main source                |
| ------------------------- | ------------------------------------------------ | -------------------------- |
| `dim_course`              | One row per module                               | `courses_clean`            |
| `dim_module_presentation` | One row per module presentation                  | `courses_clean`            |
| `dim_student`             | One row per student                              | `student_info_clean`       |
| `dim_demographics`        | One row per distinct demographic profile         | `student_info_clean`       |
| `dim_assessment`          | One row per assessment                           | `assessment_clean`         |
| `dim_vle_resource`        | One row per VLE resource and module presentation | `vle_clean`                |
| `dim_relative_day`        | One row per relative day                         | Clean relative-date fields |

### Facts

| Mart table                | Grain                                             | Main source                               |
| ------------------------- | ------------------------------------------------- | ----------------------------------------- |
| `fact_student_enrollment` | One student enrolled in one module presentation   | Student information and registration      |
| `fact_assessments`        | One student result for one assessment             | Student assessment and assessment context |
| `fact_vle_interactions`   | One student-resource interaction per relative day | Clean student VLE interactions            |

---

## 10. Dimension Specifications

## 10.1 `dim_course`

**Grain:** One row per module.

**Possible fields:**

* `course_key`
* `code_module`
* Mart audit columns

The natural course key is `code_module`.

---

## 10.2 `dim_module_presentation`

**Grain:** One row per module presentation.

**Possible fields:**

* `presentation_key`
* `course_key`
* `code_module`
* `code_presentation`
* `module_presentation_length`
* Mart audit columns

The business key is:

* `code_module`
* `code_presentation`

---

## 10.3 `dim_student`

**Grain:** One row per student.

**Possible fields:**

* `student_key`
* `id_student`
* Mart audit columns

Presentation-dependent attributes such as `final_result`, `studied_credits`, and `num_of_prev_attempts` must not be stored as permanent student attributes. They belong in `fact_student_enrollment`.

---

## 10.4 `dim_demographics`

**Grain:** One row per distinct demographic profile.

**Possible fields:**

* `demographics_key`
* `gender`
* `region`
* `highest_education`
* `imd_band`
* `age_band`
* `disability`
* Mart audit columns

A missing `imd_band` may be displayed as `Unknown` for reporting, but the Clean-layer value must remain NULL.

---

## 10.5 `dim_assessment`

**Grain:** One row per assessment.

**Possible fields:**

* `assessment_key`
* `id_assessment`
* `presentation_key`
* `assessment_type`
* `assessment_relative_day`
* `assessment_weight`
* Mart audit columns

---

## 10.6 `dim_vle_resource`

**Grain:** One VLE resource in one module presentation.

**Possible fields:**

* `vle_resource_key`
* `id_site`
* `presentation_key`
* `activity_type`
* `week_from`
* `week_to`
* Mart audit columns

---

## 10.7 `dim_relative_day`

**Grain:** One row per relative day.

**Possible fields:**

* `relative_day_key`
* `relative_day`
* `relative_week`
* `timing_group`
* `is_before_presentation`
* Mart audit columns

Possible timing groups include:

* Before presentation
* Week 1 to Week 4
* Week 5 to Week 8
* Week 9 onward

OULAD date values represent days relative to the start of a module presentation. They must not be converted into calendar dates unless actual presentation start dates are provided.

---

## 11. Fact Table Specifications

## 11.1 `fact_student_enrollment`

**Purpose:** Support dropout, completion, and demographic analysis.

**Grain:** One student enrolled in one module presentation.

**Business key:**

* `code_module`
* `code_presentation`
* `id_student`

**Possible fields:**

* `student_key`
* `course_key`
* `presentation_key`
* `demographics_key`
* `date_registration`
* `date_unregistration`
* `num_of_prev_attempts`
* `studied_credits`
* `final_result`
* `is_withdrawn`
* Mart audit columns

The `is_withdrawn` field will be based on:

**`final_result = 'Withdrawn'`**

The expected row count is 32,593, provided that the Clean student-information and registration tables remain one-to-one.

---

## 11.2 `fact_assessments`

**Purpose:** Support assessment-performance analysis.

**Grain:** One student result for one assessment.

**Business key:**

* `id_assessment`
* `id_student`

**Possible fields:**

* `student_key`
* `assessment_key`
* `course_key`
* `presentation_key`
* `demographics_key`
* `submission_relative_day`
* `score`
* `is_banked`
* `assessment_weight`
* `weighted_score`
* Mart audit columns

A missing score must remain NULL. It must not be treated as zero unless a future business requirement explicitly requires it.

The expected fact count is 173,912.

---

## 11.3 `fact_vle_interactions`

**Purpose:** Support engagement and VLE activity analysis.

**Grain:** One student interacting with one VLE resource during one module presentation on one relative date.

**Business key:**

* `code_module`
* `code_presentation`
* `id_student`
* `id_site`
* `date`

**Possible fields:**

* `student_key`
* `course_key`
* `presentation_key`
* `demographics_key`
* `vle_resource_key`
* `relative_day_key`
* `sum_click`
* Mart audit columns

The expected fact count is 8,459,320.

The total `sum_click` must match the total from the Bronze source after valid type conversion.

---

## 12. Mart Validation Requirements

Every Mart model must be tested for:

* Unique dimension keys
* Unique fact business keys
* Missing foreign keys
* Orphan fact records
* Invalid measures
* Missing audit columns
* Fact-to-Clean row reconciliation
* Aggregate reconciliation

Expected fact counts:

| Fact table                | Expected rows |
| ------------------------- | ------------: |
| `fact_student_enrollment` |        32,593 |
| `fact_assessments`        |       173,912 |
| `fact_vle_interactions`   |     8,459,320 |

Important aggregate checks:

* Total assessment records must reconcile with `student_assessment_clean`.
* Total VLE clicks must reconcile with `student_vle_raw`.
* Enrollment outcomes must reconcile with `student_info_clean`.
* Withdrawal counts must reconcile with `final_result = 'Withdrawn'`.

---

## 13. Recommended Build Order

The implementation should follow this order:

1. Build `courses_clean`.
2. Build `assessment_clean`.
3. Build `student_assessment_clean`.
4. Build `student_info_clean`.
5. Build `student_registration_clean`.
6. Build `vle_clean`.
7. Build `student_vle_clean`.
8. Run all Clean validation tests.
9. Build `dim_course`.
10. Build `dim_module_presentation`.
11. Build `dim_student`.
12. Build `dim_demographics`.
13. Build `dim_assessment`.
14. Build `dim_vle_resource`.
15. Build `dim_relative_day`.
16. Build `fact_student_enrollment`.
17. Build `fact_assessments`.
18. Build `fact_vle_interactions`.
19. Run all Mart validation tests.
20. Build the analytics queries.
21. Create the ERD.
22. Complete the project README.
23. Configure the Databricks job.
24. Add CI/CD validation when the pipeline scripts are stable.

Dimensions must be created before fact tables that reference them.

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

Recommended Clean files:

* `src/sql/02_clean/courses_clean.sql`
* `src/sql/02_clean/assessment_clean.sql`
* `src/sql/02_clean/student_assessment_clean.sql`
* `src/sql/02_clean/student_info_clean.sql`
* `src/sql/02_clean/student_registration_clean.sql`
* `src/sql/02_clean/vle_clean.sql`
* `src/sql/02_clean/student_vle_clean.sql`

Recommended Mart files:

* `src/sql/03_mart/dim_course.sql`
* `src/sql/03_mart/dim_module_presentation.sql`
* `src/sql/03_mart/dim_student.sql`
* `src/sql/03_mart/dim_demographics.sql`
* `src/sql/03_mart/dim_assessment.sql`
* `src/sql/03_mart/dim_vle_resource.sql`
* `src/sql/03_mart/dim_relative_day.sql`
* `src/sql/03_mart/fact_student_enrollment.sql`
* `src/sql/03_mart/fact_assessments.sql`
* `src/sql/03_mart/fact_vle_interactions.sql`

Recommended test areas:

* `tests/02_clean_checks`
* `tests/03_mart_checks`
* `tests/04_business_checks`

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

Suggested branch names:

* `feature/clean-assessments`
* `feature/clean-students`
* `feature/clean-vle`
* `feature/build-assessment-mart`
* `feature/build-vle-mart`
* `feature/add-quality-tests`
* `docs/update-project-documentation`

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
