function U = vsd_frontend(x, fs, c)
%VSD_FRONTEND Audio -> the two feature streams used by the v4.1.4_Final engine.
%
%   U = VSD_FRONTEND(X, FS) processes one recording X (any rate, mono or
%   stereo) and returns a struct with
%     U.Content  [T x 24]  c1..c12 + delta of the SPEECH frames, CMVN.
%                          "What was said" -- compared by DTW (text dependent).
%     U.Speaker  [T x 24]  c1..c12 (mean/var normalised) + delta (var norm).
%                          "Who said it" -- scored by the GMM-UBM (text independent).
%     U.SpeechSec, U.RawRms, U.Peak, U.ClipFrac, U.NumFrames, U.Speech (mask)
%
%   DSP chain (each block maps to an EEE 312 experiment):
%     1  mono + rational resampling to 8 kHz (L/M = 80/441 or 1/6)   Expt 1-2
%     2  DC removal, power spectral subtraction (Boll 1979) with the
%        noise PSD = mean of the quietest 10 % of 32 ms Hann frames    Expt 4
%     3  peak normalisation (gain invariance)                         Expt 1
%     4  pre-emphasis H(z) = 1 - 0.97 z^-1                            Expt 3/5
%     5  25 ms Hamming frames, 10 ms hop, |FFT_256|^2                 Expt 4
%     6  26 mel triangles 100-3800 Hz, log, DCT-II -> c0..c12, lifter Expt 4
%     7  frame log-energy speech mask (30 dB below the peak frame)    Expt 3
%     8  delta = FIR regression over +-2 frames                       Expt 2/5
%     9  CMVN along time: removes the microphone transfer function    (theory)
%        log|X(w)H(w)| = log|X(w)| + log|H(w)|  ->  a constant cepstral
%        offset per utterance, subtracted exactly by the mean.
%
%   This file is mirrored line by line by proto/feat.py (Python) which was
%   used for the corpus experiments, so the thresholds in VSD_CONFIG apply.

if nargin < 3 || isempty(c), c = vsd_config(); end
x = double(x);
if size(x,2) > 1 && size(x,1) > 1, x = mean(x,2); end
x = x(:);
U = struct('Content',zeros(0,24),'Speaker',zeros(0,24),'SpeechSec',0,'RawRms',0, ...
    'Peak',0,'ClipFrac',0,'NumFrames',0,'Speech',false(0,1),'Fs',c.Fs,'Audio8k',zeros(0,1));
if isempty(x), return; end
U.RawRms = sqrt(mean(x.^2));
U.Peak = max(abs(x));
U.ClipFrac = mean(abs(x) >= 0.999);

% 1. rational resampling ------------------------------------------------------
y = vsd_resample(x, fs, c.Fs);
U.Audio8k = y;
% 2. DC removal + spectral subtraction -----------------------------------------
y = y - mean(y);
y = spectral_subtract_quiet(y, c);
% 3. peak normalisation ---------------------------------------------------------
pk = max(abs(y));
if pk > 0, y = y / pk; end
% 4. pre-emphasis ---------------------------------------------------------------
y = [y(1); y(2:end) - c.PreEmph * y(1:end-1)];
% 5. framing --------------------------------------------------------------------
N = round(c.FrameMs * 1e-3 * c.Fs);  H = round(c.HopMs * 1e-3 * c.Fs);
if numel(y) < N, y = [y; zeros(N - numel(y), 1)]; end
nf = 1 + floor((numel(y) - N) / H);
idx = (1:N) + H * (0:nf-1)';                    % [nf x N]
w = 0.54 - 0.46 * cos(2*pi*(0:N-1)/(N-1));      % symmetric Hamming
fr = y(idx) .* w;
S = fft(fr, c.NFFT, 2);
P = abs(S(:, 1:c.NFFT/2+1)).^2 / N;
% 6. mel filter bank, log, DCT, lifter ------------------------------------------
B = vsd_melbank(c.NumMel, c.NFFT, c.Fs, c.MelLowHz, c.MelHighHz);
me = P * B.';
logm = log(max(me, 1e-12));
D = vsd_dct(c.NumMel, c.NumCep);
cc = logm * D.';
lift = 1 + (c.Lifter/2) * sin(pi * (0:c.NumCep-1) / c.Lifter);
cc = cc .* lift;
% 7. speech mask ----------------------------------------------------------------
logE = log(sum(me, 2) + 1e-12);
speech = logE > max(logE) - c.SpeechFloorDb/10 * log(10);
if sum(speech) < 10, speech(:) = true; end
% 8. c1..c12 and delta -------------------------------------------------------
st = cc(:, 2:end);
d1 = vsd_delta(st, c.DeltaN);
cs = st(speech, :);  ds = d1(speech, :);
% 9. CMVN ------------------------------------------------------------------------
content = [cs ds];
mu = mean(content, 1);  sd = std(content, 1, 1);  sd(sd < 1e-8) = 1e-8;
U.Content = (content - mu) ./ sd;
s1 = std(cs, 1, 1); s1(s1 < 1e-8) = 1e-8;
s2 = std(ds, 1, 1); s2(s2 < 1e-8) = 1e-8;
U.Speaker = [(cs - mean(cs,1)) ./ s1, ds ./ s2];
U.SpeechSec = sum(speech) * H / c.Fs;
U.NumFrames = nf;
U.Speech = speech;
U.LogE = logE;
end

