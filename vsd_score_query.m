function S = vsd_score_query(M, Uid, Uname, c, opts)
%VSD_SCORE_QUERY Score one transaction (spoken ID + spoken name) against everyone.
%
%   S = VSD_SCORE_QUERY(M, UID, UNAME) returns, for every enrolled student k,
%     S.Did(k), S.Dname(k)  smallest DTW distance to k's ID / name templates
%     S.Pid(k), S.Pname(k)  cohort-normalised phrase scores
%                 P(k) = log( mean of the 5 smallest distances to OTHER
%                             students / distance to k )
%     S.LLR(k)              GMM-UBM log-likelihood ratio of all speech frames
%     S.V(k)                cohort-normalised voice score
%                 V(k) = LLR(k) - mean of the 5 largest LLRs of OTHER students
%
%   Why cohort normalisation: a new microphone, room or loudness changes the
%   raw distance to EVERY template in the same direction.  The ratio against
%   the nearest competitors cancels that common shift (Rosenberg et al. 1992),
%   so one threshold keeps working when the microphone changes.  P > 0 means
%   "closer to k than to k's nearest rivals".
%
%   OPTS.ExcludePaths (cellstr) removes templates from the comparison; the
%   offline evaluation uses it for leave-one-take-out testing.

if nargin < 4 || isempty(c), c = vsd_config(); end
if nargin < 5, opts = struct(); end
excl = {};
if isfield(opts,'ExcludePaths'), excl = opts.ExcludePaths; end
N = numel(M.Students);
S = struct('Students', {M.Students}, 'Did', inf(1,N), 'Dname', inf(1,N), ...
    'Pid', -ones(1,N), 'Pname', -ones(1,N), 'LLR', -inf(1,N), 'V', -ones(1,N), ...
    'HasID', ~isempty(Uid) && size(Uid.Content,1) > 2, ...
    'HasName', ~isempty(Uname) && size(Uname.Content,1) > 2);
for k = 1:N
    if S.HasID,   S.Did(k)   = best_distance(Uid.Content,   M.Templates.ID{k},   excl, c); end
    if S.HasName, S.Dname(k) = best_distance(Uname.Content, M.Templates.Name{k}, excl, c); end
end
if S.HasID,   S.Pid   = cohort_lower(S.Did, c.CohortSize);   end
if S.HasName, S.Pname = cohort_lower(S.Dname, c.CohortSize); end
X = [];
if S.HasID, X = [X; Uid.Speaker]; end
if S.HasName, X = [X; Uname.Speaker]; end
if isfield(opts,'ExtraSpeech') && ~isempty(opts.ExtraSpeech), X = [X; opts.ExtraSpeech]; end
models = M.Speaker;
if isfield(opts,'Models'), models = opts.Models; end
if size(X,1) >= 5
    S.LLR = vsd_gmm('llr', X, models, M.UBM);
    S.V = cohort_higher(S.LLR, c.CohortSize);
end
S.NumVoiceFrames = size(X,1);
end

% =========================================================================
function d = best_distance(q, T, excl, c)
d = Inf;
for t = 1:numel(T)
    if ~isempty(excl) && any(strcmp(T{t}.Path, excl)), continue; end
    d = min(d, vsd_dtw(q, T{t}.Content, c.DtwBand));
end
end

function P = cohort_lower(d, k)
P = -ones(size(d));
for c = 1:numel(d)
    if ~isfinite(d(c)), continue; end
    o = d([1:c-1, c+1:end]);  o = sort(o(isfinite(o)));
    if isempty(o), continue; end
    P(c) = log(mean(o(1:min(k,numel(o)))) / max(d(c), 1e-9));
end
end

function V = cohort_higher(s, k)
V = -ones(size(s));
for c = 1:numel(s)
    if ~isfinite(s(c)), continue; end
    o = s([1:c-1, c+1:end]);  o = sort(o(isfinite(o)), 'descend');
    if isempty(o), continue; end
    V(c) = s(c) - mean(o(1:min(k,numel(o))));
end
end
