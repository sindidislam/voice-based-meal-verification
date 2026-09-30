# Current dining verification workflow

In MATLAB, open this folder and run `run_meal_system`. Use `test_current_system` for the current security, GUI, roster and evidence regressions, or `run_meal_system('check')` for the DSP diagnostic. The HTML presentation and manuals retain earlier workflow measurements; this file and the GUI Improvements tab describe the current policy.

The system records the spoken ID **once** and full name **once**. **Both recordings must independently pass their calibrated distance and runner-up margin checks for the same student.** An optional typed seven-digit ID binds both checks to that student; typing it does not weaken the policy. A name match cannot override a conflicting ID match or a failed distance/margin check. A weighted joint ranking is diagnostic only. There is no manual-entry bypass. Stop cancels the active transaction; a new transaction starts only after the preceding callback has finished.

Each recording lasts **up to 8 seconds**, including the initial 0.5-second ambient profile and a short speaking-cue cushion. Wait for **SPEAK NOW** and say the complete phrase naturally. Recording ends automatically after detected speech is followed by a sustained pause. Its energy threshold adapts to the ambient profile. The eight-second limit bounds recordings when speech or its ending cannot be detected. Enrollment and the supplied three-take corpus are separate from verification.

A low distance alone is not permission to serve a meal. Successful biometrics are followed by current-month roster membership, the meal schedule, and the one-meal-per-session CSV check. Coupon assignment, redemption and reset are retired, including their legacy entry points. Historical coupon files are preserved but cannot authorize service.

## Assign students to the current month

Open **Admin**, enter the administrator credentials and click **Unlock / current month**. Type a full or partial ID in **Search enrolled ID** to filter the dropdown and table. Choose one exact ID and click **Assign for this month**, or tick several rows and click **Assign selected**. **Select all shown** marks the filtered rows; **Clear selection** clears the marks. Marks survive filtering, and the assignment button shows their count. A partial search cannot itself be assigned.

Assignments use the calendar month at click time and require valid ID and name enrollment recordings. Reassignment is harmless; previous months remain intact. The table shows membership for the current month. Removing one selected ID affects only that month. No actual student assignments are prepopulated by the update or its tests.

## Show proposal changes and calculations

After unlocking, click **Open DSP / improvements** and choose **Improvements**. Select a view and a table row to inspect its formula, trial counts, source CSV and limitations. Comparisons include sample reduction, measured compute time, synthetic noise/AGC results, matcher demonstrations, and the proposal's implemented DSP stages. The original seniors' source is unavailable, so reconstructed conditions are explicitly labeled.

The stricter rule trades acceptance for stronger rejection: replaying it on the archived final-test scores accepts **15/31 (48.39%)** genuine cases versus **30/31 (96.77%)** under the old fallback policy. This is a saved-score replay, not a new microphone benchmark. Neither result measures a person deliberately speaking another student's ID and name. Improve usability using fresh development recordings and calibration, then evaluate on new held-out genuine and impersonation trials; do not tune against the archived final-test failures.

## Voice profiles and evaluation

`VSD_Enrollment/Train` contains 31 profiles, with one ID and one Name enrollment recording per student. `VSD_Corpus/Train` contains the three distinct takes used by the evaluation: take1 enrollment, take2 calibration, take3 final. Existing `Train` and the uploaded recordings remain preserved.

The upload provides 29 complete sets. Existing profiles fill the empty 148/149 uploads. Roll135 has only one ID recording and stays under `VSD_Corpus/Provisional`; two additional distinct ID takes are needed. Roll134 has no folder and155 is empty. Speaker labels come from the supplied folders. Display names use student IDs because exact name spelling is unverified. Roll137's full-name completeness remains unconfirmed.

For a complete upload, recording positions 1–9 are digits 1–9, position 10 is zero, positions 11–13 are three whole-name takes, positions 14–16 are three whole-ID takes, and position 17 is the full counting sequence. These are ordinal positions: filenames may start at zero or use another offset. All 29 complete uploaded profiles / 174 selected ID-and-Name files already match that order. The incomplete 135 set remains provisional; preserved 148/149 references are outside the upload-order check.

The application loads frozen DSP settings from `VoiceCalibration.mat` when present. The calibration keeps only `1.wav` eligible in each active profile, preventing evaluation takes from silently entering enrollment. Switching to an uncalibrated frontend is refused. Recalibration must use development data and finish before inspecting final-test results.

`Results/experiments_20260927` records the candidate comparison and frozen evaluation. `Results/security_20260927` records the actual deployed scorer check and 150-claiming149 challenges. The report separates saved-pair trials from live microphone behavior and automatic stopping. It also separates synthetic noise/level experiments from field measurements.

The 20–200Hz energy-ratio check is a spectral heuristic. No labeled phone-replay test set or saved targeted 150-speaking149 impersonation recording was supplied, so the package does not establish universal spoof-detection accuracy. Identity verification uses the acoustic DSP features, template distances, and configured claim gates.

The HTML documents link to the relevant MATLAB source and saved tables. The imported-file inventory and file hashes remain preserved under `Results/vsd_import_20260927`.
