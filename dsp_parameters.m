function params = dsp_parameters(loadCalibration)
%DSP_PARAMETERS Single source of truth for the meal-verification DSP chain.
%
%   Voice-Based Meal Verification System for Hall Dining
%   EEE 312 Digital Signal Processing I Laboratory -- Group 07, Section C1
%
%   Default DSP and business parameters are declared here. A saved calibration
%   may override the feature settings, profile paths and phrase gates.
%   Current measured results are in Results/experiments_20260927 and the
%   deployment audit; comments are explanations, not live measurement output.
%
%   DSP_PARAMETERS(false) returns the pre-calibration reference for experiments.
%   See also PREPROCESS_AUDIO, VERIFY_MEAL_WORKFLOW, VERIFY_DSP_PIPELINE.
if nargin<1, loadCalibration=true; end

% ---------------------------------------------------------------------
% 1. ACQUISITION AND RATE CONVERSION
%    Experiment 1 (Sampling / Nyquist) and Experiment 2 (Rate conversion)
%    Proposal modification 1a: decimate the 44.1 kHz capture to 8 kHz.
%
%    At 8 kHz the Nyquist boundary is 4 kHz. Anti-alias filtering removes
%    out-of-band content before decimation; higher-frequency speaker cues may
%    be lost. Saved rate experiments justify this corpus-specific choice.
%    A fixed-duration waveform has 44100/8000 fewer samples, but fixed 10 ms
%    feature hops retain approximately the same frame count and DTW grid.
%    Sample-count reduction is not a measured end-to-end speedup.
% ---------------------------------------------------------------------
params.fs           = 44100;   % Hz, native sound-card capture rate.
params.processingFs = 8000;    % Hz, DSP rate. rat(8000/44100) = 80/441 exactly.
params.recordDur    = 8;       % s maximum; automatic stopping may end capture earlier.
params.maxVoiceRetries = 2;    % Legacy setting; current workflow uses maxVerificationAttempts.
params.maxVerificationAttempts = 1; % One ID and one Name recording; both must verify.
params.speechStop = struct('FrameDuration',.02,'OnsetDuration',.12, ...
    'HangoverDuration',3.0,'MinVoicedDuration',.25,'StartNoiseRatio',3.5, ...
    'EndNoiseRatio',2.0,'MinStartRms',0.0025,'MinEndRms',0.0012,'UseZcr',false, ...
    'EndRelativeDb',25.0);

params.requireMonthlyRoster = true;   % Verify against direct MonthlyFeeEntitlement.csv roster (no coupon required).
params.requireCoupon        = false;  % Coupon system replaced by direct ID roster.
params.couponMode           = 'disabled'; % Legacy metadata only; coupon authorization has been removed.
params.quality.MinLiveSpeechDuration = 0.60; % Reject brief bursts before speaker matching.

% Anti-imaging / anti-aliasing FIR half-length used by RESAMPLE.  The
% designed filter length is 2*FilterOrder*max(L,M)+1 taps, so the transition
% band is narrow enough that the 4 kHz folding frequency is protected.
params.resample.FilterOrder = 20;
params.resample.Beta        = 5;   % Kaiser window shape parameter.

% ---------------------------------------------------------------------
% 2. AUTOMATIC GAIN CONTROL
%    Experiment 1 (amplitude scaling of discrete-time signals)
%    Proposal modification 1b: reduce level variation with RMS normalization.
%    RMS averages squared amplitudes and remains sensitive to large outliers.
%    Gain alone does not improve SNR or remove room/microphone effects.
%    The peak-headroom guard rescales the entire signal rather than clipping.
% ---------------------------------------------------------------------
params.agc.TargetRms = 0.05;   % Target root-mean-square amplitude.
params.agc.MaxGain   = 40;     % Cap so that near-silence is not amplified.
params.agc.MinRms    = 1e-5;   % Below this the frame is treated as silence.
params.agc.Headroom  = 0.99;   % Peak limit applied after scaling.

% ---------------------------------------------------------------------
% 3. NOISE PROFILING AND SPECTRAL SUBTRACTION
%    Experiment 4 (DFT / spectral analysis)
%    Proposal modification 3: estimate the dining-hall noise floor from a
%    0.5 s pre-roll instead of applying a pre-emphasis filter.
%
%    Pre-emphasis tilts the spectrum toward higher frequencies; it is not a
%    noise estimator. The selected path leaves it off. Optional support remains
%    for controlled comparisons. Noise and accuracy claims must come from the
%    declared synthetic or recording protocol, not from a filter name.
% ---------------------------------------------------------------------
params.usePreEmphasis = false; % Proposal: pre-emphasis is DISCARDED.
params.alpha          = 0.97;  % Baseline value, used only when the above is true.

