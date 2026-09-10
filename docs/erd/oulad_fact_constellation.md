# OULAD fact-constellation diagram instructions

The diagram must show exactly five shared dimensions:

- `dim_student`
- `dim_course`
- `dim_module_presentation`
- `dim_date`
- `dim_demographics`

It must show exactly two fact tables:

- `fact_student_enrollment`, at one row per student and module presentation
- `fact_vle_interactions`, at one row per student, module presentation, VLE resource and relative day

Show each primary key, foreign key, measure and one-to-many relationship. Keep both dimensions directly connected to the facts; do not connect `dim_course` to `dim_module_presentation`.

Label `vw_student_outcomes` as a supporting reporting view if it is shown. It is not a third fact. Assessment results are summarized inside the enrollment fact, while detailed assessment records remain in Silver.

OULAD dates are relative days. Negative values are valid, day 0 is presentation start, and the Unknown date row represents missing dates without inventing a relative day.

Save the final image as `oulad_fact_constellation.png` and keep the editable DBML source when available.
