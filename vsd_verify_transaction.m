function T = vsd_verify_transaction(status, p, options)
%VSD_VERIFY_TRANSACTION One counter transaction with the v4.1.4_Final engine.
%
%   T = VSD_VERIFY_TRANSACTION(STATUS, P, OPTIONS) records (or reads) the
%   spoken Student ID and full name, identifies the student from BOTH the
%   phrase content and the voice, checks for imposters, runs the replay
%   guard (random-digit challenge + replay memory + low-band advisory) and
%   returns a struct T consumed by VERIFY_MEAL_WORKFLOW.
%
%   OPTIONS
%     .ClaimedID   optional typed 7-digit ID (binds the decision)
%     .Files       struct('ID',path,'Name',path,'Challenge',path) - offline test
%                  / demo input (no microphone; challenge optional)
%     .Audio       struct('ID',{x,fs},'Name',{x,fs},...) raw audio instead of files
%     .CaptureFcn  @(label,status,p,promptText) -> [x, fs, diag]  (test seam)
%     .ChallengeCode fixed code for tests (normally random)
%     .NoAdapt     true = never store adaptive templates (tests)
%     .HoldOut     true = the given Files are removed from the enrolment for
%                  this transaction (leave-one-out demo with stored takes;
%                  otherwise a stored file is, correctly, flagged as a replay)
%     .SkipChallenge true = skip the random-digit step (offline demos only)
%
%   T fields: Verified, Decision, Student, StudentName, Stage, Reason,
%   ImposterSuspect, ImposterName, ReplayFlag, ReplayReason, Challenge
%   (struct), Scores (struct from VSD_DECIDE), IDFeatures/NameFeatures (U).

if nargin < 3, options = struct(); end
c = vsd_cfg(p);
T = struct('Verified',false,'Decision','RETRY','Student','','StudentName','','Stage','capture-id', ...
    'Reason','','ImposterSuspect','','ImposterName','','ReplayFlag',false,'ReplayReason','', ...
    'Challenge',struct('Used',false,'Passed',false,'Code',[],'Info',struct()),'Scores',struct(), ...
    'IDU',[],'NameU',[],'LowBandRatio',NaN,'Advisory','','Timing',struct());
t0 = tic;
M = vsd_models(c);
if isempty(M.Students)
    T.Stage = 'enrollment'; T.Reason = 'No students with both ID and name recordings are enrolled.'; return;
end
T.Timing.Models = toc(t0);
claim = '';
if isfield(options,'ClaimedID') && ~isempty(options.ClaimedID), claim = char(options.ClaimedID); end

% ---- 1. acquisition + front-end ------------------------------------------------
[Uid, xid, fsid, T] = acquire('ID', 'your Student ID (roll number)', status, p, c, options, T);
if isempty(Uid), return; end
[Unm, ~, ~, T] = acquire('Name', 'your full name', status, p, c, options, T);
if isempty(Unm), return; end
T.IDU = Uid;  T.NameU = Unm;
[T.LowBandRatio, lb] = vsd_replay_guard('lowband', xid, fsid, c);
if lb.Advisory
    T.Advisory = sprintf('Low-band (20-200 Hz) energy ratio %.5f is unusually small (loudspeaker-like). Logged for audit.', T.LowBandRatio);
end
T.Timing.Capture = toc(t0);

% ---- 2. scoring and fused decision ---------------------------------------------
update_status_text(status, '  Scoring phrase content (DTW) and voice (GMM-UBM) against all enrolled students...');
sopts = struct();
if isfield(options,'HoldOut') && options.HoldOut && isfield(options,'Files')
    [sopts.ExcludePaths, sopts.Models] = hold_out(M, options.Files, c);
end
S = vsd_score_query(M, Uid, Unm, c, sopts);
R = vsd_decide(S, c, claim, M);
T.Scores = R;  T.ScoreVectors = S;
T.Timing.Scoring = toc(t0);
report_top(status, S, M);
T.Decision = R.Decision;  T.Stage = R.Stage;  T.Reason = R.Reason;  T.Student = R.Student;
T.ImposterSuspect = R.ImposterSuspect;  T.ImposterName = R.ImposterName;
if ~R.Verified
    update_status_text(status, ['● ' R.Reason]);
    return;
end
k = find(strcmp(M.Students, R.Student), 1);
T.StudentName = M.Names{k};

% ---- 3. replay memory (exact copy of a stored / previously accepted take) -------
excl = {};  if isfield(sopts,'ExcludePaths'), excl = sopts.ExcludePaths; end
[f1, i1] = vsd_replay_guard('duplicate', Uid, R.Student, M, c, excl);
[f2, i2] = vsd_replay_guard('duplicate', Unm, R.Student, M, c, excl);
if f1 || f2
    T.Verified = false; T.Decision = 'REPLAY'; T.Stage = 'replay'; T.ReplayFlag = true;
    T.ReplayReason = sprintf(['REPLAY ATTACK SUSPECTED: the recording is a near-identical copy of a stored ' ...
        'utterance (DTW distance %.2f < %.2f; natural repetitions are never below 2.4).'], ...
        min(i1.MinDist, i2.MinDist), c.Replay.DuplicateDist);
    T.Reason = T.ReplayReason; update_status_text(status, ['● ' T.Reason]); return;
