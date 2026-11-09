# ==============================================================================
# 02_sampling_correction.R — corrections of step 02 (sampling)
#
# Fixes 02_sampling/output/sampling_metadata.csv from A to Z and saves it again under
# the same name. Works on the original file as on an already-corrected one
# (safe to re-run: nothing is done twice).
#   1. exact duplicated rows removed
#   2. columns for which we will never have information removed
#   3. dates -> YYYY-MM-DD (collection_date, id_date, injection_date)
#   4. coordinates (decimal comma -> point, swapped lat/lon), missing ones from MassIVE
#   5. NA filled from MassIVE (never overwriting), + is_wild / collector
#   6. taxonomic columns removed (taxonomy lives in step 01)
#   7. summary + conflict report, then save
#
# No dependency on step 01. Time-stamped backup before overwriting.
#
# Only EMPTY cells are filled, so re-running it on old + new rows is safe and
# changes nothing on rows that are already complete.
#
# INPUT  : 02_sampling/output/sampling_metadata.csv, BASE_DIR/massive_metadata_complete_set.tsv
# OUTPUT : 02_sampling/output/sampling_metadata.csv           (updated in place)
#          02_sampling/output/sampling_metadata_conflits.csv  (MassIVE vs sampling)
# ==============================================================================

library(data.table)

if (!exists("BASE_DIR")) BASE_DIR <- "."
to_num <- function(x) suppressWarnings(as.numeric(gsub(",", ".", x, fixed = TRUE)))

OUT_DIR <- file.path(BASE_DIR, "02_sampling", "output")
F_SAMP  <- file.path(OUT_DIR, "sampling_metadata.csv")
F_CONF  <- file.path(OUT_DIR, "sampling_metadata_conflits.csv")
F_MASS  <- file.path(BASE_DIR, "massive_metadata_complete_set.tsv")
# Prague: file -> MassIVE dataset (batch004 = MSV000102437, batch005 = MSV000102439,
# batch006 = MSV000102438; batch104 / 105 are not on MassIVE)
F_PRAGUE <- file.path(BASE_DIR, "02_sampling", "metadata_prague_merged.tsv")
old_conf <- file.path(OUT_DIR, "sampling_metadata_filled_conflits.csv")
if (file.exists(old_conf)) file.remove(old_conf)          # former name
if (!file.exists(F_SAMP)) stop("Run 02_sampling_metadata.R first: ", F_SAMP, " not found")
if (!file.exists(F_MASS)) stop("MassIVE file not found: ", F_MASS)

# Columns for which we will never have information
TO_REMOVE <- c("developmental_stage", "phenology", "pathogen_visible", "fresh_weight_g",
               "time_to_preservation_min", "storage_duration_d", "extraction_date",
               "internal_standard", "abs_permit_id")

# Countries of the gardens (lat/lon ranges): used to detect swapped coordinates
REGIONS <- list(
  Switzerland   = list(lat = c(45.8, 47.9), lon = c(5.9, 10.6)),
  CzechRepublic = list(lat = c(48.5, 51.1), lon = c(12.0, 18.9)),
  UnitedKingdom = list(lat = c(49.9, 58.7), lon = c(-8.2, 1.8))
)

# Plant part -> Plant Ontology term
PO <- c(leaf = "PO:0025034", leaves = "PO:0025034",
        flower = "PO:0009046", flowers = "PO:0009046", inflorescence = "PO:0009049",
        stem = "PO:0009047", stems = "PO:0009047", bud = "PO:0000055", buds = "PO:0000055",
        root = "PO:0009005", roots = "PO:0009005", fruit = "PO:0009001", seed = "PO:0009010",
        bark = "PO:0004518", shoot = "PO:0009006", "aerial part" = "PO:0009006",
        "aerial parts" = "PO:0009006", "whole plant" = "PO:0000003", "whole organism" = "PO:0000003", bulb = "PO:0025356",
        rhizome = "PO:0004542", tuber = "PO:0025522", wood = "PO:0005848")

# ==============================================================================
# Helpers
# ==============================================================================
in_range    <- function(x, r) !is.na(x) & x >= r[1] & x <= r[2]
in_region   <- function(la, lo) Reduce(`|`, lapply(REGIONS, function(R) in_range(la, R$lat) & in_range(lo, R$lon)))
first_value <- function(x) { x <- x[!is.na(x) & x != ""]; if (length(x)) x[1] else NA_character_ }
norm_fn     <- function(x) tolower(sub("\\.mzml$", "", basename(trimws(x)), ignore.case = TRUE))

