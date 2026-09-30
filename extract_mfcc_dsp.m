function [features, info] = extract_mfcc_dsp(signal, fs, p)
%EXTRACT_MFCC_DSP Mel-frequency cepstral coefficients with delta and
%delta-delta -- the senior-baseline front-end, retained for comparison.
%
%   [FEATURES, INFO] = EXTRACT_MFCC_DSP(SIGNAL, FS, P) returns a
%   (3*P.C)-by-NUMFRAMES matrix: P.C static cepstra stacked with their first
%   and second time derivatives.  Columns are frames.
%
%   This function is NOT the front-end the Group 07 proposal specifies.  It
%   reproduces what the senior project did, so that EXPERIMENT_FRONTEND_
%   COMPARISON can measure the two on identical audio and the choice made in
%   the proposal can be defended with numbers instead of assertion.  CO2.
%
%   Chain: optional pre-emphasis -> 25 ms Hamming frames, 10 ms hop -> FFT
%   magnitude -> 26 mel-spaced triangular filters over 300-3700 Hz -> log ->
%   DCT keeping 13 coefficients -> sinusoidal liftering -> optional c0 removal
%   -> optional cepstral mean and variance subtraction -> delta, delta-delta.
%
%   Note on pre-emphasis
%   --------------------
%   The baseline applied 1 - alpha*z^-1 unconditionally.  Proposal modification
%   3 discards it in favour of measured spectral subtraction, so it is applied
%   here only when P.usePreEmphasis is true.  That flag is false by default and
%   exists purely so the baseline condition can be reproduced exactly.
%
%   Note on cepstral mean subtraction (P.mfcc.CmsNormalise)
%   ------------------------------------------------------
%   The senior baseline did not do this, and on a corpus recorded on mixed
%   hardware it is the single largest omission in that front-end.  A microphone
%   and room impose a fixed transfer function H(w), which multiplies the
%   magnitude spectrum.  The log turns that product into a sum, and the DCT is
%   linear, so the channel survives into the cepstrum as a constant additive
%   vector -- the same offset on every frame of the utterance.  Subtracting the
%   per-utterance mean cepstrum therefore removes the channel exactly, leaving
%   only what the talker did.  Without it, two recordings of the same student on
%   two different laptops differ by a constant the matcher cannot distinguish
%   from a difference of speaker.
%
%   Note on c0 (P.mfcc.DropC0)
%   --------------------------
%   The zeroth cepstral coefficient is the sum of the log mel energies, i.e.
%   overall loudness.  AGC_NORMALIZE has already fixed loudness to a target RMS,
%   so c0 carries no speaker information at that point and only adds variance.
%   The senior PROJECT_MFCC dropped it (cc(:,2:13)); this option reproduces that.
%
%   See also EXTRACT_FEATURES, EXTRACT_DFT_FEATURES, SPECTRAL_SUBTRACT_NOISE.

if nargin < 3, p = dsp_parameters(); end

% Option defaults, so that a params struct predating these fields still runs.
if ~isfield(p,'mfcc'), p.mfcc = struct(); end
o = p.mfcc;
if ~isfield(o,'CmsNormalise'),      o.CmsNormalise      = false; end
if ~isfield(o,'CmvNormalise'),      o.CmvNormalise      = false; end
if ~isfield(o,'DropC0'),            o.DropC0            = false; end
if ~isfield(o,'IncludeDelta'),      o.IncludeDelta      = true;  end
if ~isfield(o,'IncludeDeltaDelta'), o.IncludeDeltaDelta = true;  end
if ~isfield(o,'Rasta'),             o.Rasta             = false; end
if ~isfield(o,'IncludePitch'),      o.IncludePitch      = false; end
if ~isfield(o,'IncludeSpectral'),   o.IncludeSpectral   = false; end
if ~isfield(o,'useCMVN'),           o.useCMVN           = false; end
weights = {'StaticWeight','DeltaWeight','DeltaDeltaWeight','PitchWeight','SpectralWeight'};
for k = 1:numel(weights)
    if ~isfield(o,weights{k}), o.(weights{k}) = 1; end
    validateattributes(o.(weights{k}),{'numeric'},{'scalar','real','finite','nonnegative'});
end

signal = double(signal(:));
features = [];
info = struct('NumFrames',0,'FrameLength',0,'HopLength',0,'Nfft',0, ...
    'Dimension',0,'PreEmphasisApplied',false, ...
    'CmsNormalise',o.CmsNormalise,'DropC0',o.DropC0);

if isempty(signal)
    return;
end

if isfield(p,'usePreEmphasis') && p.usePreEmphasis
    signal = filter([1 -p.alpha], 1, signal);
    info.PreEmphasisApplied = true;
