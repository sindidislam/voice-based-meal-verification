function [y, info] = hybrid_endpoint_detect(x, fs, opts)
%HYBRID_ENDPOINT_DETECT Endpoint detection by short-time energy AND a
%two-sided zero-crossing-rate band.
%
%   [Y, INFO] = HYBRID_ENDPOINT_DETECT(X, FS, OPTS) returns the speech region
%   of X together with a diagnostic structure.
%
%   Proposal modification 4.  EEE 312 Experiment 3 (short-time energy and
%   short-time zero-crossing rate).
%
%   What the senior baseline did, and why it failed
%   ----------------------------------------------
%   silence_remover.m split the signal into fixed 4096-sample blocks and kept
%   every block whose energy exceeded the mean energy of the whole recording.
%   That is a single energy threshold, and it has two failure modes in a
%   dining hall:
%
%     1. A dropped steel tray produces a short burst far above the mean, so
%        the block is kept and the impulse is fed to the matcher as speech.
%     2. Unvoiced consonants -- the /s/ of "six", the /f/ of "four", the /t/
%        of "two" -- carry very little energy, fall below the mean, and are
%        discarded.  The digits then lose exactly the sounds that tell them
%        apart.
%
%   The hybrid test
%   ---------------
%   A frame is declared active only if all three conditions hold:
%
%       (1)  E[k] > EnergyThreshold                     (short-time energy)
%       (2)  ZcrLow <= Z[k] <= ZcrHigh                  (two-sided ZCR band)
%       (3)  the frame belongs to a run of at least MinActiveFrames frames
%
%   Condition (2) is the two-sided band the proposal specifies, and both
%   edges are set by physics rather than by tuning:
%
%     Lower edge.  The lowest adult male fundamental in the group is about
%       85 Hz.  A periodic waveform at F0 crosses zero twice per period, so
%       at FS = 8000 Hz its zero-crossing rate is 2*85/8000 = 0.021.  Any
%       frame below ZCRAbsoluteMin = 0.008 therefore contains almost no
%       energy above about 30 Hz: it is a table thump, a footstep or DC
%       drift, not a voiced sound.
%
%     Upper edge.  With the folding frequency at 4 kHz, a frame whose ZCR
%       exceeds about 0.45 has its energy concentrated near Nyquist, which is
%       the signature of metallic clatter.  A sustained /s/ observed inside a
%       0-4 kHz band sits near 0.30-0.45, so the ceiling admits the soft
%       consonants while excluding the impulse.  The ceiling is tightened
%       towards ZCRMaxFactor*Z_noise in a quiet room but never falls below
%       0.25, so the fricatives are protected in every acoustic condition.
%
%   Condition (3) is what finally removes the dropped tray: an impulse lasts
%   one or two frames, whereas the shortest spoken digit lasts more than
%   MinActiveFrames*HopDuration seconds.  Short pauses inside the utterance
%   are bridged first, so that the gap between two digits is not mistaken for
%   the end of the phrase.
%
%   Noise statistics
%   ----------------
%   The energy threshold is referred to the ambient floor measured over the
%   first OPTS.NoiseDuration seconds.  If that pre-roll turns out to be as
%   loud as the rest of the recording -- which is the case for the legacy
%   templates, already cropped to the spoken word -- the estimator falls back
%   to the 10th percentile of the frame energies, so a cropped file is never
%   forced to learn its own speech onset as noise.
%
%   INFO fields: HasSpeech, StartSample, EndSample, EnergyThreshold,
%   ZcrLow, ZcrHigh, NoiseEnergy, NoiseZcr, NumActiveFrames, NumFrames,
%   Estimator, Energy, Zcr, ActiveMask, RejectedHighZcr, RejectedLowZcr.
%
%   See also PREPROCESS_AUDIO, DSP_PARAMETERS.

