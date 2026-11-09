# ==============================================================================
# build_final_table.R — DBGI final metadata table (one row per MS file)
#
# Builds the final table of the DBGI method system in two versions:
#   A. every column of the MS file points to a sub-table (86 numeric columns)
#   B. the MS file points to 6 method codes (I, S, D, E, L, P); the method tables
#      point to the sub-tables
# See README.md for the full description of input, process and output.
#
# Run:   BASE_DIR <- "path/to/dbgi_methods"; source(file.path(BASE_DIR, "src/build_final_table.R"))
# Input: BASE_DIR/input/ + step 02 output (sampling_metadata.csv, path in IN_CSV)
# Output: BASE_DIR/output/
# ==============================================================================

library(data.table)
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0 || is.na(a[1])) b else a

if (!exists("BASE_DIR")) BASE_DIR <- "."
# MS files (output of step 02). Default: input/sampling_metadata.csv.
# Set IN_CSV before sourcing the script to read another file.
step02_out <- file.path(BASE_DIR, "02_sampling", "output", "sampling_metadata.csv")
if (!exists("IN_CSV")) IN_CSV <- if (exists("FINAL_INPUT")) FINAL_INPUT else
                                 if (file.exists(step02_out)) step02_out else      # real step 02 output
                                 file.path(BASE_DIR, "input", "sampling_metadata.csv")   # shipped extract
if (!file.exists(IN_CSV)) stop("MS file table not found: ", IN_CSV)
IN_DIR  <- file.path(BASE_DIR, "input")
OUT_DIR <- file.path(BASE_DIR, "output")
dir.create(OUT_DIR, showWarnings = FALSE, recursive = TRUE)

rd  <- function(...) fread(file.path(IN_DIR, ...), colClasses = "character", na.strings = c("", "NA"))
low <- function(x) tolower(trimws(as.character(x)))

meth <- list(I = rd("method_tables", "identification_methods.csv"), S = rd("method_tables", "sampling_methods.csv"),
             D = rd("method_tables", "drying_methods.csv"),          E = rd("method_tables", "extraction_methods.csv"),
             L = rd("method_tables", "lcms_methods.csv"),            P = rd("method_tables", "processing_methods.csv"))
batches <- rd("config", "dbgi_batches.csv")
cols    <- rd("config", "final_table_columns.csv")
STEP_OF <- c("1. Identification" = "I", "2. Sampling" = "S", "3. Lab drying" = "D",
             "4. Extraction" = "E", "5. LC-MS" = "L", "6. Data processing" = "P")
ID_COL  <- c(I = "identification_method_id", S = "sampling_method_id", D = "drying_method_id",
             E = "extraction_method_id", L = "lcms_method_id", P = "processing_method_id")
L_IDS   <- sub(" .*", "", grep("^L[0-9]+ ", names(meth$L), value = TRUE))        # "L1 · Synapt XS" -> L1
L_INSTR <- sub("^L[0-9]+ · ", "", grep("^L[0-9]+ ", names(meth$L), value = TRUE))

# ------------------------------------------------------------------------------
# Read the MS files
# ------------------------------------------------------------------------------
f <- fread(IN_CSV, colClasses = "character", na.strings = c("", "NA"))
for (cl in c("batch_id", "instrument_model", "extraction_method_id", "identification_method",
             "preservation_method", "raw_conversion_tool", "collector_full_name", "plant_part", "garden"))
  if (!cl %in% names(f)) f[, (cl) := NA_character_]
f[, extraction_method_id := sub("\\.0$", "", extraction_method_id)]
cat("MS files:", nrow(f), "\n")
unmatched <- list()
note <- function(i, what, value) if (length(i))
  unmatched[[length(unmatched) + 1]] <<- data.table(sample_id = f$sample_id[i], mzml_filename = f$mzml_filename[i],
                                                    garden = f$garden[i], what = what, value = value[i])

