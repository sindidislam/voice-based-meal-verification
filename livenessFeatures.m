function [featVec, featNames, det] = livenessFeatures(rawAudio, fsRaw, cqccFeatures)
%LIVENESSFEATURES Eight physically-motivated acoustic replay clues on NATIVE audio.
%
%   1 LowBandRatio_dB   E(60-250)/E(300-3400). Small phone drivers cannot
%                       reproduce below ~400 Hz. LIVE = higher.
%   2 HighBandRatio_dB  E(4k-8k)/E(300-3400). Band-limiting during replay. LIVE = higher.
%   3 SpectralRipple    std of LTAS residual after detrending. Playback convolves
%                       with room impulse response, adding comb ripple. REPLAY = higher.
%   4 ModulationDepth   2-16 Hz envelope energy over total. Reverberation and device
%                       compression fill syllabic valleys. LIVE = higher.
%   5 SilenceTilt_dB    Spectral tilt of non-speech frames (excluding exact digital zeros).
%                       Replay carries original room noise + playback DAC hiss.
%   6 CQCCQuefRatio     High/low quefrency CQCC variance ratio.
%   7 UltraBandRatio_dB E(8k-16k)/E(300-3400) (Witkowski et al., Interspeech 2017). LIVE = higher.
%   8 HighSlope_dBkHz   Slope of speech LTAS from 4 to 16 kHz. Phone playback rolls off faster.

featNames = {'LowBandRatio_dB', 'HighBandRatio_dB', 'SpectralRipple', ...
             'ModulationDepth', 'SilenceTilt_dB', 'CQCCQuefRatio', ...
             'UltraBandRatio_dB', 'HighSlope_dBkHz'};
featVec = nan(1, numel(featNames));
det     = struct('Fs', fsRaw, 'WidebandAvailable', fsRaw >= 16000);

if size(rawAudio, 2) > 1
    x = mean(double(rawAudio), 2);
else
    x = double(rawAudio(:));
end
x0 = x;                                  % Kept to identify exact digital silence zeros
x = x - mean(x);
if max(abs(x)) > 0, x = x / max(abs(x)); end

if numel(x) < round(0.20 * fsRaw)
    det.Error = 'Signal too short for liveness analysis.';
    return;
end

% Short-time power spectra
winLen = 2^nextpow2(round(0.032 * fsRaw));
hop    = round(winLen/2);
nFr    = max(1, floor((numel(x) - winLen) / hop) + 1);
w      = 0.54 - 0.46 * cos(2*pi*(0:winLen-1)'/(winLen-1)); % Hamming
nBin   = winLen/2 + 1;
fAx    = (0:winLen/2).' * (fsRaw / winLen);

S   = zeros(nBin, nFr);
eFr = zeros(nFr, 1);
zFr = zeros(nFr, 1);
cFr = false(nFr, 1);
for k = 1:nFr
    idx     = (k-1)*hop + (1:winLen);
    zFr(k)  = mean(x0(idx) == 0);
    cFr(k)  = any(abs(x0(idx)) >= 0.999);
    seg     = x(idx) .* w;
    Sk      = abs(fft(seg, winLen)).^2;
    S(:, k) = Sk(1:nBin);
    eFr(k)  = sum(seg.^2);
end

% Speech frames (within 30 dB of the loudest frame)
eN0  = eFr / (max(eFr) + eps);
spF  = eN0 > 1e-3;
if ~any(spF), spF = true(size(eN0)); end
LTAS = mean(S(:, spF), 2);
det.LTAS = LTAS; det.FreqAx = fAx;
det.ClippedFrames = mean(cFr(spF));

bandE = @(f1, f2) sum(LTAS((fAx >= f1) & (fAx <= f2))) + eps;
eMid  = bandE(300, 3400);

% 1. LowBandRatio
featVec(1) = 10 * log10(bandE(60, 250) / eMid);

% 2. HighBandRatio
if fsRaw >= 16000
    fHi = min(8000, fsRaw/2 - 100);
    if fHi > 4200
        featVec(2) = 10 * log10(bandE(4000, fHi) / eMid);
    end
end

% 3. SpectralRipple
band = (fAx >= 200) & (fAx <= min(3800, fsRaw/2 - 100));
if nnz(band) > 20
    lb    = 10 * log10(LTAS(band) + eps);
    span  = max(3, round(nnz(band) * 0.06));
    % Centered moving average
    c = [0; cumsum(lb)];
    h = floor(span/2);
    mvg = zeros(size(lb));
    for i = 1:numel(lb)
        a = max(1, i-h); b = min(numel(lb), i+h);
        mvg(i) = (c(b+1) - c(a)) / (b - a + 1);
    end
    resid = lb - mvg;
    featVec(3) = std(resid);
    det.RippleResidual = resid;
end

% 4. ModulationDepth
envFs = fsRaw / hop;
if nFr > 8 && envFs > 40
    env = sqrt(eFr / winLen);
    env = env - mean(env);
    nE  = 2^nextpow2(numel(env));
    E   = abs(fft(env, nE)).^2;
    fE  = (0:nE-1).' * (envFs / nE);
    h   = 1:floor(nE/2);
    mB  = (fE(h) >= 2)   & (fE(h) <= 16);
    tB  = (fE(h) >= 0.5) & (fE(h) <= min(50, envFs/2));
    if any(mB) && any(tB)
        featVec(4) = sum(E(h(mB))) / (sum(E(h(tB))) + eps);
    end
end

% 5. SilenceTilt
if nFr >= 6
    % Exclude frames of exact digital zeros created by driver noise suppression
    sil = find(eN0 < 0.02 & zFr < 0.5);
    det.SilenceFrames = numel(sil);
    if numel(sil) >= 3
        silLTAS = mean(S(:, sil), 2);
        bt = (fAx >= 200) & (fAx <= min(3800, fsRaw/2 - 100));
        if nnz(bt) > 10
            cf = polyfit(fAx(bt)/1000, 10*log10(silLTAS(bt) + eps), 1);
            featVec(5) = cf(1);
        end
    end
end

% 6. CQCC Quefrency Ratio
if nargin >= 3 && ~isempty(cqccFeatures) && size(cqccFeatures, 1) >= 3
    C = cqccFeatures;
    if size(C, 1) < size(C, 2), C = C.'; end
    nC = size(C, 2);
    half = floor(nC/2);
    if half >= 4
        v  = var(C(:, 1:half), 0, 1);
        lo = sum(v(1:min(8, half))) + eps;
        hi = sum(v(min(9, half):half));
        featVec(6) = hi / lo;
    end
end

% 7 & 8. UltraBandRatio & HighSlope
if fsRaw >= 32000
    featVec(7) = 10 * log10(bandE(8000, 16000) / eMid);
    bh = (fAx >= 4000) & (fAx <= 16000);
    cf = polyfit(fAx(bh) / 1000, 10 * log10(LTAS(bh) + eps), 1);
    featVec(8) = cf(1);
end

det.FeatureVector = featVec;
det.FeatureNames  = featNames;
end
