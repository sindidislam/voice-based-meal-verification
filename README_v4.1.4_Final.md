# Voice-Based Meal Verification System for Hall Dining — v4.1.4_Final

EEE 312 (DSP Laboratory) · Group 07 · BUET

This folder is a copy of **Final project v4.1.4** with a new verification
engine (the *VSD engine*, files `vsd_*.m`). The meal windows, monthly roster,
admin tools, logs and GUI still work the way they did in v4.1.4. What changed
is how the system decides **who is speaking**, plus two new security layers:
imposter identification and replay-attack prevention.

## 0. Check which engine is running

Open MATLAB **inside this folder** (`Final project v4.1.4_Final`) and type `RUN_ME`.
The first line of every transaction in the status box must read

```
Engine: v4.1.4-Final (phrase content + voice biometrics + anti-replay)
```

and the footer must say `ENGINE v4.1.4-Final`. If you see lines such as
"Multi-modal joint biometric ranking" and "39-dimensional MFCC features" with no
"Engine:" line, MATLAB is running the **old** `Final project v4.1.4` folder, which
has no working voice check and no anti-replay.

## 1. How to run

```matlab
>> RUN_ME              % counter GUI (first run builds the voice models, ~1 min)
>> RUN_ME('demo')      % 7 end-to-end cases: genuine, 2 imposters, 4 replay attacks
>> RUN_ME('evaluate')  % every stored voice: LOTO, cross-mic, unknown speaker, mimic
>> RUN_ME('rebuild')   % re-extract every recording and retrain the models
```

**Where the recordings come from.** The engine looks for the voice profiles in
this order:

1. `VSD_Enrollment/Train` (inside this folder)
2. `Train`
3. The sibling folder `../Final project v4.1.4/VSD_Enrollment/Train`

So the version runs without copying the WAV files. Each student has three
sub-folders:

- `ID/<id>/*.wav` and `Name/<id>/*.wav`: all takes are used.
- `Digits/<id>/<id>_<digit>_01.wav`: the ten isolated digits.

The Admin workspace has two new buttons. **Record digits 0-9** records the
digits for a new student. **Rebuild voice models** updates the models on demand.
The models also update automatically whenever a recording is added.

## 2. Why v4.1.4 rejected genuine students (e.g. 2206147)

| # | Root cause (found in code + `VerificationAttempts.csv`) | Effect |
|---|---|---|
| 1 | `apply_voice_calibration` forced `enrollmentTemplateFileNames = {'1.wav'}` | Each student had **one** template, recorded on one microphone |
| 2 | The frozen calibration set `mfcc.CmsNormalise = 0` | The microphone's transfer function H(ω) stayed inside every MFCC |
| 3 | The roll numbers `2206xxx` share 4–5 of 7 digits | ID-phrase DTW margins were 1.00–1.05 for everyone, so "ID top-1 = Name top-1" failed at random |
| 4 | Fixed raw-distance ceilings (31.35 / 30.35) | A new mic or room shifts **all** distances up, so everyone was rejected |
| 5 | The 8-mixture GMM was trained on only 1 take per student | The voice model was weak and was not used to decide |

## 3. What the new engine does

```
mic ─► resample 8 kHz ─► DC removal ─► spectral subtraction ─► pre-emphasis
      ─► 25 ms Hamming frames ─► |FFT|² ─► 26 mel filters (100–3800 Hz) ─► log ─► DCT
      ─► c1..c12 + Δ   ──► CMVN ──► content features (WHAT was said)
      └► c1..c12 CMVN + Δ          ──► speaker features (WHO is speaking)

content: DTW (Sakoe-Chiba 0.4) against ALL takes of every student
         P(k) = log( mean 5 nearest rival distances / d_k )     (cohort score)
voice:   GMM-UBM, 64 mixtures, UBM from everyone's digits, MAP adaptation r = 16
         V(k) = LLR(k) − mean of the 5 best rival LLRs
decision F = 0.5·P_id + 1.0·P_name + 0.25·V ;  c = argmax F
  accept c if P_name ≥ 0.07, P_id ≥ −0.15, V ≥ 0 and c is the best voice
  or if c is a CLEAR WINNER: F(c) − F(rank 2) ≥ 0.08, P_name ≥ 0.12,
     voice rank ≤ 3, V ≥ −0.10                                   (v1.1)
  IMPOSTER if the words point to X but voice Y beats X by ≥ 0.15 (report Y)
  UNKNOWN  if no voice and no name matches (not enrolled)
anti-replay: 1) random 3-digit challenge checked against the student's own
             digits + 27 one-digit decoys, in the same voice (gap < 0.40),
             splice guard (distance < 2.0 = pasted from the stored digits)
             2) replay memory: exact copy of a stored / accepted take (DTW < 1)
             3) sub-200 Hz loudspeaker heuristic (advisory, logged)
self-adaptation: confident accepts on a new microphone are stored as extra
             templates (max 3 per phrase), so the system learns the new mic
```

## 4. Measured results (all voices in the folder)

All figures below come from `RUN_ME('evaluate')` and `RUN_ME('demo')`, run in GNU Octave 8.4. The same code runs in MATLAB. Output files are in `Results/final_eval/`.

| Protocol | Result |
|---|---|
| Leave-one-take-out, all microphones | **114/116 = 98.3 %** genuine accepted (same mic 88/88, other mics 26/28), **0** wrong-student accepts |
| Cross-microphone: enrolled on the database mic only, tested on other mics | **18/20 = 90.0 %**, 0 wrong accepts |
| Unknown speaker: each student removed from enrolment in turn | **0/116** accepted |
| Perfect-words imposter: the words are right but the voice is another student | **0.22 %** accepted (8 of 3596); the real speaker is named as "likely imposter" in **97.4 %** |
| Full transaction per student, challenge included (`vsd_transaction_sweep`) | **30/32** verified end-to-end |
| `RUN_ME('demo')`: genuine, 2 imposters, digital replay, loudspeaker replay, stale code, splice | **7/7** behave as designed |

