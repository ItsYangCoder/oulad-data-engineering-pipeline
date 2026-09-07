# OULAD Source Assessment

## 1. Project Overview

The Open University Learning Analytics Dataset (OULAD) contains anonymized information about students, module registrations, assessments, academic results, and Virtual Learning Environment (VLE) interactions.

The project follows this pipeline:

```text
Source CSV → Raw → Clean → Mart → Analytics → Dashboard
```

The main business questions are:

1. How do student demographics influence dropout?
2. How does VLE engagement affect student performance?

---

## 2. Source Location

The original files are stored in this Databricks Volume:

```text
/Volumes/open_university/oulad_bronze/ftw-b12/shared/week07/
```

The source CSV files will remain in the Databricks Volume and will not be uploaded to GitHub.

---

## 3. Source Files and Row Counts

| Source file | Row count | Description |
|---|---:|---|
| `assessments.csv` | 206 | Assessment definitions, types, dates, and weights |
| `courses.csv` | 22 | Module presentations and their duration |
| `studentAssessment.csv` | 173,912 | Student assessment submissions and scores |
| `studentInfo.csv` | 32,593 | Student demographics and final results |
| `studentRegistration.csv` | 32,593 | Student registration and withdrawal information |
| `studentVle.csv` | 10,655,280 | Daily student interactions with VLE resources |
| `vle.csv` | 6,364 | VLE resources and activity types |

The row-count results were saved in:

```text
open_university.oulad_quality.source_row_count_audit
```

The audit table contains:

- `LoadDate`
- `source_file`
- `row_count`
- `EntryTime`

---

## 4. Expected Grain and Candidate Keys

The following grains and keys are initial candidates. They must be confirmed using SQL validation.

| Source table | Expected grain | Candidate key |
|---|---|---|
| `courses` | One module presentation | `code_module`, `code_presentation` |
| `assessments` | One assessment | `id_assessment` |
| `studentInfo` | One student in one module presentation | `code_module`, `code_presentation`, `id_student` |
| `studentRegistration` | One registration in one module presentation | `code_module`, `code_presentation`, `id_student` |
| `studentAssessment` | One student result for one assessment | `id_assessment`, `id_student` |
| `vle` | One VLE resource in one module presentation | `code_module`, `code_presentation`, `id_site` |
| `studentVle` | One student-resource interaction on one relative day | `code_module`, `code_presentation`, `id_student`, `id_site`, `date` |

### Validation status

| Source table | Key tested? | Duplicate count | Null-key count | Status |
|---|---|---:|---:|---|
| `courses` | No | To be checked | To be checked | Pending |
| `assessments` | No | To be checked | To be checked | Pending |
| `studentInfo` | Yes | 0 | 1,111 in imd_band | Flag |
| `studentRegistration` | No | To be checked | To be checked | Pending |
| `studentAssessment` | No | To be checked | To be checked | Pending |
| `vle` | Yes | 0 | 5,243 | Review depending on business context |
| `studentVle` | No | To be checked | To be checked | Pending |

---

## 5. Expected Source Relationships

| Child table | Parent table | Join columns | Status |
|---|---|---|---|
| `assessments` | `courses` | `code_module`, `code_presentation` | Pending |
| `studentInfo` | `courses` | `code_module`, `code_presentation` | Pending |
| `studentRegistration` | `studentInfo` | `code_module`, `code_presentation`, `id_student` | Pending |
| `studentAssessment` | `assessments` | `id_assessment` | Pending |
| `vle` | `courses` | `code_module`, `code_presentation` | Pending |
| `studentVle` | `studentInfo` | `code_module`, `code_presentation`, `id_student` | Pending |
| `studentVle` | `vle` | `code_module`, `code_presentation`, `id_site` | Pending |

These relationships must be tested for unmatched records before building the Mart layer.

---

## 6. Important Date Interpretation

Several date columns contain the number of days relative to the official start of a module presentation.

These columns include:

- `date_registration`
- `date_unregistration`
- `date_submitted`
- Assessment `date`
- Student VLE `date`

Important rules:

- Negative values can be valid.
- Day `0` represents the official module start.
- Positive values represent days after the module starts.
- Negative values must not automatically be treated as errors.
- Relative-day values must not be directly cast to a normal SQL `DATE`.

---

## 7. Initial Data-Quality Risks

The following possible issues must be investigated:

