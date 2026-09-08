## Source Profiling Results

**Suggested branch:** `docs/update-source-assessment`

### Assessment Dates

The `assessment_raw` table contains 11 missing assessment dates.

| Assessment type | Total rows | Missing dates |
|---|---:|---:|
| CMA | 76 | 0 |
| Exam | 24 | 11 |
| TMA | 106 | 0 |

All missing assessment dates belong to Exam records. These values will
remain NULL in the Clean layer because no reliable deadline is available.
They will not be guessed or imputed.

### Student Assessment Scores

The `student_assessment_raw` table contains 173 missing scores.

| Assessment type | Total results | Missing scores |
|---|---:|---:|
| CMA | 70,527 | 0 |
| Exam | 4,959 | 0 |
| TMA | 98,426 | 173 |

All missing scores belong to TMA assessments.

Clean-layer treatment:

- Convert source placeholders to NULL.
- Do not replace missing scores with zero.
- Exclude NULL scores from average-score calculations.
- Keep the records for submission and participation analysis.

### Registration Dates

| Final result | Students | Missing registration date | Missing unregistration date |
|---|---:|---:|---:|
| Distinction | 3,024 | 0 | 3,024 |
| Fail | 7,052 | 5 | 7,043 |
| Pass | 12,361 | 1 | 12,361 |
| Withdrawn | 10,156 | 39 | 93 |

A missing `date_unregistration` is expected for students who completed
the module without withdrawing.

Confirmed exceptions:

- 45 records have no registration date.
- 93 Withdrawn records have no unregistration date.
- 9 Fail records have a recorded unregistration date.

Clean-layer treatment:

- Convert source placeholders to NULL.
- Preserve students with missing dates.
- Use `final_result = 'Withdrawn'` as the primary dropout indicator.
- Use `date_unregistration` only when the date is available.
- Do not invent missing registration or withdrawal dates.

### VLE Availability Weeks

The `vle_raw` table contains 5,243 records where both `week_from` and
`week_to` are missing.

| Check | Rows |
|---|---:|
| Both week fields missing | 5,243 |
| Only `week_from` missing | 0 |
| Only `week_to` missing | 0 |

The two fields are consistently missing together. This indicates that
the source does not specify a limited availability period for those VLE
resources.

Both fields will be converted to NULL in the Clean layer.

### Repeated Student VLE Daily Keys

The `student_vle_raw` table contains:

| Metric | Rows |
|---|---:|
| Source rows | 10,655,280 |
| Unique daily interaction keys | 8,459,320 |
| Repeated key groups | 1,614,505 |
| Repeated or excess key rows | 2,195,960 |

The candidate key is:

- `code_module`
- `code_presentation`
- `id_student`
- `id_site`
- `date`

Bronze retains every source row. The Clean layer will group records
using this candidate key and calculate:

`SUM(sum_click)`

The expected Clean output is 8,459,320 daily interaction rows.

### Relationship Validation

All tested source relationships returned zero orphan records.

| Relationship | Orphan rows | Status |
|---|---:|---|
| Student assessment to assessment | 0 | PASS |
| Student information to course | 0 | PASS |
| Student registration to student information | 0 | PASS |
| VLE resource to course | 0 | PASS |
| Student VLE interaction to VLE resource | 0 | PASS |
| Student VLE interaction to student information | 0 | PASS |

The source tables can be safely connected using their documented
candidate and composite keys.