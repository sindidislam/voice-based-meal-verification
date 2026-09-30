# Voice-Based Meal Verification System for Hall Dining

[![Platform](https://img.shields.io/badge/Platform-MATLAB%20R2024a+%20%7C%20GNU%20Octave%208.4+-orange.svg)](#requirements--environment)
[![Course](https://img.shields.io/badge/Course-BUET%20EEE%20312%20(DSP%20Lab)-blue.svg)](#authors--project-credits)
[![Group](https://img.shields.io/badge/Group-Group%2007%20(Section%20C1)-success.svg)](#authors--project-credits)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Engine](https://img.shields.io/badge/Engine-v4.1.4_Final--1.1-brightgreen.svg)](#system-architecture)

> **EEE 312: Digital Signal Processing I Laboratory — Final Capstone Project**  
> *Department of Electrical and Electronic Engineering (EEE)*  
> *Bangladesh University of Engineering and Technology (BUET)*

---

## Authors & Project Credits

This project was engineered and submitted by **Group 07 (Section C1)**:

1. **S M Sindid Islam Mahodi** (Roll: `2206147`) — **Lead Author & System Architect**  
   *Email: [sindidislam101@gmail.com](mailto:sindidislam101@gmail.com)*
2. **Samin Zahan Khan** (Roll: `2206135`)
3. **Syed Ibnul Morshed** (Roll: `2206141`)
4. **Abdullah Al Rohan** (Roll: `2206150`)

**Academic Supervision:**  
Department of Electrical and Electronic Engineering  
Bangladesh University of Engineering and Technology (BUET), Dhaka-1000, Bangladesh

---

## Executive Summary

In university residence hall dining facilities, meal token theft, manual paper roster overhead, buddy-punching, and coupon duplication cause substantial administrative and financial inefficiencies. 

This repository delivers a **state-of-the-art Voice-Based Dining Hall Verification and Access Control System** combining:
- **Acoustic Front-end Preprocessing**: Rational downsampling (44.1 kHz $\to$ 8 kHz), pre-emphasis, Short-Time Energy (STE) + Zero-Crossing Rate (ZCR) voice activity detection, and adaptive spectral noise subtraction.
- **Content Matching (What was said)**: 26-channel Mel-filterbank Cepstral Coefficients (MFCC $c_1..c_{12}$ + $\Delta$) with Cepstral Mean and Variance Normalization (CMVN) evaluated against enrolled phrase takes using Dynamic Time Warping (DTW) with Sakoe-Chiba constraint band and cohort normalization.
- **Voice Biometrics (Who is speaking)**: 64-mixture Gaussian Mixture Model — Universal Background Model (GMM-UBM) with Maximum A Posteriori (MAP) acoustic adaptation.
- **Active Anti-Replay Defense**: Dynamic randomized 3-digit challenges, acoustic splice detection, and loudspeaker sub-200 Hz spectral energy ratio checks.
- **Comprehensive Dining Hall Administration**: Real-time MATLAB App Designer/uifigure GUI, admin meal window scheduler (Breakfast/Lunch/Dinner), monthly roster entitlements, and immutable single-meal-per-service-session enforcement.

---

## System Architecture

```text
                                [ MICROPHONE INPUT ]
                                         │
                    Rational Resampling (44.1 kHz -> 8 kHz)
                                         │
                         DC Removal & Pre-Emphasis (0.97)
                                         │
                    Adaptive Spectral Noise Subtraction (α=2.0, β=0.02)
                                         │
                  Speech Endpoint Detection (STE + ZCR + 0.8s Hangover)
                                         │
                    25 ms Hamming Windowing / 10 ms Frame Shift
                                         │
                        26 Mel-Scale Filterbanks (100 - 3800 Hz)
                                         │
                          Log Compression + DCT -> c0..c12
                                         │
                       ┌─────────────────┴─────────────────┐
                       ▼                                   ▼
            [ CONTENT STREAM (WHAT) ]           [ VOICE STREAM (WHO) ]
          c1..c12 + Delta Features             c1..c12 CMVN + Delta
                       │                                   │
             Cohort-Normalized DTW              64-Mixture GMM-UBM
           (Sakoe-Chiba Band R=0.4)             MAP Adaptation (r=16)
                       │                                   │
              P_id & P_name Scores                   LLR Voice Score
                       │                                   │
                       └─────────────────┬─────────────────┘
                                         ▼
                             [ FUSED DECISION ENGINE ]
                     Score: F = 0.5·P_id + 1.0·P_name + 0.25·V
                                         │
                 ┌───────────────────────┼───────────────────────┐
                 ▼                       ▼                       ▼
           [ GENUINE ]             [ IMPOSTER ]             [ REPLAY ]
       Standard / Clear-Winner  Spoken phrase matches   Fails random 3-digit
       Roster & Schedule check  target, but voice veto  challenge or acoustic
           -> MEAL SERVED       triggers -> REFUSED     splice test -> REFUSED
```

---

## Benchmark Results & Empirical Performance

All metrics below are verified across stored student voice trials using `RUN_ME('evaluate')` and `RUN_ME('demo')` under leave-one-take-out cross-validation protocols.

### 1. Comparative Performance Against Baselines

| Verification Architecture | Same-Mic Genuine Acceptance (GAR) | Cross-Mic Genuine Acceptance (GAR) | Unknown Speaker False Acceptance (FAR) | Imposter Interception Rate |
| :--- | :---: | :---: | :---: | :---: |
| **Senior's Baseline (VQ-LBG, 44.1 kHz)** | 87.9 % | 25.9 % | 15.4 % | < 50.0 % (No voice veto) |
| **Previous Project v4.1.4 (Fixed-Threshold DTW)** | 84.5 % | 7.4 % | 1.7 % | Unprotected (Words only) |
| **Current Engine (v4.1.4-Final)** | **100.0 %** | **85.2 %** | **0.9 %** | **99.78 %** |

### 2. Full Protocol Evaluation Summary

- **Leave-One-Take-Out (LOTO) Across All Microphones**: **114 / 116 = 98.3%** genuine accepted, **0 wrong-student accepts**.
- **Cross-Microphone Invariance**: **18 / 20 = 90.0%** genuine accepted when enrolled strictly on database mic and tested on unseen mics.
- **Zero-Trust Unknown Speaker Test**: **0 / 116 (0.0% FAR)** accepted when a non-enrolled person speaks valid phrases.
- **Perfect-Words Imposter Attack Defense**: When an imposter deliberately speaks a victim's exact roll number and full name, only **0.22%** (8 of 3,596) leak through; the true imposter's identity is correctly localized in **97.4%** of attempts.
- **End-to-End Counter Transactions (Challenge Included)**: **30 / 32** students verified end-to-end on real classroom recordings.

### 3. Anti-Replay Defense Evaluation

| Attack Vector | Test Trials | Accepted | Interception Rate | Detection Mechanism |
| :--- | :---: | :---: | :---: | :---: |
| **Digital Replay (WAV injection)** | 18 | 0 | **100.0 %** | Dynamic 3-digit challenge code mismatch |
| **Acoustic Loudspeaker Playback** | 18 | 0 | **100.0 %** | Replay memory + Sub-200 Hz spectral energy ratio |
| **Stale Challenge Code Replay** | 18 | 0 | **100.0 %** | One-time code invalidation |
| **Acoustic Splice / Concatenation** | 18 | 0 | **100.0 %** | Unnatural transition distance (DTW < 2.0 splice threshold) |

---

## Repository Directory Structure

```text
├── README.md                      # Primary documentation, architecture, and results
├── LICENSE                        # MIT License + plain-English legal & academic explanation
├── .gitignore                     # Git filter for MATLAB/Octave, temporary, and OS files
├── RUN_ME.m                       # Unified executable launcher
├── meal_verification_gui.m        # Interactive Dining Hall GUI (Verify, Enroll, Admin, Logs)
│
├── vsd_*.m                        # Core VSD Biometrics Engine:
│   ├── vsd_config.m               # Central hyperparameters and DSP constants
│   ├── vsd_frontend.m             # Resampling, filtering, Hamming, MFCC & CMVN
│   ├── vsd_build_models.m         # Automated GMM-UBM training & MAP adaptation
│   ├── vsd_dtw.m                  # Sakoe-Chiba band dynamic time warping
│   ├── vsd_gmm.m                  # GMM-UBM likelihood estimation
│   ├── vsd_decide.m               # Fused decision logic with Clear-Winner engine
│   ├── vsd_challenge.m            # Anti-replay random digit challenge generator
│   ├── vsd_replay_guard.m         # Splice and replay memory verification
│   └── vsd_voice_veto.m           # Voice biometric imposter veto
│
├── VSD_Enrollment/Train/          # Enrolled biometric voice templates (Group 07 members)
│   ├── ID/                        # Spoken roll number recordings
│   ├── Name/                      # Spoken full name recordings
│   └── Digits/                    # Isolated zero-to-nine calibration recordings
│
├── docs/                          # Comprehensive Technical & Academic Documentation
│   ├── EEE312_RevisedProposal_Group_07.pdf  # Official BUET Project Proposal
│   ├── Group07_Project_Guide_v4.1.4_Final.pdf # Complete system tuning & engineering manual
│   ├── DSP_THEORY_MANUAL.html     # Interactive DSP theory manual
│   ├── SYSTEM_MANUAL.html         # Dining hall deployment manual
│   └── ADMIN_MANUAL.html          # Hall administrator manual
│
├── presentation/                  # Slide Decks & Presentation Materials
│   ├── Group07_Voice_Meal_Verification_Presentation.pptx # Project defense presentation
│   └── PROJECT_PRESENTATION.html  # Interactive presentation companion
│
├── MealSchedule.csv               # Configurable meal service windows (Breakfast, Lunch, Dinner)
├── MonthlyFeeEntitlement.csv      # Current-month paid student entitlement database
└── MealLog.csv                    # Immutable record of verified and served dining transactions
```

---

## How to Run

### Requirements & Environment

- **MATLAB**: R2024a or later (recommended, with *Signal Processing Toolbox* and *Statistics and Machine Learning Toolbox*).
- **GNU Octave**: Version 8.4+ (fully supported; requires `pkg load signal`).
- **Operating System**: Windows 10/11, Linux, or macOS.
- **Hardware**: Any standard computer microphone (USB or built-in, 16 kHz or 44.1 kHz input).

### Quickstart

1. **Clone the repository**:
   ```bash
   git clone https://github.com/<your-username>/<repo-name>.git
   cd <repo-name>
   ```

2. **Open MATLAB or GNU Octave**:
   Set your working directory to the repository folder:
   ```matlab
   cd('path/to/repository')
   ```

3. **Launch the Dining Hall Counter GUI**:
   ```matlab
   RUN_ME
   ```
   *Note: On first execution, the system validates the enrolled templates and preloads the GMM-UBM voice models (~30 seconds).*

---

### Command-Line Modes & Test Suites

The root runner `RUN_ME.m` supports several operational modes:

| Command | Functionality | Expected Output |
| :--- | :--- | :--- |
| `RUN_ME` | Launches the primary graphical dining hall interface | Full-featured UI for live enrollment, dining verification, and administration |
| `RUN_ME('demo')` | Executes 7 automated attack scenarios (Genuine, 2 Imposters, 4 Replays) | **7/7** test cases intercepted and classified correctly |
| `RUN_ME('evaluate')` | Performs exhaustive leave-one-take-out cross-validation across all enrolled voices | Detailed confusion matrix, GAR, FAR, and imposter report |
| `RUN_ME('rebuild')` | Re-extracts all audio features and retrains the UBM and MAP models | Refreshed `VSD_Models.mat` |
| `RUN_ME('check')` | Runs diagnostic self-checks on audio paths and parameter files | Health confirmation |

---

### Administrator Workflow & Hall Operations

To access administrator settings:
1. In the GUI, navigate to the **Admin** tab.
2. Enter the administrator credentials (default: password `admin` or as configured in `admin_authorised.m`).
3. Click **Unlock / current month**.

From the Admin panel, administrators can:
- **Configure Meal Hours**: Click **Meal hours...** to interactively adjust Breakfast, Lunch, and Dinner operating windows with real-time overlap and bounds validation.
- **Assign Monthly Roster**: Filter students by ID, inspect payment records, and batch-assign dining eligibility for the calendar month (`MonthlyFeeEntitlement.csv`).
- **Reset Meal Logs**: Safely clear today's serving transactions (`Reset today only`) to allow re-verification during testing, without touching permanent historical records or student profiles.
- **Record Calibration Digits**: Click **Record digits 0-9** to enroll new student calibration samples.

---

## Biometric Data & Privacy Notice

In strict accordance with academic ethics and biometric privacy standards:
- **All non-consenting third-party voice samples were permanently removed from this public release.**
- This repository contains voice recordings **strictly from the consenting Group 07 project authors** (`2206147`, `2206135`, `2206141`, `2206150`), ensuring full reproducibility while protecting student privacy.
- These sample recordings are provided solely to enable academic verification and demonstration.

---

## License & Plain-English Explanation

This project is released under the **[MIT License](LICENSE)**.

### Plain-English Summary:
- **Permissions**: You are free to run, study, modify, merge, publish, and distribute this software for educational, academic, research, or commercial purposes.
- **Conditions**: You must retain the original copyright notice crediting **S M Sindid Islam Mahodi** and co-authors in any distribution or derivative work.
- **Academic Citation**: If this work contributes to your research or academic project, please cite:
  ```bibtex
  @software{mahodi2026voicemeal,
    author       = {S M Sindid Islam Mahodi and Samin Zahan Khan and Syed Ibnul Morshed and Abdullah Al Rohan},
    title        = {Voice-Based Meal Verification System for Hall Dining},
    year         = {2026},
    organization = {Department of EEE, Bangladesh University of Engineering and Technology (BUET)},
    version      = {v4.1.4-Final}
  }
  ```
- **Warranty**: Provided "as is", without warranty of any kind. Authors assume no liability for real-world deployments.
