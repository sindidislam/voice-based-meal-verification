function [features, info] = extract_dft_features(x, fs, params)
%EXTRACT_DFT_FEATURES Log magnitude-spectrum features from 30 ms frames.
%
%   [FEATURES, INFO] = EXTRACT_DFT_FEATURES(X, FS, PARAMS) returns a
%   D-by-NUMFRAMES matrix in which each column is the feature vector of one
%   30 ms analysis frame.  Rows are feature dimensions, columns are time; this
%   is the orientation DTW_DISTANCE_DSP expects.
%
%   This is the front-end specified in the Group 07 proposal.  EEE 312
%   Experiment 3 (short-time framing and windowing) and Experiment 4 (DFT).
%
%   The processing chain
%   --------------------
%     1. Frame the signal into 30 ms frames advanced by 15 ms, i.e. 50 percent
%        overlap.  Speech is quasi-stationary over roughly 20-40 ms, so 30 ms
%        is long enough to resolve the formant structure yet short enough that
%        the vocal tract shape does not change within a frame.
%
%     2. Apply a Hann window.  Rectangular truncation would produce sidelobes
%        only 13 dB below the mainlobe, and that spectral leakage lets a strong
%        low-frequency component mask a weak neighbouring formant.  The Hann
%        window trades a factor-of-two wider mainlobe for sidelobes below
%        31 dB, which is the right trade for formant estimation.
%
%     3. Take the DFT via an FFT of length 2^nextpow2(frameLength) and keep the
%        magnitude spectrum |X[k]|.  Phase is discarded: it depends on where in
%        the glottal cycle the frame happens to start, so it varies from one
%        recording of the same word to the next and carries no information the
%        matcher can use.
%
%     4. Sum the magnitudes into NumBands bands spaced UNIFORMLY in linear
%        frequency across PARAMS.dft.Band.  Uniform spacing is a deliberate
%        departure from the senior baseline, which used 26 mel-spaced filters.
%        Mel warping models human loudness perception, which is the correct
%        thing to do when the task is to recognise WHAT was said across many
%        different talkers.  Here the task is the opposite -- decide WHO is
%        speaking a known phrase -- and the speaker-specific detail lives in
%        the higher formants that mel warping deliberately compresses.
%
%     5. Compress with a logarithm.  Loudness is perceived roughly
%        logarithmically, and more importantly the log turns the multiplicative
%        effect of microphone and room transfer functions into an additive
%        offset, which step 6 can then remove.
%
%     6. Optionally append the first time derivative of each band, estimated by
%        a symmetric linear-regression FIR over +/- DeltaSpan frames.  A static
%        log spectrum records the vocal tract shape the talker held; its
%        derivative records how fast the talker moved between shapes, which is a
%        habit of articulation and differs between people who are saying the
%        same words.  The derivative is also immune to the additive channel
%        offset of step 5 by construction, since differencing annihilates a
%        constant.  Measured effect on this corpus is reported by
%        EXPERIMENT_FRONTEND_COMPARISON.
%
%     7. Normalise each feature dimension to zero mean and unit variance over
%        the utterance.  Subtracting the mean of each log band removes exactly
%        the additive offset created in step 5, so a recording made on a laptop
%        microphone becomes comparable with one made on a headset.  This is the
%        magnitude-spectrum analogue of cepstral mean subtraction.  The static
%        and delta blocks are normalised separately, because a raw derivative has
%        a far smaller dynamic range than the value it is derived from, and the
%        Euclidean local distance inside DTW would otherwise be decided almost
%        entirely by the static block.
%
%   No pre-emphasis is applied, in line with proposal modification 3, and the
%   band is not truncated to 300-3700 Hz as the baseline did.
%
%   INFO reports NumFrames, FrameLength, HopLength, Nfft, BandEdges,
%   IncludeDelta and Dimension.
%
%   See also EXTRACT_FEATURES, EXTRACT_MFCC_DSP, DTW_DISTANCE_DSP.

if nargin < 3, params = dsp_parameters(); end
o = params.dft;
if ~isfield(o,'IncludeDelta'), o.IncludeDelta = false; end
if ~isfield(o,'DeltaSpan'),    o.DeltaSpan    = 2;     end

x = double(x(:));
features = [];
info = struct('NumFrames',0,'FrameLength',0,'HopLength',0,'Nfft',0, ...
    'BandEdges',[],'IncludeDelta',o.IncludeDelta,'Dimension',0);

