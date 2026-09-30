function c = vsd_config(projectRoot)
%VSD_CONFIG Every setting of the v4.1.4_claude voice-security engine (VSD engine).
%
%   Voice-Based Meal Verification System for Hall Dining -- EEE 312, Group 07
%   v4.1.4_claude: robust two-evidence speaker verification + imposter
%   identification + replay-attack prevention.
%
%   C = VSD_CONFIG() returns the configuration struct used by VSD_FRONTEND,
%   VSD_BUILD_MODELS, VSD_SCORE_QUERY, VSD_DECIDE, VSD_CHALLENGE and
%   VSD_REPLAY_GUARD. The numbers below were selected on the development
%   protocols (leave-one-take-out genuine trials + held-out unknown speakers)
%   of the 32-student corpus and then checked on the cross-microphone
%   recordings; see Results/claude_eval and the project guide (Chapter 8).
%
%   WHY A NEW ENGINE (root causes found in v4.1.4)
%   1. Only 1.wav per student was enrolled (VoiceCalibration forced it), so a
%      single, same-microphone template had to cover every future session.
%   2. The frozen calibration switched cepstral mean subtraction OFF, so a new
%      microphone's transfer function H(w) remained inside every feature.
%   3. The roll number phrase "2206xxx" is 57 % identical across students; its
%      DTW distance to ALL templates is nearly equal (margins 1.00-1.05 in the
%      live log), so demanding "ID top-1 == Name top-1" failed genuine users.
%   4. Raw DTW distances drift together when the channel changes; fixed
%      ceilings (31.35 / 30.35) therefore rejected everyone on a new mic.
%   The engine replaces these with: all takes enrolled, CMVN features,
%   cohort-normalised scores, a GMM-UBM voice model and a fused decision.

if nargin < 1 || isempty(projectRoot)
    projectRoot = fileparts(mfilename('fullpath'));
end
c.Version = 'v4.1.4_claude-1.1';
c.Enable  = true;

% ---------------- data -------------------------------------------------
% Profile root: VSD_Enrollment/Train (deployed), else Train, else the sibling
% "Final project v4.1.4" folder, so this version runs without copying WAVs.
cands = {fullfile(projectRoot,'VSD_Enrollment','Train'), fullfile(projectRoot,'Train'), ...
    fullfile(fileparts(projectRoot),'Final project v4.1.4','VSD_Enrollment','Train'), ...
    fullfile(fileparts(projectRoot),'Final project v4.1.4','Train')};
c.DataRoot = cands{1};
for k = 1:numel(cands)
    if exist(fullfile(cands{k},'ID'),'dir') == 7, c.DataRoot = cands{k}; break; end
end
c.ModelFile   = fullfile(projectRoot,'VSD_Models.mat');
c.AdaptiveDir = 'Adaptive';            % sub-folder inside DataRoot/ID/<id> etc.
c.ReplayMemoryFile = fullfile(projectRoot,'VSD_ReplayMemory.mat');

% ---------------- front-end (Experiments 1-5) -----------------------------
c.Fs          = 8000;      % processing rate (rational resampling 441:80 / 6:1)
c.FrameMs     = 25;        % Hamming frame
c.HopMs       = 10;        % frame shift
c.NFFT        = 256;
c.NumMel      = 26;
c.MelLowHz    = 100;
c.MelHighHz   = 3800;      % below the 4 kHz Nyquist of the 8 kHz signal
c.NumCep      = 13;        % c0..c12 computed, c0 (loudness) discarded
c.Lifter      = 22;
c.PreEmph     = 0.97;
c.SSAlpha     = 2.0;       % spectral subtraction over-subtraction
c.SSBeta      = 0.02;      % spectral floor
c.SSNoiseFrac = 0.10;      % quietest 10 % of STFT frames = noise estimate
c.SSFrameMs   = 32;
c.SpeechFloorDb = 30;      % frames > 30 dB below the loudest frame = pause
c.DeltaN      = 2;         % regression window of the delta filter

