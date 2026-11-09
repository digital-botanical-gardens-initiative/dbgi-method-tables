# ==============================================================================
# 02_sampling_metadata.R — sampling + analytical LC-MS metadata
#
# Per-garden values are read from 02_sampling/garden_defaults.R, no interactive question.
#
# INPUT  : BASE_DIR/metadata_all_merged.csv   (bloc 00 — already contains garden,
#          instrument_model, extraction_method, Ionization_mode, lat/lon,
#          taxon_scientific_name, collection_date, sample_type, ...)
#          02_sampling/batch_mzmine/*.mzbatch  (MZmine batch files)
#          No dependency on bloc 01: taxonomy is NOT joined here.
# OUTPUT : 02_sampling/output/sampling_metadata.csv   (one row per mzML file)
#
# INCREMENTAL: files (sample_id + mzml_filename) already in the output are kept
# as they are; only the missing ones are added. FORCE_ALL <- TRUE in 02_inst.r
# rebuilds everything (needed after changing garden_defaults.R).
#
# Per-garden values (absent from the merged CSV), in 02_sampling/garden_defaults.R:
#   - LC details (column, gradient, flow, solvents...)
#   - MS details (CE, DDA parameters, AGC targets, gases...)
#   - preservation / extraction / transport / grinding
#   - QC, MassIVE accession, batch_id
#   - MZmine parameters (parsed from the .mzbatch files)
# ==============================================================================

library(dplyr)
library(xml2)

if (!exists("BASE_DIR"))  BASE_DIR  <- "."
if (!exists("FORCE_ALL")) FORCE_ALL <- FALSE
`%||%` <- function(a, b) if (!is.null(a) && length(a) > 0 && !is.na(a[[1]])) a[[1]] else b

STEP_DIR   <- file.path(BASE_DIR, "02_sampling")
OUT_DIR    <- file.path(STEP_DIR, "output")
dir.create(OUT_DIR, showWarnings = FALSE, recursive = TRUE)
INPUT_CSV  <- file.path(BASE_DIR, "metadata_all_merged.csv")
OUTPUT_CSV <- file.path(OUT_DIR, "sampling_metadata.csv")
# former name of the output: renamed once so the incremental mode keeps working
OLD_CSV    <- file.path(OUT_DIR, "sampling_metadata_filled.csv")
if (!file.exists(OUTPUT_CSV) && file.exists(OLD_CSV)) {
  file.rename(OLD_CSV, OUTPUT_CSV)
  cat("  Renamed", basename(OLD_CSV), "->", basename(OUTPUT_CSV), "\n")
}
BATCH_DIR  <- file.path(STEP_DIR, "batch_mzmine")
DEFAULTS_R <- file.path(STEP_DIR, "garden_defaults.R")
if (!file.exists(INPUT_CSV))  stop("Run bloc 00 first: ", INPUT_CSV, " not found")
if (!file.exists(DEFAULTS_R)) stop("garden_defaults.R not found: ", DEFAULTS_R)