params.noise.NoiseDuration       = 0.50;  % s, ambient pre-roll length (proposal / templates).
params.noise.LiveNoiseDuration   = 1.00;  % s, ambient pre-roll length for live capture.
params.noise.FrameDuration       = 0.032; % s, STFT analysis window.
params.noise.HopFraction     = 0.25;  % Hop as a fraction of the window.
params.noise.Oversubtraction = 2.0;   % Multiplier for noise POWER subtraction.
params.noise.SpectralFloor   = 0.02;  % Noise-power floor; limits artifacts, does not eliminate them.
params.noise.Enable          = true;

% ---------------------------------------------------------------------
% 4. HYBRID ENDPOINT DETECTION (STE AND TWO-SIDED ZCR)
%    Experiment 3 (Short-time analysis: energy and zero-crossing rate)
%    Proposal modification 4: replace the single energy threshold with a
%    logical AND of short-time energy and a two-sided zero-crossing band.
%
%    A two-sided ZCR band can reject some low-frequency and high-crossing
%    interference. Combined energy, run-length and gap rules are heuristics:
%    they do not guarantee preservation of every soft consonant or rejection
%    of every tray impact. Field speech-boundary labels are unavailable.
% ---------------------------------------------------------------------
params.endpoint.FrameDuration    = 0.020; % s, short-time frame.
params.endpoint.HopDuration      = 0.010; % s, frame advance.
params.endpoint.NoiseDuration    = 0.50;  % s, statistics learnt from pre-roll.
params.endpoint.EnergyMultiplier = 4.0;   % STE threshold = mult * noise STE.
params.endpoint.ZCRMinFactor     = 0.50;  % Retained legacy field; active lower edge is absolute.
params.endpoint.ZCRMaxFactor     = 2.50;  % Noise-relative term, combined with absolute bounds.
params.endpoint.ZCRAbsoluteMax   = 0.45;  % Upper crossing-rate bound; heuristic.
params.endpoint.ZCRAbsoluteMin   = 0.008; % Lower crossing-rate bound; heuristic.
params.endpoint.MinActiveFrames  = 3;     % Reject isolated single-frame events.
params.endpoint.MaxGapFrames     = 8;     % Bridge inter-word pauses.
params.endpoint.PaddingDuration  = 0.040; % s, context kept either side.

% ---------------------------------------------------------------------
% 5. LOW-BAND ENERGY HEURISTIC
%    Experiment 4 (DFT band energy), proposal modification 2.
%    The low/wide-band energy ratio depends on pitch, phonetic content,
%    microphone, room and playback hardware. Genuine voices may have little
%    sub-200 Hz energy, while loudspeakers can preserve it. This is not proof
%    of liveness; no labeled live-versus-replay accuracy is established.
% ---------------------------------------------------------------------
params.liveness.Enable      = true;
params.liveness.LowBand     = [20 200];   % Hz, low-frequency diagnostic band.
params.liveness.FullBand    = [20 3800];  % Hz, speech band below Nyquist.
% These reference bounds are retained in the selected configuration. Historical
% genuine-only calibration does not establish replay detection, and the current
% recording results must be reported with their own roster and denominators.
params.liveness.MinRatio    = 0.00024;    % Low-band heuristic; not proof of replay.
params.liveness.MaxRatio    = 0.70000;    % High ratios may indicate rumble; heuristic.
params.liveness.MinDuration = 0.15;       % s, minimum speech needed to judge.
params.liveness.CentroidBand = [150 3500];% Hz, band to evaluate spectral centroid.
params.liveness.MaxCentroid = 1200;       % Hz, centroid ceiling (loudspeaker roll-off / resonance).

% ---------------------------------------------------------------------
% 6. FEATURE FRONT-END
%    Experiment 4 (DFT) and Experiment 3 (short-time framing)
%
%    'dft' uses uniform log-spectrum bands; 'mfcc' uses mel filters, log, DCT,
%    liftering and temporal derivatives. Their distance scales differ.
%    The current frozen configuration selects MFCC. Historical comparison
%    tables are separate from the 31-profile recording-disjoint experiment.
%    Switching a deployed frontend requires a corresponding phrase gate map.
% ---------------------------------------------------------------------
params.featureFrontEnd = 'mfcc';