end

% ---- 4. random-digit challenge ------------------------------------------------------
skipCh = isfield(options,'SkipChallenge') && options.SkipChallenge;
if c.Challenge.Enable && ~skipCh
    [~, vorder] = sort(S.V, 'descend');
    passed = false;  okContent = false;  okVoice = false;  info = struct('VoiceTop', '');
    for attempt = 1:c.Challenge.MaxAttempts
        if isfield(options,'ChallengeCode') && ~isempty(options.ChallengeCode)
            code = options.ChallengeCode(min(attempt, size(options.ChallengeCode,1)), :);
        else
            code = vsd_challenge('new', c);
        end
        txt = vsd_challenge('text', code);
        T.Challenge.Used = true;  T.Challenge.Code = code;
        update_status_text(status, sprintf('>>> ANTI-REPLAY CHALLENGE (attempt %d): please say the digits  "%s"', attempt, upper(txt)));
        chKey = 'Challenge';  if attempt > 1, chKey = sprintf('Challenge%d', attempt); end
        [Uch, ~, ~, T2] = acquire(chKey, sprintf('the digits %s', upper(txt)), status, p, c, options, T, ...
            sprintf('Say the digits %s', txt));
        if isempty(Uch)
            T = T2;  T.Verified = false;  T.Decision = 'RETRY';
            if strcmp(T.Stage,'user-stop'), return; end
            if ~(isfield(options,'Files') || isfield(options,'Audio')) || attempt == c.Challenge.MaxAttempts
                T.Stage = 'challenge'; T.Reason = 'The anti-replay challenge was not answered.'; return;
            end
            continue;
        end
        [okContent, info] = vsd_challenge('verify', Uch, code, M, k, c, vorder);
        % the digits must also be spoken in the claimed student's voice
        chModels = M.Speaker;  if isfield(sopts,'Models'), chModels = sopts.Models; end
        Lch = vsd_gmm('llr', Uch.Speaker, chModels, M.UBM);
        Vch = Lch(k) - mean_top_others(Lch, k, c.CohortSize);
        allV = arrayfun(@(j) Lch(j) - mean_top_others(Lch, j, c.CohortSize), 1:numel(Lch));
        gap = max(allV) - allV(k);
        okVoice = gap < c.Challenge.VoiceGap;
        info.VoiceV = Vch;  info.VoiceGap = gap;  [~, topj] = max(allV);  info.VoiceTop = M.Students{topj};
        T.Challenge.Info = info;
        if okContent && okVoice
            passed = true;
            update_status_text(status, ['  ' info.Reason ' Voice of the digits matches.']);
            break;
        end
        if ~okContent
            update_status_text(status, ['  ' info.Reason]);
        else
            update_status_text(status, sprintf(['  Challenge digits were correct but spoken in a different voice ' ...
                '(closest voice %s, gap %.2f).'], info.VoiceTop, gap));
        end
        if isfield(options,'Files') && ~isfield(options.Files,'Challenge2'), break; end
        if isfield(options,'Audio') && ~isfield(options.Audio,'Challenge2'), break; end
    end
    T.Challenge.Passed = passed;
    if ~passed
        T.Verified = false;  T.Decision = 'REPLAY';  T.Stage = 'challenge';  T.ReplayFlag = true;
        T.ReplayReason = ['REPLAY / LIVENESS CHECK FAILED: the random digits were not spoken correctly ' ...
            'in the claimed voice. A recording cannot answer a fresh code.'];
        if isfield(info,'Splice') && info.Splice
            T.ReplayReason = [T.ReplayReason ' ' info.Reason];
        end
        if okContent && ~okVoice && ~isempty(info.VoiceTop) && ~strcmp(info.VoiceTop, R.Student)
            T.ImposterSuspect = info.VoiceTop;
            T.ReplayReason = [T.ReplayReason sprintf(' The digits sounded like %s.', info.VoiceTop)];
        end
        T.Reason = T.ReplayReason;  update_status_text(status, ['● ' T.Reason]);
        return;
    end
end

