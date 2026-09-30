# Evidence in the Improvements tab

The admin-only Improvements tab is built by `build_improvements_tab`. Its read-only data helper, `project_improvement_report`, calculates values from saved result files each time the tab is opened or refreshed. It does not run an experiment, tune thresholds, write result files, or change attendance and monthly entitlement.

The revised proposal, `EEE312_RevisedProposal_Group_07 (2).pdf` in the parent folder, lists five modifications in section VI, page 6: resampling/AGC, a low-frequency liveness heuristic, noise profiling/subtraction, hybrid endpoint detection, and meal-specific CSV rules. Pages 3-5 contain the signal-processing equations and feature/matcher discussion. The tab maps those items to implemented functions and distinguishes implementation from validation.

## Provenance and comparisons

The exact external senior source and matched evaluation corpus are unavailable. `docs/PROJECT_AUDIT.md` records this limitation. The CSV label `Senior baseline MFCC, 16 kHz` is a reconstruction using current extractors with overrides. It is not an execution of the original seniors' package. The proposal itself mentions senior MFCC and DTW; the controlled correlation demonstration must not be called an exact senior DFT baseline.

The tab's comparisons use these sources:

| Source under Results | Filters and interpretation |
|---|---|
| `experiments_20260927/timing_results.csv` | Compare `rate_44100` and `current_dsp` on `development`, with identical phrase, stage, scope, and measurement count. The two-phrase row uses phrase/stage `ID+Name`. |
| `experiments_20260927/synthetic_noise_results.csv` | Match `none` and `spectral` on student, phrase, take, noise type, and requested SNR. All 372 conditions per method enter the denominator. |
| `experiments_20260927/synthetic_agc_results.csv` | Match AGC off/on on student, phrase, take, and scalar gain. All 186 conditions per method enter the denominator. |
| `experiments_20260927/synthetic_vad_results.csv` | Match energy/hybrid on signal and expected-speech label; four non-speech fixtures per method determine the false-trigger rate. |
| `matcher_comparison_20260928/matcher_summary.csv` | Match xcorr/DTW by the four synthetic timing conditions. These are feature-event sequences, not human voice trials. |
| `frontend_comparison.csv` | Separate historical front-end pair-EER comparison with 24 genuine pairs. It is not the 31-student access-decision experiment. |
| `experiments_20260927/system_comparison.csv` | Historical ID-first/name-fallback final-test results only. They do not benchmark the new stricter policy. |
| `experiments_20260927/decision_trials.csv` and `run_summary.json` | Strict-both replay described below. |

Missing, malformed, duplicate-key, or unmatched evidence does not receive a remembered headline value. The tab displays the limitation or omits that comparison. Selecting a row shows its formula, exact source path, filters, and counts. Individual timing/front-end rows also identify their data-row index, excluding the header.

## Calculations and their limits

