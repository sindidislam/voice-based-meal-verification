function [x, info] = synth_voiced_signal(fs, duration, f0Range, formants, peak)
%SYNTH_VOICED_SIGNAL Synthesise a voiced sound from the source-filter model.
%
%   X = SYNTH_VOICED_SIGNAL(FS, DURATION, F0RANGE, FORMANTS, PEAK) returns a
%   DURATION-second signal at FS Hz built as a harmonic stack on a fundamental that
%   sweeps linearly from F0RANGE(1) to F0RANGE(2) Hz, shaped by resonances at the
%   frequencies in FORMANTS, amplitude-modulated at a syllabic rate and tapered at
%   both ends.  PEAK sets the absolute peak amplitude.
%
%   [X, INFO] = ... also returns the harmonic count used, the sub-200 Hz band-energy
%   ratio, and the median short-time zero-crossing rate.
%
%   Defaults: DURATION 0.6 s, F0RANGE [110 150], FORMANTS [500 1500 2500], PEAK 0.35.
%
%   EEE 312 CO1 (implement DSP algorithms), CO2 (theory against measurement).
%   PO(a) Engineering knowledge, PO(e) Modern tool usage.
%
%   Why a synthesiser is needed at all
%   ---------------------------------
%   VERIFY_DSP_PIPELINE has to feed the deployed chain a signal whose correct answer
%   is known in advance, and a pure tone is not that signal.  Three of the five
%   proposal modifications reject a tone, correctly, for reasons that have nothing to
%   do with the property under test:
%
%     Modification 2 (liveness) measures the ratio of sub-200 Hz energy to total
%     speech-band energy.  A 700 Hz tone has none of the former, so the gate calls it
%     loudspeaker playback -- which is exactly what it is supposed to do to a signal
%     with no glottal fundamental.
%
%     Modification 4 (endpointing) learns its noise floor from the first 0.5 s and
%     needs frames that exceed four times it.  A constant-amplitude tone cannot
%     exceed four times its own mean energy anywhere, so no speech is ever found.
%
%     The DFT front-end normalises each utterance to zero mean and unit variance per
%     band.  A stationary tone has the same spectrum in every frame, so mean
%     subtraction drives the whole feature matrix to zero -- and a DTW distance
%     between two all-zero matrices is zero, which makes "different content scores
%     farther than a warped copy" pass on floating-point noise rather than on merit.
%     A test that passes for the wrong reason is worse than one that fails.
%
%   What the model reproduces, and what it does not
%   ----------------------------------------------
%   The source-filter decomposition of voiced speech: a quasi-periodic glottal source
%   whose harmonics are spaced at F0, passed through a vocal-tract filter whose
%   resonances are the formants.  Here the source is SUM_k (1/k) sin(k*phi), a
%   spectrum falling at 6 dB per octave, and the filter is a sum of second-order
%   resonances each with a 150 Hz half-power bandwidth.
%
%   The sweep in F0 is what makes the signal non-stationary, and the syllabic
%   modulation is what gives short-time energy something to vary.  Neither is
%   cosmetic: without the first the DFT front-end degenerates, and without the second
%   the endpoint detector finds nothing.
%
%   This is not a speech synthesiser.  There is no noise excitation, so fricatives
%   and stops are absent, and no glottal pulse shape beyond the 1/k tilt.  It
%   produces one sustained voiced sound, which is what a deterministic test needs.
%
%   Choosing arguments so the signal survives the liveness gate
%   ----------------------------------------------------------
%   The band-energy ratio depends only on how much of the harmonic series falls below
%   200 Hz.  With a 1/k source alone the fundamental holds 1/sum(1/k^2) = 63 % of the
%   power, which is near PARAMS.liveness.MaxRatio and would be read as low-frequency
%   rumble.  The formant filter is what fixes this: resonances at 500 Hz and above
%   attenuate the fundamental relative to the mid harmonics, and the measured ratio
%   for the default arguments lands around 0.13 -- inside the accepted band with room
%   on both sides.  INFO.LowBandRatio reports it so a caller can check rather than
%   assume.
%
%   No harmonic is ever placed above 0.98 of the Nyquist frequency, at any point in
%   the sweep, so the signal is alias-free by construction and any aliasing measured
%   downstream belongs to the code under test.
%
%   See also VERIFY_DSP_PIPELINE, CHECK_LIVENESS_LOWFREQ, HYBRID_ENDPOINT_DETECT.

if nargin < 2 || isempty(duration), duration = 0.60; end
if nargin < 3 || isempty(f0Range),  f0Range  = [110 150]; end
if nargin < 4 || isempty(formants), formants = [500 1500 2500]; end
if nargin < 5 || isempty(peak),     peak     = 0.35; end