% Proposal DFT front-end.
params.dft.FrameDuration = 0.030;  % s, 30 ms frame as specified.
params.dft.HopDuration   = 0.015;  % s, 50 percent overlap.
params.dft.NumBands      = 24;     % Uniform magnitude bands retained.
params.dft.Band          = [80 3800]; % Hz, full usable band (not truncated).
params.dft.LogFloor      = 1e-8;   % Guards log of zero.
params.dft.CmvNormalise  = true;   % Per-utterance mean/variance normalisation.

% Optional temporal regression derivative for the DFT feature sequence.
% Its default is retained for compatibility; adding dimensions is not assumed
% to improve discrimination without a controlled development comparison.
params.dft.IncludeDelta  = false;
params.dft.DeltaSpan     = 2;      % Frames either side, i.e. +/- 30 ms.

% MFCC front-end used by the selected configuration.
params.Tw = 25;          % ms, frame duration.
params.Ts = 10;          % ms, frame shift.
params.R  = [300 3700];  % Hz, baseline band limits.
params.M  = 26;          % Mel filters.
params.C  = 13;          % Cepstral coefficients retained.
params.L  = 22;          % Sinusoidal lifter parameter.

% Robust MFCC defaults: Cepstral Mean Subtraction (CMS) is enabled to eliminate
% stationary microphone transfer function offsets c_mic across different hardware.
params.mfcc.CmsNormalise      = true;
params.mfcc.CmvNormalise      = false;
params.mfcc.DropC0            = false;
params.mfcc.useCMVN           = false;
params.mfcc.IncludeDelta      = true;
params.mfcc.IncludeDeltaDelta = true;

% ---------------------------------------------------------------------
% 7. DYNAMIC TIME WARPING MATCHER
%    Experiment 5 / 6 (Correlation and time-domain comparison of sequences)
%    Proposal Goal 2: DTW replaces the time-domain cross-correlation match.
%
%    Local Euclidean costs are accumulated along monotone three-predecessor
%    paths. This implementation normalizes by N+M, not actual path length.
%    Gates depend on feature scale, preprocessing and reference protocol.
%    APPLY_VOICE_CALIBRATION loads the frozen ID/Name gates; use
%    SELECT_FEATURE_FRONTEND to preserve the frontend-to-gate binding.
% ---------------------------------------------------------------------
params.dtw.SakoeChibaBand = 0.45;  % Warping constraint, fraction of length (accommodates slow/fast speech).
params.dtw.Normalise      = true;  % Divide by N+M, not the actual path length.

% Historical single-phrase reference values retained for legacy experiments.
% These values are not the current saved ID/Name deployment gates.
params.perPhraseReference.mfcc = struct('Threshold',31.6868,'Far',0.010, ...
    'Frr',0.1546,'Eer',0.0829,'EerThreshold',37.1585);
params.perPhraseReference.dft  = struct('Threshold', 1.8188,'Far',0.010, ...
    'Frr',0.2062,'Eer',0.1131,'EerThreshold', 2.2064);

% Legacy frontend defaults are retained below. When VoiceCalibration.mat is
% present, its frozen phrase-specific ceilings and margins replace deployment
% settings. Current verification is ID-first independent Name fallback; the
% two phrases are not required to agree or pass together.
params.dtwThresholdByFrontEnd.mfcc = 37.1585;
params.dtwThresholdByFrontEnd.dft  =  2.4227;

if isfield(params.dtwThresholdByFrontEnd, params.featureFrontEnd)
    params.dtwThreshold = params.dtwThresholdByFrontEnd.(params.featureFrontEnd);
else
    error('dsp_parameters:noThreshold', ...
        ['Front-end "%s" has no calibrated DTW threshold. Run ' ...
         'CALIBRATE_DTW_THRESHOLD and add the result to ' ...
         'params.dtwThresholdByFrontEnd.'], params.featureFrontEnd);
end

% Default runner-up / best-distance margin. The accepting phrase must win
% the independently entered claim and satisfy both its ceiling and margin.
% A runner outside the distance ceiling never waives the margin requirement.
params.dtwMarginRatio = 1.20;
params.cohortGate = 0.12;
params.cohortMaxDistanceFactor = 1.35;
params.useCohortRatio = true;

% Biometric score-level fusion for live open voice identification
params.enableScoreFusion = true;
params.liveFusedThreshold = 1.15;
params.demoMode24x7 = false; % Set to true for 24/7 testing without meal window enforcement



% GMM-UBM text-independent voice timbre verification
params.voiceGMM.Enable = loadCalibration;
params.voiceGMM.ModelFile = fullfile(fileparts(mfilename('fullpath')), 'VoiceGMM_Model.mat');
params.voiceGMM.NumMixtures = 8;
params.voiceGMM.RelevanceFactor = 16;