if isempty(x)
    return;
end

% Optional baseline pre-emphasis, retained only for the CO2 comparison. The
% proposal discards it, so params.usePreEmphasis is false by default.
if isfield(params,'usePreEmphasis') && params.usePreEmphasis
    x = filter([1 -params.alpha], 1, x);
end

frameLen = max(8, round(o.FrameDuration * fs));
hopLen   = max(1, round(o.HopDuration   * fs));
if numel(x) < frameLen
    return;
end

nfft = 2^nextpow2(frameLen);
w = 0.5 - 0.5*cos(2*pi*(0:frameLen-1)'/(frameLen-1));   % Hann window

freq = (0:nfft/2)' * fs / nfft;
lowEdge  = max(o.Band(1), 0);
highEdge = min(o.Band(2), fs/2);
edges = linspace(lowEdge, highEdge, o.NumBands + 1);

% Precompute which FFT bins belong to which uniform band.
bandBins = cell(o.NumBands,1);
for b = 1:o.NumBands
    if b < o.NumBands
        bandBins{b} = find(freq >= edges(b) & freq <  edges(b+1));
    else
        bandBins{b} = find(freq >= edges(b) & freq <= edges(b+1));
    end
    if isempty(bandBins{b})
        % Guarantee every band has at least one bin even for a short FFT.
        [~, nearest] = min(abs(freq - 0.5*(edges(b)+edges(b+1))));
        bandBins{b} = nearest;
    end
end

numFrames = 1 + floor((numel(x) - frameLen) / hopLen);
features = zeros(o.NumBands, numFrames);

for k = 1:numFrames
    idx = (k-1)*hopLen + (1:frameLen);
    frame = x(idx);
    frame = frame - mean(frame);            % Per-frame DC removal.
    X = fft(frame .* w, nfft);
    mag = abs(X(1:nfft/2+1));               % Magnitude spectrum; phase dropped.
    for b = 1:o.NumBands
        features(b,k) = sum(mag(bandBins{b}));
    end
end

features = log(features + o.LogFloor);

% Dynamic features are derived from the log spectrum BEFORE normalisation.
% Differencing already removes the additive channel term, so the derivative
% needs no mean subtraction to be channel-invariant.
if o.IncludeDelta
    d = delta_regression(features, o.DeltaSpan);
    features = [normalise_block(features, o.CmvNormalise); ...
                normalise_block(d,        o.CmvNormalise)];
else
    features = normalise_block(features, o.CmvNormalise);
end

info.NumFrames = numFrames;
info.FrameLength = frameLen;
info.HopLength = hopLen;
info.Nfft = nfft;
info.BandEdges = edges;
info.IncludeDelta = o.IncludeDelta;
info.Dimension = size(features,1);
end

% -------------------------------------------------------------------------
function y = normalise_block(y, doNormalise)
%NORMALISE_BLOCK Zero mean, unit variance per dimension across the utterance.
if ~doNormalise
    return;
end
if size(y,2) > 1
    sd = std(y, 0, 2);
    sd(sd < 1e-6) = 1;              % Guard a dimension that never varies.
    y = (y - mean(y,2)) ./ sd;
else
    y = y - mean(y,2);
end
end

function d = delta_regression(c, span)
%DELTA_REGRESSION Symmetric linear-regression estimate of dc/dframe.
%
%   d[k] = sum_{n=1..span} n*(c[k+n] - c[k-n]) / (2 * sum_{n=1..span} n^2)
%
%   This is the least-squares slope of a straight line fitted to the 2*span+1
%   frames centred on k, which is a far better derivative estimate than the
%   first difference c[k]-c[k-1]: the simple difference is a high-pass filter
%   with unity gain rising to Nyquist, so it amplifies frame-to-frame estimation
%   noise, whereas the regression averages over a window and suppresses it.
%   Frames beyond the ends are replaced by the nearest real frame, which makes
%   the derivative tend to zero at the utterance boundaries rather than jump.
n = size(c,2);
if n == 1
    d = zeros(size(c));
    return;
end
span = max(1, min(span, n-1));
denom = 2 * sum((1:span).^2);
d = zeros(size(c));
for k = 1:span
    ahead  = c(:, min(n, (1:n) + k));
    behind = c(:, max(1, (1:n) - k));
    d = d + k * (ahead - behind);
end
d = d / denom;
end