# ------------------------------------------------------------------------------
# MZmine batch parser: extracts the key processing parameters
# ------------------------------------------------------------------------------
parse_mzbatch <- function(path) {
  if (is.na(path) || !file.exists(path)) return(list())
  xml   <- read_xml(path)
  root  <- xml_root(xml)
  steps <- xml_find_all(root, "batchstep")

  # batch steps whose "method" attribute contains `s`
  get_step  <- function(s) Filter(function(x) grepl(s, xml_attr(x, "method"), fixed = TRUE), steps)
  # text value of the first parameter called `name`
  get_param <- function(step, name) {
    if (is.null(step)) return(NA_character_)             # step absent from this batch
    n <- xml_find_all(step, sprintf(".//parameter[@name='%s']", name))
    if (!length(n)) return(NA_character_)
    trimws(xml_text(n[[1]]))
  }
  # noise level of the selected mass detector
  get_noise <- function(s) {
    det <- xml_find_first(s, ".//parameter[@name='Mass detector']")
    if (is.na(det)) return(NA_character_)
    sel <- xml_attr(det, "selected_item")
    for (m in xml_find_all(det, "module"))
      if (xml_attr(m, "name") == sel)
        for (p in xml_find_all(m, "parameter"))
          if (grepl("Noise factor|Noise level", xml_attr(p, "name")))
            return(trimws(xml_text(p)))
    NA_character_
  }
  # m/z tolerance (absolute Da + ppm)
  get_tol <- function(step) {
    tol <- xml_find_first(step, ".//parameter[contains(@name,'m/z tolerance')]")
    if (is.na(tol)) return(list(abs = NA_character_, ppm = NA_character_))
    list(abs = trimws(xml_text(xml_find_first(tol, "absolutetolerance"))),
         ppm = trimws(xml_text(xml_find_first(tol, "ppmtolerance"))))
  }

  ms  <- get_step("featdet_massdetection")
  ch  <- { s <- get_step("featdet_adapchromatogrambuilder"); if (length(s)) s[[1]] else NULL }
  res <- { s <- get_step("minimumsearch.MinimumSearchFeatureResolverModule"); if (length(s)) s[[1]] else NULL }
  aln <- { s <- get_step("align_join.JoinAlignerModule"); if (length(s)) s[[1]] else NULL }

  rt_node <- if (!is.null(ch)) xml_find_first(ch, ".//parameter[@name='Retention time']") else NA
  ct <- if (!is.null(ch))  get_tol(ch)  else list(abs = NA_character_, ppm = NA_character_)
  at <- if (!is.null(aln)) get_tol(aln) else list(abs = NA_character_, ppm = NA_character_)

  list(
    mzmine_version   = xml_attr(root, "mzmine_version"),
    ms1_detector     = if (length(ms) >= 1) xml_attr(xml_find_first(ms[[1]], ".//parameter[@name='Mass detector']"), "selected_item") else NA,
    ms1_noise        = as.numeric(if (length(ms) >= 1) get_noise(ms[[1]]) else NA),
    ms2_noise        = as.numeric(if (length(ms) >= 2) get_noise(ms[[2]]) else NA),
    chrom_mz_abs_da  = as.numeric(ct$abs),
    chrom_mz_ppm     = as.numeric(ct$ppm),
    chrom_min_height = as.numeric(get_param(ch, "Minimum absolute height")),
    chrom_min_scans  = as.integer(get_param(ch, "Minimum consecutive scans")),
    rt_range         = if (!is.na(rt_node)) paste0(trimws(xml_text(xml_find_first(rt_node, "min"))), "-",
                                                   trimws(xml_text(xml_find_first(rt_node, "max"))), " min") else NA,
    resolver_thresh  = as.numeric(get_param(res, "Chromatographic threshold")),
    resolver_min_h   = as.numeric(get_param(res, "Minimum absolute height")),
    align_mz_abs_da  = as.numeric(at$abs),
    align_mz_ppm     = as.numeric(at$ppm),
    align_rt_tol_min = as.numeric(get_param(aln, "Retention time tolerance"))
  )
}

# ------------------------------------------------------------------------------
# MZmine batch files (02_sampling/batch_mzmine/) + parsing
# ------------------------------------------------------------------------------
batch_file <- function(pattern) {
  f <- list.files(BATCH_DIR, pattern = pattern, full.names = TRUE, ignore.case = TRUE)
  if (length(f)) f[1] else NA_character_
}
# Reference batch per garden: used ONLY for files that are not listed in any
# batch of BATCH_DIR (see FILE2BATCH below: each mzML file gets the parameters
# of the batch that actually processed it -> JBUF Plus/HF-X x pos/neg and the
# 3 JBP batches are split correctly).
MZBATCH_PATHS <- list(
  JBN  = batch_file("^JBN_batch.*\\.mzbatch$"),
  JBC  = batch_file("^JBC_batch.*\\.mzbatch$"),
  JBP  = batch_file("^dbgi_JBP_batch\\.mzbatch$"),      # also dbgi_JBP_batch104/105_batch
  JBUF = batch_file("^JBF_plus_pos.*\\.mzbatch$"),      # also JBF_plus_neg, JBF_HFX_pos/neg
  JBK  = batch_file("^JBK_batch.*\\.mzbatch$")
)

missing_batch <- names(MZBATCH_PATHS)[is.na(unlist(MZBATCH_PATHS))]
if (length(missing_batch) == length(MZBATCH_PATHS))
  stop("No .mzbatch file found in ", BATCH_DIR)
if (length(missing_batch))
  warning(".mzbatch missing for: ", paste(missing_batch, collapse = ", "),
          " — MZmine parameters empty for these gardens")

cat("=== Parsing MZmine batch files ===\n")
MZBATCH_PARAMS <- setNames(lapply(names(MZBATCH_PATHS), function(g) {
  cat(sprintf("  [%s] %s\n", g, MZBATCH_PATHS[[g]]))
  parse_mzbatch(MZBATCH_PATHS[[g]])
}), names(MZBATCH_PATHS))

