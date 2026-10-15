-- Actual UEVR camera settings, in the same units as its menu.
-- forward/right/up are absolute values, not additions to another preset.
-- Save edits during play; the file is checked every 60 engine ticks.
-- Manual UEVR menu edits remain until the aircraft/config changes or a cinematic ends.
-- Unlisted aircraft and menus use default. Cinematics/hangars retain camera control.
-- Invalid edits retain the last valid configuration. Axes must be -100..100.
return {
    mode = "uevr_absolute",
    enabled = true,
    default = { forward = 0, right = 0, up = 0 },
    planes = {
        ["BP_PlayerPlane_PP0007_f18c_C"] = { forward = 0, right = 0, up = 0 },
        ["BP_PlayerPlane_PP0003_f04e_C"] = { forward = -10, right = 0, up = 5 },

        -- Verified catalog identifiers; uncomment an entry after tuning its position.
        -- These example values equal default; they are NOT measured per-plane offsets.
        -- Labels are normalized from internal model codes, not decoded display strings.
        -- A-10C | PlaneID 1010
        -- ["BP_PlayerPlane_PP0001_a10c_C"] = { forward = -18, right = 0, up = 5 },
        -- F-2A | PlaneID 2010
        -- ["BP_PlayerPlane_PP0002_f02a_C"] = { forward = -18, right = 0, up = 5 },
        -- F-15C | PlaneID 4010
        -- ["BP_PlayerPlane_PP0004_f15c_C"] = { forward = -18, right = 0, up = 5 },
        -- F-22A | PlaneID 5010
        -- ["BP_PlayerPlane_PP0005_f22a_C"] = { forward = -18, right = 0, up = 5 },
        -- F-35C | PlaneID 6010
        -- ["BP_PlayerPlane_PP0006_f35c_C"] = { forward = -18, right = 0, up = 5 },
        -- Gripen E | PlaneID 8010
        -- ["BP_PlayerPlane_PP0008_j39e_C"] = { forward = -18, right = 0, up = 5 },
        -- Su-34 | PlaneID 9010
        -- ["BP_PlayerPlane_PP0009_su34_C"] = { forward = -18, right = 0, up = 5 },
        -- EA-18G | PlaneID 10010
        -- ["BP_PlayerPlane_PP0010_e18g_C"] = { forward = -18, right = 0, up = 5 },
        -- Typhoon | PlaneID 11010
        -- ["BP_PlayerPlane_PP0011_typn_C"] = { forward = -18, right = 0, up = 5 },
        -- F-15J | PlaneID 12010
        -- ["BP_PlayerPlane_PP0012_f15j_C"] = { forward = -18, right = 0, up = 5 },
        -- A-6E | PlaneID 13010
        -- ["BP_PlayerPlane_PP0013_a06e_C"] = { forward = -18, right = 0, up = 5 },
        -- Rafale M | PlaneID 14010
        -- ["BP_PlayerPlane_PP0014_rflm_C"] = { forward = -18, right = 0, up = 5 },
        -- Su-25 | PlaneID 15010
        -- ["BP_PlayerPlane_PP0015_su25_C"] = { forward = -18, right = 0, up = 5 },
        -- x40a (internal model code) | PlaneID 16010
        -- ["BP_PlayerPlane_PP0016_x40a_C"] = { forward = -18, right = 0, up = 5 },
        -- Mirage 2000 (variant unverified) | PlaneID 17010
        -- ["BP_PlayerPlane_PP0017_mr2k_C"] = { forward = -18, right = 0, up = 5 },
        -- fa36 (internal model code) | PlaneID 18010
        -- ["BP_PlayerPlane_PP0018_fa36_C"] = { forward = -18, right = 0, up = 5 },
        -- ea36 (internal model code) | PlaneID 19010
        -- ["BP_PlayerPlane_PP0019_ea36_C"] = { forward = -18, right = 0, up = 5 },
        -- MiG-29A | PlaneID 20010
        -- ["BP_PlayerPlane_PP0020_m29a_C"] = { forward = -18, right = 0, up = 5 },
        -- Su-57 | PlaneID 21010
        -- ["BP_PlayerPlane_PP0021_su57_C"] = { forward = -18, right = 0, up = 5 },
        -- F-16C | PlaneID 22010
        -- ["BP_PlayerPlane_PP0022_f16c_C"] = { forward = -18, right = 0, up = 5 },
        -- F-14D | PlaneID 23010
        -- ["BP_PlayerPlane_PP0023_f14d_C"] = { forward = -18, right = 0, up = 5 },
        -- F/A-18F | PlaneID 24010
        -- ["BP_PlayerPlane_PP0024_f18f_C"] = { forward = -18, right = 0, up = 5 },
        -- F-15E | PlaneID 25010
        -- ["BP_PlayerPlane_PP0025_f15e_C"] = { forward = -18, right = 0, up = 5 },
        -- Su-47 | PlaneID 26010
        -- ["BP_PlayerPlane_PP0026_su47_C"] = { forward = -18, right = 0, up = 5 },
        -- MiG-21 (variant unverified) | PlaneID 27010
        -- ["BP_PlayerPlane_PP0027_m21b_C"] = { forward = -18, right = 0, up = 5 },
        -- Su-35 (variant unverified) | PlaneID 28010
        -- ["BP_PlayerPlane_PP0028_su35_C"] = { forward = -18, right = 0, up = 5 },
        -- MiG-31 (variant unverified) | PlaneID 29010
        -- ["BP_PlayerPlane_PP0029_m31b_C"] = { forward = -18, right = 0, up = 5 },
        -- Su-33 | PlaneID 30010
        -- ["BP_PlayerPlane_PP0030_su33_C"] = { forward = -18, right = 0, up = 5 },
        -- EA-6B | PlaneID 31010
        -- ["BP_PlayerPlane_PP0031_e06b_C"] = { forward = -18, right = 0, up = 5 },
        -- F/A-18E | PlaneID 32010
        -- ["BP_PlayerPlane_PP0032_f18e_C"] = { forward = -18, right = 0, up = 5 },
        -- F-14A | PlaneID 10034010
        -- ["BP_PlayerPlane_PP0034_f14a_C"] = { forward = -18, right = 0, up = 5 },
        -- ADFX-02 (L001 internal variant) | PlaneID 38010
        -- ["BP_PlayerPlane_PP0038_adfx02_L001_C"] = { forward = -18, right = 0, up = 5 },

        -- Mission-specific variants (not separate aircraft in the normal roster).
        -- A-6E | PlaneID 10013010
        -- ["BP_PlayerPlane_PP0013_a06e_ms15_C"] = { forward = -18, right = 0, up = 5 },
        -- F/A-18F | PlaneID 10024010
        -- ["BP_PlayerPlane_PP0024_f18f_ms01_C"] = { forward = -18, right = 0, up = 5 },
    },
}