if nargin < 3, opts = struct(); end
if ~isfield(opts,'FrameDuration'),    opts.FrameDuration    = 0.020; end
if ~isfield(opts,'HopDuration'),      opts.HopDuration      = 0.010; end
if ~isfield(opts,'NoiseDuration'),    opts.NoiseDuration    = 0.50;  end
if ~isfield(opts,'EnergyMultiplier'), opts.EnergyMultiplier = 4.0;   end
if ~isfield(opts,'ZCRMinFactor'),     opts.ZCRMinFactor     = 0.50;  end
if ~isfield(opts,'ZCRMaxFactor'),     opts.ZCRMaxFactor     = 2.50;  end
if ~isfield(opts,'ZCRAbsoluteMax'),   opts.ZCRAbsoluteMax   = 0.45;  end
if ~isfield(opts,'ZCRAbsoluteMin'),   opts.ZCRAbsoluteMin   = 0.008; end
if ~isfield(opts,'MinActiveFrames'),  opts.MinActiveFrames  = 3;     end
if ~isfield(opts,'MaxGapFrames'),     opts.MaxGapFrames     = 8;     end
if ~isfield(opts,'PaddingDuration'),  opts.PaddingDuration  = 0.040; end
if ~isfield(opts,'Mode'),             opts.Mode             = 'hybrid'; end
mode = validatestring(opts.Mode, {'hybrid','energy'});

% Optional rate experiments preserve the physical crossing-frequency band.
% Noise ZCR is already measured at fs, so only fixed bounds are scaled.
zcrScale = 1;
if isfield(opts,'ZcrReferenceFs') && ~isempty(opts.ZcrReferenceFs)
    validateattributes(opts.ZcrReferenceFs,{'numeric'},{'scalar','real','finite','positive'});
    validateattributes(fs,{'numeric'},{'scalar','real','finite','positive'});
    zcrScale = opts.ZcrReferenceFs / fs;
    opts.ZCRAbsoluteMin = opts.ZCRAbsoluteMin * zcrScale;
    opts.ZCRAbsoluteMax = min(1,opts.ZCRAbsoluteMax * zcrScale);
end

x = double(x(:));
info = empty_info(opts);
info.Mode = mode;

frameLen = max(2, round(opts.FrameDuration * fs));
hopLen   = max(1, round(opts.HopDuration   * fs));

if numel(x) < frameLen
    y = zeros(0,1);
    return;
end

% ---- Short-time analysis (Experiment 3) -----------------------------------
numFrames = 1 + floor((numel(x) - frameLen) / hopLen);
E = zeros(numFrames,1);
Z = zeros(numFrames,1);
for k = 1:numFrames
    idx = (k-1)*hopLen + (1:frameLen);
    f = x(idx);
    E(k) = mean(f.^2);
    % Zero-crossing rate: count sign changes, normalised by comparisons made.
    s = f >= 0;
    Z(k) = sum(abs(diff(s))) / (frameLen - 1);
end

info.NumFrames = numFrames;
info.Energy = E;
info.Zcr = Z;

% ---- Ambient noise statistics -------------------------------------------
noiseFrames = max(1, min(numFrames, floor(opts.NoiseDuration * fs / hopLen)));
prerollE = median(E(1:noiseFrames));
prerollZ = median(Z(1:noiseFrames));

% Decide whether the pre-roll really is ambient noise.  If the pre-roll median
% energy is within 6 dB of the overall median the file has no quiet lead-in.
useRobust = numFrames <= noiseFrames + 2 || prerollE > 0.25 * median(E);
if useRobust
    noiseE = prctile(E, 10);
    noiseZ = median(Z);
    info.Estimator = 'percentile';
else
    noiseE = prerollE;
    noiseZ = prerollZ;
    info.Estimator = 'preroll';
end

info.NoiseEnergy = noiseE;
info.NoiseZcr = noiseZ;

% ---- Thresholds ----------------------------------------------------------
% Energy threshold adapts to the measured floor; the additive term keeps the
% threshold meaningful when the floor is numerically zero (synthetic input).
energyThr = max([opts.EnergyMultiplier * noiseE, ...
                 noiseE + 0.02 * (max(E) - noiseE), ...
                 10*eps]);

