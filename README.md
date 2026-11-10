# DBGI method system: final metadata table

This folder builds the **final metadata table of the DBGI samples**: one row per MS
file (mzML), where **every cell is a number**. A number is never explained in the
table itself: it is the `id` of a row in an associated table (a **sub-table** or a
**method table**), where the meaning is written once.

The output is produced in **two versions** of the same information. Both are plain,
relational CSV files, ready to be imported into Directus (one CSV = one collection,
one numeric column = one many-to-one relation). Which version goes to Directus is
still to be decided.

---

## Contents

```
dbgi_methods/
├── README.md                         this file
├── CURATION.md                       every manual choice and correction
├── src/
│   └── build_final_table.R           the script that builds the final table
├── 02_sampling/                      upstream: the scripts that produce input/sampling_metadata.csv
│   ├── 02_inst.r                     runs step 02
│   ├── 02_sampling_metadata.R        garden defaults + MZmine batches -> 1 row / MS file
│   ├── 02_sampling_correction.R      Directus (reference) + MassIVE + manual corrections
│   └── garden_defaults.R             per-garden protocol written by hand (with sources)
├── input/
│   ├── sampling_metadata.csv         the MS files (output of step 02, 12 columns used)
│   ├── sub_tables/                   67 sub-tables: the options of each parameter
│   ├── method_tables/                6 method tables: what each method code (I, S, D, E, L, P) means
│   └── config/
│       ├── dbgi_batches.csv          default method codes of each acquisition batch
│       └── final_table_columns.csv   the 86 columns of the final table, in order
└── output/
    ├── version_A_link_to_sub_tables/
    │   └── final_table.csv
    ├── version_B_link_to_method_codes/
    │   ├── final_table.csv
    │   └── method_tables/            the 6 method tables, written with sub-table ids
    └── unmatched.csv                 what could not be linked (to check)
```


`build_final_table.R` reads `02_sampling/output/sampling_metadata.csv` when it exists,
otherwise the extract shipped in `input/sampling_metadata.csv`.

## Vocabulary used in this README

| Term | Meaning |
|------|---------|
| **MS file** | one injection = one mzML file. A sample injected in positive and negative mode has two MS files. |
| **Sub-table** | the list of allowed options for **one parameter**, e.g. `preservation_method_sheet.csv`: 1 = liquid_N2, 2 = dry_ice, 3 = silica_gel… Columns: `id`, the option, `description`, `details`. Some sub-tables have extra columns (e.g. `instrument_model_sheet.csv`: vendor, mass analyser). |
| **Method table** | one table per protocol **step**. Each row is one complete method of that step, with a code: `I` identification, `S` sampling, `D` lab drying, `E` extraction, `L` LC-MS, `P` data processing. Example: `S3` = dry ice, aluminium foil, falcon tube 50 mL, transport on dry ice < 8 h, storage at -80 °C. |
| **Method code** | the id of a method-table row: `I1`, `S3`, `E4`, `L3`… |

---

## 1. Input

### 1.1 The MS files (output of step 02 of the pipeline)

`input/sampling_metadata.csv`: one row per MS file, produced by step 02 (scripts in
`02_sampling/`). To read another file, set `IN_CSV` before running the script. Step 02
merges the four sources of the DBGI metadata:

| Source | What it gives | How it enters |
|--------|---------------|---------------|
| **Directus** (reference: wins over every other source) | garden / QField project, collector, plant part, collection date, dry weight, extraction volume, **extraction method** | `directus_metadata.csv` export, read in `02_sampling_correction.R` |
| **`garden_defaults.R`** | what no database stores: preservation, transport, grinding, agitation, all LC-MS settings | written by hand per garden; values read in the instrument methods are commented with their source |
| **RAW / mzML files** | LC and MS settings of each instrument (gradient, source, DDA, resolution…) | read with MetaXtract / `extract_methods.py`, then written into `garden_defaults.R` |
| **MZmine batch files** (`.mzbatch`) | which batch processed each file, MZmine version and parameters | parsed in `02_sampling_metadata.R` |

Columns read by this script: `sample_id`, `mzml_filename`, `garden`, `batch_id`,
`instrument_model`, `extraction_method_id` (Directus code), `identification_method`,
`preservation_method`, `raw_conversion_tool`, `ionization_polarity`,
`collector_full_name`, `plant_part`.

The file shipped here keeps only the 12 columns used, taken from the complete DBGI
metadata export (4 361 MS files). Replace it with the full step 02 output to rebuild.