**Fair comparison against the older systems (enrol take 1 only, as v4.1.4 did).** These numbers come from the Python mirror of the same front-end:

| System | same mic GAR | other mic GAR | unknown-speaker FAR |
|---|---|---|---|
| Senior baseline (VQ-LBG, 44.1 kHz) | 87.9 % | 25.9 % | 15.4 % |
| v4.1.4 (Group 07 previous) | 84.5 % | 7.4 % | 1.7 % |
| **v4.1.4_Final 1.1** | **100 %** | **85.2 %** | **0.9 %** |

**Anti-replay challenge.**

- Genuine live answers pass the digit-content check 93 % of the time per attempt.
- Adding the voice check gives 90.7 % genuine vs 1.9 % another student (`vsd_calibrate_challenge_voice`).
- Replayed ID/name recordings passed 0 of 18 trials, and old-code recordings passed 0 of 18.
- A spliced answer built from the enrolled digit files is caught: its distance is 0.01, while the smallest genuine distance is 3.58.

**Known gaps.**

- Two genuine students failed the sweep: 2206145 failed the challenge on both codes, and 2206150's name score was 0.05, below the 0.07 threshold (and below the 0.12 clear-winner floor).
- Students 2206135, 2206148 and 2206149 have no isolated digits, so their challenge uses cohort templates. Record their digits with **Record digits 0-9**.

## 5. What changed in v1.1 (30 September 2026) and why

Two field logs from the counter drove these changes. Both logs came from the **old v4.1.4 matcher**.

**Log 1: 2206141 was refused although he ranked first.**

- The ID phrase picked another student (2206157, then 2206144). This happened because roll numbers are near-identical.
- The name picked 2206141, but its lead of 1.209 and 1.194 missed the fixed 1.212 margin.

The fix was a choice between two options, both measured with enrolment on take 1:

| Option | Genuine accepted | Unknown speakers accepted | Perfect-words imposters accepted |
|---|---|---|---|
| v1.0 | 91.8 % | 0.9 % | 0.08 % |
| Lower `MinPname` 0.07 → 0.05 | 91.8 % | 3.4 % (2.6 % with all takes) | 0.08 % |
| **v1.1: `MinPid` −0.15 + clear-winner rule** | **95.3 %** | **0.9 %** | 0.25 % |

We chose the clear-winner rule. It accepts rank 1 when it is far ahead of rank 2, has a strong name score and a top-3 voice. Lowering the threshold would also admit strangers.

**Log 2: 2206147 said 2206150's roll number and name and was served a meal.**

- The old matcher only compares words: joint score 1.13 against 1.21 for rank 2, and both distances were above their limits.
- The v4.1.4_Final engine refuses this attack. Each of 2206147's four takes, scored as perfect words for 2206150, returns **IMPOSTER — likely imposter 2206147**. The voice scores are V(2206150) = −0.46 to −0.85 (rank 16–28) against V(2206147) = +0.26 to +1.47.

**Changes in v1.1:**

- `vsd_config.m`: `MinPid` changed from −0.10 to −0.15, and `ClearWin.*` was added. Version is now `v4.1.4-Final`.
- `vsd_decide.m`: clear-winner branch, with `R.Rule` set to `'standard'` or `'clear-winner'`.
- `speaker_verification_decision.m`: relative clear-winner rescue for the legacy matcher.
- `vsd_voice_veto.m` (new), `capture_voice_features.m` and `verify_meal_workflow.m`: the legacy matcher's accept must now pass the GMM-UBM voice check. An imposter is refused and named.
- `meal_verification_gui.m` and `verify_meal_workflow.m`: the status box names the engine on every transaction.

## 6. Files

**New files:**

- `vsd_config.m`
- `vsd_frontend.m`
- `vsd_dtw.m`
- `vsd_gmm.m`
- `vsd_build_models.m`
- `vsd_models.m`
- `vsd_score_query.m`
- `vsd_decide.m`
- `vsd_challenge.m`
- `vsd_replay_guard.m`
- `vsd_adapt.m`
- `vsd_record_phrase.m`
- `vsd_enrol_digits.m`
- `vsd_verify_transaction.m`
- `vsd_evaluate_corpus.m`
- `vsd_transaction_sweep.m`
- `vsd_calibrate_challenge_voice.m`
- `vsd_voice_veto.m`
- `test_vsd_engine.m`
- `test_vsd_engine_answer.m`

**Changed files:**

- `verify_meal_workflow.m`: runs the VSD engine and keeps the legacy fallback.
- `dsp_parameters.m`: adds `params.vsd` and unified profile paths.
- `apply_voice_calibration.m`: no 1.wav-only rule; no hard error on missing folders.
- `meal_verification_gui.m`: 6-gate security table, IMPOSTER/REPLAY/UNKNOWN banners, digit recorder, model rebuild, evaluation entries.
- `log_verification_attempt.m`: new columns Engine, VoiceScore, ImposterSuspect, ReplayFlag, Challenge.
- `RUN_ME.m`: path hygiene and the new modes.
- `speaker_verification_decision.m`: clear-winner rescue (legacy matcher).
- `capture_voice_features.m`: keeps the raw capture for the voice veto.

To switch back to the v4.1.4 matcher, set `params.vsd.Enable = false`.
