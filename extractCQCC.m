function [cqccFeatures, cqtSpectrogram, freqBins] = extractCQCC(signal, fs, cfg)
%EXTRACTCQCC Constant-Q Cepstral Coefficients (CQCC) for acoustic anti-spoofing.
%   [CQCCFEATURES, CQTSPECTROGRAM, FREQBINS] = EXTRACTCQCC(SIGNAL, FS, CFG)
%   computes the Constant-Q Transform with geometrically spaced frequency bins,
%   takes the log power spectrum, and applies DCT decorrelation.
%
%   f_k = fmin * 2^(k/B),   Q = 1/(2^(1/B) - 1),   N_k = round(Q*fs/f_k)
%
%   Narrow time windows at high frequencies expose transient loudspeaker
%   transducer distortions and DAC artefacts during replay attacks.

if nargin < 3, cfg = struct(); end
if ~isfield(cfg, 'BinsPerOctave'), cfg.BinsPerOctave = 16; end
if ~isfield(cfg, 'CQTFmin'),        cfg.CQTFmin = 50; end
if ~isfield(cfg, 'CQTFmax'),        cfg.CQTFmax = min(fs/2 - 100, 16000); end
if ~isfield(cfg, 'NumCQCC'),        cfg.NumCQCC = 16; end
if ~isfield(cfg, 'CQTHopMs'),       cfg.CQTHopMs = 10; end

B    = cfg.BinsPerOctave;
fmin = cfg.CQTFmin;
fmax = min(cfg.CQTFmax, fs/2 - 10);
nc   = cfg.NumCQCC;

signal = double(signal(:));
total  = numel(signal);

numBins  = max(4, floor(B * log2(fmax / fmin)));
freqBins = fmin * (2 .^ ((0:numBins-1).' / B));
Q        = 1 / (2^(1/B) - 1);

N_k = round(Q * fs ./ freqBins);
N_k = max(8, min(total, N_k));

kernels = cell(numBins, 1);
for k = 1:numBins
    Nc = N_k(k);
    n  = (0:Nc-1).';
    w  = 0.54 - 0.46 * cos(2*pi*(0:Nc-1)'/(Nc-1)); % Hamming
    kernels{k} = (w / Nc) .* exp(-1j * 2*pi * (freqBins(k)/fs) * n);
end

hop     = max(1, round(cfg.CQTHopMs * 1e-3 * fs));
padLen  = ceil(max(N_k) / 2);
padded  = [zeros(padLen,1); signal; zeros(padLen,1)];
centers = (1:hop:total) + padLen;
nT      = numel(centers);

cqtSpectrogram = zeros(numBins, nT);
for t = 1:nT
    c = centers(t);
    for k = 1:numBins
        Nc = N_k(k);
        s  = c - floor(Nc/2);
        seg = padded(s : s+Nc-1);
        cqtSpectrogram(k, t) = abs(sum(seg .* kernels{k}))^2;
    end
end

logSpec  = log(max(cqtSpectrogram, 1e-12));
try
    D = dctmtx(numBins);
catch
    % Fallback DCT matrix if toolbox function missing
    [cc, rr] = meshgrid(0:numBins-1, 0:numBins-1);
    D = sqrt(2/numBins) * cos(pi * (2*cc + 1) .* rr / (2*numBins));
    D(1, :) = D(1, :) / sqrt(2);
end

fullCQCC = D * logSpec;

if numBins >= nc + 1
    staticCQCC = fullCQCC(2:nc+1, :).';     % drop p=0 energy term
else
    staticCQCC = fullCQCC(1:min(nc, numBins), :).';
end

if nT >= 3
    cqccFeatures = [staticCQCC, fir_delta_local(staticCQCC, 2)];
else
    cqccFeatures = staticCQCC;
end
end

function delta = fir_delta_local(x, N)
[T, D] = size(x);
delta  = zeros(T, D);
denom  = 2 * sum((1:N).^2);
padded = [repmat(x(1,:), N, 1); x; repmat(x(end,:), N, 1)];
for t = 1:T
    pi_ = t + N;
    s   = zeros(1, D);
    for n = 1:N
        s = s + n * (padded(pi_+n, :) - padded(pi_-n, :));
    end
    delta(t, :) = s / denom;
end
end