end

N = round(p.Tw * 1e-3 * fs);
H = round(p.Ts * 1e-3 * fs);
if N < 4 || numel(signal) < N
    return;
end

nf = 1 + floor((numel(signal) - N) / H);
idx = (1:N)' + (0:nf-1) * H;
frames = signal(idx) .* hamming(N);
nfft = 2^nextpow2(N);
K = nfft/2 + 1;
mag = abs(fft(frames, nfft, 1));
mag = mag(1:K, :);

F = melbank_local(p.M, K, p.R, fs);
D = dctmtx(p.M);
logMel = log(max(F * (mag.^2), eps));
if o.Rasta
    % RASTA-like temporal high pass on each log-mel channel. Subtract the
    % first frame before zero-state filtering so constant channel offsets
    % cannot create a start-up transient. This is a controlled optional block.
    logMel = filter([.2 .1 0 -.1 -.2],[1 -.94], ...
        logMel - logMel(:,1),[],2);
end
c = D(1:p.C, :) * logMel;
lifter = 1 + (p.L/2) * sin(pi * (0:p.C-1) / p.L);
c = lifter' .* c;

if isfield(o, 'DropQuietFrames') && o.DropQuietFrames
    frameLogE = 10 * log10(sum(frames.^2, 1) + 1e-12);
    validSpeech = frameLogE > (max(frameLogE) - 28.0);
    if sum(validSpeech) >= 10
        c = c(:, validSpeech);
    end
end

% c0 is overall loudness, already fixed by AGC. Dropping it must happen before
% mean subtraction, otherwise its variance is still normalised into the rest.
if o.DropC0 && size(c,1) > 1
    c = c(2:end, :);
end

% Channel removal. See the header note: the microphone transfer function is a
% constant additive vector in the cepstral domain, so its per-utterance mean is
% exactly what has to go.
if o.CmsNormalise || o.CmvNormalise
    c = c - mean(c, 2);
    if o.CmvNormalise && size(c,2) > 1
        sd = std(c, 0, 2);
        sd(sd < 1e-6) = 1;
        c = c ./ sd;
    end
end

% Derivatives are computed after normalisation. Subtracting a constant does not
% change a derivative, so the order is immaterial for CMS; it matters for
% variance scaling, and normalising first keeps the static and dynamic blocks on
% a common scale for the Euclidean local distance inside DTW.
features = o.StaticWeight * c;
if o.IncludeDelta
    d = delta_local(c);
    features = [features; o.DeltaWeight * d];
    if o.IncludeDeltaDelta
        features = [features; o.DeltaDeltaWeight * delta_local(d)];
    end
end
if o.IncludePitch || o.IncludeSpectral
    [pitch, spectral] = mfcc_auxiliary_features(signal(idx),mag,fs,nfft,o);
    if o.IncludePitch, features = [features; o.PitchWeight * pitch]; end
    if o.IncludeSpectral, features = [features; o.SpectralWeight * spectral]; end
end

if (isfield(o,'useCMVN') && o.useCMVN) || (isfield(p,'useCMVN') && p.useCMVN)
    mu = mean(features, 2);
    sd = std(features, 0, 2);
    sd(sd < 1e-8) = 1e-8;
    features = (features - mu) ./ sd;
end

info.NumFrames = nf;
info.FrameLength = N;
info.HopLength = H;
info.Nfft = nfft;
info.Dimension = size(features,1);
info.Rasta = o.Rasta;
info.IncludePitch = o.IncludePitch;
info.IncludeSpectral = o.IncludeSpectral;
end

% -------------------------------------------------------------------------
function d = delta_local(x)
%DELTA_LOCAL First-order regression derivative over a +/-2 frame window.
[~, n] = size(x);
d = zeros(size(x));
for t = 1:n
    for k = 1:2
        d(:,t) = d(:,t) + k * (x(:, min(n, t+k)) - x(:, max(1, t-k)));
    end
end
d = d / 10;    % 2*sum(k^2) for k = 1..2
end

function B = melbank_local(M, K, R, fs)
%MELBANK_LOCAL Triangular filterbank equally spaced on the mel scale.
h2m = @(h) 1127 * log(1 + h/700);
m2h = @(m) 700 * (exp(m/1127) - 1);
f = linspace(0, fs/2, K);
c = m2h(linspace(h2m(R(1)), h2m(min(R(2), fs/2)), M + 2));
B = zeros(M, K);
for m = 1:M
    rising  = (f - c(m))    / max(c(m+1) - c(m),   eps);
    falling = (c(m+2) - f)  / max(c(m+2) - c(m+1), eps);
    B(m,:) = max(0, min(rising, falling));
end
end