% ---------------- matcher ---------------------------------------------------
c.DtwBand     = 0.40;      % Sakoe-Chiba half width (fraction of longer sequence)
c.CohortSize  = 5;         % nearest competitors used for cohort normalisation

% ---------------- voice model (GMM-UBM) -------------------------------------
c.UbmMixtures = 64;
c.UbmIters    = 30;
c.UbmKmeansIters = 10;
c.UbmMaxFrames = 80000;
c.UbmVarFloor = 1e-3;      % added to every variance (regularisation)
c.MapRelevance = 16;       % r in alpha_k = n_k/(n_k + r)
c.Seed        = 312;

% ---------------- decision (selected on development data) -------------------
c.WeightID    = 0.5;       % fused score F = wID*P_id + wName*P_name + lambda*V
c.WeightName  = 1.0;
c.Lambda      = 0.25;
c.MinPid      = -0.15;     % ID phrase may be weak but must not point elsewhere
                           % (v1.1: -0.10 -> -0.15, +1.1 % genuine, 0 extra false accepts)
c.MinPname    = 0.07;      % name phrase must single out the student
c.MinVoice    = 0.00;      % cohort-normalised voice LLR of the student
c.VoiceRankMax = 1;        % the student must be the best-matching voice
% "Clear winner" rule (v1.1): if the spoken NAME puts one student clearly ahead
% of all rivals AND the fused score leads by a clear margin, accept even when the
% voice model ranks him only 2nd or 3rd (typical right after a microphone
% change).  Just lowering MinPname instead was measured to let 2.6 % of
% unknown speakers in; this rule kept unknown-speaker acceptance at 0 %
% (take-1 genuine acceptance 91.8 % -> 95.3 %, perfect-mimic 0.08 % -> 0.25 %).
c.ClearWin.Enable      = true;
c.ClearWin.MinPname    = 0.12;   % name >= e^0.12 = 1.13x closer than the 5 nearest rivals
c.ClearWin.MinFMargin  = 0.08;   % fused score of rank 1 - rank 2
c.ClearWin.VoiceRankMax = 3;     % voice must still be among the best 3
c.ClearWin.MinVoice    = -0.10;  % and not clearly someone else's
c.ImpGap      = 0.15;      % imposter: voice of Y beats claimed X by this much
c.ImpMinVoice = 0.20;      %           and Y's voice score is at least this
c.MinSpeechSec = 0.35;     % per phrase
c.MinRms      = 1e-3;      % raw recording level below this = "speak louder"

% ---------------- replay prevention -----------------------------------------
c.Challenge.Enable   = true;   % random 3-digit freshness challenge
c.Challenge.Length   = 3;
c.Challenge.MinMargin = 0.97;  % D(best decoy)/D(requested) must be >= this
c.Challenge.MaxDist  = 5.40;   % and D(requested) <= this
c.Challenge.MinDist  = 2.00;   % below this the answer is a splice of the stored digit files
                               % (smallest genuine live answer measured: 3.58)
c.Challenge.VoiceGap = 0.40;   % the digits must be spoken in the claimed voice:
                               % max_j V(j) - V(claimed) < 0.40 (genuine 90.7 %, other
                               % student speaking the digits 1.9 % per attempt;
                               % vsd_calibrate_challenge_voice, 18 speakers)
c.Challenge.MaxAttempts = 2;   % a genuine user may get one new code
c.Challenge.LeadSec  = 0.10;
c.Challenge.GapSec   = 0.05;
c.Replay.DuplicateDist = 1.0;  % DTW distance below this = copy of a stored take
c.Replay.MemorySize  = 20;     % accepted utterances remembered per student
c.Replay.LowBandHz   = [20 200];
c.Replay.AdvisoryMinLowRatio = 2.4e-4;  % proposal's sub-200 Hz heuristic (advisory)

% ---------------- self-adaptation to a new microphone ------------------------
c.Adapt.Enable    = true;      % add high-confidence live takes as templates
c.Adapt.MinPname  = 0.12;
c.Adapt.MinVoice  = 0.30;
c.Adapt.MaxPerPhrase = 3;
end
