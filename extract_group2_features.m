function [fDynNorm, fDyn, params] = extract_group2_features(audio, fs, varargin)
% EXTRACT_GROUP2_FEATURES Extract Group 2 20-D Z-score normalized MFCC+Delta features
%
%   [FDYNNORM, FDYN, PARAMS] = EXTRACT_GROUP2_FEATURES(AUDIO, FS, ...)
%   Extracts 10 static MFCCs (c1..c10, dropping c0) and 10 dynamic delta
%   trajectories, standardized via per-utterance Z-score (CMVN) normalization:
%       fDynNorm = (fDyn - mean(fDyn, 2)) ./ (std(fDyn, 0, 2) + eps)
%
%   This representation is scale and microphone invariant because the additive
%   transfer function c_mic is subtracted out by the mean, and volume variations
%   are normalized by the variance.

if nargin < 2 || isempty(fs), fs = 8000; end
targetFs = 8000;

% Ensure mono
if size(audio, 2) > 1
    audio = mean(audio, 2);
end
audio = double(audio(:));

if fs ~= targetFs
    audio = resample(audio, targetFs, fs);
    fs = targetFs;
end

% Remove DC bias
audio = audio - mean(audio);

% Peak normalize if not silent
peakVal = max(abs(audio));
if peakVal > 0.005
    audio = audio / peakVal;
end

% 1. Pre-emphasis: H(z) = 1 - 0.95 z^(-1)
alpha = 0.95;
preemph = filter([1, -alpha], 1, audio);

% 2. 25 ms framing with 50% overlap (200 samples frame, 100 samples hop at 8 kHz)
frameLen = round(0.025 * fs);
frameHop = round(0.0125 * fs);
totalSamples = length(preemph);

if totalSamples < frameLen
    frames = [preemph; zeros(frameLen - totalSamples, 1)]';
    numFrames = 1;
else
    numFrames = floor((totalSamples - frameLen) / frameHop) + 1;
    frames = zeros(numFrames, frameLen);
    hWin = hamming(frameLen, 'periodic')';
    for i = 1:numFrames
        idx = (i - 1) * frameHop + (1:frameLen);
        frames(i, :) = preemph(idx)' .* hWin;
    end
end

% 3. Mel Filterbank (26 filters, 100 Hz to fs/2)
numFilters = 26;
nfft = 512;
numUniqueBins = nfft / 2 + 1;

hz2mel = @(f) 2595 * log10(1 + f / 700);
mel2hz = @(m) 700 * (10 .^ (m / 2595) - 1);
melPoints = linspace(hz2mel(100), hz2mel(fs/2), numFilters + 2);
hzPoints = mel2hz(melPoints);
binPoints = min(floor((nfft + 1) * hzPoints / fs) + 1, numUniqueBins);

H = zeros(numFilters, numUniqueBins);
for m = 1:numFilters
    fl = binPoints(m); fc = binPoints(m + 1); fr = binPoints(m + 2);
    if fc > fl
        H(m, fl:fc) = (fl:fc - fl) / (fc - fl);
    end
    if fr > fc
        H(m, fc:fr) = (fr - (fc:fr)) / (fr - fc);
    end
end

% 4. FFT Power Spectrum & Mel Log-Energy
fftFrames = fft(frames, nfft, 2);
powerSpec = abs(fftFrames(:, 1:numUniqueBins)) .^ 2 / frameLen;
fbEnergy = powerSpec * H';
logEnergy = log(max(fbEnergy, 1e-12));

% 5. DCT-II: Retain c1..c10 (dropping c0)
dctMat = dctmtx(numFilters);
fullCep = logEnergy * dctMat';
staticMFCC = fullCep(:, 2:11); % 10 static coefficients

% 6. FIR Linear Regression Deltas (N = 2)
deltaMFCC = computeFIRDelta(staticMFCC, 2);

% Combined 20-D features: [numFrames x 20]
fDyn = [staticMFCC, deltaMFCC];

% Transpose to [20 x numFrames] standard convention
fDyn = fDyn';

% 7. Z-Score (CMVN) Feature Normalization
% Cancels static microphone transfer functions c_mic across frames
meanVec = mean(fDyn, 2);
stdVec = std(fDyn, 0, 2);
stdVec(stdVec < 1e-6) = 1.0;

fDynNorm = (fDyn - meanVec) ./ stdVec;

params = struct('fs', fs, 'numFrames', numFrames, 'dim', 20, 'CMVN', true);
end

function delta = computeFIRDelta(cepstra, N)
[T, D] = size(cepstra);
delta = zeros(T, D);
denom = 2 * sum((1:N) .^ 2);
padded = [repmat(cepstra(1, :), N, 1); cepstra; repmat(cepstra(end, :), N, 1)];
for t = 1:T
    padIdx = t + N;
    numSum = zeros(1, D);
    for n = 1:N
        numSum = numSum + n * (padded(padIdx + n, :) - padded(padIdx - n, :));
    end
    delta(t, :) = numSum / denom;
end
end