# "20250612" or "20250612123000" -> "2025-06-12"; other formats unchanged
norm_date <- function(x) {
  x <- if (is.numeric(x)) format(x, scientific = FALSE, trim = TRUE) else as.character(x)
  x[x %in% c("NA", "")] <- NA
  ifelse(!is.na(x) & grepl("^[0-9]{8}([0-9]{6})?$", x),
         format(as.Date(substr(x, 1, 8), "%Y%m%d")), x)
}

# fill_from(): fills dt[[col]] where it is NA with `values` (aligned on dt rows).
# Never replaces an existing value; disagreements are logged in `conflicts`.
conflicts <- list()
fill_from <- function(dt, col, values, source, log = TRUE) {
  values <- as.character(values)
  values[!is.na(values) & trimws(values) == ""] <- NA
  # new or fully empty column: take the values (numeric if they all convert)
  if (!col %in% names(dt) || all(is.na(dt[[col]]))) {
    n <- to_num(values)
    set(dt, j = col, value = if (all(is.na(n) == is.na(values))) n else values)
    return(invisible())
  }
  # align types
  old <- dt[[col]]
  if (is.numeric(old)) {
    values <- to_num(values)
    if (is.integer(old)) set(dt, j = col, value = as.numeric(old))
  } else if (!is.character(old)) {
    set(dt, j = col, value = as.character(old))
  }
  old  <- dt[[col]]
  diff <- which(!is.na(old) & !is.na(values) & as.character(old) != as.character(values))
  if (log && length(diff))
    conflicts[[length(conflicts) + 1]] <<- data.table(
      sample_id = dt$sample_id[diff], garden = dt$garden[diff], column = col,
      value_sampling = as.character(old[diff]), value_source = as.character(values[diff]),
      source = source)
  idx <- which(is.na(old) & !is.na(values))
  if (length(idx)) set(dt, i = idx, j = col, value = values[idx])
}

# Swap lat/lon when they only fit the expected regions once swapped
fix_coords <- function(dt, clat = "latitude", clon = "longitude", label = "") {
  if (!all(c(clat, clon) %in% names(dt))) return(0L)
  la <- to_num(dt[[clat]]); lo <- to_num(dt[[clon]])
  ok      <- in_region(la, lo)
  swapped <- !ok & in_region(lo, la)
  outside <- !ok & !swapped & !is.na(la) & !is.na(lo)
  cat("  Coordinates", label, ": OK", sum(ok), "| swapped & fixed", sum(swapped),
      "| outside regions", sum(outside), "| missing", sum(is.na(la) | is.na(lo)), "\n")
  if (any(outside)) print(dt[outside, c("sample_id", clat, clon), with = FALSE][1:min(10, sum(outside))])
  if (any(swapped)) {
    tmp <- dt[[clat]][swapped]
    set(dt, i = which(swapped), j = clat, value = dt[[clon]][swapped])
    set(dt, i = which(swapped), j = clon, value = tmp)
  }
  sum(swapped)
}

mass <- fread(F_MASS, sep = "\t", na.strings = c("", "NA"), colClasses = "character")

# ==============================================================================
# 1-3. Read, duplicates, columns, dates
# ==============================================================================
cat("\n===== sampling_metadata.csv =====\n")
file.copy(F_SAMP, sub("\\.csv$", paste0("_backup_", format(Sys.time(), "%Y%m%d_%H%M"), ".csv"), F_SAMP))

cc   <- intersect(c("gbif_taxon_key", "ncbi_taxid", "collection_date", "id_date",
                    "injection_date", "latitude", "longitude"),
                  names(fread(F_SAMP, nrows = 0)))
samp <- fread(F_SAMP, na.strings = c("", "NA"), colClasses = list(character = cc))
n_init <- nrow(samp)

# 0. malformed sample_id (blanks, truncated ids: "dbgi", "dbgi_1", "blk_000104"...) removed
bad_id <- !grepl("^dbgi_[0-9]{6}$", samp$sample_id)
if (any(bad_id)) {
  cat("  Rows with malformed sample_id removed:", sum(bad_id), "(",
      paste(unique(samp$sample_id[bad_id]), collapse = ", "), ")\n")
  samp <- samp[!bad_id]
}

# 1. exact duplicates
samp <- unique(samp)
cat("  Exact duplicated rows removed:", n_init - nrow(samp), "->", nrow(samp), "rows\n")
multi_id <- samp[!is.na(mzml_filename), .(n = uniqueN(sample_id),
                 sample_ids = paste(unique(sample_id), collapse = " ; ")), by = mzml_filename][n > 1]
if (nrow(multi_id)) {
  warning(nrow(multi_id), " mzML file(s) linked to several sample_id — see the list printed above.")
  cat("  mzML files linked to several sample_id:\n"); print(multi_id[, .(mzml_filename, sample_ids)])
}

na_before <- sapply(samp, function(x) sum(is.na(x)))

