# Manual curation

Everything in this folder that was written, chosen or corrected by hand rather than
read from a source. **Rule: Directus is the reference.** Other sources only fill what
Directus does not hold. Code locations are given so each choice can be checked or changed.

---

## 1. Tables maintained by hand

| What | Where | Notes |
|------|-------|-------|
| The 67 sub-tables (options, ids, descriptions) | `input/sub_tables/` | Written in the DBGI Protocol Tables (HTML) and exported unchanged. Ids are permanent: never renumber or reuse one. |
| The 6 method tables (I1, S1–S3, D1–D2, E1–E5, L1–L6, P1–P2) | `input/method_tables/` | Built by hand from `garden_defaults.R`, Directus extraction methods and the instrument method reports. No script produces them. |
| Default codes per batch | `input/config/dbgi_batches.csv` | One row per acquisition batch; Fribourg HF-X has its own row `JBUF_hfx`. |
| Columns of the final table | `input/config/final_table_columns.csv` | 86 columns, their step, sub-table, source and level (core / optional). |

## 2. Protocol values written by hand: `02_sampling/garden_defaults.R`

Per-garden protocol that no database stores. Each value carries a comment with its source.

| Reliability | Fields | Gardens |
|-------------|--------|---------|
| Read in the instrument method (RAW / .wiff, MetaXtract or `extract_methods.py`, 2026-10-30) | LC model, column temperature, gradient, source, DDA and resolution settings | JBN, JBC, JBP, JBK, JBUF HF-X |
| Platform method document | LC-MS of the Q Exactive Plus | JBUF |
| Lab practice | preservation, transport, grinding, agitation, centrifugation, injection volume, dilution | all |
| **Assumption** | Kew extraction = Prague; Kew column length and diameter "probably as JBP"; HF-X source settings = Q Exactive Plus | JBK, JBUF |
| Unknown (left empty) | Kew LC model; JBUF column temperature, mass range, vaporizer temperature; scan times of JBP, JBK, JBUF | — |

`INSTRUMENT_OVERRIDES`: Fribourg Q Exactive HF-X files take a different MS method
from the Q Exactive Plus (1 µL instead of 2 µL, other resolution, AGC, top N).

## 3. Corrections in code: `02_sampling/02_sampling_correction.R`

| Rule | Code | Effect |
|------|------|--------|
| Malformed `sample_id` removed | section 0 | anything other than `dbgi_` + 6 digits |
| Exact duplicate rows removed | section 1 | |
| Never-documented columns removed | `TO_REMOVE` | phenology, fresh weight, permit id, extraction date… |
| Dates normalised | `norm_date`, `norm_inj` | `YYYYDDMM` (JBC file names) and `YYMMDD` (Synapt) → `YYYY-MM-DD` |
| Swapped latitude / longitude fixed | `fix_coords`, `REGIONS` | swapped when only the swapped pair falls in Switzerland, Czech Republic or UK |
| **Directus overrides** | section 4b | collector, ORCID, plant part, date, dry weight, extraction volume, extraction method / batch / uuid; every replaced value logged in `sampling_metadata_conflits.csv` |
| Dry weight unit | section 4b | only Directus unit id 22 (mg) kept |
| Extraction volume stored in litres | section 4b | Directus values < 0.01 multiplied by 1000 |
| Extraction ratio | sections 4b, 5b | always recomputed as dry weight / volume |
| MassIVE fills empty cells only | section 5 | never overwrites |
| Column name from the MassIVE method name | section 5 | e.g. `100mm_C18_15min…` → C18 100 mm; Fribourg 2024 batch → C18 |
| One MassIVE accession per Prague file | section 5 | needs `metadata_prague_merged.tsv` (not provided): Prague files keep the 3 accessions and have no USI / MassIVE / GNPS links |
| Wrong garden | `GARDEN_FIX` | dbgi_009962, dbgi_009963: Kew → Prague (coordinates and collector); duplicate rows removed |
| Instrument names harmonised | `INSTRUMENT_NAMES` | spelling variants → "model (vendor)" |
| Instrument forced | `INSTRUMENT_FIX` | JBC = ZenoTOF 8600 (not Synapt XS), checked in the .wiff |
| **All plants cultivated** | section 5b | `is_wild = 0` everywhere |
| **Kew extraction = Prague** | `EXTRACT_DONOR` | Kew files without Directus extraction take Prague's most frequent method |
| **Fribourg plant part = leaf** | `PLANT_PART_DEFAULT` | when Directus and MassIVE are both empty |
| **Imputation** | `IMPUTE_COLS`, `MIN_DONORS = 10` | dry weight, volume, ratio, extraction method: most frequent value of the same MZmine batch, otherwise of the garden; every imputed cell listed in `imputed_fields`. Collectors and dates are never imputed. |

## 4. Choices in `src/build_final_table.R`

| Rule | Effect |
|------|--------|
| Batch default first, then what the file says | a file always gets 6 codes, even when one source is missing |
| Extraction from Directus | the Directus `extraction_method_id` chooses the E code; when one Directus code covers several E methods (code 4 = E1 and E2), the batch default is kept |
| Fribourg HF-X detected by name | `instrument_model` containing "HF-X" → batch row `JBUF_hfx` |
| Polarity per file | positive and negative files share one L method; polarity is a separate column |
| Unknown values left empty | never guessed; listed in `output/unmatched.csv` |

## 5. Open points

- `garden_defaults.R` still holds older solvents for Prague, Champex and part of Kew; Directus wins in the final table, but step 02 should be aligned.
- Directus code 4 "MeOH/H2O" covers two protocols (Neuchâtel with formic acid, Fribourg without).
- Kew: collector listed as "Mazzarine Laboureau; Davide; Katerina" when Directus has no collector (3 files); extraction partly imputed from Prague.
- Directus extraction code 1 has no DBGI method yet (2 Fribourg files).
