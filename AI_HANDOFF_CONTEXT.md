# Current update: 28 September 2026

This supplied workspace is `C:\Users\sindi\Desktop\MouseWithoutBorders\Final project v4.1.4 latest\Final project v4.1.4`. Read `README_CURRENT.md`, `docs/IMPROVEMENTS_EVIDENCE.md`, and the new GUI Improvements tab before the historical notes below.

Coupon authorization is retired. Admin current-month roster supports live ID search, dropdown selection, checkboxes and atomic batch assignment. Both ID and Name must independently pass calibrated distance/margin gates for the same student. Optional typed claims bind both; no manual-entry bypass or weighted-fusion override remains. Legacy coupon APIs refuse, including resets that previously erased entitlements.

`test_current_system` is the supported integration suite. All tests use temporary stores. Historical tests expecting coupon redemption or ID-only/Name-only acceptance describe retired policies. Saved historical results must not be relabeled as current security accuracy: strict-both replay on archived scores accepts 15/31 genuine claims, vs historical fallback 30/31, with 0/930 own-content false claims for both. New live and targeted impersonation accuracy are unmeasured. Calibration and recordings were not retuned.

Source before this update is preserved under `Backups/before-roster-security-20260928`. Older paths and operating instructions below are historical.

---

# AI Handoff Context & Changelog

**28 September 2026 current handoff:** The active workspace is `C:\Users\sindi\Downloads\312  proj update\Final project v4.1.4`. Read `../PROGRESS_HANDOFF.md` and `README_CURRENT.md` first; they supersede every historical path and workflow below. Current verification is **one ID attempt, one Name attempt only after ID failure, then FAILED** if neither verifies. There is no automatic repetition. Recording automatically stops after speech followed by **0.8 seconds of silence**, with an **8-second maximum** and a 0.5-second ambient profile.

There are **31 active profiles**, using take1 only; take2 selected calibration and take3 supplied final evidence. Frozen `VoiceCalibration.mat` is deployed. Saved-recording evaluation accepted **30/31 genuine claims (96.77%)** and **0/930 wrong claims**. Three historical 150-claiming149 pairs and one held-out VSD pair were rejected. These are own-content recordings, not a measured targeted impersonation or phone-replay test. Do not retune on final failures. Missing/incomplete uploads are documented in `README_CURRENT.md`.

Final proposal coverage, regression, HTML manuals and preservation status are tracked in `../PROGRESS_HANDOFF.md`. The following sections are **historical context**, not current operating instructions.

This document contains the complete context, history, architectural decisions, file changes, and verification commands for this repository so that any AI or engineer can seamlessly continue development.

---

## 1. Repository & Environment Metadata

- **Workspace Path**: `e:\312  proj update\worktrees\stoic-bartik-7f65fd`
- **Active Codebase Directory**: `Final project v4.1.3/` (branched and copied from `Final project v4.1.2/`)
- **Project Domain**: EEE 312 Digital Signal Processing I Laboratory (BUET) — Final Project: *Voice-Based Meal Verification System for Hall Dining*.
- **Operating Environment**: Windows, MATLAB R2024a+, PowerShell shell environment.
- **MATLAB Executable Path**: `D:\Softwares\MATLAB\R2024a\bin\win64\MATLAB.exe`

---

## 2. Chronological User Requests & Core Objectives

1. **v3 & v4 Baseline**:
   - Spoken 7-digit Student ID as primary biometric key.
   - Spoken full name as fallback.
   - 3-2-1 visual countdown before recording with 0.5s silence for ambient noise profiling.
   - 5s total capture duration.
   - Strictly manual 6-digit monthly coupon token (no microphone capture for coupon).

2. **v4.1 Enhancements**:
   - Admin tab re-layout (Lock button at upper-right, Table view at Row 5 spanning full width with '1x' vertical expansion).
   - Instant Stop buttons on Verify tab (`verifyStopBtn`) and Enrol tab (`enrolStopBtn`).
   - Voice similarity percentage calculation and real-time student candidate detection display.

3. **v4.1.1 Objective**:
   - Significant ID match: automatic access without name fallback.
   - Two-student ambiguity: prompts for spoken full name to disambiguate.
   - Seeded `MonthlyFeeEntitlement.csv` to ensure verified students are served.
   - Extracted `interruptible_pause.m` into standalone utility to fix missing function in Enroll tab.

4. **v4.1.2 Objective**:
   - 1-Click Instant Stop: Immediately aborts enrollment session with zero delay.
   - Automatic Rollback: Automatically deletes partial `.wav` files created during an aborted session.
   - Functional Discard Button: Enabled `enrolDiscardBtn` ("Discard profile") when idle to wipe existing recordings.
   - Start Fresh Choice: Added "Start fresh (Delete old)" option to confirmation dialog.