Step 02 itself (`02_sampling/`) needs, in the `kg-dataprep` folders (upstream of this folder:
`metadata_all_merged.csv` comes from step 00, `directus_metadata.csv` from the Directus
export script, which renames the Directus fields to `identified_by`, `dry_weight_mg`,
`extraction_method_id`…): `metadata_all_merged.csv`
(step 00), `massive_metadata_complete_set.tsv`, `directus_metadata.csv` and the `.mzbatch`
files. Its manual corrections (`GARDEN_FIX`,
`INSTRUMENT_FIX`, `EXTRACT_DONOR`, imputation…) are commented in
`02_sampling_correction.R`, and the hand-written protocol values in `garden_defaults.R`.

### 1.2 The sub-tables (`input/sub_tables/`)

67 CSV files, one per parameter, named `<parameter>_sheet.csv`. These are the
sheets of the DBGI Protocol Tables (HTML), exported unchanged. **To add an option,
add a row with the next free id. Never renumber or reuse an id**: the final table
stores only the ids.

Sub-tables and method tables are **maintained by hand** (no script produces them):
see `CURATION.md`.

### 1.3 The method tables (`input/method_tables/`)

| File | Codes | One row (or column) = |
|------|-------|-----------------------|
| `identification_methods.csv` | I1 | one identification method |
| `sampling_methods.csv` | S1–S3 | preservation + packaging + transport + storage |
| `drying_methods.csv` | D1–D2 | lab drying + delay before drying |
| `extraction_methods.csv` | E1–E5 | Directus extraction method + material state, grinding, solvent, agitation, centrifugation, storage |
| `lcms_methods.csv` | L1–L6 | one instrument method. **Stored the other way round**: one row per parameter, one column per method (`L1 · Synapt XS`, …) |
| `processing_methods.csv` | P1–P2 | raw conversion tool + processing software |

The method tables are written in words (as in the HTML). The script translates them into
sub-table ids for version B.

### 1.4 Configuration (`input/config/`)

- `dbgi_batches.csv`: for each acquisition batch (`JBN_synapt_2025`, `JBP_orbitrap_2026`,
  …), the 6 method codes its files carry by default.
- `final_table_columns.csv`: the 86 columns of the final table, their step, their
  sub-table, where the value comes from (`Directus`, `people`, `mzML/RAW file`) and
  their level (`core` = asked for every protocol, `optional`).

---

## 2. Process

Run (needs R and the `data.table` package):

```r
BASE_DIR <- "path/to/dbgi_methods"
# optional: IN_CSV <- "path/to/sampling_metadata.csv"   (default: input/sampling_metadata.csv)
source(file.path(BASE_DIR, "src/build_final_table.R"))
```

The script never stops on missing or unknown values: anything it cannot link is left
empty and listed in `output/unmatched.csv`.

### Step a. Give every MS file its 6 method codes

For each MS file, in this order (a later rule replaces an earlier one):

1. **Batch default.** The file takes the 6 codes of its `batch_id` in
   `dbgi_batches.csv`. Fribourg files acquired on the Q Exactive HF-X take the row
   `JBUF_hfx` (detected from `instrument_model`). A batch absent from
   `dbgi_batches.csv` takes the first batch of the same garden, and is reported.
2. **What the file itself says**, when it matches a method table:

   | Code | Matched on | Rule |
   |------|------------|------|
   | I | `identification_method` | same value in `identification_methods.csv` |
   | S | `preservation_method` | first sampling method with this preservation |
   | L | `instrument_model` | the LC-MS method of this instrument (vendor in brackets ignored) |
   | P | `raw_conversion_tool` | same tool in `processing_methods.csv` |
   | E | Directus `extraction_method_id` | **Directus is the reference.** Candidates = extraction methods whose `directus_extraction_method` starts with this Directus code. If the batch default is one of them it is kept (one Directus code can cover several DBGI methods, e.g. code 4 = E1 and E2); otherwise the first candidate is taken. |
   | D | — | not stored per file: always the batch default |

### Step b. Fill the 86 columns

For every column of `final_table_columns.csv`:

1. **Value.**
   - Steps 1 to 6: the value is read in the method table of the file's code for that
     step (e.g. `primary_packaging` of the file = `primary_packaging` of its S method).
     For LC-MS, the row of that parameter, column of the L code.
   - Step 0 (Directus): read from the file itself: `garden_id` ← garden,
     `collector` ← collector, `observation_subject` ← plant part,
     `extraction_method` ← the E code.
   - `ionization_polarity` is read from the file (positive and negative files share
     the same LC-MS method).
