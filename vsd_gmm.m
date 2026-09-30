function varargout = vsd_gmm(op, varargin)
%VSD_GMM Gaussian-mixture voice models: UBM training, MAP adaptation, LLR.
%
%   UBM = VSD_GMM('train', X, c)           X [T x d] pooled speech frames
%   MU  = VSD_GMM('adapt', X, UBM, r)      MAP-adapted means of one student
%   S   = VSD_GMM('llr', X, MUcell, UBM)   mean per-frame log-likelihood ratio
%                                          for every model in MUcell
%
%   Theory (Reynolds, Quatieri & Dunn 2000, "Speaker verification using
%   adapted Gaussian mixture models"):
%     p(x|lambda) = sum_k w_k N(x; mu_k, diag(sigma_k^2))
%   * UBM = one GMM fitted by EM to the speech of MANY speakers ("a voice in
%     general" on these microphones).
%   * Student model = UBM with means pulled towards the student's frames:
%        n_k = sum_t P(k|x_t),  E_k[x] = sum_t P(k|x_t) x_t / n_k
%        alpha_k = n_k/(n_k + r),   mu_k' = alpha_k E_k[x] + (1-alpha_k) mu_k
%     Components the student never used keep the UBM mean, so 10-20 s of
%     speech is enough and the model cannot over-fit.
%   * Score: LLR = (1/T) sum_t [log p(x_t|student) - log p(x_t|UBM)].
%     > 0 means "sounds more like this student than like people in general".
%     The UBM term cancels most of the channel and phrase effects.

switch lower(op)
    case 'train',  varargout{1} = train_ubm(varargin{:});
    case 'adapt',  varargout{1} = map_adapt(varargin{:});
    case 'llr',    varargout{1} = llr_scores(varargin{:});
    case 'loglik', varargout{1} = frame_loglik(varargin{:});
    otherwise, error('vsd_gmm:op', 'Unknown operation %s', op);
end
end

function ubm = train_ubm(X, c)
X = double(X);
T = size(X,1);
if T > c.UbmMaxFrames
    X = X(round(linspace(1, T, c.UbmMaxFrames)), :);  T = size(X,1);
end
K = c.UbmMixtures;
% deterministic initialisation: K frames spread evenly over the pooled data
% (different students / recordings), so every run gives the same UBM
perm = round(linspace(1, T, K));
mu = X(perm, :);
% k-means initialisation
for it = 1:c.UbmKmeansIters
    d2 = sum(X.^2,2) + sum(mu.^2,2).' - 2*X*mu.';
    [~, a] = min(d2, [], 2);
    for k = 1:K
        sel = (a == k);
        if any(sel), mu(k,:) = mean(X(sel,:), 1); else, mu(k,:) = X(mod(perm(k) + 97*it, T) + 1, :); end
    end
end
v = zeros(K, size(X,2));  w = zeros(K,1);
for k = 1:K
    sel = (a == k);
    if sum(sel) > 1, v(k,:) = var(X(sel,:), 1, 1); else, v(k,:) = var(X, 1, 1); end
    w(k) = max(sum(sel), 1) / T;
end
v = v + c.UbmVarFloor;  w = w / sum(w);
for it = 1:c.UbmIters
    L = log_joint(X, w, mu, v);
    m = max(L, [], 2);
    P = exp(L - m);  P = P ./ sum(P, 2);
    nk = sum(P, 1).' + 1e-10;
    w = nk / T;
    mu = (P.' * X) ./ nk;
    v = max((P.' * (X.^2)) ./ nk - mu.^2, 0) + c.UbmVarFloor;
end
ubm = struct('w', w, 'mu', mu, 'var', v, 'K', K, 'NumFrames', T);
end

function mu = map_adapt(X, ubm, r)
X = double(X);
if isempty(X), mu = ubm.mu; return; end
L = log_joint(X, ubm.w, ubm.mu, ubm.var);
m = max(L, [], 2);
P = exp(L - m);  P = P ./ sum(P, 2);
n = sum(P, 1).';
Ex = (P.' * X) ./ max(n, 1e-10);
a = n ./ (n + r);
mu = a .* Ex + (1 - a) .* ubm.mu;
end

function s = llr_scores(X, MU, ubm)
X = double(X);
s = -inf(1, numel(MU));
if size(X,1) < 5, return; end
lu = frame_loglik(X, ubm.w, ubm.mu, ubm.var);
for j = 1:numel(MU)
    if isempty(MU{j}), continue; end
    lj = frame_loglik(X, ubm.w, MU{j}, ubm.var);
    s(j) = mean(lj - lu);
end
end

function ll = frame_loglik(X, w, mu, v)
L = log_joint(X, w, mu, v);
m = max(L, [], 2);
ll = m + log(sum(exp(L - m), 2));
end

function L = log_joint(X, w, mu, v)
% log( w_k N(x | mu_k, diag(v_k)) ) for every frame (rows) and component (cols)
iv = 1 ./ v;
L = log(w(:)).' - 0.5 * sum(log(2*pi*v), 2).' ...
    - 0.5 * ((X.^2) * iv.' - 2 * X * (mu .* iv).' + sum(mu.^2 .* iv, 2).');
end