# 2. columns removed
rm_cols <- intersect(TO_REMOVE, names(samp))
if (length(rm_cols)) samp[, (rm_cols) := NULL]
cat("  Columns removed:", length(rm_cols), "\n")

# 3. dates
for (dc in intersect(c("collection_date", "id_date"), names(samp)))
  set(samp, j = dc, value = norm_date(samp[[dc]]))

# injection_date: "20260327" (YYYYMMDD), "20262605" (YYYYDDMM: "month" > 12),
#                 "250402_M" (YYMMDD from Synapt file names) -> YYYY-MM-DD
norm_inj <- function(x) {
  vapply(as.character(x), function(v) {
    if (is.na(v)) return(NA_character_)
    if (grepl("^[0-9]{4}-[0-9]{2}-[0-9]{2}$", v)) return(v)
    if (grepl("^[0-9]{8}$", v)) {
      a <- substr(v, 5, 6); b <- substr(v, 7, 8)
      return(if (as.integer(a) > 12) paste(substr(v, 1, 4), b, a, sep = "-")
             else paste(substr(v, 1, 4), a, b, sep = "-"))
    }
    if (grepl("^[0-9]{6}_", v))
      return(paste0("20", substr(v, 1, 2), "-", substr(v, 3, 4), "-", substr(v, 5, 6)))
    v
  }, character(1), USE.NAMES = FALSE)
}
if ("injection_date" %in% names(samp)) set(samp, j = "injection_date", value = norm_inj(samp$injection_date))

# ==============================================================================
# 4. Coordinates
# ==============================================================================
for (cc_ in intersect(c("latitude", "longitude"), names(samp)))
  set(samp, j = cc_, value = to_num(samp[[cc_]]))          # "46,032890" -> 46.03289
fix_coords(samp, label = "sampling")

# ==============================================================================
# 4b. Directus = REFERENCE source (field + lab database): its values replace
#     garden defaults; MassIVE (section 5) then only fills what is still empty
#     identified_by = person who collected / identified the sample in the field
# ==============================================================================
F_DIRECTUS <- file.path(BASE_DIR, "directus", "output", "directus_metadata.csv")
if (file.exists(F_DIRECTUS)) {
  dir_ <- fread(F_DIRECTUS, colClasses = "character", na.strings = c("", "NA"))
  dir_ <- unique(dir_, by = "sample_id")
  d <- dir_[match(samp$sample_id, dir_$sample_id)]
  cat("  Rows linked to Directus:", sum(!is.na(d$sample_id)), "/", nrow(samp), "\n")

  # Directus = reference source: every non-empty Directus value REPLACES the current
  # value (garden default, MassIVE...). Replaced values are logged in the conflicts.
  override_from <- function(col, values, source) {
    if (!col %in% names(samp)) set(samp, j = col, value = NA_character_)
    num <- is.numeric(samp[[col]])
    if (is.integer(samp[[col]])) set(samp, j = col, value = as.numeric(samp[[col]]))   # 21.4 mg must not be truncated
    values <- if (num) to_num(values) else as.character(values)
    if (!num) set(samp, j = col, value = as.character(samp[[col]]))
    old <- samp[[col]]
    i   <- which(!is.na(values) & as.character(values) != "")
    chg <- i[!is.na(old[i]) & as.character(old[i]) != as.character(values[i])]
    if (length(chg))
      conflicts[[length(conflicts) + 1]] <<- data.table(
        sample_id = samp$sample_id[chg], garden = samp$garden[chg], column = col,
        value_sampling = as.character(old[chg]), value_source = as.character(values[chg]),
        source = paste(source, "(Directus kept)"))
    set(samp, i = i, j = col, value = values[i])
    cat(sprintf("    %-28s %4d from Directus (%d replaced)\n", col, length(i), length(chg)))
  }

  #   dry weight: unit id 22 = mg (4350 / 4425 rows); other unit ids ignored
  #   extraction volume: mixed units in Directus (0.001 = 1 mL stored in litres) -> < 0.01 x 1000
  dw_d <- to_num(ifelse(!is.na(d$dried_weight_unit_id) & d$dried_weight_unit_id != "22", NA, d$dry_weight_mg))
  ev_d <- to_num(d$extraction_volume_ml)
  ev_d <- ifelse(!is.na(ev_d) & ev_d < 0.01, ev_d * 1000, ev_d)

  override_from("collector_full_name",  d$identified_by,                      "directus:identified_by")
  override_from("collector_orcid",      d$collector_orcid,                    "directus:collector_orcid")
  override_from("plant_part",           tolower(trimws(d$observation_subject)), "directus:observation_subject")
  override_from("collection_date",      norm_date(substr(d$event_date, 1, 10)), "directus:event_date")
  for (cl in c("dry_weight_mg", "extraction_volume_ml"))          # always double (not integer)
    set(samp, j = cl, value = if (cl %in% names(samp)) as.numeric(to_num(samp[[cl]])) else NA_real_)
  override_from("dry_weight_mg",        dw_d,                                 "directus:dry_weight_mg")
  override_from("extraction_volume_ml", ev_d,                                 "directus:extraction_volume_ml")
  override_from("extraction_method_id", d$extraction_method_id,               "directus:extraction_method_id")
  override_from("extraction_batch",     d$extraction_batch,                   "directus:extraction_batch")
  override_from("uuid_extraction",      d$uuid_extraction,                    "directus:uuid_extraction")
  # ratio always recomputed from weight / volume (Directus ratio column is not in mg/mL)
  if ("extraction_ratio_mg_per_ml" %in% names(samp))
    set(samp, j = "extraction_ratio_mg_per_ml", value = NA_real_)
} else {
  cat("  Directus export not found (", F_DIRECTUS, ") -> skipped\n")
}