2. **Number.** The value is looked up in the column's sub-table: first in its
   option column, then in its other name columns (e.g. full name in
   `person_sheet.csv`). The cell receives the `id`. A value absent from the sub-table
   is left empty and reported. `extraction_method` keeps the E code.

Empty cell = the parameter does not apply to this method (e.g. RNAlater fields of a
liquid-nitrogen sample) or is not known yet.

### Step c. Write the two versions

**Version A — link to sub-tables.** The MS file carries the 86 numbers directly.

**Version B — link to method codes.** The MS file carries only what differs from
file to file (garden, collector, plant part, polarity, as sub-table ids) and its
6 method codes. The method tables are written again with every word replaced by its
sub-table id; measured values without a sub-table (flow rate 0.35, 14000 rpm…) stay
as they are.

---

## 3. Output

### Version A: `output/version_A_link_to_sub_tables/final_table.csv`

```
MS file ──(86 numbers)──> sub-tables
```

| Columns | Content |
|---------|---------|
| `sample_id`, `mzml_filename`, `garden` | identification of the MS file |
| 86 parameter columns | sub-table id (see the table at the end of this README) |

To read `preservation_method = 2`: open `input/sub_tables/preservation_method_sheet.csv`,
row `id = 2` → dry_ice.

- Directus: one collection per sub-table + one MS file collection with 86 many-to-one fields.
- **For:** everything visible in one table; easy to filter on any single parameter.
- **Against:** 86 relations; the same protocol is repeated on thousands of rows; a
  correction to a protocol has to be applied to every file.

### Version B: `output/version_B_link_to_method_codes/`

```
MS file ──(6 codes)──> method tables ──(numbers)──> sub-tables
```

| File | Content |
|------|---------|
| `final_table.csv` | `sample_id`, `mzml_filename`, `garden`, `garden_id`, `collector`, `observation_subject`, `ionization_polarity` (sub-table ids) + `identification_method_id`, `sampling_method_id`, `drying_method_id`, `extraction_method_id`, `lcms_method_id`, `processing_method_id` |
| `method_tables/*.csv` | the 6 method tables, one row per method code, every option written as its sub-table id. `lcms_methods.csv` is turned to one row per method. |

To read `sampling_method_id = S3`: open `method_tables/sampling_methods.csv`, row S3 →
`preservation_method = 2` → `preservation_method_sheet.csv`, row 2 → dry_ice.

- Directus: one collection per sub-table, one per method table, one MS file
  collection with 6 many-to-one fields (+ 4 per-file fields).
- **For:** a protocol is described once; a correction is made in one place; the 6
  codes are the natural query keys of the knowledge graph ("all files extracted with E4").
- **Against:** two hops to reach a value.

### `output/unmatched.csv`

One row per file and value that could not be linked: `sample_id`, `mzml_filename`,
`garden`, `what`, `value`. Current run: a Directus extraction code without DBGI
method (code 1, 2 Fribourg files) and a collector absent from `person_sheet.csv` (3 Kew files).

### Current run

Built on the complete DBGI metadata export: 4 361 MS files (JBN 829, JBC 101,
JBP 615, JBUF 2 297, JBK 519), 6 method tables, 67 sub-tables.

---

## Maintenance

| To… | Do |
|-----|----|
| add an option (e.g. a new solvent) | add a row with the next free id to its sub-table |
| add a method (new garden protocol, new instrument method) | add a row to the method table with the next free code (S4, L7…) |
| add a batch | add a row to `dbgi_batches.csv` with its 6 codes |
| add a column to the final table | add a row to `final_table_columns.csv`, and its sub-table if it has one |

Never renumber an id or a code: the final tables only store numbers.

---

## 4. Manual curation

All hand-written values, corrections and assumptions are listed in
[`CURATION.md`](CURATION.md): the hand-maintained tables, the protocol values of
`garden_defaults.R` with their reliability, every correction rule of step 02 and the
choices made by `build_final_table.R`.

---

## Appendix: the 86 columns