# ------------------------------------------------------------------------------
# a. Method codes
# ------------------------------------------------------------------------------
# batch defaults (Fribourg HF-X has its own row)
b_key <- f$batch_id
b_key[grepl("HF-?X", f$instrument_model, ignore.case = TRUE) & f$garden == "JBUF"] <- "JBUF_hfx"
b <- batches[match(b_key, batches$batch_id)]
nb <- which(is.na(b$batch_id))
if (length(nb)) {                                   # unknown batch: first batch of the garden
  g <- batches[match(f$garden[nb], batches$garden)]
  b[nb] <- g
  note(nb, "batch not in dbgi_batches.csv (garden default used)", f$batch_id)
}
ids <- data.table(I = b$identification_method_id, S = b$sampling_method_id, D = b$drying_method_id,
                  E = b$extraction_method_id, L = b$lcms_method_id, P = b$processing_method_id)

# matched from the file itself
by_value <- function(tab, col, x) tab[[1]][match(low(x), low(tab[[col]]))]
v <- by_value(meth$I, "identification_method", f$identification_method); ids[!is.na(v), I := v[!is.na(v)]]
v <- by_value(meth$S, "preservation_method",   f$preservation_method);   ids[!is.na(v), S := v[!is.na(v)]]
v <- meth$P$processing_method_id[match(low(sub(" \\(.*", "", f$raw_conversion_tool)),
                                       low(sub(" \\(.*", "", meth$P$raw_conversion_tool)))]
ids[!is.na(v), P := v[!is.na(v)]]
v <- L_IDS[match(low(sub(" \\(.*", "", f$instrument_model)), low(L_INSTR))]
ids[!is.na(v), L := v[!is.na(v)]]
note(which(is.na(v) & !is.na(f$instrument_model)), "instrument not in lcms_methods.csv", f$instrument_model)

# extraction: Directus is the reference
e_code <- sub(" .*", "", meth$E$directus_extraction_method)
for (i in which(!is.na(f$extraction_method_id))) {
  cand <- meth$E$extraction_method_id[e_code == f$extraction_method_id[i]]
  if (!length(cand)) next
  if (!ids$E[i] %in% cand) ids$E[i] <- cand[1]
}
note(which(!is.na(f$extraction_method_id) & !f$extraction_method_id %in% e_code),
     "Directus extraction method not in extraction_methods.csv", f$extraction_method_id)
setnames(ids, ID_COL[names(ids)])

# ------------------------------------------------------------------------------
# b. Final table: every column from the method table of its step
# ------------------------------------------------------------------------------
value_of <- function(step, key, code) {
  t <- meth[[step]]
  if (step == "L") {                                  # LC-MS table: one row per parameter
    r <- which(t$parameter == key)
    if (!length(r)) return(rep(NA_character_, length(code)))
    vals <- unlist(t[r[1], grep("^L[0-9]+ ", names(t), value = TRUE), with = FALSE])
    return(unname(vals[match(code, L_IDS)]))
  }
  if (!key %in% names(t)) return(rep(NA_character_, length(code)))
  t[[key]][match(code, t[[1]])]
}

out   <- f[, .(sample_id, mzml_filename, garden, batch_id)]
out   <- cbind(out, ids)
codes <- copy(out)
# columns that differ between files of the same method (read from the file itself)
FILE_COLS <- c("ionization_polarity")
directus_val <- list(garden_id = f$garden, collector = f$collector_full_name,
                     observation_subject = f$plant_part, extraction_method = ids$extraction_method_id)
for (k in seq_len(nrow(cols))) {
  key <- cols$column[k]; step <- STEP_OF[cols$step[k]]
  val <- if (!is.na(step)) value_of(step, key, ids[[ID_COL[[step]]]]) else directus_val[[key]]
  if (is.null(val)) val <- rep(NA_character_, nrow(f))
  if (key %in% FILE_COLS && key %in% names(f))          # varies per file: the file wins
    val <- ifelse(is.na(f[[key]]), val, low(f[[key]]))
  val[val %in% c("", "n/a")] <- NA
  set(out, j = key, value = val)
  vf <- file.path(IN_DIR, "sub_tables", paste0(cols$vocabulary[k], "_sheet.csv"))
  cv <- if (key == "extraction_method") val else if (file.exists(vf)) { voc <- fread(vf, colClasses = "character"); hit <- voc$id[match(low(val), low(voc[[2]]))]          # value column
         for (vc in setdiff(names(voc), c("id", names(voc)[2], "description", "details")))   # e.g. person full_name
           hit[is.na(hit)] <- voc$id[match(low(val[is.na(hit)]), low(voc[[vc]]))]
         hit } else val
  set(codes, j = key, value = cv)
  miss <- which(!is.na(val) & is.na(cv))
  note(miss, paste0("value not in vocabulary '", cols$vocabulary[k], "' (", key, ")"), val)
}