% ZCR band. The lower edge is absolute (fundamental-frequency physics). The
% upper edge tightens in a quiet room but is never allowed below 0.25, which
% is where unvoiced fricatives live once the band is limited to 0-4 kHz.
zcrLow  = opts.ZCRAbsoluteMin;
zcrHigh = min(opts.ZCRAbsoluteMax, max(0.25*zcrScale, opts.ZCRMaxFactor * noiseZ));

info.EnergyThreshold = energyThr;
info.ZcrLow  = zcrLow;
info.ZcrHigh = zcrHigh;

% ---- The hybrid logic gate ----------------------------------------------
loudEnough = E > energyThr;
inZcrBand  = Z >= zcrLow & Z <= zcrHigh;
active     = loudEnough & inZcrBand;

% Diagnostics: how many loud frames each ZCR edge removed.
info.RejectedHighZcr = sum(loudEnough & Z > zcrHigh);
info.RejectedLowZcr  = sum(loudEnough & Z < zcrLow);
if strcmp(mode,'energy')
    active = loudEnough;
    info.RejectedHighZcr = 0;
    info.RejectedLowZcr = 0;
end

% Bridge short internal pauses so inter-digit silence does not end the phrase.
active = bridge_gaps(active, opts.MaxGapFrames);

% Discard runs too short to be a spoken sound. This is the step that finally
% removes an impulsive tray strike, which survives the energy test but lasts
% only one or two frames.
active = drop_short_runs(active, opts.MinActiveFrames);

info.ActiveMask = active;
info.NumActiveFrames = sum(active);

if ~any(active)
    y = zeros(0,1);
    info.HasSpeech = false;
    info.StartSample = 1;
    info.EndSample = 0;
    return;
end

firstFrame = find(active, 1, 'first');
lastFrame  = find(active, 1, 'last');
pad = round(opts.PaddingDuration * fs);

startSample = max(1, (firstFrame-1)*hopLen + 1 - pad);
endSample   = min(numel(x), (lastFrame-1)*hopLen + frameLen + pad);

y = x(startSample:endSample);
info.HasSpeech = true;
info.StartSample = startSample;
info.EndSample = endSample;
end

% -------------------------------------------------------------------------
function info = empty_info(opts)
info = struct('HasSpeech',false,'StartSample',1,'EndSample',0, ...
    'EnergyThreshold',NaN,'ZcrLow',opts.ZCRAbsoluteMin,'ZcrHigh',opts.ZCRAbsoluteMax, ...
    'NoiseEnergy',NaN,'NoiseZcr',NaN,'NumActiveFrames',0,'NumFrames',0, ...
    'Estimator','none','Energy',[],'Zcr',[],'ActiveMask',false(0,1), ...
    'RejectedHighZcr',0,'RejectedLowZcr',0);
end

function m = bridge_gaps(m, maxGap)
%BRIDGE_GAPS Fill runs of false shorter than maxGap that lie between trues.
if maxGap < 1 || ~any(m), return; end
first = find(m,1,'first');
last  = find(m,1,'last');
k = first;
while k <= last
    if m(k)
        k = k + 1;
        continue;
    end
    gapEnd = k;
    while gapEnd <= last && ~m(gapEnd)
        gapEnd = gapEnd + 1;
    end
    if (gapEnd - k) <= maxGap
        m(k:gapEnd-1) = true;
    end
    k = gapEnd;
end
end

function m = drop_short_runs(m, minRun)
%DROP_SHORT_RUNS Clear any run of trues shorter than minRun frames.
if minRun <= 1 || ~any(m), return; end
n = numel(m);
k = 1;
while k <= n
    if ~m(k)
        k = k + 1;
        continue;
    end
    runEnd = k;
    while runEnd <= n && m(runEnd)
        runEnd = runEnd + 1;
    end
    if (runEnd - k) < minRun
        m(k:runEnd-1) = false;
    end
    k = runEnd;
end
end