| Column | Step | Sub-table | Value comes from | Level |
|--------|------|-----------|------------------|-------|
| `garden_id` | 0. Directus | `garden_sheet.csv` | Directus | core |
| `collector` | 0. Directus | `person_sheet.csv` | Directus | core |
| `observation_subject` | 0. Directus | `observation_subject_sheet.csv` | Directus | core |
| `extraction_method` | 0. Directus | `extraction_methods_sheet.csv` | Directus | core |
| `identification_method` | 1. Identification | `identification_method_sheet.csv` | people | core |
| `preservation_method` | 2. Sampling | `preservation_method_sheet.csv` | people | core |
| `air_drying_place` | 2. Sampling | `air_drying_place_sheet.csv` | people | optional |
| `oven_type` | 2. Sampling | `oven_type_sheet.csv` | people | optional |
| `ethanol_liquid_use` | 2. Sampling | `ethanol_liquid_use_sheet.csv` | people | optional |
| `rnalater_removal` | 2. Sampling | `rnalater_removal_sheet.csv` | people | optional |
| `ethanol_tissue_disruption` | 2. Sampling | `field_disruption_sheet.csv` | people | optional |
| `rnalater_tissue_disruption` | 2. Sampling | `field_disruption_sheet.csv` | people | optional |
| `field_disruption` | 2. Sampling | `field_disruption_sheet.csv` | people | optional |
| `field_mass_method` | 2. Sampling | `field_mass_method_sheet.csv` | people | optional |
| `ethanol_container` | 2. Sampling | `field_extraction_tube_sheet.csv` | people | optional |
| `rnalater_container` | 2. Sampling | `field_extraction_tube_sheet.csv` | people | optional |
| `field_extraction_tube` | 2. Sampling | `field_extraction_tube_sheet.csv` | people | optional |
| `field_extract_postprocessing` | 2. Sampling | `field_extract_postprocessing_sheet.csv` | people | optional |
| `primary_packaging` | 2. Sampling | `primary_packaging_sheet.csv` | people | core |
| `secondary_packaging` | 2. Sampling | `secondary_packaging_sheet.csv` | people | optional |
| `field_extract_temperature` | 2. Sampling | `transport_temperature_sheet.csv` | people | optional |
| `transport_temperature` | 2. Sampling | `transport_temperature_sheet.csv` | people | core |
| `transport_duration` | 2. Sampling | `transport_duration_sheet.csv` | people | core |
| `ethanol_storage_temperature` | 2. Sampling | `storage_temperature_sheet.csv` | people | optional |
| `rnalater_storage_temperature` | 2. Sampling | `storage_temperature_sheet.csv` | people | optional |
| `dried_storage_temperature` | 2. Sampling | `storage_temperature_sheet.csv` | people | optional |
| `storage_temperature` | 2. Sampling | `storage_temperature_sheet.csv` | people | core |
| `storage_container` | 2. Sampling | `storage_container_sheet.csv` | people | optional |
| `lab_drying` | 3. Lab drying | `lab_drying_sheet.csv` | people | core |
| `time_before_drying` | 3. Lab drying | `time_before_drying_sheet.csv` | people | core |
| `material_state` | 4. Extraction | `material_state_sheet.csv` | people | core |
| `grinding_device` | 4. Extraction | `grinding_device_sheet.csv` | people | core |
| `bead_homog_device` | 4. Extraction | `grinding_device_sheet.csv` | people | optional |
| `field_beads` | 4. Extraction | `grinding_beads_sheet.csv` | people | optional |
| `grinding_beads` | 4. Extraction | `grinding_beads_sheet.csv` | people | optional |
| `grinding_precooling` | 4. Extraction | `grinding_precooling_sheet.csv` | people | optional |
| `field_extraction_solvent` | 4. Extraction | `extraction_solvent_sheet.csv` | people | optional |
| `extraction_solvent` | 4. Extraction | `extraction_solvent_sheet.csv` | Directus (Extraction_Methods, name only) | core |
| `extraction_agitation` | 4. Extraction | `extraction_agitation_sheet.csv` | people | core |
| `shaker_type` | 4. Extraction | `shaker_type_sheet.csv` | people | optional |
| `sonication_type` | 4. Extraction | `sonication_type_sheet.csv` | people | optional |
| `filtration` | 4. Extraction | `filtration_sheet.csv` | people | core |
| `extract_storage_temperature` | 4. Extraction | `extract_storage_temperature_sheet.csv` | people | core |
| `extract_evaporation_method` | 4. Extraction | `extract_evaporation_method_sheet.csv` | people | optional |
| `field_redissolution_solvent` | 4. Extraction | `redissolution_solvent_sheet.csv` | people | optional |
| `redissolution_solvent` | 4. Extraction | `redissolution_solvent_sheet.csv` | people | optional |
| `extract_container` | 4. Extraction | `extract_container_sheet.csv` | Directus (Container_Models) | optional |
| `instrument_model` | 5. LC-MS | `instrument_model_sheet.csv` | Directus (+ file) | core |
| `lc_model` | 5. LC-MS | `lc_model_sheet.csv` | people | core |
| `column_model` | 5. LC-MS | `column_model_sheet.csv` | people | core |
| `injection_mode` | 5. LC-MS | `injection_mode_sheet.csv` | people (no value yet) | optional |
| `needle_wash_mode` | 5. LC-MS | `needle_wash_mode_sheet.csv` | people | optional |
| `uv_detection` | 5. LC-MS | `uv_detection_sheet.csv` | mzML/RAW file | core |
| `column_oven_mode` | 5. LC-MS | `column_oven_mode_sheet.csv` | mzML/RAW file | core |
| `mobile_phase_a_solvent` | 5. LC-MS | `mobile_phase_solvent_sheet.csv` | mzML/RAW file | core |
| `mobile_phase_b_solvent` | 5. LC-MS | `mobile_phase_solvent_sheet.csv` | mzML/RAW file | core |
| `mobile_phase_a_modifier` | 5. LC-MS | `mobile_phase_modifier_sheet.csv` | people | optional |
| `mobile_phase_b_modifier` | 5. LC-MS | `mobile_phase_modifier_sheet.csv` | people | optional |
| `sample_dilution` | 5. LC-MS | `sample_dilution_sheet.csv` | people | optional |
| `gradient_curve` | 5. LC-MS | `gradient_curve_sheet.csv` | mzML/RAW file | core |
| `ionization_source` | 5. LC-MS | `ionization_source_sheet.csv` | mzML/RAW file | core |
| `ionization_polarity` | 5. LC-MS | `ionization_polarity_sheet.csv` | mzML/RAW file | core |
| `spray_voltage_mode` | 5. LC-MS | `spray_voltage_mode_sheet.csv` | mzML/RAW file | core |
| `faims` | 5. LC-MS | `faims_sheet.csv` | mzML/RAW file | core |
| `acquisition_mode` | 5. LC-MS | `acquisition_mode_sheet.csv` | mzML/RAW file | core |
| `dd_mode` | 5. LC-MS | `dd_mode_sheet.csv` | mzML/RAW file | core |
| `isotope_exclusion` | 5. LC-MS | `isotope_exclusion_sheet.csv` | mzML/RAW file | core |
| `fragmentation_method` | 5. LC-MS | `fragmentation_method_sheet.csv` | mzML/RAW file | core |
| `isolation_mode` | 5. LC-MS | `isolation_mode_sheet.csv` | mzML/RAW file | core |
| `ce_type` | 5. LC-MS | `ce_type_sheet.csv` | mzML/RAW file | core |
| `ce_mode` | 5. LC-MS | `ce_mode_sheet.csv` | mzML/RAW file | core |
| `ms1_agc_mode` | 5. LC-MS | `agc_mode_sheet.csv` | mzML/RAW file | core |
| `ms2_agc_mode` | 5. LC-MS | `agc_mode_sheet.csv` | mzML/RAW file | core |
| `ms1_max_it_mode` | 5. LC-MS | `max_it_mode_sheet.csv` | mzML/RAW file | core |
| `ms2_max_it_mode` | 5. LC-MS | `max_it_mode_sheet.csv` | mzML/RAW file | core |
| `ms1_data_type` | 5. LC-MS | `data_type_sheet.csv` | mzML/RAW file | core |
| `ms2_data_type` | 5. LC-MS | `data_type_sheet.csv` | mzML/RAW file | core |
| `lock_mass_correction` | 5. LC-MS | `lock_mass_correction_sheet.csv` | mzML/RAW file | core |
| `external_calibration` | 5. LC-MS | `external_calibration_sheet.csv` | people | optional |
| `background_exclusion` | 5. LC-MS | `background_exclusion_sheet.csv` | people | optional |
| `q1_resolution` | 5. LC-MS | `q1_resolution_sheet.csv` | to check (file?) | optional |
| `lc_software` | 5. LC-MS | `acquisition_software_sheet.csv` | mzML/RAW file | core |
| `ms_software` | 5. LC-MS | `acquisition_software_sheet.csv` | people | optional |
| `raw_conversion_tool` | 6. Data processing | `raw_conversion_tool_sheet.csv` | people | core |
| `peak_picking` | 6. Data processing | `peak_picking_sheet.csv` | people | optional |
| `processing_software` | 6. Data processing | `processing_software_sheet.csv` | people | core |