# ------------------------------------------------------------------------------
# c. Write the two versions
# ------------------------------------------------------------------------------
# sub-table id of one value of column `key` (NA if the column has no sub-table)
sheet_of <- setNames(cols$vocabulary, cols$column)
sub_id <- function(key, val) {
  vf <- file.path(IN_DIR, "sub_tables", paste0(sheet_of[[key]] %||% key, "_sheet.csv"))
  if (!file.exists(vf)) return(NULL)
  st  <- fread(vf, colClasses = "character")
  hit <- st$id[match(low(val), low(st[[2]]))]
  for (vc in setdiff(names(st), c("id", names(st)[2], "description", "details")))
    hit[is.na(hit)] <- st$id[match(low(val[is.na(hit)]), low(st[[vc]]))]
  hit
}

# VERSION A: every column links to its sub-table
dA <- file.path(OUT_DIR, "version_A_link_to_sub_tables")
dir.create(dA, showWarnings = FALSE, recursive = TRUE)
fwrite(codes[, c("sample_id", "mzml_filename", "garden", cols$column), with = FALSE],
       file.path(dA, "final_table.csv"))

# VERSION B: the MS file links to the 6 method codes; each method table links to the sub-tables
dB <- file.path(OUT_DIR, "version_B_link_to_method_codes")
dir.create(file.path(dB, "method_tables"), showWarnings = FALSE, recursive = TRUE)
per_file <- c("garden_id", "collector", "observation_subject", "ionization_polarity")   # differ inside a method
fwrite(cbind(codes[, c("sample_id", "mzml_filename", "garden", per_file), with = FALSE], ids),
       file.path(dB, "final_table.csv"))

# method tables: words -> sub-table ids (numbers without sub-table, e.g. 0.35 mL/min, stay as they are)
lc <- meth$L                                          # LC-MS: one row per parameter -> one row per method
lw <- data.table(lcms_method_id = L_IDS)
for (r in seq_len(nrow(lc))) {
  p <- lc$parameter[r]; if (is.na(p) || p %in% c("source", "ionization_polarity")) next   # polarity is per file (final table)
  set(lw, j = p, value = unname(unlist(lc[r, grep("^L[0-9]+ ", names(lc), value = TRUE), with = FALSE])))
}
tabs <- list(identification_methods = meth$I, sampling_methods = meth$S, drying_methods = meth$D,
             extraction_methods = meth$E, lcms_methods = lw, processing_methods = meth$P)
for (nm in names(tabs)) {
  t <- copy(tabs[[nm]])
  for (cl in names(t)[-1]) {
    v <- t[[cl]]; v[v %in% c("", "n/a")] <- NA
    id <- if (cl %in% names(sheet_of) || file.exists(file.path(IN_DIR, "sub_tables", paste0(cl, "_sheet.csv")))) sub_id(cl, v) else NULL
    set(t, j = cl, value = if (is.null(id)) v else ifelse(is.na(v), NA, ifelse(is.na(id), v, id)))
  }
  fwrite(t, file.path(dB, "method_tables", paste0(nm, ".csv")))
}

um <- rbindlist(unmatched, fill = TRUE)
fwrite(um, file.path(OUT_DIR, "unmatched.csv"))

cat("\nFinal table:", nrow(out), "files x", ncol(out), "columns ->", OUT_DIR, "\n")
print(out[, .N, by = c("garden", unname(ID_COL))][order(garden)])
if (nrow(um)) { cat("\nTo check (unmatched.csv):\n"); print(um[, .(n = .N, examples = paste(head(unique(value), 3), collapse = " | ")), by = what]) }