% ---------------------------------------------------------------------
% 8. ENROLMENT TEMPLATE HANDLING
% ---------------------------------------------------------------------
projectRoot = find_project_root();
params.trainBaseFolder   = fullfile(projectRoot,'Train');
% The seven-digit Student ID is the canonical identity. Each profile stores its
% spoken-ID takes under Train/ID/<id>, its spoken-name takes under
% Train/Name/<id>, and its spoken-coupon takes under Train/Coupon/<id>. Every
% root is keyed by the ID, so the display name is metadata rather than a key.
params.trainIdFolder     = fullfile(params.trainBaseFolder,'ID');
params.trainNameFolder   = fullfile(params.trainBaseFolder,'Name');
params.trainCouponFolder = fullfile(params.trainBaseFolder,'Coupon');
% Filename that holds the display name inside a student's ID folder.
params.profileFileName   = 'profile.mat';
% The deployed matcher only considers folders whose name is a valid seven-digit
% Student ID, so the legacy name-keyed senior corpus is ignored. Offline
% experiments that deliberately measure the old corpus set this to false.
params.idKeyedProfilesOnly = true;
params.testFolder        = fullfile(projectRoot,'Test');
params.codeFileName      = 'code.txt';
params.samplesPerPhrase  = 3;

% A stored WAV that begins with speech has no ambient pre-roll to profile.
% The ratio below decides whether a template is "raw with quiet lead-in" or
% "legacy cropped"; the two cases take different preprocessing paths.
params.templateQuietLeadInRatio = 0.35;
params.templateMinimumRms       = 1e-4;

% The low-band heuristic is enforced on live capture and recorded as a
% diagnostic on archived templates. Archived recordings use a distinct
% preprocessing policy and cannot establish live replay performance.
params.enforceLivenessOnTemplates = false;

% ---------------------------------------------------------------------
% 9. DINING HALL BUSINESS LOGIC
%    Proposal modification 5 and Goal 5 (CO4, CO5).
% ---------------------------------------------------------------------
params.logFile = fullfile(projectRoot,'MealLog.csv');
params.monthlyEntitlementFile = fullfile(projectRoot,'MonthlyFeeEntitlement.csv');
params.monthlyCouponFile = fullfile(projectRoot,'MonthlyCouponRegistry.csv');
params.mealScheduleFile = fullfile(projectRoot,'MealSchedule.csv');

% Meal service windows as [startHour startMinute endHour endMinute].
% v4.1.4: Loaded from persistent MealSchedule.csv if present, else defaults.
params.meals = load_meal_schedule(params);

% One serving per student per meal window per calendar day.
params.oneMealPerWindow = true;

params.adminId       = 'admin';
params.adminPassword = 'admin';

% ---------------------------------------------------------------------
% 10. EVALUATION AND REPRODUCIBILITY
% ---------------------------------------------------------------------
params.evaluation.ComparisonRates = [8000 16000];
params.evaluation.FrontEnds       = {'dft','mfcc'};
params.evaluation.Matchers        = {'dtw','xcorr'};
params.evaluation.ResultsFolder   = fullfile(projectRoot,'Results');
params.evaluation.RandomSeed      = 312;
if loadCalibration && exist('apply_voice_calibration','file')==2
    % v4.1.4_claude: a missing or stale calibration must never stop the counter
    % (v4.1.4 raised an error when the profile folders were absent).
    try
        params=apply_voice_calibration(params,projectRoot);
    catch err
        warning('dsp_parameters:calibration', 'Legacy voice calibration skipped: %s', err.message);
    end
end

% ---------------------------------------------------------------------
% 11. v4.1.4_claude VOICE-SECURITY ENGINE (VSD engine)
%     Two-evidence verification (phrase content + GMM-UBM voice), imposter
%     identification and replay-attack prevention.  See VSD_CONFIG.
%     Set params.vsd.Enable = false to fall back to the v4.1.4 matcher.
% ---------------------------------------------------------------------
if exist('vsd_config','file')==2
    params.vsd = vsd_config(projectRoot);
    if params.vsd.Enable
        % every enrolment / import / explorer path uses the same profile root
        params.trainBaseFolder   = params.vsd.DataRoot;
        params.trainIdFolder     = fullfile(params.vsd.DataRoot,'ID');
        params.trainNameFolder   = fullfile(params.vsd.DataRoot,'Name');
        params.trainCouponFolder = fullfile(params.vsd.DataRoot,'Coupon');
        params.trainDigitsFolder = fullfile(params.vsd.DataRoot,'Digits');
        params.voiceGMM.Enable   = false;   % replaced by the 64-mixture GMM-UBM of the engine
    end
end
end