# ==============================================================================
# 5. Fill from MassIVE
# ==============================================================================
SAMPLE_FIELDS <- intersect(c("observation_subject", "dried_weight", "dried_weight_unit",
                             "extraction_solvent_volume", "extraction_solvent_volume_unit",
                             "extraction_method", "extraction_data_id", "collection_date",
                             "is_wild", "collector_full_name", "collector_orcid",
                             "latitude", "longitude"), names(mass))

# one row per sample (first non-empty value) + conflicts inside MassIVE itself
ms <- mass[, lapply(.SD, first_value), by = sample_id, .SDcols = SAMPLE_FIELDS]
multi <- melt(mass[, lapply(.SD, function(x) uniqueN(x[!is.na(x) & x != ""])),
                   by = sample_id, .SDcols = setdiff(SAMPLE_FIELDS, c("latitude", "longitude"))],
              id.vars = "sample_id", variable.name = "column", value.name = "n")[n > 1]
if (nrow(multi)) {
  vals <- mass[sample_id %in% multi$sample_id]
  conflicts[[length(conflicts) + 1]] <- multi[, .(
    sample_id, garden = samp$garden[match(sample_id, samp$sample_id)],
    column = as.character(column), value_sampling = NA_character_,
    value_source = mapply(function(s, cl) paste(unique(na.omit(vals[sample_id == s][[cl]])), collapse = " | "),
                          sample_id, as.character(column)),
    source = "MassIVE: several values for the same sample (first kept)")]
}

m <- ms[match(samp$sample_id, ms$sample_id)]
cat("  Rows linked to MassIVE (sample):", sum(!is.na(m$sample_id)), "/", nrow(samp), "\n")

# -- plant part + Plant Ontology
fill_from(samp, "plant_part", tolower(trimws(m$observation_subject)), "massive:observation_subject")
pp <- tolower(trimws(samp$plant_part))
fill_from(samp, "po_term_id", unname(PO[pp]), "derived from plant_part")
unmapped <- setdiff(unique(na.omit(pp)), names(PO))
if (length(unmapped)) cat("  plant_part without PO term (complete the PO table):",
                          paste(unmapped, collapse = ", "), "\n")

# -- dry weight (mg), solvent volume (ml), ratio
dw  <- to_num(m$dried_weight); dwu <- tolower(trimws(m$dried_weight_unit))
dw  <- ifelse(is.na(dwu) | dwu == "mg", dw, ifelse(dwu == "g", dw * 1000, NA))
fill_from(samp, "dry_weight_mg", dw, "massive:dried_weight", log = FALSE)

ev  <- to_num(m$extraction_solvent_volume); evu <- tolower(trimws(m$extraction_solvent_volume_unit))
ev  <- ifelse(grepl("^(µ|μ|u)l$", evu), ev / 1000, ifelse(evu == "ml", ev, NA))
fill_from(samp, "extraction_volume_ml", ev, "massive:extraction_solvent_volume", log = FALSE)

fill_from(samp, "extraction_ratio_mg_per_ml",
          round(to_num(samp$dry_weight_mg) / to_num(samp$extraction_volume_ml), 2),
          "computed: dry_weight_mg / extraction_volume_ml")

# -- extraction
# extraction_method_id: Directus ids only (MassIVE gives free text, not the same field)
# massive:extraction_data_id is NOT the Directus extraction uuid (3427 / 3427 differ) -> not used

# -- collection date
fill_from(samp, "collection_date", norm_date(m$collection_date), "massive:collection_date")

# -- missing coordinates (different decimals are not a conflict -> not logged)
fill_from(samp, "latitude",  m$latitude,  "massive:latitude",  log = FALSE)
fill_from(samp, "longitude", m$longitude, "massive:longitude", log = FALSE)

