function S = vsd_transaction_sweep(outFile)
%VSD_TRANSACTION_SWEEP Full counter transaction for EVERY enrolled student.
%
%   S = VSD_TRANSACTION_SWEEP() runs VSD_VERIFY_TRANSACTION once per student
%   with that student's LAST ID + name take held out of the enrolment
%   (leave-one-out) and a random 3-digit challenge answered with digits cut
%   from his connected counting recording.  It is the closest offline
%   equivalent of every student walking up to the counter once.  Results are
%   written to Results/claude_eval/transaction_sweep.csv.

if nargin < 1 || isempty(outFile)
    outFile = fullfile(fileparts(mfilename('fullpath')), 'Results', 'claude_eval', 'transaction_sweep.csv');
end
if exist(fileparts(outFile),'dir') ~= 7, mkdir(fileparts(outFile)); end
if exist('OCTAVE_VERSION','builtin'), try, pkg load signal; catch, end, end
c = vsd_config();
c.ReplayMemoryFile = [tempname '.mat'];     % never touch the counter's replay memory
p = struct('fs', 44100, 'vsd', c);
M = vsd_models(c);  rng(7);
root = c.DataRoot;
S = struct('student',{},'take',{},'decision',{},'stage',{},'verified',{},'challenge',{},'Pid',{},'Pname',{},'V',{},'reason',{});
for s = 1:numel(M.Students)
    sid = M.Students{s};
    ids = cellfun(@(t) fileparts_name(t.Path), M.Templates.ID{s}, 'UniformOutput', false);
    nms = cellfun(@(t) fileparts_name(t.Path), M.Templates.Name{s}, 'UniformOutput', false);
    common = intersect(ids(~cellfun(@isempty, regexp(ids, '^\d+$'))), nms);
    if isempty(common), continue; end
    [~, j] = max(str2double(common));  take = common{j};
    code = randi([0 9], 1, 3);
    opts = struct('Files', struct('ID', fullfile(root,'ID',sid,[take '.wav']), 'Name', fullfile(root,'Name',sid,[take '.wav'])), ...
        'HoldOut', true, 'NoAdapt', true, 'ChallengeCode', [code; mod(code + [1 3 7], 10)]);
    ch = [];
    try, ch = test_vsd_engine_answer(root, sid, code, M, c); catch, end
    if ~isempty(ch)
        opts.Audio = struct('Challenge', {{ch, c.Fs}}, 'Challenge2', {{test_vsd_engine_answer(root, sid, opts.ChallengeCode(2,:), M, c), c.Fs}});
    else
        opts.SkipChallenge = true;
    end
    T = vsd_verify_transaction([], p, opts);
    R = T.Scores;  if ~isfield(R,'Pid'), R = struct('Pid',NaN,'Pname',NaN,'V',NaN); end
    chs = 'not tested (no independent digit recording)';
    if T.Challenge.Used, chs = sprintf('%s', mat2str(T.Challenge.Code)); if T.Challenge.Passed, chs = [chs ' passed']; else, chs = [chs ' FAILED']; end, end
    S(end+1) = struct('student', sid, 'take', take, 'decision', T.Decision, 'stage', T.Stage, 'verified', T.Verified, ...
        'challenge', chs, 'Pid', R.Pid, 'Pname', R.Pname, 'V', R.V, 'reason', T.Reason); %#ok<AGROW>
    fprintf('SWEEP %s take %s -> %s (%s)\n', sid, take, T.Decision, chs);
end
fid = fopen(outFile, 'w');
fprintf(fid, 'student,take,decision,stage,verified,challenge,P_id,P_name,V\n');
for r = S
    fprintf(fid, '%s,%s,%s,%s,%d,%s,%.4f,%.4f,%.4f\n', r.student, r.take, r.decision, r.stage, r.verified, r.challenge, r.Pid, r.Pname, r.V);
end
fclose(fid);
fprintf('TRANSACTION SWEEP: %d/%d students verified end-to-end (challenge included).\n', sum([S.verified]), numel(S));
end

function n = fileparts_name(p)
[~, n] = fileparts(p);
end