# ------------------------------------------------------------------------------
# File -> batch: every .mzbatch of BATCH_DIR is parsed, with the list of mzML
# files it imports. Each file then gets the parameters of ITS batch.
# ------------------------------------------------------------------------------
fn_key <- function(x) tolower(sub("\\.mzml$", "", sub(".*[\\\\/]", "", trimws(x)), ignore.case = TRUE))

batch_mzml <- function(path) {
  x <- read_xml(path)
  n <- xml_find_all(x, "//batchstep[contains(@method,'import_rawdata')]//parameter[@name='File names']/file")
  sub(".*[\\\\/]", "", trimws(xml_text(n)))           # original file names (case kept)
}

ALL_BATCHES <- list.files(BATCH_DIR, pattern = "\\.mzbatch$", full.names = TRUE, ignore.case = TRUE)
ALL_PARAMS  <- setNames(lapply(ALL_BATCHES, parse_mzbatch), ALL_BATCHES)
FILE2BATCH  <- do.call(rbind, lapply(ALL_BATCHES, function(b) {
  f <- batch_mzml(b)
  if (length(f)) data.frame(fn = fn_key(f), file = f, batch = b, stringsAsFactors = FALSE) else NULL
}))
if (is.null(FILE2BATCH)) FILE2BATCH <- data.frame(fn = character(), file = character(), batch = character())
dup_fn <- unique(FILE2BATCH$fn[duplicated(FILE2BATCH$fn)])
if (length(dup_fn))
  warning(length(dup_fn), " mzML file(s) listed in several batches (first batch kept), e.g. ",
          paste(head(dup_fn, 3), collapse = ", "))
FILE2BATCH <- FILE2BATCH[!duplicated(FILE2BATCH$fn), ]
cat("  File -> batch map:", nrow(FILE2BATCH), "mzML files in", length(ALL_BATCHES), "batches\n")
for (b in ALL_BATCHES)
  cat(sprintf("    %-40s %4d files\n", basename(b), sum(FILE2BATCH$batch == b)))

# MZmine columns of one row, from the parsed parameters of a batch
mz_cols <- function(p, path) list(
  mzbatch_path            = path,
  mzmine_version          = p$mzmine_version   %||% NA_character_,
  ms1_detector            = p$ms1_detector     %||% NA_character_,
  mzmine_noise_ms1        = p$ms1_noise        %||% NA_real_,
  mzmine_noise_ms2        = p$ms2_noise        %||% NA_real_,
  chrom_mz_abs_da         = p$chrom_mz_abs_da  %||% NA_real_,
  chrom_mz_ppm            = p$chrom_mz_ppm     %||% NA_real_,
  chrom_min_height        = p$chrom_min_height %||% NA_real_,
  chrom_min_scans         = p$chrom_min_scans  %||% NA_integer_,
  rt_range                = p$rt_range         %||% NA_character_,
  resolver_thresh         = p$resolver_thresh  %||% NA_real_,
  resolver_min_h          = p$resolver_min_h   %||% NA_real_,
  align_mz_abs_da         = p$align_mz_abs_da  %||% NA_real_,
  align_mz_ppm            = p$align_mz_ppm     %||% NA_real_,
  align_rt_tol_min        = p$align_rt_tol_min %||% NA_real_,
  mz_tol_scan_to_scan     = if (!is.null(p$chrom_mz_abs_da) && !is.na(p$chrom_mz_abs_da))
    sprintf("%.4f Da / %.1f ppm", p$chrom_mz_abs_da, p$chrom_mz_ppm) else NA_character_,
  mz_tol_sample_to_sample = if (!is.null(p$align_mz_abs_da) && !is.na(p$align_mz_abs_da))
    sprintf("%.4f Da / %.1f ppm", p$align_mz_abs_da, p$align_mz_ppm) else NA_character_,
  processing_params_file  = basename(path)
)

# ------------------------------------------------------------------------------
# GARDEN DEFAULTS — only what is NOT in the merged CSV
# (preservation, detailed LC, detailed MS, QC, MassIVE)
# Stored as configuration in 02_sampling/garden_defaults.R (creates GARDEN_DEFAULTS)
# ------------------------------------------------------------------------------
source(DEFAULTS_R, local = TRUE, encoding = "UTF-8")
stopifnot("garden_defaults.R must create GARDEN_DEFAULTS" = exists("GARDEN_DEFAULTS"))