# -- new columns
fill_from(samp, "is_wild",             m$is_wild,             "massive:is_wild")
fill_from(samp, "collector_full_name", m$collector_full_name, "massive:collector_full_name")
fill_from(samp, "collector_orcid",     m$collector_orcid,     "massive:collector_orcid")

# -- file level (injection)
if (all(c("filename", "injection_volume", "injection_method") %in% names(mass))) {
  mf <- unique(mass[, .(fn = norm_fn(filename), injection_volume, injection_volume_unit,
                        injection_method)], by = "fn")
  fm <- mf[match(norm_fn(samp$mzml_filename), mf$fn)]
  cat("  Rows linked to MassIVE (mzML file):", sum(!is.na(fm$fn)), "/", nrow(samp), "\n")

  iv <- to_num(fm$injection_volume)
  iv <- ifelse(is.na(fm$injection_volume_unit) |
               grepl("^(µ|μ|u)l$", tolower(fm$injection_volume_unit)), iv, NA)
  fill_from(samp, "injection_volume_ul", iv, "massive:injection_volume")

  # "100mm_C18_15min_DDA_ELON_pos" -> 15 min, "C18 100 mm" ; "..._PMA_C18_DDA_pos" -> "C18"
  im <- fm$injection_method
  rt <- ifelse(!is.na(im) & grepl("[0-9]+min", im), sub(".*?([0-9]+)min.*", "\\1", im), NA)
  fill_from(samp, "run_time_min", rt, "derived from massive:injection_method")
  phase <- "(^|_)(C18|C8|HILIC|PFP|T3)(_|$)"
  col <- ifelse(!is.na(im) & grepl("^[0-9]+mm_[A-Za-z0-9]+", im),
                sub("^([0-9]+)mm_([A-Za-z0-9]+).*", "\\2 \\1 mm", im),
                ifelse(!is.na(im) & grepl(phase, im, ignore.case = TRUE),
                       toupper(sub(paste0(".*", phase, ".*"), "\\2", im, ignore.case = TRUE)), NA))
  fill_from(samp, "column_name", col, "derived from massive:injection_method")
}
# Fallback: Fribourg Q Exactive 2024 batch (methods "..._PMA_C18_DDA_pos/neg")
if (all(c("column_name", "batch_id") %in% names(samp)))
  set(samp, i = which(is.na(samp$column_name) & samp$batch_id == "JBUF_qexactive_2024"),
      j = "column_name", value = "C18")

# -- polarity (positive / negative) and sample type, as used by ENPKG
if ("ionization_polarity" %in% names(samp))
  set(samp, j = "ionization_polarity", value = tolower(trimws(samp$ionization_polarity)))
fill_from(samp, "ionization_polarity",
          tolower(mass$ionization_mode[match(norm_fn(samp$mzml_filename), norm_fn(mass$filename))]),
          "massive:ionization_mode")
fill_from(samp, "sample_type",
          mass$sample_type[match(norm_fn(samp$mzml_filename), norm_fn(mass$filename))],
          "massive:sample_type")

# -- Prague: one MassIVE accession per file (the garden default lists the 3 datasets)
if (file.exists(F_PRAGUE) && "massive_accession" %in% names(samp)) {
  pr  <- fread(F_PRAGUE, sep = "\t", colClasses = "character", na.strings = c("", "NA"))
  acc_file <- pr$dataset[match(norm_fn(samp$mzml_filename), norm_fn(pr$filename))]
  multi    <- !is.na(samp$massive_accession) & grepl(";", samp$massive_accession)
  set(samp, i = which(multi), j = "massive_accession", value = acc_file[multi])   # NA = not on MassIVE
  cat("  Prague: accession set for", sum(multi & !is.na(acc_file)), "files |",
      sum(multi & is.na(acc_file)), "files not on MassIVE (batch104/105) -> no accession\n")
} else if (!file.exists(F_PRAGUE)) {
  cat("  Prague mapping not found (", F_PRAGUE, ") -> JBP files keep the 3 accessions, no USI\n")
}

# -- persistent links of each MS file (same prefixes as ENPKG; one accession only)
acc    <- trimws(as.character(samp$massive_accession))
acc_ok <- !is.na(acc) & grepl("^MSV[0-9]+$", acc) & !is.na(samp$mzml_filename)
usi    <- ifelse(acc_ok, paste0("mzspec:", acc, ":", basename(samp$mzml_filename)), NA)
fill_from(samp, "usi_file", usi, "derived: massive_accession + mzml_filename", log = FALSE)
fill_from(samp, "massive_link",
          ifelse(acc_ok, paste0("https://massive.ucsd.edu/ProteoSAFe/dataset.jsp?accession=", acc), NA),
          "derived", log = FALSE)
fill_from(samp, "gnps_dashboard_link",
          ifelse(acc_ok, paste0("https://dashboard.gnps2.org/?usi=", usi), NA), "derived", log = FALSE)
