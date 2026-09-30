function E = vsd_evaluate_corpus(outDir, protocols)
%VSD_EVALUATE_CORPUS Measure the v4.1.4_Final engine on every stored voice.
%
%   E = VSD_EVALUATE_CORPUS() runs, on DataRoot of VSD_CONFIG:
%     'loto'   leave-one-take-out: each (student, take) ID+name pair is tested
%              with that take removed from enrolment (all microphones).
%     'cross'  enrol with the database-microphone takes only, test the takes
%              recorded on OTHER microphones (the "mic changed" complaint).
%     'open'   each student in turn is removed from enrolment and plays the role
%              of an UNKNOWN person saying his own ID and name (must be refused).
%     'mimic'  worst-case imposter: every genuine utterance of student A is
%              scored as if it perfectly spoke victim B's phrases; refused
%              unless B's voice gates pass.  Also reports whether A is named.
%   Results go to OUTDIR (default Results/final_eval): trials CSVs and
%   summary.txt.  The same protocols were run with proto/*.py while
%   designing the engine; both implementations should agree.
%
%   Mic of a file is inferred from its format: 44.1 kHz = our GUI laptop mic,
%   48 kHz stereo/float = original database mic, 48 kHz mono int16 = the second
%   external USB microphone.

if nargin < 1 || isempty(outDir), outDir = fullfile(fileparts(mfilename('fullpath')),'Results','final_eval'); end
if nargin < 2 || isempty(protocols), protocols = {'loto','cross','open','mimic'}; end
if exist(outDir,'dir') ~= 7, mkdir(outDir); end
c = vsd_config();
t0 = tic;
M = vsd_build_models('update', c);
fprintf('models: %d students, UBM from %s (%.0fs)\n', numel(M.Students), M.UbmSource, toc(t0));
E = struct();
mic = containers.Map();
for s = 1:numel(M.Students)
    for p = {'ID','Name'}
        T = M.Templates.(p{1}){s};
        for t = 1:numel(T), mic(T{t}.Path) = mic_of(T{t}.Path); end
    end
end
lines = {};
if any(strcmp(protocols,'loto')) || any(strcmp(protocols,'mimic'))
    rows = run_pairs(M, c, 'loto', mic);
    E.loto = rows;
    write_rows(fullfile(outDir,'loto_trials.csv'), rows);
    g = [rows.ok];  lines{end+1} = sprintf('LOTO genuine acceptance: %d/%d = %.1f %% (wrong-student accepts: %d)', ...
        sum(g), numel(g), 100*mean(g), sum([rows.wrong]));
    db = strcmp({rows.mic},'db');
    lines{end+1} = sprintf('   same (database) mic: %d/%d, other mics: %d/%d', sum(g(db)), sum(db), sum(g(~db)), sum(~db));
    fprintf('%s\n', lines{end-1}); fprintf('%s (%.0fs)\n', lines{end}, toc(t0));
end
if any(strcmp(protocols,'cross'))
    rows = run_pairs(M, c, 'cross', mic);
    E.cross = rows;
    write_rows(fullfile(outDir,'cross_mic_trials.csv'), rows);
    g = [rows.ok];
    lines{end+1} = sprintf('CROSS-MIC (enrol database mic only): %d/%d = %.1f %% (wrong accepts %d)', sum(g), numel(g), 100*mean(g), sum([rows.wrong]));
    fprintf('%s (%.0fs)\n', lines{end}, toc(t0));
end
if any(strcmp(protocols,'open'))
    rows = run_open(M, c, mic);
    E.open = rows;
    write_rows(fullfile(outDir,'unknown_speaker_trials.csv'), rows);
    fa = ~strcmp({rows.accepted}, '');
    lines{end+1} = sprintf('UNKNOWN-SPEAKER false accepts: %d/%d = %.1f %%', sum(fa), numel(fa), 100*mean(fa));
    fprintf('%s (%.0fs)\n', lines{end}, toc(t0));
end
if any(strcmp(protocols,'mimic'))
    [far, named, n] = mimic(E.loto, c);
    lines{end+1} = sprintf('PERFECT-MIMIC imposter trials: %d, false accepts %.2f %%, imposter correctly named %.1f %%', n, 100*far, 100*named);
    fprintf('%s\n', lines{end});
end
fid = fopen(fullfile(outDir,'summary.txt'),'w');
fprintf(fid, 'v4.1.4_Final corpus evaluation  %s\n', datestr(now,31));
fprintf(fid, 'DataRoot: %s\n', c.DataRoot);
fprintf(fid, '%s\n', lines{:});
fclose(fid);
E.summary = lines;
end

% =========================================================================
function rows = run_pairs(M, c, proto, mic)
rows = struct('student',{},'sidx',{},'take',{},'mic',{},'accepted',{},'decision',{},'ok',{},'wrong',{}, ...
    'Pid',{},'Pname',{},'V',{},'vrank',{},'Vall',{},'imposter',{});
N = numel(M.Students);
for s = 1:N
    Tid = M.Templates.ID{s};  Tnm = M.Templates.Name{s};
    for a = 1:numel(Tid)
        [~, nmA] = fileparts(Tid{a}.Path);
        b = find(cellfun(@(t) strcmp(fileparts_name(t.Path), nmA), Tnm), 1);
        if isempty(b), continue; end
        m = mic(Tid{a}.Path);
        if strcmp(proto,'cross') && (strcmp(m,'db') || strcmp(mic(Tnm{b}.Path),'db')), continue; end
        Uid = struct('Content', Tid{a}.Content, 'Speaker', Tid{a}.Speaker);
        Unm = struct('Content', Tnm{b}.Content, 'Speaker', Tnm{b}.Speaker);
        if strcmp(proto,'loto')
            excl = {Tid{a}.Path, Tnm{b}.Path};
            models = M.Speaker;
            models{s} = model_without(M, s, excl, c);
        else
            % cross: only database-mic templates of EVERY student remain
            [excl, models] = cross_setup(M, c, mic);
            if isempty(models{s}), continue; end
            excl = [excl, {Tid{a}.Path, Tnm{b}.Path}];
        end
        S = vsd_score_query(M, Uid, Unm, c, struct('ExcludePaths', {excl}, 'Models', {models}));
        R = vsd_decide(S, c);
        rows(end+1) = pack(M, s, nmA, m, S, R); %#ok<AGROW>
    end
end
end

function r = pack(M, s, take, m, S, R)
acc = '';  if R.Verified, acc = R.Student; end
r = struct('student', M.Students{s}, 'sidx', s, 'take', take, 'mic', m, 'accepted', acc, 'decision', R.Decision, ...
    'ok', strcmp(acc, M.Students{s}), 'wrong', ~isempty(acc) && ~strcmp(acc, M.Students{s}), ...
    'Pid', S.Pid(s), 'Pname', S.Pname(s), 'V', S.V(s), 'vrank', R.VoiceRank, 'Vall', S.V, ...
    'imposter', R.ImposterSuspect);
end

function n = fileparts_name(p)
[~, n] = fileparts(p);
end

function mu = model_without(M, s, excl, c)
X = [];
for p = {'ID','Name'}
    T = M.Templates.(p{1}){s};
    for t = 1:numel(T)
        if ~any(strcmp(T{t}.Path, excl)), X = [X; T{t}.Speaker]; end %#ok<AGROW>
    end
end
mu = vsd_gmm('adapt', X, M.UBM, c.MapRelevance);
end

function [excl, models] = cross_setup(M, c, mic)
persistent cache
if ~isempty(cache), excl = cache.excl; models = cache.models; return; end
excl = {};  models = cell(1, numel(M.Students));
for s = 1:numel(M.Students)
    X = [];
    for p = {'ID','Name'}
        T = M.Templates.(p{1}){s};
        for t = 1:numel(T)
            if strcmp(mic(T{t}.Path), 'db'), X = [X; T{t}.Speaker]; else, excl{end+1} = T{t}.Path; end %#ok<AGROW>
        end
    end
    if ~isempty(X), models{s} = vsd_gmm('adapt', X, M.UBM, c.MapRelevance); end
end
cache = struct('excl', {excl}, 'models', {models});
end

function rows = run_open(M, c, mic)
rows = struct('student',{},'sidx',{},'take',{},'mic',{},'accepted',{},'decision',{},'ok',{},'wrong',{}, ...
    'Pid',{},'Pname',{},'V',{},'vrank',{},'Vall',{},'imposter',{});
for u = 1:numel(M.Students)
    keep = setdiff(1:numel(M.Students), u);
    Mu = M;  Mu.Students = M.Students(keep);  Mu.Names = M.Names(keep);
    Mu.Templates.ID = M.Templates.ID(keep);  Mu.Templates.Name = M.Templates.Name(keep);
    Mu.Speaker = M.Speaker(keep);  Mu.Digits = M.Digits(keep);
    Tid = M.Templates.ID{u};  Tnm = M.Templates.Name{u};
    for a = 1:numel(Tid)
        [~, nmA] = fileparts(Tid{a}.Path);
        b = find(cellfun(@(t) strcmp(fileparts_name(t.Path), nmA), Tnm), 1);
        if isempty(b), continue; end
        S = vsd_score_query(Mu, struct('Content',Tid{a}.Content,'Speaker',Tid{a}.Speaker), ...
            struct('Content',Tnm{b}.Content,'Speaker',Tnm{b}.Speaker), c);
        R = vsd_decide(S, c);
        acc = ''; if R.Verified, acc = R.Student; end
        rows(end+1) = struct('student', M.Students{u}, 'sidx', u, 'take', nmA, 'mic', mic(Tid{a}.Path), ...
            'accepted', acc, 'decision', R.Decision, 'ok', isempty(acc), 'wrong', ~isempty(acc), ...
            'Pid', max(S.Pid), 'Pname', max(S.Pname), 'V', max(S.V), 'vrank', NaN, 'Vall', S.V, ...
            'imposter', R.ImposterSuspect); %#ok<AGROW>
    end
end
end

function [far, named, n] = mimic(rows, c)
fa = 0; nm = 0; n = 0;
for r = rows
    V = r.Vall;
    [~, vo] = sort(V, 'descend');
    sIdx = r.sidx;
    for v = 1:numel(V)
        if v == sIdx || ~isfinite(V(v)) || V(v) == -1, continue; end
        n = n + 1;
        vr = find(vo == v, 1);
        imp = vo(1) ~= v && V(vo(1)) - V(v) >= c.ImpGap && V(vo(1)) >= c.ImpMinVoice;
        acc = V(v) >= c.MinVoice && vr <= c.VoiceRankMax && ~imp;
        if isfield(c,'ClearWin') && c.ClearWin.Enable      % perfect words = clear winner
            acc = acc || (~imp && vr <= c.ClearWin.VoiceRankMax && V(v) >= c.ClearWin.MinVoice);
        end
        fa = fa + acc;  nm = nm + (imp && vo(1) == sIdx);
    end
end
far = fa / max(n,1);  named = nm / max(n,1);
end

function m = mic_of(path)
try
    info = audioinfo(path);
    if info.SampleRate == 44100, m = 'laptop';
    elseif info.NumChannels > 1 || info.BitsPerSample == 32, m = 'db';
    else, m = 'usb';
    end
catch
    m = 'unknown';
end
end

function write_rows(file, rows)
fid = fopen(file, 'w');
fprintf(fid, 'student,take,mic,decision,accepted,correct,wrong_accept,P_id,P_name,V,voice_rank,imposter_suspect\n');
for r = rows
    fprintf(fid, '%s,%s,%s,%s,%s,%d,%d,%.4f,%.4f,%.4f,%g,%s\n', r.student, r.take, r.mic, r.decision, ...
        r.accepted, r.ok, r.wrong, r.Pid, r.Pname, r.V, r.vrank, r.imposter);
end
fclose(fid);
end
