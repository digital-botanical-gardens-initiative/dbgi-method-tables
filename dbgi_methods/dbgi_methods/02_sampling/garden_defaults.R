# ==============================================================================
# garden_defaults.R — CONFIGURATION (not code): per-garden values that are NOT
# in the merged MassIVE / Directus CSV (preservation, extraction, detailed LC,
# detailed MS, QC, MassIVE accession, batch id).
#
# Read by 02_sampling/02_sampling_metadata.R. To add a garden or an instrument, add a
# block here; no script needs to change. Unknown values: NA_character_ /
# NA_real_ / NA_integer_ (keep the type so columns stay consistent).
# ==============================================================================
GARDEN_DEFAULTS <- list(

  JBN = list(
    # --- Preservation & extraction ---
    preservation_method   = "liquid_N2",
    transport_conditions  = "liquid_N2 dewar, <24h",
    storage_temp_c        = -80L,
    storage_duration_d    = NA_integer_,
    grinding_method       = "Retsch mill, 5 min at 30 Hz, stainless-steel UFO beads (Next Advance SSUFO35)",
    extraction_solvent    = "MeOH:H2O:formic acid 80:19.9:0.1 (v/v/v)",
    extraction_volume_ml  = 1,
    extraction_conditions = "homogenized 3 min at 30 Hz; centrifuged 5 min at 14000 rpm; ~0.7 mL supernatant re-centrifuged 3 min at 14000 rpm",
    extraction_operator   = "ML",
    extract_storage       = "-80 C, plastic tube",
    # --- Identification ---
    identification_method     = "botanical_garden_ID",
    identification_confidence = "certain",
    # --- LC ---
    # Checked against the RAW method (extract_methods.py, 2026-10-30) of a pooled QC
    # (250407_ML_Metabo_DDA_QC4_5.raw, 2025-04-08): inlet method 100x21_HSS_metabo_DDA_10min,
    # MS method UltrafastDDA_50-1200_10min_pos.EXP, tune DBA023-UPLC_low_stepwave.IPR.
    lc_vendor            = "Waters",
    lc_model             = "Acquity UPLC I-Class",     # RAW: "Waters Acquity SDS" binary pump (SN F19BSP572G)
                                                       #      + "ACQUITY FTN AutoSampler" (SN G19FNP373G)
    chromatography_type  = "UPLC",
    column_name          = "Waters Acquity UPLC HSS T3, 100 x 2.1 mm, 1.8 um",   # RAW: "ACQUITY UPLC HSS T3 1.8um", comment "HSS T3 100mm"
    stationary_phase     = "C18",
    column_temp_c        = 40,                         # RAW: 40.0 C (min = max = 40.0)
    autosampler_temp_c   = 20,                         # RAW: target sample temperature 20.0 C
    mobile_phase_a       = "H2O + 0.05% formic acid",  # RAW names only "Water" (additive not in the method)
    mobile_phase_b       = "ACN + 0.05% formic acid",  # RAW names only "Acetonitrile"
    gradient_program     = "0-100% B in 10 min at 0.5 mL/min; hold 100% B 3 min at 0.7 mL/min; reequil 3 min at 0.5 mL/min",  # RAW: identical
    flow_rate_ml_min     = 0.5,
    injection_volume_ul  = 1,                          # of the 1:5 diluted extract (confirmed; the pooled QC
                                                       # file checked shows 0.5 uL, samples are 1 uL)
    sample_dilution      = "1:5 in extraction solvent",
    run_time_min         = 16,                         # RAW: 16.10 min
    lc_software          = "MassLynx 4.2 (Waters)",
    # --- MS (what is not in instrument_model) ---
    mass_analyzer        = "QTOF",
    ionization_source    = "ESI",
    ionization_polarity  = "positive",                 # RAW: ES+
    acquisition_mode     = "DDA",
    fragmentation_method = "CID",
    collision_energy     = "ramped 5-40 V (m/z 50) to 20-70 V (m/z 1200)",
    mass_range_mz        = "50-1200 (MS1); 50-1200 (MS2)",
    ms1_resolution       = 20000L,                     # RAW: resolution mode, 20000
    ms_scan_time_s       = 0.1,
    msms_scan_time_s     = 0.05,
    dda_top_n            = 7L,
    ms2_intensity_threshold_cps = 25000,
    dynamic_exclusion_s  = 1.5,                        # RAW: real-time exclusion, include after 1.5 s
    background_exclusion = "static exclusion list of 200 most intense blank ions",
                                                       # RAW: file 250407_DDA_ML_Exclusion-List_Pos.txt (+/- 40 mDa, RT window 10)
    capillary_kv         = 1.0,
    source_temp_c        = 140,
    desolvation_temp_c   = 500,
    cone_voltage_v       = 40,
    cone_gas_l_h         = 250,
    desolvation_gas_l_h  = 1000,
    nebuliser_gas_bar    = 6.5,
    mass_calibration     = "external sodium formate (50-1200 m/z) + LockSpray leucine enkephalin every 20 s",
    mass_accuracy_ppm    = 5,
    raw_conversion_tool  = "DataConvert (Waters)",
    centroided           = TRUE,
    # --- QC ---
    processing_software  = "MZmine 4.10.6",
    qc_sample_type       = "pooled QC",
    qc_conditioning_n    = 12L,
    qc_frequency         = "every 20 samples",
    randomization        = TRUE,
    internal_standard    = NA_character_,
    massive_accession    = "MSV000102459",
    batch_id             = "JBN_synapt_2025"
  ),

  JBC = list(
    # --- Preservation & extraction ---
    preservation_method   = "silica_gel",
    transport_conditions  = "silica_gel, ambient temperature, 24-72h",
    storage_temp_c        = -80L,
    storage_duration_d    = NA_integer_,
    grinding_method       = "Retsch mill, 5 min at 30 Hz, stainless-steel UFO beads (Next Advance SSUFO35)",
    extraction_solvent    = "MeOH:H2O:formic acid 80:19.9:0.1 (v/v/v)",
    extraction_volume_ml  = 1,
    extraction_conditions = "homogenized 3 min at 30 Hz; centrifuged 5 min at 14000 rpm; ~0.7 mL supernatant re-centrifuged 3 min at 14000 rpm",
    extraction_operator   = "ML",
    extract_storage       = "-80 C, plastic tube",
    # --- Identification ---
    identification_method     = "botanical_garden_ID",
    identification_confidence = "certain",
    # --- LC ---
    # Checked against the .wiff (extract_methods.py, 2026-10-30) of 20262605_QC_5.wiff
    # (2026-05-28, method DDA_pos_9MSMS_6.5min, SCIEX OS 4.0.0.8559). The .wiff gives the
    # instrument, LC modules, temperatures and source parameters, NOT mass range / CE / gradient.
    lc_vendor            = "Waters",
    lc_model             = "Acquity UPLC I-Class",     # .wiff: ACQUITY Binary Solvent Manager (SN F19BSP572G)
                                                       #        + Sample Manager FTN (SN G19FNP373G)
                                                       #        = the SAME LC units as the Synapt (JBN)
    chromatography_type  = "UPLC",
    column_name          = "Acquity Premier HSS T3, 50 x 2.1 mm, 1.8 um",
    stationary_phase     = "C18",
    column_temp_c        = 30,                         # .wiff: 30.0 C
    autosampler_temp_c   = 20,                         # .wiff: 20.0-20.1 C
    mobile_phase_a       = "H2O + 0.05% formic acid",
    mobile_phase_b       = "ACN + 0.05% formic acid",
    gradient_program     = "2-90% B in 6.5 min; wash 100% B 2 min; reequil 2 min at 2% B",
    flow_rate_ml_min     = 0.4,
    injection_volume_ul  = 0.2,                        # undiluted extract; usual protocol = 1 uL of a 1:5 dilution
                                                       # (same amount injected). MassIVE says 1 uL -> conflict expected
    sample_dilution      = "none (usual protocol: 1:5 dilution, 1 uL injected)",
    run_time_min         = 10.5,
    lc_software          = "SCIEX OS 4.0",             # .wiff: SCIEX OS 4.0.0.8559
    # --- MS ---
    instrument_serial    = "FR20182507",               # .wiff: ZenoTOF 8600 system
    mass_analyzer        = "QTOF",
    ionization_source    = "ESI (OptiFlow Pro source)",   # .wiff: source housing OptiFlow Pro Analytical
    ionization_polarity  = "positive",                 # .wiff: IS > 0
    acquisition_mode     = "DDA",
    fragmentation_method = "CID",
    collision_energy     = "dynamic: intercept 15, slope 0.05, max CE 80 V, CE spread 10 V",
    mass_range_mz        = "10-1000 (MS1); 50-1000 (MS2)",
    ms_scan_time_s       = 0.05,
    msms_scan_time_s     = 0.025,
    dda_top_n            = 9L,                         # .wiff: 9 dependent experiments
    ms2_intensity_threshold_cps = 2000,
    dynamic_exclusion_s  = 3,
    background_exclusion = "dynamic background subtraction, no static exclusion list",
    ion_spray_voltage_kv = 1.5,                        # .wiff ion source table: IS 1500, TEM 450, GS1 35,
                                                       # GS2 70, CUR 40, CAD 7 -> all confirmed
    gas_temperature_c    = 450,
    ion_source_gas1_psi  = 35,
    ion_source_gas2_psi  = 70,
    curtain_gas_psi      = 40,
    cad_gas_psi          = 7,
    zeno_pulsing         = TRUE,
    zeno_threshold       = 1e6,
    q1_resolution        = "unit",
    mass_accuracy_ppm    = 5,
    raw_conversion_tool  = "MSConvert (ProteoWizard)",
    centroided           = TRUE,
    # --- QC ---
    processing_software  = "MZmine 4.10.6",
    qc_sample_type       = "pooled QC",
    qc_conditioning_n    = NA_integer_,
    qc_frequency         = "every 20 samples",
    randomization        = TRUE,
    internal_standard    = NA_character_,
    massive_accession    = "MSV000102458",
    batch_id             = "JBC_zenotof_2026"
  ),

  JBP = list(
    # --- Preservation & extraction ---
    preservation_method   = "dry_ice",
    transport_conditions  = "dry_ice, <24h",
    storage_temp_c        = -80L,
    storage_duration_d    = NA_integer_,
    grinding_method       = "Retsch_MM400",
    extraction_solvent    = "MeOH:H2O 80:20 (v/v)",
    extraction_conditions = "shaking 30 min, 20C, 200 rpm; Centrifugation, 14000rpm, 5 min",
    extraction_operator   = "KK",
    extract_storage       = "-80 C, plastic tube",
    # --- Identification ---
    identification_method     = "botanical_garden_ID",
    identification_confidence = "certain",
    # --- LC ---
    # Checked against the RAW method (extract_methods.py, 2026-10-30) of
    # 20260928_91_210554_KK_general_ms2_pos_dbgi_011926_01_02_uL.raw (2026-09-30, method
    # general_ms2_pos.meth) = the reference DBGI method for Prague.
    lc_vendor            = "Thermo Scientific",
    lc_model             = "Vanquish H",               # RAW: "Instrument: Vanquish_H"
    chromatography_type  = "UHPLC",
    column_name          = "Kinetex 2.6 um, 100 A, 150 x 2.1 mm (PN=00F-4462-AN)",   # not in the RAW
    stationary_phase     = "C18",
    column_temp_c        = 40,                         # RAW: 40.00 C
    autosampler_temp_c   = 10,                         # RAW: 10.0 C
    mobile_phase_a       = "H2O + 0.1% formic acid",   # RAW: "Water+0.1%FA"
    mobile_phase_b       = "ACN + 0.1% formic acid",   # RAW: "ACN+0.1%FA"
    gradient_program     = "5-100% B in 15.5 min; wash 100% B 1.8 min; reequil 2 min at 5% B",
                                                       # RAW: 5% B 0-0.5 min; 5->100% 0.5-15.5; 100% to 17.3; 5% to 19.3
    flow_rate_ml_min     = 0.35,
    injection_volume_ul  = 1,                          # confirmed (RAW sequence + lab practice: always 1 uL) [was 0.1]
    run_time_min         = 19.3,
    lc_software          = "Thermo Scientific Xcalibur",   # RAW: instrument software 4.3
    # --- MS ---
    instrument_model     = "Orbitrap ID-X (Thermo Scientific)",   # used when the merged CSV has none
    instrument_serial    = "FSN30172",
    mass_analyzer        = "Orbitrap",
    ionization_source    = "H-ESI",                    # RAW: Ion Source Type = H-ESI
    ionization_polarity  = "positive",                 # RAW (pos method checked; neg = 2.0 kV spray)
    acquisition_mode     = "DDA",
    fragmentation_method = "HCD",
    collision_energy     = "normalized CE 35%",
    mass_range_mz        = "100-1000 (MS1)",           # MS2: scan range auto
    ms_scan_time_s       = NA_real_,
    msms_scan_time_s     = NA_real_,
    dda_top_n            = NA_integer_,                # not Top-N: cycle-time DDA (dda_cycle_time_s = 0.6)
    ms2_intensity_threshold_cps = 1e5,
    dynamic_exclusion_s  = 2,
    background_exclusion = "dynamic exclusion after 1 occurrence for 2 s (5 ppm, isotopes excluded) + targeted exclusion list (7 ions)",
    mass_accuracy_ppm    = 5,
    ms1_resolution       = 60000L,                     # RAW: 60K
    ms1_agc_target       = 2e5,                        # RAW: 200000 (normalized 50%)  [was 2.1e5]
    ms1_max_inject_ms    = 118,
    ms2_resolution       = 15000,
    ms2_agc_target       = 5e4,
    ms2_max_inject_ms    = 80,
    precursor_isolation_window_mz = 0.8,
    sheath_gas_arb       = 50,
    aux_gas_arb          = 10,
    sweep_gas_arb        = 1,
    ion_transfer_tube_c  = 325,
    vaporizer_temp_c     = 350,
    spray_voltage_kv     = 3.0,                        # RAW: time-dependent, 0 V for 0-0.2 min then 3000 V (neg 2000 V)
    rf_lens_pct          = 45,
    expected_peak_width_s = 6,
    internal_calibration = "EASY-IC, RunStart",        # RAW
    dda_cycle_time_s     = 0.6,
    raw_conversion_tool  = "MSConvert (ProteoWizard), vendor algorithm",
    centroided           = TRUE,
    # --- QC ---
    processing_software  = "MZmine 4.10.6",
    qc_sample_type       = "pooled QC + blank",
    qc_conditioning_n    = NA_integer_,
    qc_frequency         = NA_character_,
    randomization        = TRUE,
    internal_standard    = NA_character_,
    data_type            = "profile, centroided with MSConvert vendor algorithm",
    massive_accession    = "MSV000102437; MSV000102438; MSV000102439",
    batch_id             = "JBP_orbitrap_2026"
  ),

  # ── JBUF — Fribourg, Orbitrap Q Exactive Plus / Q Exactive HF-X ─────────
  # Method from the Fribourg platform: Vanquish Flex UPLC + Q Exactive Plus,
  #   HESI-II, Xcalibur 3.1. Values below = Q Exactive Plus.
  #   The HF-X runs a DIFFERENT MS method (checked in the RAW files, 2026-10-30)
  #   -> see INSTRUMENT_OVERRIDES at the end of this file.
  JBUF = list(
    # --- Preservation & extraction ---
    preservation_method   = "liquid_N2",
    transport_conditions  = "liquid_N2 dewar, <24h",
    storage_temp_c        = -80L,
    storage_duration_d    = NA_integer_,
    grinding_method       = "Retsch_MM400",
    extraction_solvent    = "MeOH:H2O 80:20 (v/v)",
    extraction_conditions = "shaking 30 min, 20C, 200 rpm; Centrifugation, 14000rpm, 5 min",
    extraction_operator   = NA_character_,
    extract_storage       = "-80 C, plastic tube",
    # --- Identification ---
    identification_method     = "botanical_garden_ID",
    identification_confidence = "certain",
    # --- LC ---
    lc_vendor            = "Thermo Scientific",
    lc_model             = "Vanquish Flex UPLC",
    chromatography_type  = "UPLC",
    column_name          = "Waters Acquity UPLC BEH C18, 100 x 2.1 mm, 1.7 um",
    stationary_phase     = "C18",
    column_temp_c        = NA_real_,                   # not reported in the method
    mobile_phase_a       = "H2O + 0.1% formic acid",
    mobile_phase_b       = "ACN + 0.1% formic acid",
    gradient_program     = "2-100% B in 10 min (linear); hold 100% B 2 min; re-equilibration to 2% B",
    flow_rate_ml_min     = 0.6,
    injection_volume_ul  = 2,                          # Q Exactive Plus (HF-X = 1 uL, see INSTRUMENT_OVERRIDES)
    run_time_min         = 15,                         # total run incl. re-equilibration (MassIVE injection_method)
    lc_software          = "Thermo Scientific Xcalibur 3.1",
    # --- MS ---
    mass_analyzer        = "Orbitrap",
    ionization_source    = "HESI-II",
    acquisition_mode     = "DDA",
    fragmentation_method = "HCD",
    collision_energy     = "stepped normalized CE 15, 30, 45",
    mass_range_mz        = NA_character_,              # not reported in the method
    ms_scan_time_s       = NA_real_,
    msms_scan_time_s     = NA_real_,
    dda_top_n            = 3L,
    ms2_intensity_threshold_cps = NA_real_,
    dynamic_exclusion_s  = 3,
    background_exclusion = "dynamic exclusion 3 s",
    mass_accuracy_ppm    = 5,
    ms1_resolution       = 35000L,                     # FWHM at m/z 200
    ms1_agc_target       = NA_real_,
    ms1_max_inject_ms    = NA_integer_,                # automatic
    ms2_resolution       = 17500L,                     # FWHM at m/z 200
    ms2_agc_target       = NA_real_,
    ms2_max_inject_ms    = NA_integer_,                # automatic
    precursor_isolation_window_mz = 1.0,
    sheath_gas_arb       = 55,
    aux_gas_arb          = 15,
    sweep_gas_arb        = 3,                          # "spare gas" in the method
    ion_transfer_tube_c  = 350,                        # capillary temperature
    vaporizer_temp_c     = NA_real_,                   # not reported
    spray_voltage_kv     = 3.5,                        # positive mode
    rf_lens_pct          = 50,                         # S-Lens RF level
    mass_calibration     = "external, direct infusion: caffeine, MRFA, SDS, sodium taurocholate, Ultramark 1621 in ACN/MeOH/H2O + 1% FA",
    raw_conversion_tool  = "MSConvert (ProteoWizard)",
    centroided           = TRUE,
    # --- QC ---
    processing_software  = "MZmine 4.10.6",
    qc_sample_type       = "pooled QC",
    qc_conditioning_n    = NA_integer_,
    qc_frequency         = NA_character_,
    randomization        = TRUE,
    internal_standard    = NA_character_,
    massive_accession    = "MSV000090090",
    batch_id             = "JBUF_qexactive_2024"
  ),

  # ── JBK — Kew (Royal Botanic Gardens), 2025 batch ────────
  # Sampling / extraction: same as Prague (JBP) — dry ice, 1 mL MeOH:H2O 80:20.
  # LC-MS: Thermo Orbitrap Exploris 120 (SN MB10922C), Xcalibur 4.4.
  #   Source: instrument method embedded in 20251006_11_dbgi_010669_01_01_1uL.raw
  #   (exported with FreeStyle by Kata, Method_LC.csv + Method_MS.csv).
  #   Pump channels in the method: %B = B1 "Water + 0.1% FA", %A = A2 "ACN + 0.1% FA";
  #   reported below with the usual convention A = aqueous, B = organic.
  #   Checked on the mzML files (last retention time): all Kew injections
  #   (20251006 batch) are 19.3-min runs = this method. A second 9.3-min method
  #   (cycle-time DDA 0.6 s, threshold 1e5, time-dependent spray 3000/2000 V)
  #   exists on the instrument but was NOT used for these files.
  JBK = list(
    # --- Preservation & extraction ---
    preservation_method   = "dry_ice",
    transport_conditions  = "dry_ice",              # duration to be specified
    storage_temp_c        = -80L,                  # as JBP
    storage_duration_d    = NA_integer_,
    grinding_method       = "Retsch_MM400",        # as JBP
    dry_weight_mg         = 20,                    # fallback only: Directus weights (measured) replace it
    extraction_solvent    = "MeOH:H2O 80:20 (v/v)",
    extraction_volume_ml  = 1,
    extraction_conditions = "shaking 30 min, 20C, 200 rpm; Centrifugation, 14000rpm, 5 min",  # as JBP
    extraction_operator   = "KK",                  # as JBP
    extract_storage       = "-80 C, plastic tube", # as JBP
    # --- Identification ---
    collector_full_name   = "Mazzarine Laboureau; Davide; Katerina",   # sampling team (per-sample collector unknown) -> complete surnames
    identification_method     = "botanical_garden_ID",   # Kew catalogue numbers (K:LCD-...)
    identification_confidence = "certain",
    # --- LC ---
    lc_vendor            = "Thermo Scientific",
    lc_model             = NA_character_,              # not in Method_LC (modules only) -> unknown
    chromatography_type  = "UHPLC",
    column_name          = "Kinetex C18, 2.6 um",      # from the .meth file name (MetaXtract, 2026-10-30):
                                                       # posESI_Top4_hcd35_350ACN20min_40C_2-6umKinetexC18[_ExcList].meth
                                                       # length / ID not in the method -> probably 150 x 2.1 mm as JBP, to confirm with Kata
    stationary_phase     = "C18",
    column_temp_c        = 40,
    mobile_phase_a       = "H2O + 0.1% formic acid",
    mobile_phase_b       = "ACN + 0.1% formic acid",
    gradient_program     = "5% B 0-0.5 min; 5-100% B 0.5-15.5 min; 100% B 15.5-17.3 min; back to 5% B and reequil 17.3-19.3 min",
    flow_rate_ml_min     = 0.35,
    injection_volume_ul  = 1,                        # "_1uL" in file names
    run_time_min         = 19.3,
    lc_software          = "Thermo Scientific Xcalibur 4.4",
    autosampler_temp_c   = 15,
    uv_detection         = "PDA 210-500 nm, 5 Hz",
    # --- MS ---
    instrument_model     = "Orbitrap Exploris 120 (Thermo Scientific)",   # Method_MS: "OE120"
    instrument_serial    = "MB10922C",
    mass_analyzer        = "Orbitrap",
    ionization_source    = "H-ESI",
    ionization_polarity  = "positive",              # Kew files not in MassIVE -> no polarity in the CSV
    acquisition_mode     = "DDA",
    fragmentation_method = "HCD",
    collision_energy     = "normalized CE 35% (fixed)",
    mass_range_mz        = "100-1000 (MS1)",
    ms_scan_time_s       = NA_real_,
    msms_scan_time_s     = NA_real_,
    dda_top_n            = 4L,                         # "Number of dependent scans = 4"
    ms2_intensity_threshold_cps = 2.5e5,
    dynamic_exclusion_s  = 2,
    background_exclusion = "dynamic exclusion after 1 occurrence for 2 s (5 ppm, isotopes excluded) + targeted exclusion list of ~210 background ions",
                                                       # WARNING (MetaXtract, 2026-10-30): two method versions exist.
                                                       #   ..._2-6umKinetexC18.meth         (blank 20251002_12): NO exclusion list
                                                       #   ..._2-6umKinetexC18_ExcList.meth (20251006 files):    with exclusion list
                                                       #   -> any sample injected on 2025-10-02 should get "dynamic exclusion only"
    mass_accuracy_ppm    = 5,
    ms1_resolution       = 60000L,
    ms1_agc_target       = 5e5,                        # normalized 50%
    ms1_max_inject_ms    = 118,
    ms2_resolution       = 15000,
    ms2_agc_target       = NA_real_,                   # "Standard"
    ms2_max_inject_ms    = 80,
    precursor_isolation_window_mz = 0.8,
    sheath_gas_arb       = 50,
    aux_gas_arb          = 10,
    sweep_gas_arb        = 1,
    ion_transfer_tube_c  = 325,
    vaporizer_temp_c     = 350,
    spray_voltage_kv     = 3.0,                        # positive; negative = 2.5 kV
    rf_lens_pct          = 45,
    expected_peak_width_s = 8,
    internal_calibration = "EASY-IC, RunStart",
    raw_conversion_tool  = "MSConvert (ProteoWizard 3.0.24130), vendor peak picking",
    centroided           = TRUE,
    data_type            = "MS1 centroid, MS2 profile in RAW (MetaXtract); MS2 centroided with MSConvert vendor algorithm",
    # --- QC ---
    processing_software  = "MZmine 4.10",
    qc_sample_type       = "solvent blanks + extraction blanks + standard mix (MixCaffFlav 1 ug/mL)",
    qc_conditioning_n    = NA_integer_,
    qc_frequency         = NA_character_,
    randomization        = NA,
    internal_standard    = NA_character_,
    massive_accession    = NA_character_,
    batch_id             = "JBK_2025"
  )
)
# ==============================================================================
# INSTRUMENT_OVERRIDES — values that differ between instruments of the SAME garden.
# Applied by 02_sampling_metadata.R right after GARDEN_DEFAULTS, to the files of
# `garden` whose instrument_model matches `pattern` (regex, case-insensitive).
# Only the fields listed in `values` are replaced.
# ==============================================================================
INSTRUMENT_OVERRIDES <- list(

  # Fribourg, Q Exactive HF-X: 1 uL injected (MassIVE: 410/432 HF-X files per
  # polarity at 1 uL; Plus files at 2 uL).
  # MS/LC parameters below extracted with MetaXtract (2026-10-30) from the RAW
  # method of 6 HF-X files (vine 236/304/313, pos + neg), methods
  # 20250319_PMA_C18_DDA_pos.meth / _neg.meth (pos and neg identical except polarity).
  # They DIFFER from the Q Exactive Plus defaults -> to check that all HF-X files
  # used these methods. LC: 2-100% B in 10 min, hold 2 min, back to 2% B, end at
  # 15 min -> run_time 15 min and gradient as the Plus (confirmed).
  # Source settings (spray, gases, capillary temp) are in the tune file, not in
  # the method -> kept from the Plus, unverified for the HF-X.
  list(garden  = "JBUF",
       pattern = "HFX|HF-X",
       values  = list(
         injection_volume_ul           = 1,
         column_temp_c                 = 40,
         mass_range_mz                 = "120-1800 (MS1); 200-2000 (MS2)",
         dda_top_n                     = 5L,
         ms2_intensity_threshold_cps   = 1.6e5,
         dynamic_exclusion_s           = 2,
         background_exclusion          = "dynamic exclusion 2 s, isotopes excluded",
         ms1_resolution                = 45000L,
         ms1_agc_target                = 3e6,
         ms1_max_inject_ms             = 100L,
         ms2_resolution                = 30000L,
         ms2_agc_target                = 1e5,
         ms2_max_inject_ms             = 50L,
         precursor_isolation_window_mz = 2.0,
         mass_calibration              = "lock mass m/z 391.2843 (mode 'best'), rarely found (<5% of scans pos, 0% neg) -> mostly external calibration"
       ))
)