cat("  USI / links:", sum(acc_ok), "/", nrow(samp), "files",
    if (any(!acc_ok & !is.na(acc))) "(none for gardens with several MassIVE accessions)" else "", "\n")

# ==============================================================================
# 5a. Samples attributed to the wrong garden (checked against Directus coordinates
#     and collector): set to the right garden BEFORE the garden-level imputation
# ==============================================================================
GARDEN_FIX <- c(dbgi_009962 = "JBP",   # in JBK batch, but Prague coordinates, coll. A. Maliukova
                dbgi_009963 = "JBP")
gf <- which(samp$sample_id %in% names(GARDEN_FIX))
if (length(gf)) {
  set(samp, i = gf, j = "garden", value = unname(GARDEN_FIX[samp$sample_id[gf]]))
  if ("dataset" %in% names(samp)) set(samp, i = gf, j = "dataset", value = tolower(samp$garden[gf]))
  cat("  Garden fixed:", paste(unique(samp$sample_id[gf]), "->", samp$garden[gf], collapse = "; "), "\n")

  # Ghost rows: a fixed sample that has NO mzML while the same sample_id already has
  # a row WITH an mzML (= its real injection in the right garden) -> row removed.
  ghost <- gf[is.na(samp$mzml_filename[gf]) &
              samp$sample_id[gf] %in% samp$sample_id[!is.na(samp$mzml_filename)]]
  if (length(ghost)) {
    cat("  Ghost rows removed (sample already injected in its real garden):",
        paste(samp$sample_id[ghost], collapse = ", "), "\n")
    samp <- samp[-ghost]
    gf   <- which(samp$sample_id %in% names(GARDEN_FIX) & is.na(samp$mzml_filename))
  } else {
    gf   <- gf[is.na(samp$mzml_filename[gf])]
  }

  # Remaining fixed rows without mzML: their LC-MS / instrument / MZmine fields still
  # come from the OLD garden defaults -> replaced by the most common LC-MS profile of
  # the new garden (no mzML file -> deposition fields emptied).
  nm   <- names(samp)
  rng  <- function(a, b) if (all(c(a, b) %in% nm)) nm[match(a, nm):match(b, nm)] else character(0)
  LCMS_COLS <- intersect(unique(c("mzbatch_path", "batch_id",
                                  rng("lc_vendor", "processing_params_file"),
                                  "qc_sample_type", "qc_conditioning_n", "qc_frequency", "randomization")),
                         nm)
  for (g in unique(samp$garden[gf])) {
    ref_rows <- which(samp$garden == g & !samp$sample_id %in% names(GARDEN_FIX) & !is.na(samp$mzml_filename))
    if (!length(ref_rows)) next
    prof <- names(which.max(table(samp$processing_params_file[ref_rows])))
    ref  <- ref_rows[samp$processing_params_file[ref_rows] == prof][1]
    tgt  <- gf[samp$garden[gf] == g]
    for (cl in LCMS_COLS) {
      if (!is.character(samp[[cl]]) && !is.character(samp[[cl]][ref])) {
        set(samp, i = tgt, j = cl, value = samp[[cl]][ref])
      } else {
        set(samp, j = cl, value = as.character(samp[[cl]]))
        set(samp, i = tgt, j = cl, value = as.character(samp[[cl]][ref]))
      }
    }
    for (cl in intersect(c("massive_accession", "usi_file", "massive_link", "gnps_dashboard_link"), nm))
      set(samp, i = tgt, j = cl, value = NA)
    cat(sprintf("    LC-MS fields of %d sample(s) set to the %s profile (%s)\n",
                length(tgt), g, prof))
  }
}

# ==============================================================================
# 5a-ter. Instrument names harmonised (the merged CSV mixes several spellings:
#   "LCMS Orbitrap ID-X", "LCMS – Synapt XS", "LC-MS QExactive Plus"...)
#   Pattern (regex, case-insensitive) -> standard name "<model> (<vendor>)"
# ==============================================================================
INSTRUMENT_NAMES <- c(
  "ID-?X"                    = "Orbitrap ID-X (Thermo Scientific)",
  "Exploris ?120"            = "Orbitrap Exploris 120 (Thermo Scientific)",
  "Q ?Exactive ?HF-?X"       = "Q Exactive HF-X (Thermo Scientific)",
  "Q ?Exactive ?Plus"        = "Q Exactive Plus (Thermo Scientific)",
  "Synapt ?XS"               = "Synapt XS (Waters)",
  "ZenoTOF ?8600"            = "ZenoTOF 8600 (SCIEX)"
)
if ("instrument_model" %in% names(samp)) {
  old_im <- samp$instrument_model
  for (p in names(INSTRUMENT_NAMES)) {
    ix <- which(grepl(p, samp$instrument_model, ignore.case = TRUE) &
                samp$instrument_model != INSTRUMENT_NAMES[[p]])
    if (length(ix)) set(samp, i = ix, j = "instrument_model", value = INSTRUMENT_NAMES[[p]])
  }
  chg <- which(old_im != samp$instrument_model)
  if (length(chg)) {
    cat("  Instrument names harmonised:\n")
    print(unique(data.table(before = old_im[chg], after = samp$instrument_model[chg])))
  }
  left <- setdiff(unique(na.omit(samp$instrument_model)), INSTRUMENT_NAMES)
  if (length(left)) cat("  Instrument names not in INSTRUMENT_NAMES:", paste(left, collapse = ", "), "\n")
}

