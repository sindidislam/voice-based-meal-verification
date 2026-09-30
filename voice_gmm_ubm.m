function varargout = voice_gmm_ubm(op, varargin)
%VOICE_GMM_UBM Text-independent speaker timbre modeling via GMM-UBM.
%
%   ubm   = voice_gmm_ubm('trainubm', X, K, iters)
%   mu    = voice_gmm_ubm('adapt', X, ubm, relevance)
%   [llr, ranks, best] = voice_gmm_ubm('score', X, MU, ubm)
%
%   Reference: Reynolds, Quatieri and Dunn, "Speaker verification using adapted
%   Gaussian mixture models", Digital Signal Processing 10, 2000.

switch lower(char(op))
    case 'trainubm'
        varargout = {trainUBM(varargin{:})};
    case 'adapt'
        varargout = {mapAdapt(varargin{:})};
    case 'score'
        [llr, ranks, best] = scoreLLR(varargin{:});
        varargout = {llr, ranks, best};
    otherwise
        error('voice_gmm_ubm:unknownOp', 'Unknown operation "%s".', char(op));
end
end

% -------------------------------------------------------------------------
function ubm = trainUBM(X, K, iters)
if nargin < 2 || isempty(K), K = 16; end
if nargin < 3 || isempty(iters), iters = 10; end
X = double(X);
N = size(X, 1);
if N < K, K = max(1, N); end

floorVar = 1e-3 * var(X, 0, 1);
floorVar(floorVar < 1e-6) = 1e-6;

mu = lbg_codebook(X, K, iters);
K  = size(mu, 1);
v  = repmat(var(X, 0, 1), K, 1);
v  = max(v, floorVar);
w  = ones(K, 1) / K;

for it = 1:iters
    L = logJoint(X, w, mu, v);
    P = exp(L - max(L, [], 2));
    P = P ./ max(sum(P, 2), 1e-12);
    n = sum(P, 1).' + 1e-10;
    w  = n / N;
    mu = (P.' * X) ./ n;
    v  = max((P.' * (X.^2)) ./ n - mu.^2, floorVar);
end

ubm = struct('w', w, 'mu', mu, 'var', v, 'K', K, 'NumFrames', N);
end

% -------------------------------------------------------------------------
function mu = mapAdapt(X, ubm, r)
if nargin < 3 || isempty(r), r = 16; end
X = double(X);
if isempty(X)
    mu = ubm.mu;
    return;
end
L = logJoint(X, ubm.w, ubm.mu, ubm.var);
P = exp(L - max(L, [], 2));
P = P ./ max(sum(P, 2), 1e-12);
n = sum(P, 1).';
Ex = (P.' * X) ./ max(n, 1e-10);
a = n ./ (n + r);
mu = a .* Ex + (1 - a) .* ubm.mu;
end

% -------------------------------------------------------------------------
function [llr, ranks, best] = scoreLLR(X, MU, ubm)
X = double(X);
N = size(MU, 3);
llr = -inf(1, N);
ranks = inf(1, N);
best = 0;
if size(X, 1) < 2 || N == 0
    return;
end

lu = frameLogLik(X, ubm.w, ubm.mu, ubm.var);
for j = 1:N
    lj = frameLogLik(X, ubm.w, double(MU(:, :, j)), ubm.var);
    llr(j) = mean(lj - lu);
end

[sortedLLR, vorder] = sort(llr, 'descend');
for j = 1:N
    pos = find(vorder == j, 1);
    if ~isempty(pos)
        ranks(j) = pos;
    end
end
if ~isempty(vorder)
    best = vorder(1);
end
end

% -------------------------------------------------------------------------
function ll = frameLogLik(X, w, mu, v)
L = logJoint(X, w, mu, v);
m = max(L, [], 2);
ll = m + log(sum(exp(L - m), 2));
end

% -------------------------------------------------------------------------
function L = logJoint(X, w, mu, v)
% Compute log-likelihood of each frame (row) for each Gaussian component (col)
iv = 1 ./ max(v, 1e-8);
L = log(max(w(:), 1e-12)).' - 0.5 * sum(log(2 * pi * max(v, 1e-8)), 2).' ...
    - 0.5 * ((X.^2) * iv.' - 2 * X * (mu .* iv).' + sum(mu.^2 .* iv, 2).');
end

% -------------------------------------------------------------------------
function C = lbg_codebook(X, K, iters)
if nargin < 3, iters = 15; end
X = double(X);
K = max(1, min(K, size(X, 1)));
C = mean(X, 1);
e = 0.01 * std(X, 0, 1);
e(e == 0) = 1e-3;
while size(C, 1) < K
    C = [C + e; C - e];
    if size(C, 1) > K, C = C(1:K, :); end
    for it = 1:iters
        D2 = sum(X.^2, 2) + sum(C.^2, 2).' - 2 * (X * C.');
        [~, a] = min(D2, [], 2);
        for k = 1:size(C, 1)
            m = (a == k);
            if any(m)
                C(k, :) = mean(X(m, :), 1);
            end
        end
    end
end
end