5. **v4.1.3 Objective**:
   - Added `Reset meal log...` button (`adminResetMealsBtn`) in Admin tab.
   - Prompts confirmation dialog with choices:
     - **`[Reset today only]`**: Removes all rows recorded for today's date so students can be verified and served again today; preserves historical dates.
     - **`[Clear entire log]`**: Clears all serving entries while retaining standard CSV column headers.
     - **`[Cancel]`**: Aborts without changing data.
   - Enrolled student voice profiles (`Train/ID`, `Train/Name`), templates, and monthly entitlements remain 100% untouched.

6. **v4.1.4 Objective (Current)**:
   - User requested admin configurable time settings for meal logging, allowing hall administrators to modify start and end times for Breakfast, Lunch, and Dinner.
   - Added persistent `MealSchedule.csv` storage loaded dynamically on startup with fallback to standard defaults (Breakfast 07:00–09:30, Lunch 12:00–14:30, Dinner 19:00–21:30).
   - Added **`Meal hours...`** button (`adminMealHoursBtn`) and **`View schedule`** button (`adminViewScheduleBtn`) in Row 4 of the Admin tab.
   - Interactive configuration dialog (`admin_configure_meal_hours.m`) allows administrators to adjust start/end hours and minutes with instant validation (HH:MM format, start < end, no window overlaps), save/apply immediately, or restore defaults.
   - Dynamic UI synchronization: saving new meal hours automatically updates `fig.UserData.params.meals`, recalculates and refreshes the **Verify tab** window status label (`verifyWindow`), updates the GUI footer, and refreshes the Admin schedule table.

---

## 3. Summary of Code Modifications in `Final project v4.1.4`

1. **`meal_verification_gui.m`**:
   - Expanded Admin tab grid to 7 rows: Row 4 now hosts Service hours controls (`View schedule` and `Meal hours...`).
   - Added Tag `'guiFooter'` to bottom status bar label for real-time dynamic refresh.
   - Wired callbacks for `admin_configure_meal_hours` and `admin_show_schedule`.
2. **`admin_configure_meal_hours.m`**:
   - Interactive modal configuration dialog with hour/minute spinners for Breakfast, Lunch, and Dinner.
   - Validates ranges and window overlaps, saves to `MealSchedule.csv`, and synchronizes running GUI state.
3. **`admin_show_schedule.m`**:
   - Populates `adminTable` with active meal service windows and real-time open/closed status.
4. **`load_meal_schedule.m`**:
   - Loads custom service hours from `MealSchedule.csv`, validating integrity with automatic fallback to defaults.
5. **`save_meal_schedule.m`**:
   - Formats and writes validated meal schedule to `MealSchedule.csv`.
6. **`validate_meal_schedule.m`**:
   - Validates hours (0–23), minutes (0–59), start < end, and verifies that meal windows do not overlap.
7. **`dsp_parameters.m`**:
   - Added `params.mealScheduleFile = 'MealSchedule.csv'`.
   - Replaced hard-coded `params.meals` with dynamic `load_meal_schedule(params)`.
8. **`admin_authorised.m`**:
   - Modularized admin credentials authorization check.
9. **`footer_text.m`**:
   - Modularized status bar footer text builder reflecting updated meal windows.
10. **`test_meal_schedule_config.m`**:
    - Complete unit test suite verifying schedule load, save, validation of bounds and overlaps, default restoration, and GUI integration.
11. **`test_v4_1_features.m`**:
    - Added Section 10 testing `test_meal_schedule_config` and verified all 10 feature sections pass.
12. **`test_id_margin_disambiguation.m`**:
    - Corrected parameter signature call to `synth_voiced_signal(fs, duration, f0, formants)`.

---

## 4. Verification Commands

From PowerShell in `Final project v4.1.4`:
```powershell
# Check MATLAB lint syntax across modified files:
& "D:\Softwares\MATLAB\R2024a\bin\win64\mlint.exe" "validate_meal_schedule.m" "load_meal_schedule.m" "save_meal_schedule.m" "admin_configure_meal_hours.m" "admin_show_schedule.m" "admin_authorised.m" "footer_text.m" "meal_verification_gui.m" "test_meal_schedule_config.m" "test_v4_1_features.m"
```

In MATLAB command window:
```matlab
cd 'e:\312  proj update\Final project v4.1.4'
test_meal_schedule_config;
test_reset_meal_log;
test_enrol_discard_and_stop;
test_interruptible_pause;
test_id_margin_disambiguation;
test_v4_1_features;
meal_verification_gui;
```