% =========================================================================
function y = vsd_resample(x, fsIn, fsOut)
if fsIn == fsOut, y = x; return; end
g = gcd(round(fsOut), round(fsIn));
p = round(fsOut)/g;  q = round(fsIn)/g;
y = resample(x, p, q);          % polyphase FIR, Kaiser window (beta 5)
y = y(:);
end

function y = spectral_subtract_quiet(x, c)
%SPECTRAL_SUBTRACT_QUIET Power spectral subtraction, noise from quietest frames.
%   |Y|^2 = max(|X|^2 - alpha*Pn, beta*|X|^2)  (as a gain), periodic Hann, 50 %
%   overlap-add (the periodic Hann window sums to 1 at 50 % overlap).
N = round(c.SSFrameMs * 1e-3 * c.Fs);  N = N + mod(N,2);  H = N/2;
L = numel(x);
if L < 4*N, y = x; return; end
w = 0.5 - 0.5*cos(2*pi*(0:N-1)'/N);
pad = [zeros(N,1); x; zeros(N,1)];
nF = floor((numel(pad) - N)/H) + 1;
idx = (1:N)' + (0:nF-1)*H;                  % [N x nF]
F = fft(pad(idx) .* w, N, 1);
Pw = abs(F).^2;
[~, order] = sort(sum(Pw, 1));
q = order(1:max(3, round(c.SSNoiseFrac * nF)));
Pn = mean(Pw(:, q), 2);
G = max(1 - c.SSAlpha * Pn ./ max(Pw, 1e-20), c.SSBeta);
yf = real(ifft(F .* sqrt(G), N, 1));
out = zeros(numel(pad), 1);
for k = 1:nF
    out(idx(:,k)) = out(idx(:,k)) + yf(:,k);
end
y = out(N+1:N+L);
end

function B = vsd_melbank(M, nfft, fs, fmin, fmax)
h2m = @(f) 2595*log10(1 + f/700);
m2h = @(m) 700*(10.^(m/2595) - 1);
K = nfft/2 + 1;
f = linspace(0, fs/2, K);
cf = m2h(linspace(h2m(fmin), h2m(fmax), M+2));
B = zeros(M, K);
for m = 1:M
    up = (f - cf(m)) / (cf(m+1) - cf(m));
    dn = (cf(m+2) - f) / (cf(m+2) - cf(m+1));
    B(m,:) = max(0, min(up, dn));
end
end

function D = vsd_dct(M, n)
[k, m] = ndgrid(0:n-1, 0:M-1);
D = sqrt(2/M) * cos(pi * k .* (m + 0.5) / M);
D(1,:) = D(1,:) / sqrt(2);
end

function d = vsd_delta(c, N)
T = size(c,1);
pad = [repmat(c(1,:), N, 1); c; repmat(c(end,:), N, 1)];
d = zeros(size(c));
for n = 1:N
    d = d + n * (pad(N+n+1:N+n+T, :) - pad(N-n+1:N-n+T, :));
end
d = d / (2 * sum((1:N).^2));
end