validateattributes(fs, {'numeric'}, {'scalar','positive','finite'});
validateattributes(duration, {'numeric'}, {'scalar','positive','finite'});
formants = reshape(double(formants), 1, []);

n = round(duration * fs);
if n < 2
    x = zeros(n, 1);
    info = struct('NumHarmonics', 0, 'LowBandRatio', NaN, 'MedianZcr', NaN, 'F0', []);
    return;
end

% ---- Source: harmonic stack on a swept fundamental ----------------------------
% The instantaneous phase is the running integral of frequency, so a linear sweep in
% f0 gives a quadratic phase. Summing sin(k*phase) keeps every harmonic locked to the
% same fundamental as it moves, which a sum of independent fixed-frequency sinusoids
% would not.
f0 = linspace(f0Range(1), f0Range(2), n)';
phase = 2*pi * cumsum(f0) / fs;

bandwidth = 150;              % formant half-power bandwidth, Hz
nyquist = fs / 2;
x = zeros(n, 1);
numHarmonics = 0;

for k = 1:64
    fk = k * f0;
    % Stop before any harmonic reaches Nyquist at ANY point in the sweep. Testing
    % min(fk) instead would let the top of the sweep alias while the bottom did not,
    % putting a fold-over in the very signal used to measure fold-over.
    if max(fk) >= 0.98 * nyquist
        break;
    end
    % Vocal-tract filter: sum of second-order resonances, evaluated at this
    % harmonic's instantaneous frequency. bw^2/((f-fc)^2 + bw^2) is the squared
    % magnitude of a single pole pair, unity at resonance and falling as 1/f^2.
    gain = sum(bandwidth^2 ./ ((fk - formants).^2 + bandwidth^2), 2);
    % The +k phase offset stops all harmonics starting in phase, which would produce
    % one enormous impulse at t = 0 and a crest factor no voice has.
    x = x + (gain / k) .* sin(k*phase + k);
    numHarmonics = k;
end

% ---- Syllabic amplitude modulation -------------------------------------------
% ~3.5 Hz is the rate at which syllables arrive in ordinary speech. The trough is at
% 0.2 of the peak rather than at zero: deeper than that and the endpoint detector sees
% two separate runs joined by a gap wider than PARAMS.endpoint.MaxGapFrames.
t = (0:n-1)' / fs;
x = x .* (0.6 + 0.4 * sin(2*pi*3.5*t - pi/2));

% ---- Onset and offset taper ---------------------------------------------------
% A hard start is a step, and a step has energy at every frequency including the
% sub-200 Hz band the liveness gate reads. 20 ms of raised cosine removes it.
x = x .* edge_taper(n, round(0.020 * fs));

scale = max(abs(x));
if scale > 0
    x = peak * x / scale;
end

if nargout > 1
    info = struct('NumHarmonics', numHarmonics, 'F0', f0, ...
        'LowBandRatio', low_band_ratio(x, fs), 'MedianZcr', median_zcr(x, fs));
end
end

% -------------------------------------------------------------------------
function w = edge_taper(n, m)
%EDGE_TAPER Raised-cosine ramp up over M samples, flat, then ramp down.
m = max(1, min(m, floor(n/2)));
ramp = 0.5 - 0.5*cos(pi*(0:m-1)'/m);
w = [ramp; ones(n - 2*m, 1); flipud(ramp)];
end

% -------------------------------------------------------------------------
function r = low_band_ratio(x, fs)
%LOW_BAND_RATIO Sub-200 Hz energy as a fraction of 20-3800 Hz energy.
%   Reported so a caller can verify the signal is inside PARAMS.liveness rather than
%   assuming it. Computed independently of CHECK_LIVENESS_LOWFREQ on purpose: two
%   agreeing implementations is evidence, one implementation checking itself is not.
X = abs(fft(x .* hann(numel(x)))).^2;
f = (0:numel(X)-1)' * fs / numel(X);
low  = sum(X(f >= 20 & f <= 200));
full = sum(X(f >= 20 & f <= 3800));
r = low / max(full, eps);
end

% -------------------------------------------------------------------------
function z = median_zcr(x, fs)
%MEDIAN_ZCR Median short-time zero-crossing rate over 20 ms frames.
len = max(2, round(0.020 * fs));
hop = max(1, round(0.010 * fs));
starts = 1:hop:(numel(x) - len + 1);
if isempty(starts), z = NaN; return; end
rates = zeros(numel(starts), 1);
for i = 1:numel(starts)
    frame = x(starts(i) : starts(i)+len-1);
    rates(i) = mean(abs(diff(sign(frame))) > 0);
end
z = median(rates);
end