# Inject the parsed MZmine parameters into each garden
for (g in names(GARDEN_DEFAULTS)) {
  p <- MZBATCH_PARAMS[[g]]
  if (length(p) == 0) next
  GARDEN_DEFAULTS[[g]] <- modifyList(GARDEN_DEFAULTS[[g]], list(
    mzmine_version          = p$mzmine_version,
    ms1_detector            = p$ms1_detector,
    mzmine_noise_ms1        = p$ms1_noise,
    mzmine_noise_ms2        = p$ms2_noise,
    chrom_mz_abs_da         = p$chrom_mz_abs_da,
    chrom_mz_ppm            = p$chrom_mz_ppm,
    chrom_min_height        = p$chrom_min_height,
    chrom_min_scans         = p$chrom_min_scans,
    rt_range                = p$rt_range,
    resolver_thresh         = p$resolver_thresh,
    resolver_min_h          = p$resolver_min_h,
    align_mz_abs_da         = p$align_mz_abs_da,
    align_mz_ppm            = p$align_mz_ppm,
    align_rt_tol_min        = p$align_rt_tol_min,
    processing_params_file  = basename(MZBATCH_PATHS[[g]]),
    mz_tol_scan_to_scan     = if (isTRUE(!is.na(p$chrom_mz_abs_da)))
      sprintf("%.4f Da / %.1f ppm", p$chrom_mz_abs_da, p$chrom_mz_ppm) else NA_character_,
    mz_tol_sample_to_sample = if (isTRUE(!is.na(p$align_mz_abs_da)))
      sprintf("%.4f Da / %.1f ppm", p$align_mz_abs_da, p$align_mz_ppm) else NA_character_
  ))
}

cat("=== Garden defaults ready ===\n")
for (g in names(GARDEN_DEFAULTS)) {
  d <- GARDEN_DEFAULTS[[g]]
  cat(sprintf("  [%s] MZmine %s | MS1 noise=%s | MS2 noise=%s\n",
              g, d$mzmine_version %||% "NA", d$mzmine_noise_ms1 %||% "NA", d$mzmine_noise_ms2 %||% "NA"))
}

# ------------------------------------------------------------------------------
# Injection date from the file name -> YYYY-MM-DD
#   "20260327_..."  YYYYMMDD (JBP, JBUF)
#   "20262605_..."  YYYYDDMM (JBC: "month" > 12 -> swapped)
#   "250402_ML_..." YYMMDD   (JBN, Synapt)
# ------------------------------------------------------------------------------
parse_injection_date <- function(fn) {
  fn <- basename(coalesce(fn, ""))
  vapply(fn, function(v) {
    if (grepl("^[0-9]{8}", v)) {
      y <- substr(v, 1, 4); a <- substr(v, 5, 6); b <- substr(v, 7, 8)
      if (as.integer(a) > 12) return(paste(y, b, a, sep = "-"))
      return(paste(y, a, b, sep = "-"))
    }
    if (grepl("^[0-9]{6}_", v))
      return(paste0("20", substr(v, 1, 2), "-", substr(v, 3, 4), "-", substr(v, 5, 6)))
    NA_character_
  }, character(1), USE.NAMES = FALSE)
}

# Value from the garden defaults, or NA when the field is not defined
dflt <- function(def, field, na = NA) if (is.null(def[[field]])) na else def[[field]]

# Detailed instrument fields of garden_defaults.R (per-vendor: a garden that does not
# define a field gets NA). Also listed in cols_final so they reach the output.
INSTRUMENT_DETAIL_COLS <- c(
  # instrument / LC
  "instrument_serial", "autosampler_temp_c", "uv_detection",
  # Orbitrap scan settings
  "ms1_resolution", "ms2_resolution", "ms1_agc_target", "ms2_agc_target",
  "ms1_max_inject_ms", "ms2_max_inject_ms", "precursor_isolation_window_mz",
  "dda_cycle_time_s", "expected_peak_width_s",
  # calibration / data type
  "mass_calibration", "internal_calibration", "data_type",
  # ion source - Thermo
  "spray_voltage_kv", "sheath_gas_arb", "aux_gas_arb", "sweep_gas_arb",
  "ion_transfer_tube_c", "vaporizer_temp_c", "rf_lens_pct",
  # ion source - Waters
  "capillary_kv", "source_temp_c", "desolvation_temp_c", "cone_voltage_v",
  "cone_gas_l_h", "desolvation_gas_l_h", "nebuliser_gas_bar",
  # ion source / TOF - SCIEX
  "ion_spray_voltage_kv", "gas_temperature_c", "ion_source_gas1_psi",
  "ion_source_gas2_psi", "curtain_gas_psi", "cad_gas_psi",
  "zeno_pulsing", "zeno_threshold", "q1_resolution"
)

