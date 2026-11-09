# Bloc 02 — échantillonnage + LC-MS + paramètres MZmine
# Lit BASE_DIR/metadata_all_merged.csv -> 02_sampling/output/sampling_metadata.csv
# Valeurs par jardin : 02_sampling/garden_defaults.R ; batchs : 02_sampling/batch_mzmine/
# Incrémental : seuls les fichiers absents de sampling_metadata.csv sont ajoutés.
BASE_DIR <- "."   # the dbgi_methods folder (setwd() on it before running)

FORCE_ALL <- TRUE    # TRUE = tout reconstruire (à faire si tu modifies garden_defaults.R ou les batchs)

source(file.path(BASE_DIR, "02_sampling/02_sampling_metadata.R"))
source(file.path(BASE_DIR, "02_sampling/02_sampling_correction.R"))   # compléments depuis massive


smp <- fread(file.path(BASE_DIR, "02_sampling/output/sampling_metadata.csv"))
smp[, .N, by = sample_id][, .N, by = .(fichiers_par_echantillon = N)][order(fichiers_par_echantillon)]
smp[, .(fichiers = .N, echantillons = uniqueN(sample_id)), by = garden]