# ==============================================================================
# 5a-bis. Instrument forced by garden (the merged CSV is wrong for these gardens):
#   JBC was acquired on the SCIEX ZenoTOF 8600 (Sciex OS, Zeno pulsing; batch
#   JBC_zenotof_2026), not on the Waters Synapt XS of JBN.
#   Model checked in the .wiff (2026-10-30): "ZenoTOF 8600 system", SN FR20182507.
# ==============================================================================
INSTRUMENT_FIX <- c(JBC = "ZenoTOF 8600 (SCIEX)")
if ("instrument_model" %in% names(samp)) {
  for (g in names(INSTRUMENT_FIX)) {
    ix <- which(samp$garden == g & (is.na(samp$instrument_model) | samp$instrument_model != INSTRUMENT_FIX[[g]]))
    if (length(ix)) {
      set(samp, i = ix, j = "instrument_model", value = INSTRUMENT_FIX[[g]])
      cat("  Instrument fixed:", g, "->", INSTRUMENT_FIX[[g]], "(", length(ix), "samples )\n")
    }
  }
}

# ==============================================================================
# 5b. Remaining gaps filled from samples of the SAME batch (protocol-level fields)
#     For each column below, an empty cell takes the most frequent value of the
#     same MZmine batch (processing_params_file); if the whole batch is empty,
#     the most frequent value of the same garden (donors: >= MIN_DONORS filled
#     samples, otherwise the cell stays empty). Sample-specific fields
#     (uuid_extraction, collection_date, coordinates...) are NOT imputed.
#     Every imputed cell is listed in imputed_fields (traceability).
# ==============================================================================
# collector_full_name / collector_orcid are NOT imputed: several people sampled the
# same garden (e.g. Kew: Mazzarine, Davide, Katerina) -> a copied name would be wrong.
# All DBGI individuals are cultivated (botanical gardens) -> is_wild = 0 everywhere
set(samp, j = "is_wild", value = 0L)

# Gardens without extraction record take the extraction method of a garden with
# the same protocol (Kew = same extraction as Prague)
EXTRACT_DONOR <- c(JBK = "JBP")
if ("extraction_method_id" %in% names(samp)) {
  for (g in names(EXTRACT_DONOR)) {
    v <- names(which.max(table(na.omit(samp$extraction_method_id[samp$garden == EXTRACT_DONOR[[g]]]))))
    i <- which(samp$garden == g & is.na(samp$extraction_method_id))
    if (length(v) && length(i)) {
      set(samp, j = "extraction_method_id", value = as.character(samp$extraction_method_id))
      set(samp, i = i, j = "extraction_method_id", value = v)
      cat(sprintf("  extraction_method_id: %d %s rows <- %s (same protocol as %s)\n",
                  length(i), g, v, EXTRACT_DONOR[[g]]))
    }
  }
}

# Plant part still unknown after Directus + MassIVE: garden default (assumption),
# traced in imputed_fields. JBUF 2024: leaves.
PLANT_PART_DEFAULT <- c(JBUF = "leaf")
pp_imp <- integer(0)
for (g in names(PLANT_PART_DEFAULT)) {
  i <- which(samp$garden == g & (is.na(samp$plant_part) | samp$plant_part == ""))
  if (!length(i)) next
  set(samp, i = i, j = "plant_part", value = PLANT_PART_DEFAULT[[g]])
  set(samp, i = i, j = "po_term_id", value = unname(PO[PLANT_PART_DEFAULT[[g]]]))
  pp_imp <- c(pp_imp, i)
  cat(sprintf("  plant_part: %d %s rows <- '%s' (garden default, assumption)\n",
              length(i), g, PLANT_PART_DEFAULT[[g]]))
}

IMPUTE_COLS <- intersect(c("dry_weight_mg", "extraction_volume_ml", "extraction_ratio_mg_per_ml",
                           "extraction_method_id"), names(samp))
