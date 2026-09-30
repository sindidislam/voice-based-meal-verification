function varargout = vsd_replay_guard(op, varargin)
%VSD_REPLAY_GUARD Replay-attack prevention layers 2 and 3 (layer 1 = challenge).
%
%   [FLAG, INFO] = VSD_REPLAY_GUARD('duplicate', U, SID, M, C [, EXCLUDEPATHS])
%       Layer 2 - replay memory.  Compares the new utterance with every stored
%       take of student SID and with the last C.Replay.MemorySize ACCEPTED live
%       utterances.  Two natural repetitions are never identical: on the corpus
%       the smallest DTW distance between two genuine takes was 2.41, while a
%       digitally injected copy of a stored file scores ~0.  FLAG is true when
%       the distance is below C.Replay.DuplicateDist (1.0).
%   VSD_REPLAY_GUARD('remember', U, SID, C)   store an accepted utterance.
%   [RATIO, INFO] = VSD_REPLAY_GUARD('lowband', X, FS, C)
%       Layer 3 - the proposal's sub-200 Hz energy ratio on the NATIVE-rate
%       signal (small phone loudspeakers cannot reproduce < 200 Hz).  It is
%       ADVISORY only: it is logged and shown, never used alone to refuse,
%       because a microphone change moves it as well and no labelled replay
%       corpus exists to calibrate it.

switch lower(op)
    case 'duplicate', [varargout{1}, varargout{2}] = duplicate(varargin{:});
    case 'remember',  remember(varargin{:});
    case 'lowband',   [varargout{1}, varargout{2}] = lowband(varargin{:});
    otherwise, error('vsd_replay_guard:op','Unknown operation %s', op);
end
end

function [flag, info] = duplicate(U, sid, M, c, excl)
if nargin < 5, excl = {}; end
info = struct('MinDist', Inf, 'Against', '');
flag = false;
if isempty(U) || size(U.Content,1) < 5, return; end
k = find(strcmp(M.Students, sid), 1);
T = {};
if ~isempty(k), T = [M.Templates.ID{k}, M.Templates.Name{k}]; end
mem = load_memory(c);
if isfield(mem, 'S') && isfield(mem.S, key(sid)), T = [T, mem.S.(key(sid))]; end
for t = 1:numel(T)
    if isfield(T{t}, 'Path') && any(strcmp(T{t}.Path, excl)), continue; end
    d = vsd_dtw(U.Content, T{t}.Content, c.DtwBand);
    if d < info.MinDist
        info.MinDist = d;
        if isfield(T{t}, 'Path'), info.Against = T{t}.Path; else, info.Against = 'accepted live take'; end
    end
end
flag = info.MinDist < c.Replay.DuplicateDist;
end

function remember(U, sid, c)
mem = load_memory(c);
if ~isfield(mem, 'S'), mem.S = struct(); end
f = key(sid);
L = {};
if isfield(mem.S, f), L = mem.S.(f); end
L{end+1} = struct('Content', single(U.Content), 'Path', ['live ' datestr(now, 31)]);
if numel(L) > c.Replay.MemorySize, L = L(end - c.Replay.MemorySize + 1:end); end
mem.S.(f) = L;
S = mem.S; %#ok<NASGU>
try, save(c.ReplayMemoryFile, 'S', '-v7'); catch, end
end

function mem = load_memory(c)
mem = struct();
if exist(c.ReplayMemoryFile, 'file') == 2
    try, mem = load(c.ReplayMemoryFile); catch, mem = struct(); end
end
end

function f = key(sid)
f = ['s' regexprep(char(sid), '\W', '')];
end

function [ratio, info] = lowband(x, fs, c)
x = double(x(:)); x = x - mean(x);
X = abs(fft(x)).^2;  f = (0:numel(x)-1)' * fs / numel(x);
half = f <= fs/2;
lo = sum(X(half & f >= c.Replay.LowBandHz(1) & f <= c.Replay.LowBandHz(2)));
tot = sum(X(half & f >= 20 & f <= min(3800, fs/2)));
ratio = lo / max(tot, eps);
info = struct('Ratio', ratio, 'Advisory', ratio < c.Replay.AdvisoryMinLowRatio);
end
