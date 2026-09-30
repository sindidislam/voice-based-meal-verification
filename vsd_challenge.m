function varargout = vsd_challenge(op, varargin)
%VSD_CHALLENGE Random-digit freshness challenge (replay-attack prevention).
%
%   CODE = VSD_CHALLENGE('new', C)            random code, e.g. [4 7 2]
%   TXT  = VSD_CHALLENGE('text', CODE)        'four seven two'
%   [PASS, INFO] = VSD_CHALLENGE('verify', U, CODE, M, SIDX, C, VOICEORDER)
%
%   Why: a replay attacker plays a RECORDING of the victim's roll number and
%   name.  A recording made yesterday cannot contain digits the kiosk chose a
%   second ago, so the attacker fails this step.  (Text-prompted speaker
%   verification; the voice of the challenge is also scored by the GMM.)
%
%   Verification (template concatenation + DTW, EEE 312 Expt 5 idea):
%   * reference sequence for any code = the claimed student's own isolated
%     digit recordings (Train/Digits) joined in that order (0.05 s gaps);
%   * decoys = the 27 codes that differ from the requested code in exactly
%     one position (the hardest possible confusions);
%   * PASS if  D(requested) <= 5.40  and  min D(decoy) / D(requested) >= 0.97.
%   Measured on the corpus (connected counting takes vs isolated templates):
%   genuine pass 93 % per attempt (99.5 % with one new code), replayed ID /
%   name recordings 0/18, stale (previous) codes 0/18.
%   If the student has no digit recordings, digits of the 3 closest voices are
%   used and INFO.Mode = 'cohort' (less accurate; enrol digits to fix).

switch lower(op)
    case 'new'
        c = varargin{1};
        varargout{1} = randi([0 9], 1, c.Challenge.Length);
    case 'text'
        w = {'zero','one','two','three','four','five','six','seven','eight','nine'};
        code = varargin{1};
        varargout{1} = strjoin(w(code + 1), ' ');
    case 'verify'
        [varargout{1}, varargout{2}] = verify(varargin{:});
    otherwise
        error('vsd_challenge:op', 'Unknown operation %s', op);
end
end

function [pass, info] = verify(U, code, M, sidx, c, voiceOrder)
if nargin < 6, voiceOrder = 1:numel(M.Students); end
info = struct('Mode','own','Requested',code,'Dreq',Inf,'Margin',0,'BestDecoy',[], ...
    'Recognised',code,'Templates',{{}},'Reason','','Splice',false);
pass = false;
if isempty(U) || size(U.Content,1) < 5
    info.Reason = 'No speech in the challenge recording.'; return;
end
tspk = sidx;
if ~has_digits(M, sidx)
    info.Mode = 'cohort';
    hasAll = cellfun(@(D) all(~cellfun(@isempty, D)), M.Digits);
    cand = voiceOrder(hasAll(voiceOrder));        % closest voices first
    cand(cand == sidx) = [];
    if isempty(cand), info.Reason = 'No digit templates enrolled.'; pass = true; info.Mode = 'unavailable'; return; end
    tspk = cand(1:min(3, numel(cand)));
end
info.Templates = M.Students(tspk);
codes = [code; neighbours(code)];
D = inf(size(codes,1), 1);
for k = 1:size(codes,1)
    for t = tspk(:)'
        T = template(M.Digits{t}, codes(k,:), c);
        D(k) = min(D(k), vsd_dtw(U.Content, T.Content, c.DtwBand));
    end
end
info.Dreq = D(1);
[dmin, j] = min(D(2:end));
info.Margin = dmin / max(D(1), 1e-9);
info.BestDecoy = codes(j+1, :);
[~, r] = min(D);  info.Recognised = codes(r, :);
pass = (D(1) <= c.Challenge.MaxDist) && (info.Margin >= c.Challenge.MinMargin);
info.Splice = D(1) < c.Challenge.MinDist && strcmp(info.Mode, 'own');
if info.Splice
    % A live answer never matches the stored digit recordings this closely
    % (smallest genuine distance on the corpus is far above MinDist); an answer
    % cut and pasted from the enrolled digit files does.
    pass = false;
    info.Reason = sprintf(['Challenge answer is a near-exact copy of the ENROLLED digit recordings ' ...
        '(distance %.2f < %.2f): spliced replay attack.'], D(1), c.Challenge.MinDist);
    return;
end
if pass
    info.Reason = sprintf('Challenge "%s" verified (distance %.2f, margin %.3f).', ...
        vsd_challenge('text', code), D(1), info.Margin);
else
    info.Reason = sprintf(['Challenge "%s" NOT verified (distance %.2f, need <= %.2f; margin %.3f, ' ...
        'need >= %.2f). A recorded/replayed voice cannot answer a fresh code.'], ...
        vsd_challenge('text', code), D(1), c.Challenge.MaxDist, info.Margin, c.Challenge.MinMargin);
end
end

function tf = has_digits(M, s)
tf = s >= 1 && s <= numel(M.Digits) && all(~cellfun(@isempty, M.Digits{s}));
end

function N = neighbours(code)
N = zeros(0, numel(code));
for p = 1:numel(code)
    for d = 0:9
        if d ~= code(p), q = code; q(p) = d; N(end+1,:) = q; end %#ok<AGROW>
    end
end
end

function T = template(digits, code, c)
fs = c.Fs;
x = zeros(round(0.2*fs), 1);
for d = code
    z = digits{d+1}(:);
    z = z / (max(abs(z)) + 1e-9);
    x = [x; z; zeros(round(c.Challenge.GapSec*fs), 1)]; %#ok<AGROW>
end
x = [x; zeros(round(0.2*fs), 1)];
T = vsd_frontend(x, fs, c);
end