# ------------------------------------------------------------------------------
# Load data
# ------------------------------------------------------------------------------
cat("\n=== LOADING DATA ===\n")
df <- read.csv(INPUT_CSV, sep = ";", stringsAsFactors = FALSE, na.strings = c("", "NA"))
cat(sprintf("  %d rows (files) in merged\n", nrow(df)))
# Rows without file name (e.g. Kew: not in MassIVE yet): the mzML file is looked up
# in the MZmine batches, by the sample_id contained in the file name
# (20251006_11_dbgi_010669_01_01_1uL.mzML -> dbgi_010669)
no_file <- is.na(df$filename) | trimws(df$filename) == ""
# Only batches whose files are NOT already named in the merged CSV are searched
# (JBK_batch), so a sample can't be matched to a file of another garden.
known_fn  <- fn_key(df$filename[!is.na(df$filename)])
free_b    <- setdiff(unique(FILE2BATCH$batch), unique(FILE2BATCH$batch[FILE2BATCH$fn %in% known_fn]))
cand      <- FILE2BATCH[FILE2BATCH$batch %in% free_b, ]
if (any(no_file) && nrow(cand)) {
  cat("  Batches searched for missing file names:", paste(basename(free_b), collapse = ", "), "\n")
  sid_in_fn <- toupper(sub(".*(dbgi_[0-9]{6}).*", "\\1", cand$fn))
  sid_in_fn[!grepl("dbgi_[0-9]{6}", cand$fn)] <- NA
  # output = one row per mzML file: a sample injected several times (re-injection)
  # gets one row per file (the sample row is duplicated)
  rows_nf <- which(no_file)
  hits    <- lapply(toupper(df$sample_id[rows_nf]), function(s) cand$file[which(sid_in_fn == s)])
  n_files <- lengths(hits)
  has     <- n_files > 0
  for (r in which(has)) df$filename[rows_nf[r]] <- hits[[r]][1]
  multi <- which(n_files > 1)
  if (length(multi)) {
    extra <- do.call(rbind, lapply(multi, function(r) {
      x <- df[rep(rows_nf[r], n_files[r] - 1), , drop = FALSE]
      x$filename <- hits[[r]][-1]
      x
    }))
    df <- rbind(df, extra)
    cat("  Samples injected several times (one row per file):",
        paste(df$sample_id[rows_nf[multi]], collapse = ", "), "\n")
  }
  cat(sprintf("  File name recovered from the MZmine batches for %d samples / %d files (%s)\n",
              sum(has), sum(n_files),
              paste(unique(df$garden[rows_nf[has]]), collapse = ", ")))
  no_file <- is.na(df$filename) | trimws(df$filename) == ""
}
if (any(no_file)) {
  cat(sprintf("  %d rows without mzML file name (kept, LC-MS fields will stay empty):\n", sum(no_file)))
  print(table(garden = df$garden[no_file], useNA = "ifany"))
}
unknown_g <- setdiff(unique(df$garden), names(GARDEN_DEFAULTS))
if (length(unknown_g))
  cat("  Gardens absent from garden_defaults.R (rows skipped):",
      paste(ifelse(is.na(unknown_g), "NA", unknown_g), collapse = ", "), "\n")

# --- Incremental: keep the files already in the output, process only the others ---
file_key <- function(sid, fn) paste(sid, ifelse(is.na(fn), "", basename(fn)), sep = "|")
existing <- NULL
if (!FORCE_ALL && file.exists(OUTPUT_CSV)) {
  existing <- read.csv(OUTPUT_CSV, stringsAsFactors = FALSE, na.strings = c("", "NA"),
                       colClasses = "character", check.names = FALSE)
  file.copy(OUTPUT_CSV, sub("\\.csv$", paste0("_backup_", format(Sys.time(), "%Y%m%d_%H%M"), ".csv"),
                            OUTPUT_CSV))
  df <- df[!file_key(df$sample_id, df$filename) %in%
             file_key(existing$sample_id, existing$mzml_filename), ]
}
cat(sprintf("  %d files already in %s | %d missing -> processed now\n",
            if (is.null(existing)) 0L else nrow(existing), basename(OUTPUT_CSV), nrow(df)))
