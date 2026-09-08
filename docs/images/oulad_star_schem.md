# OULAD star-schema image instructions

**Suggested branch:** `docs/create-star-schema`

Purpose: Explain what the assigned diagram author should draw and save in this folder.

Status: The diagram has not been created. This Markdown file is an instruction note, not an image.

What to put in the finished diagram:

- Exactly five dimensions: `dim_student`, `dim_course`, `dim_module_presentation`, `dim_date` and `dim_demographics`.
- Exactly two facts: `fact_assessments` and `fact_vle_interactions`.
- Primary keys, foreign keys, measures and a short grain description in each table.
- Relationships that match the implemented key columns, with readable one-to-many cardinality.
- A note that `dim_date` contains relative days, including negative days; it does not supply invented calendar dates.
- If showing `vw_student_outcomes`, label it clearly as a supporting enrollment-level reporting view.

Use the agreed model in [pipeline_plan.md](../pipeline_plan.md). Confirm the actual columns with the model authors before drawing the final relationships. Keep assessment and VLE resource context inside their facts; the agreed design does not require separate assessment/resource dimensions or an enrollment fact.

Save the actual diagram as `oulad_star_schema.png` in this folder. Keep an editable diagram source if available, and document the grains/key mapping in `docs/star_schema.md` when that document is created. Do not rename Markdown text to a PNG extension.

Done when: table names and key links match the dbt models, text is readable without overlap, and the final image is linked from the project documentation.