% ---- 5. accepted --------------------------------------------------------------
T.Verified = true;  T.Decision = 'VERIFIED';  T.Stage = 'verified';
T.Reason = R.Reason;
if T.Challenge.Used, T.Reason = [T.Reason ' Anti-replay challenge passed.']; end
vsd_replay_guard('remember', Uid, R.Student, c);
vsd_replay_guard('remember', Unm, R.Student, c);
if c.Adapt.Enable && ~(isfield(options,'NoAdapt') && options.NoAdapt) && ...
        R.Pname >= c.Adapt.MinPname && R.V >= c.Adapt.MinVoice
    try
        n = vsd_adapt(R.Student, xid, fsid, T.adaptNameAudio, T.adaptNameFs, c);
        if n > 0
            update_status_text(status, sprintf(['  Self-adaptation: this microphone''s takes were added ' ...
                'to %s''s profile (%d adaptive take(s) per phrase kept).'], R.Student, n));
        end
    catch err
        update_status_text(status, ['  (adaptive template not stored: ' err.message ')']);
    end
end
T.Timing.Total = toc(t0);
end

function [excl, models] = hold_out(M, files, c)
%HOLD_OUT Remove the query files from the enrolment (fair offline demo).
excl = {};  models = M.Speaker;
fn = fieldnames(files);
for j = 1:numel(fn), excl{end+1} = char(files.(fn{j})); end %#ok<AGROW>
for s = 1:numel(M.Students)
    X = [];  hit = false;
    for p = {'ID','Name'}
        T = M.Templates.(p{1}){s};
        for t = 1:numel(T)
            if any(strcmp(T{t}.Path, excl)), hit = true; else, X = [X; T{t}.Speaker]; end %#ok<AGROW>
        end
    end
    if hit && ~isempty(X), models{s} = vsd_gmm('adapt', X, M.UBM, c.MapRelevance); end
end
end

% =========================================================================
function [U, x, fs, T] = acquire(phrase, label, status, p, c, options, T, prompt)
if nargin < 8, prompt = ''; end
U = [];  x = [];  fs = p.fs;
key = phrase;  T.Stage = ['capture-' lower(regexprep(phrase,'\d',''))];
if isfield(options,'Audio') && isfield(options.Audio, key)
    a = options.Audio.(key);  x = a{1};  fs = a{2};
elseif isfield(options,'Files') && isfield(options.Files, key)
    [x, fs] = audioread(options.Files.(key));
    update_status_text(status, sprintf('  %s read from file %s', phrase, options.Files.(key)));
elseif isfield(options,'Files') || isfield(options,'Audio')
    return;                              % offline run without this phrase
elseif isfield(options,'CaptureFcn') && isa(options.CaptureFcn,'function_handle')
    [x, fs, dg] = options.CaptureFcn(label, status, p, prompt);
    if ~strcmp(dg.Stage,'ok'), T.Stage = dg.Stage; T.Reason = dg.Reason; return; end
else
    [x, fs, dg] = vsd_record_phrase(label, status, p, prompt);
    if ~strcmp(dg.Stage,'ok')
        T.Stage = dg.Stage; T.Reason = dg.Reason;
        if strcmp(dg.Stage,'user-stop'), T.Decision = 'UNCERTAIN / RETRY'; end
        return;
    end
end
if size(x,2) > 1, x = mean(x,2); end
U = vsd_frontend(x, fs, c);
if strcmp(phrase,'Name'), T.adaptNameAudio = x; T.adaptNameFs = fs; end
if strcmp(phrase,'ID'), T.adaptIdAudio = x; T.adaptIdFs = fs; end
if U.RawRms < c.MinRms || U.SpeechSec < c.MinSpeechSec
    T.Stage = 'quality';
    T.Reason = sprintf(['The %s recording is too quiet or too short (level %.4f, speech %.2f s). ' ...
        'Move closer to the microphone and speak clearly.'], lower(phrase), U.RawRms, U.SpeechSec);
    update_status_text(status, ['● ' T.Reason]);
    U = [];
    return;
end
update_status_text(status, sprintf('  %s: %.2f s of speech, %d frames, level %.4f%s.', phrase, U.SpeechSec, ...
    size(U.Content,1), U.RawRms, clip_note(U)));
end

function s = clip_note(U)
s = '';
if U.ClipFrac > 0.001, s = sprintf(', CLIPPED %.1f %%', 100*U.ClipFrac); end
end

function m = mean_top_others(L, k, n)
o = L([1:k-1, k+1:end]);  o = sort(o(isfinite(o)), 'descend');
m = mean(o(1:min(n, numel(o))));
end

function report_top(status, S, M)
F = 0.5*S.Pid + S.Pname + 0.25*S.V;
[~, o] = sort(F, 'descend');
lines = {'  Candidates (fused score = 0.5*P_id + P_name + 0.25*V):'};
for j = 1:min(4, numel(o))
    k = o(j);
    lines{end+1} = sprintf('    #%d %s  P_id %+.3f  P_name %+.3f  voice %+.3f', j, M.Students{k}, ...
        S.Pid(k), S.Pname(k), S.V(k)); %#ok<AGROW>
end
update_status_text(status, strjoin(lines, newline));
end

function c = vsd_cfg(p)
if isfield(p,'vsd') && isstruct(p.vsd), c = p.vsd; else, c = vsd_config(); end
end