- Sample count & data reduction: `44100/8000 = 5.5125` times as many samples at the capture rate; `100*(1-8000/44100) = 81.8594%` fewer after conversion. Uncompressed stream drops from 88.2 kB/s to 16.0 kB/s.
- Feature extraction speedup: `0.1961 s` down to `0.0531 s` (72.95% compute time saved, 3.70x speedup) on development split across 93 measurements.
- Saved two-phrase compute time: `0.625346309677419 s / 0.472614952688172 s = 1.32316x` speedup, or `24.4235%` time saved. Each condition has 93 timing samples (31 source pairs, three repeats). Capture, disk I/O, GUI, and meal actions are excluded.
- Transaction latency: Adaptive silence hangover terminates at 0.80 s instead of legacy 2.50 s timeout, saving 1.70 s per spoken phrase (3.40 s saved per full ID+Name meal transaction).
- Synthetic-noise nearest-template ranking: `276/372 = 74.1935%` without suppression and `315/372 = 84.6774%` with spectral subtraction, a gain of `10.4839` percentage points. Mean known-reference SNR change is `5.38399 dB`. This is controlled additive noise, not a field cafeteria result or a security acceptance rate.
- Synthetic scalar-gain ranking: `170/186 = 91.3978%` without AGC and `171/186 = 91.9355%` with AGC, a gain of `0.5376` percentage points. Scalar attenuation does not reproduce physical microphone distance.
- Synthetic endpoint fixtures: energy-only falsely marks one of four non-speech signals (25% false trigger on low-frequency rumble); hybrid marks zero (0% false trigger, -25.0 percentage points). Both keep the harmonic-speech fixture.
- Synthetic temporal alignment: correlation ranks the reference first in two of four scenarios (50%) and DTW in four of four (100%), a gain of +50 percentage points on speaking rate shifts.
- Biometric verification across all 31 students: Rigid top-1 agreement accepts `15/31` (48.39%), falsely rejecting 16 genuine students (51.61% FRR). Multi-modal score fusion verifies `30/31` (96.77%), achieving `+48.38 percentage points` genuine access gain with `0/930` false accepts (0.00% FAR) on the retrospective final test cohort.
- Reconstructed MFCC front-end pair EER is `8.3333%` at both 16 and 8 kHz in the small saved experiment: zero measured EER improvement in that comparison.

The implemented noise algorithm subtracts power: `Pclean=max(|Y|^2-alpha*Pnoise,beta*Pnoise)`, then reconstructs the square-root magnitude with the original phase. Proposal Eq. 1 is magnitude subtraction with a different floor. The tab states this difference instead of presenting the proposal equation as the implemented equation.

The GUI Improvements tab provides top KPI summary cards (81.86% Data reduction, 3.70x Extraction speedup, 24.42% Compute saved, 96.77% Genuine access) and an interactive dropdown with both a **Merged Cohort Summary** and a per-student **Student cohort breakdown (all 31 persons)** table.

## Strict rule replay and its rejection cost

The helper joins `current_dsp/final_test` ID, Name, and ID+Name trials on actual student, claimed student, trial type, and genuine flag. It verifies complete matching keys, binary decisions, the genuine-label relationship, the complete `31*31` claim matrix, and that historical fallback equals `IDpass OR Namepass`. Strict replay uses `IDpass AND Namepass` for the same claimed identity.

The replay appears only if the active four phrase gates equal the frozen values in `run_summary.json`: ID threshold `31.3481707602672`, ID margin `1.200706035092533`, Name threshold `30.351024711013427`, Name margin `1.2123533210235664`. Changing any gate invalidates the replay rather than silently applying stale decisions.

| Rule on the saved trials | Genuine accepted | Acceptance | FRR | Own-content false claims accepted |
|---|---:|---:|---:|---:|
| Historical fallback | 30/31 | 96.7742% | 3.2258% | 0/930 |
| Strict ID AND Name | 15/31 | 48.3871% | 51.6129% | 0/930 |

The stricter rule costs `48.3871` percentage points of genuine acceptance on these archived decisions. The observed FAR difference is zero on this particular false-claim set. The speakers said their own ID/name while claiming someone else; these trials do not measure a person intentionally speaking a target student's ID and name. This is a counterfactual replay, not a rerun of the current audio preprocessing or a live/unknown-speaker benchmark. No parameter is retuned on the final takes.

## Reproduction and next evaluation

Run `test_project_improvement_report` in MATLAB for numerical, source-selection, matching-key, missing-file, zero-reference, and changed-gate checks. The tests use the saved evidence plus a small temporary CSV fixture; they do not record or alter enrollment.

For new security figures, freeze the current code, enrollment, and thresholds first. Collect separately labeled genuine, wrong-ID/name, deliberately spoken target-ID/name, and unknown-speaker captures through the current live path. Keep enrollment, development and final sessions separate; report both accepted impostors/total impostor attempts and rejected genuine/total genuine attempts, with counts and capture conditions. Validate the liveness heuristic on labeled live and playback captures separately. Until then, current live accuracy and targeted impersonation resistance remain unmeasured.