if (nrow(df) == 0) {
  cat("  Nothing to do: every file is already in the output.\n")
} else {
gardens_present <- sort(unique(na.omit(df$garden)))
cat(sprintf("  Gardens found: %s\n", paste(gardens_present, collapse = ", ")))

# ------------------------------------------------------------------------------
# Loop over gardens: apply the garden defaults to every file of the garden
# ------------------------------------------------------------------------------
results <- list()
for (g in gardens_present) {
  if (!g %in% names(GARDEN_DEFAULTS)) {
    warning(sprintf("Garden '%s' has no defaults — skipped", g))
    next
  }
  df_sub <- df %>% filter(garden == g)
  def    <- GARDEN_DEFAULTS[[g]]
  cat(sprintf("\n  [%s] %d files — applying defaults...\n", g, nrow(df_sub)))

  df_sub <- df_sub %>% mutate(
    # --- Identifiers ---
    mzbatch_path              = MZBATCH_PATHS[[g]],
    mzml_filename             = filename,
    # positive / negative ; garden default (ionization_polarity) if absent from the CSV
    ionization_polarity       = ifelse(is.na(Ionization_mode) & !is.na(filename),
                                       dflt(def, "ionization_polarity", NA_character_),
                                       tolower(Ionization_mode)),

    # --- Fields absent from the CSV (filled later by 02_sampling_correction.R) ---
    plant_part                = NA_character_,
    po_term_id                = NA_character_,
    phenology                 = NA_character_,
    developmental_stage       = NA_character_,
    n_individuals_pooled      = 1L,
    pathogen_visible          = NA_character_,
    fresh_weight_g            = NA_real_,
    time_to_preservation_min  = NA_integer_,
    abs_permit_id             = NA_character_,
    extraction_date           = NA_character_,
    dry_weight_mg             = dflt(def, "dry_weight_mg", NA_real_),
    extraction_volume_ml      = dflt(def, "extraction_volume_ml", NA_real_),
    extraction_method_id      = NA_character_,
    extraction_batch          = NA_character_,
    uuid_extraction           = NA_character_,
    extraction_ratio_mg_per_ml = NA_real_,

    # --- Fixed fields ---
    data_license              = "CC0",
    geodetic_datum            = "WGS84 / EPSG:4326",
    coordinate_uncertainty_m  = 1L,

    # --- Identification ---
    collector_full_name       = dflt(def, "collector_full_name", NA_character_),
    identification_method     = def$identification_method,
    identification_confidence = def$identification_confidence,

    # --- Preservation & extraction ---
    preservation_method       = def$preservation_method,
    transport_conditions      = def$transport_conditions,
    storage_temp_c            = def$storage_temp_c,
    storage_duration_d        = def$storage_duration_d,
    grinding_method           = def$grinding_method,
    extraction_solvent        = def$extraction_solvent,
    extraction_conditions     = def$extraction_conditions,
    extraction_operator       = def$extraction_operator,
    extract_storage           = def$extract_storage,

    # --- LC ---
    lc_vendor                 = def$lc_vendor,
    lc_model                  = def$lc_model,
    chromatography_type       = def$chromatography_type,
    column_name               = def$column_name,
    stationary_phase          = def$stationary_phase,
    column_temp_c             = def$column_temp_c,
    mobile_phase_a            = def$mobile_phase_a,
    mobile_phase_b            = def$mobile_phase_b,
    gradient_program          = def$gradient_program,
    flow_rate_ml_min          = def$flow_rate_ml_min,
    injection_volume_ul       = def$injection_volume_ul,
    sample_dilution           = dflt(def, "sample_dilution", NA_character_),
    run_time_min              = def$run_time_min,
    lc_software               = def$lc_software,

    # --- MS (instrument_model comes from the CSV) ---
    mass_analyzer             = def$mass_analyzer,
    ionization_source         = def$ionization_source,
    acquisition_mode          = def$acquisition_mode,
    fragmentation_method      = def$fragmentation_method,
    collision_energy          = def$collision_energy,
    mass_range_mz             = def$mass_range_mz,
    ms_scan_time_s            = def$ms_scan_time_s,
    msms_scan_time_s          = def$msms_scan_time_s,
    dda_top_n                 = def$dda_top_n,
    ms2_intensity_threshold_cps = def$ms2_intensity_threshold_cps,
    dynamic_exclusion_s       = def$dynamic_exclusion_s,
    background_exclusion      = def$background_exclusion,
    mass_accuracy_ppm         = def$mass_accuracy_ppm,
    raw_conversion_tool       = def$raw_conversion_tool,
    centroided                = def$centroided,

    # --- MZmine parameters (parsed from .mzbatch; NA if no batch file) ---
    mzmine_version            = dflt(def, "mzmine_version", NA_character_),
    ms1_detector              = dflt(def, "ms1_detector", NA_character_),
    mzmine_noise_ms1          = dflt(def, "mzmine_noise_ms1", NA_real_),
    mzmine_noise_ms2          = dflt(def, "mzmine_noise_ms2", NA_real_),
    chrom_mz_abs_da           = dflt(def, "chrom_mz_abs_da", NA_real_),
    chrom_mz_ppm              = dflt(def, "chrom_mz_ppm", NA_real_),
    chrom_min_height          = dflt(def, "chrom_min_height", NA_real_),
    chrom_min_scans           = dflt(def, "chrom_min_scans", NA_integer_),
    rt_range                  = dflt(def, "rt_range", NA_character_),
    resolver_thresh           = dflt(def, "resolver_thresh", NA_real_),
    resolver_min_h            = dflt(def, "resolver_min_h", NA_real_),
    align_mz_abs_da           = dflt(def, "align_mz_abs_da", NA_real_),
    align_mz_ppm              = dflt(def, "align_mz_ppm", NA_real_),
    align_rt_tol_min          = dflt(def, "align_rt_tol_min", NA_real_),
    mz_tol_scan_to_scan       = dflt(def, "mz_tol_scan_to_scan", NA_character_),
    mz_tol_sample_to_sample   = dflt(def, "mz_tol_sample_to_sample", NA_character_),
    processing_software       = def$processing_software,
    processing_params_file    = dflt(def, "processing_params_file", NA_character_),

    # --- QC & batch ---
    qc_sample_type            = def$qc_sample_type,
    qc_conditioning_n         = def$qc_conditioning_n,
    qc_frequency              = def$qc_frequency,
    randomization             = def$randomization,
    internal_standard         = def$internal_standard,
    massive_accession         = def$massive_accession,
    batch_id                  = def$batch_id,
    injection_date            = parse_injection_date(filename)
  )

  # Detailed instrument fields (checked in the raw files with extract_methods.py):
  # taken from garden_defaults.R when the garden defines them, NA otherwise
  for (f in INSTRUMENT_DETAIL_COLS) df_sub[[f]] <- dflt(def, f, NA)

  # instrument_model: from the merged CSV, garden default when empty
  if (!"instrument_model" %in% names(df_sub)) df_sub$instrument_model <- NA_character_
  im_na <- is.na(df_sub$instrument_model) | trimws(df_sub$instrument_model) == ""
  if (any(im_na) && !is.na(dflt(def, "instrument_model", NA_character_)))
    df_sub$instrument_model[im_na] <- def$instrument_model

  # Per-instrument overrides (garden_defaults.R -> INSTRUMENT_OVERRIDES), e.g. the
  # Fribourg HF-X injected 1 uL while the Q Exactive Plus injected 2 uL
  if (exists("INSTRUMENT_OVERRIDES") && "instrument_model" %in% names(df_sub)) {
    for (o in Filter(function(o) identical(o$garden, g), INSTRUMENT_OVERRIDES)) {
      rows <- which(grepl(o$pattern, df_sub$instrument_model, ignore.case = TRUE))
      if (!length(rows)) next
      for (f in names(o$values)) {
        if (!f %in% names(df_sub)) df_sub[[f]] <- NA
        df_sub[[f]][rows] <- o$values[[f]]
      }
      cat(sprintf("    Instrument override [%s]: %d files -> %s\n", o$pattern, length(rows),
                  paste(names(o$values), "=", unlist(o$values), collapse = ", ")))
    }
  }

  # MZmine parameters of the batch that actually processed each file
  # (garden reference batch kept for files absent from every batch)
  b_file <- FILE2BATCH$batch[match(fn_key(df_sub$filename), FILE2BATCH$fn)]
  for (b in unique(na.omit(b_file))) {
    rows <- which(b_file == b)
    vals <- mz_cols(ALL_PARAMS[[b]], b)
    for (cl in names(vals)) df_sub[[cl]][rows] <- vals[[cl]]
  }
  cat(sprintf("    MZmine parameters: %d files from their own batch (%s) | %d from the reference batch (or none)\n",
              sum(!is.na(b_file)),
              paste(unique(basename(na.omit(b_file))), collapse = ", "),
              sum(is.na(b_file))))
  results[[g]] <- df_sub
}

# ------------------------------------------------------------------------------
# Merge gardens (NO taxonomy here: step 02 is independent of step 01; the
# resolved taxonomy lives in taxonomy_metadata.csv and is joined in step 04.
# Only the field name taxon_scientific_name is kept as identification trace.)
# ------------------------------------------------------------------------------
cat("\n=== MERGING ===\n")
meta <- bind_rows(results)
n_before <- nrow(meta)
meta <- distinct(meta)                      # one row per mzML file
cat(sprintf("  Exact duplicates removed: %d\n", n_before - nrow(meta)))

# ------------------------------------------------------------------------------
# Column order + export
# ------------------------------------------------------------------------------
cols_final <- c(
  # Identifiers
  "sample_id", "mzml_filename", "sample_type", "mzbatch_path", "batch_id", "injection_date",
  "collection_event_id",
  # Field identification
  "taxon_scientific_name",
  "identified_by", "collector_full_name", "collector_orcid", "inat_observation", "catalogue_number",
  "identification_method", "identification_confidence", "herbarium_code",
  # Place & date
  "event_date", "collection_date", "latitude", "longitude",
  "coordinate_uncertainty_m", "geodetic_datum", "locality", "habitat",
  "establishment_means", "country_code", "herbivory_percent",
  # Plant & organ
  "plant_part", "po_term_id", "n_individuals_pooled", "herbivory_damage",
  # Preservation & extraction
  "preservation_method", "transport_conditions", "storage_temp_c", "grinding_method",
  "dry_weight_mg", "extraction_volume_ml", "extraction_method_id", "extraction_batch",
  "uuid_extraction", "extraction_solvent", "extraction_ratio_mg_per_ml",
  "extraction_conditions", "extraction_operator", "extract_storage",
  # LC
  "lc_vendor", "lc_model", "chromatography_type", "column_name", "stationary_phase",
  "column_temp_c", "mobile_phase_a", "mobile_phase_b", "gradient_program",
  "flow_rate_ml_min", "injection_volume_ul", "sample_dilution", "run_time_min", "lc_software",
  # MS
  "instrument_model", "ms_vendor", "mass_analyzer", "ionization_source",
  "ionization_polarity", "acquisition_mode", "fragmentation_method", "collision_energy",
  "mass_range_mz", "ms_scan_time_s", "msms_scan_time_s", "dda_top_n",
  "ms2_intensity_threshold_cps", "dynamic_exclusion_s", "background_exclusion",
  "mass_accuracy_ppm",
  # Detailed instrument settings (per vendor; NA where not applicable)
  INSTRUMENT_DETAIL_COLS,
  # Raw conversion
  "raw_conversion_tool", "centroided",
  # MZmine processing
  "mzmine_version", "ms1_detector", "mzmine_noise_ms1", "mzmine_noise_ms2",
  "chrom_mz_abs_da", "chrom_mz_ppm", "chrom_min_height", "chrom_min_scans",
  "rt_range", "resolver_thresh", "resolver_min_h",
  "align_mz_abs_da", "align_mz_ppm", "align_rt_tol_min",
  "mz_tol_scan_to_scan", "mz_tol_sample_to_sample",
  "processing_software", "processing_params_file",
  # QC
  "qc_sample_type", "qc_conditioning_n", "qc_frequency", "randomization",
  # Deposition, licence, garden
  "massive_accession", "data_license", "garden", "dataset"
)
meta_out <- meta[, intersect(cols_final, names(meta))]
# new files appended to the existing ones (existing rows untouched)
if (!is.null(existing))
  meta_out <- bind_rows(existing, mutate(meta_out, across(everything(), as.character)))
write.csv(meta_out, OUTPUT_CSV, row.names = FALSE, fileEncoding = "UTF-8", na = "")

# ------------------------------------------------------------------------------
# Completion report
# ------------------------------------------------------------------------------
cat("\n=== COMPLETION REPORT ===\n")
for (col in names(meta_out)) {
  pct  <- round(100 * mean(!is.na(meta_out[[col]]) & meta_out[[col]] != ""))
  flag <- if (pct == 100) "[OK    ]" else if (pct >= 80) "[~OK   ]" else "[BLANK ]"
  cat(sprintf("  %s %-45s : %3d%%\n", flag, col, pct))
}
cat(sprintf("\n=== DONE: %d files | %s ===\n", nrow(meta_out), OUTPUT_CSV))

}   # end of "missing files" block