1. Duplicate candidate keys
2. Missing student or module identifiers
3. Missing `imd_band` values
4. Missing assessment dates
5. Missing assessment scores
6. Null `date_unregistration` values
7. Scores outside the expected range of 0 to 100
8. Negative VLE click counts
9. Unmatched student registrations
10. Unmatched assessment results
11. Unmatched VLE interactions
12. Join multiplication caused by incomplete composite-key joins

A null value must be investigated before it is removed or replaced.

---

## 8. Confirmed Issues

Update this section after completing source profiling.

| Issue ID | Source table | Column or key | Finding | Valid or invalid? | Planned treatment |
|---|---|---|---|---|---|
| ISSUE-001 | vle_bronze, student_registration_bronze | code_module | Modules have multiple presentations (e.g., BBB occurs 4 times). Joining solely on module code causes row multiplication. | Valid | Enforce strictly composite-key joins using both code_module and code_presentation in the Mart layer. |
| ISSUE-002 | student_registration_bronze | date_unregistration | Missing unregistration dates are stored as the string character ? instead of a system NULL. | Invalid Format | Replace the literal ? with a true SQL NULL and cast the column to an integer or date type |
| ISSUE-003 | To be added | To be added | To be added | To be determined | To be determined |

### Notes

- Add one row for every confirmed issue.
- Do not classify a value as invalid without checking its business meaning.
- Record valid nulls even if they do not require cleaning.
- Document the reason for every cleaning decision.

---

## 9. Large-File Consideration

`studentVle.csv` contains 10,655,280 rows and is the largest source table.

Processing rules:

- Load it into a Raw Delta table.
- Use the Raw Delta table for later transformations.
- Avoid repeatedly scanning the original CSV.
- Avoid displaying the entire dataset.
- Use `LIMIT` only for source previews.
- Do not upload the CSV file to GitHub.

---

## 10. Proposed Mart Tables

### Fact tables

| Mart table | Proposed grain |
|---|---|
| `fact_assessments` | One student result for one assessment |
| `fact_vle_interactions` | One student interaction with one VLE resource on one relative day |

### Dimension tables

| Mart table | Proposed grain |
|---|---|
| `dim_student` | One row per student |
| `dim_course` | One row per module |
| `dim_module_presentation` | One row per module presentation |
| `dim_date` | One row per reporting date or relative module day |
| `dim_demographics` | One row per selected demographic profile or category |

The final grains and keys will be approved after source validation.

---

## 11. Source Profiling Checklist

### Structure checks

- [ ] Confirm the column names of every source
- [ ] Confirm the inferred data types
- [ ] Confirm the expected grain
- [ ] Test candidate-key uniqueness

### Data-quality checks

- [ ] Count missing required values
- [ ] Inspect categorical values
- [ ] Check assessment-score ranges
- [ ] Check VLE click ranges
- [ ] Check relative-date ranges
- [ ] Identify valid and invalid null values

### Relationship checks

- [ ] Confirm assessments match courses
- [ ] Confirm student information matches courses
- [ ] Confirm registrations match student information
- [ ] Confirm student assessments match assessment definitions
- [ ] Confirm VLE resources match courses
- [ ] Confirm student VLE interactions match students
- [ ] Confirm student VLE interactions match VLE resources

---

## 12. Validation Findings

Update this section after running the profiling queries.

### Column and data-type findings

```text
Pending source profiling.
```

### Duplicate findings

```text
Pending source profiling.
```

### Null findings

```text
Pending source profiling.
```

### Numeric-range findings

```text
Pending source profiling.
```

### Relationship findings

```text
Pending source profiling.
```

---

## 13. Assumptions

1. The delivered CSV files represent the complete initial source batch.
2. Source files will remain unchanged after ingestion.
3. Negative relative dates can represent activity before the official module start.
4. A null `date_unregistration` may mean that the student did not withdraw.
5. Candidate keys are not considered confirmed until uniqueness tests pass.
6. Missing values will not be removed or replaced without a documented rule.
7. The large `studentVle` source will be processed through a Delta table after Raw ingestion.

---

## 14. Next Step

The next activity is source profiling.

Source profiling will validate:

1. Column names and data types
2. Candidate keys
3. Duplicate records
4. Missing values
5. Categorical values
6. Numeric ranges
7. Relative-date ranges
8. Parent-child relationships

After profiling, this document will be updated with the confirmed findings before the Clean and Mart layers are finalized.