MIN_DONORS  <- 10   # a batch / garden needs >= n filled samples to serve as donor
mode_val <- function(x) { x <- x[!is.na(x) & as.character(x) != ""]
                          if (length(x) < MIN_DONORS) return(NA)
                          names(which.max(table(as.character(x)))) }
grp_batch <- if ("processing_params_file" %in% names(samp)) samp$processing_params_file else samp$batch_id
imputed   <- rep("", nrow(samp))
imputed[pp_imp] <- "plant_part (garden default)"
cat("  Imputation from the same batch / garden:\n")
for (cl in IMPUTE_COLS) {
  na_i <- which(is.na(samp[[cl]]) | as.character(samp[[cl]]) == "")
  if (!length(na_i)) next
  by_b <- tapply(samp[[cl]], grp_batch,   mode_val)
  by_g <- tapply(samp[[cl]], samp$garden, mode_val)
  v    <- by_b[as.character(grp_batch[na_i])]
  lvl  <- ifelse(is.na(v), "garden", "batch")
  v[is.na(v)] <- by_g[as.character(samp$garden[na_i[is.na(v)]])]
  ok <- !is.na(v)
  if (!any(ok)) next
  vals <- if (is.numeric(samp[[cl]])) to_num(v[ok]) else as.character(v[ok])
  set(samp, i = na_i[ok], j = cl, value = vals)
  imputed[na_i[ok]] <- paste0(imputed[na_i[ok]], ifelse(imputed[na_i[ok]] == "", "", "; "),
                              cl, " (", lvl[ok], ")")
  cat(sprintf("    %-28s %4d filled (%d from batch, %d from garden) | %d still empty\n",
              cl, sum(ok), sum(ok & lvl == "batch"), sum(ok & lvl == "garden"), sum(!ok)))
}
set(samp, j = "imputed_fields", value = ifelse(imputed == "", NA_character_, imputed))
# ratio recomputed where it was imputed but weight/volume are now known
if (all(c("dry_weight_mg", "extraction_volume_ml", "extraction_ratio_mg_per_ml") %in% names(samp))) {
  r <- round(to_num(samp$dry_weight_mg) / to_num(samp$extraction_volume_ml), 2)
  fix <- which(!is.na(r) & grepl("extraction_ratio_mg_per_ml", samp$imputed_fields))
  if (length(fix)) set(samp, i = fix, j = "extraction_ratio_mg_per_ml", value = r[fix])
}

# ==============================================================================
# 6. Independence from step 01: taxonomic columns removed
#    (useful for files produced by older versions of step 02)
# ==============================================================================
TAXO_COLS <- c("scientific_name", "taxon_accepted_name", "taxon_col_id",
               "taxon_resolution_status", "taxon_rank", "genus", "specific_epithet",
               "infraspecific_epithet", "infraspecific_rank", "taxonomic_status",
               "kingdom", "phylum", "class", "order", "family", "gbif_taxon_key",
               "ncbi_taxid", "gbif_match_type", "taxonomy_backbone_version",
               "phylo_tip_label", "ott_id_matched", "evolutionary_distinctiveness",
               "nearest_neighbour", "iucn_category", "iucn_assessment_year",
               "cites_appendix", "id_date")
rm_taxo <- intersect(TAXO_COLS, names(samp))
if (length(rm_taxo)) samp[, (rm_taxo) := NULL]
cat("  Taxonomic columns removed:", length(rm_taxo), "\n")

# ==============================================================================
# 7. Summary, conflicts, save
# ==============================================================================
na_after <- sapply(samp, function(x) sum(is.na(x)))
summary_dt <- data.table(column    = names(na_after),
                         NA_before = unname(na_before[names(na_after)]),
                         NA_after  = unname(na_after))
summary_dt[is.na(NA_before), NA_before := nrow(samp)]
summary_dt[, filled := NA_before - NA_after]

cat("\n===== SUMMARY (modified columns) =====\n")
print(summary_dt[filled != 0][order(-filled)], nrow = 100)

cat("\n===== COLUMNS STILL INCOMPLETE =====\n")
left <- summary_dt[NA_after > 0][, pct_NA := round(100 * NA_after / nrow(samp))][order(-pct_NA)]
print(left[, .(column, NA_after, pct_NA)], nrow = 100)

conf   <- rbindlist(conflicts, fill = TRUE)
f_conf <- F_CONF
if (nrow(conf)) {
  fwrite(conf, f_conf)
  cat("\nConflicts (sampling values kept):", nrow(conf), "->", basename(f_conf), "\n")
  print(conf[, .N, by = .(column, source)])
} else {
  if (file.exists(f_conf)) file.remove(f_conf)
  cat("\nNo conflict.\n")
}

fwrite(samp, F_SAMP)
cat("\nSaved:", F_SAMP, "(", nrow(samp), "rows x", ncol(samp), "columns )\n")