function R = test_vsd_engine(sid, victim)
%TEST_VSD_ENGINE End-to-end demonstration of the v4.1.4_Final security engine.
%
%   R = TEST_VSD_ENGINE() runs complete counter transactions from stored
%   recordings (no microphone needed) and prints what the counter would show:
%
%     1  GENUINE          student says his own ID + name (take held out of
%                         the enrolment) and answers a random 3-digit challenge
%     2  IMPOSTER         student A types B's Student ID and speaks  -> refused,
%        (typed claim)    "likely imposter = A"
%     3  IMPOSTER         A says B's ROLL NUMBER in A's own voice (built from
%        (spoken claim)   A's digits) + a recording of B's name -> refused
%     4  REPLAY (digital) B's stored enrolment file is injected unchanged
%                         -> REPLAY (copy of a stored take)
%     5  REPLAY (played   B's ID + name are replayed through a simulated phone
%        through speaker) loudspeaker and room -> refused: either the distorted
%                         phrases already fail, or the attacker cannot answer
%                         the fresh digits (REPLAY)
%     6  STALE CHALLENGE  a recording of B saying an OLD code is replayed -> REPLAY
%     7  SPLICE           the answer is cut and pasted from B's ENROLLED digit
%                         files -> REPLAY (splice guard, distance < MinDist)
%
%   TEST_VSD_ENGINE(SID, VICTIM) chooses the two students (defaults
%   2206147 and 2206141).  R is a struct array with the outcome of each case.
%   Challenge answers are cut from the student's connected "zero ... nine"
%   counting recording (Train/Digits/<id>/<id>_digits_01.wav), a DIFFERENT
%   recording from the isolated digit templates the challenge is checked
%   against, so the check is not trivially an exact match.

if nargin < 1 || isempty(sid), sid = '2206147'; end
if nargin < 2 || isempty(victim), victim = '2206141'; end
if exist('OCTAVE_VERSION','builtin'), try, pkg load signal; catch, end, end
p = struct('fs', 44100);
try, p = dsp_parameters(); catch, end
if ~isfield(p,'vsd'), p.vsd = vsd_config(); end
% the demonstration must not touch the counter's real replay memory
p.vsd.ReplayMemoryFile = [tempname '.mat'];
cleanup = onCleanup(@() delete_if_exists(p.vsd.ReplayMemoryFile)); %#ok<NASGU>
c = p.vsd;
M = vsd_models(c);
rng(312);
root = c.DataRoot;
f = @(ph, s, t) fullfile(root, ph, s, sprintf('%d.wav', t));
R = struct('Case', {}, 'Decision', {}, 'Student', {}, 'Imposter', {}, 'Expected', {}, 'Pass', {}, 'Reason', {});

% ---- 1 genuine ---------------------------------------------------------------
t = last_take(root, sid);
code = randi([0 9], 1, 3);
opts = struct('Files', struct('ID', f('ID',sid,t), 'Name', f('Name',sid,t)), 'HoldOut', true, ...
    'NoAdapt', true, 'ChallengeCode', code);
opts.Audio = struct('Challenge', {{test_vsd_engine_answer(root, sid, code, M, c), c.Fs}});
R(end+1) = run_case('1 GENUINE (own ID + name + live digits)', opts, p, 'VERIFIED', sid);

% ---- 2 imposter: typed claim ----------------------------------------------------
opts = struct('Files', struct('ID', f('ID',sid,t), 'Name', f('Name',sid,t)), 'HoldOut', true, ...
    'NoAdapt', true, 'ClaimedID', victim, 'SkipChallenge', true);
R(end+1) = run_case(sprintf('2 IMPOSTER: %s types %s''s ID', sid, victim), opts, p, 'IMPOSTER', victim, sid);

% ---- 3 imposter: spoken claim ------------------------------------------------------
xroll = roll_from_digits(M, sid, victim, c);
[xn, fsn] = audioread(f('Name', victim, 1));
opts = struct('Audio', struct('ID', {{xroll, c.Fs}}, 'Name', {{xn, fsn}}), 'NoAdapt', true, 'SkipChallenge', true);
R(end+1) = run_case(sprintf('3 IMPOSTER: %s says %s''s roll number', sid, victim), opts, p, 'REFUSED', victim, sid);

% ---- 4 replay: digital copy of a stored file ---------------------------------------
opts = struct('Files', struct('ID', f('ID',victim,1), 'Name', f('Name',victim,1)), 'NoAdapt', true, ...
    'SkipChallenge', true);
R(end+1) = run_case(sprintf('4 REPLAY: %s''s stored files injected', victim), opts, p, 'REPLAY', victim);

% ---- 5 replay through loudspeaker + room; challenge answered with the name ----------------
tv = last_take(root, victim);
[xi, fsi] = audioread(f('ID', victim, tv));  [xn, fsn] = audioread(f('Name', victim, tv));
code = randi([0 9], 1, 3);
opts = struct('Audio', struct('ID', {{loudspeaker(xi, fsi), fsi}}, 'Name', {{loudspeaker(xn, fsn), fsn}}, ...
    'Challenge', {{loudspeaker(xn, fsn), fsn}}), 'HoldOut', true, 'NoAdapt', true, 'ChallengeCode', code);
opts.Files = struct('ID', f('ID', victim, tv), 'Name', f('Name', victim, tv));   % only for hold-out bookkeeping
% the loudspeaker path may already spoil the phrase scores (refused at gate 2)
% or pass them and then fail the fresh-digit challenge (REPLAY): both refuse
R(end+1) = run_case(sprintf('5 REPLAY: %s played through a phone speaker', victim), opts, p, 'REFUSED', victim);

% ---- 6 stale challenge (recording of an old code) ------------------------------------------
old = randi([0 9], 1, 3);  code = mod(old + [3 5 7], 10);
opts = struct('Files', struct('ID', f('ID',victim,tv), 'Name', f('Name',victim,tv)), 'HoldOut', true, ...
    'NoAdapt', true, 'ChallengeCode', code);
opts.Audio = struct('Challenge', {{test_vsd_engine_answer(root, victim, old, M, c), c.Fs}});
R(end+1) = run_case(sprintf('6 STALE CHALLENGE: old code %s replayed for %s', num2str(old), num2str(code)), ...
    opts, p, 'REPLAY', victim);

% ---- 7 splice attack: the answer is pasted from the victim's enrolled digit files --------
code = randi([0 9], 1, 3);
kv = find(strcmp(M.Students, victim), 1);
xs = zeros(round(0.2*c.Fs), 1);
for d = code, z = M.Digits{kv}{d+1}(:); xs = [xs; z / max(abs(z)); zeros(round(0.06*c.Fs), 1)]; end %#ok<AGROW>
opts = struct('Files', struct('ID', f('ID',victim,tv), 'Name', f('Name',victim,tv)), 'HoldOut', true, ...
    'NoAdapt', true, 'ChallengeCode', code);
opts.Audio = struct('Challenge', {{[xs; zeros(round(0.2*c.Fs), 1)], c.Fs}});
R(end+1) = run_case(sprintf('7 SPLICE: %s''s enrolled digit files pasted as the answer', victim), opts, p, 'REPLAY', victim);

fprintf('\n================ v4.1.4_Final engine demonstration ================\n');
for k = 1:numel(R)
    mark = 'PASS'; if ~R(k).Pass, mark = 'FAIL'; end
    fprintf('[%s] %-55s -> %-9s %s %s\n', mark, R(k).Case, R(k).Decision, R(k).Student, R(k).Imposter);
end
fprintf('%d/%d cases behave as designed.\n', sum([R.Pass]), numel(R));
end

% =========================================================================
function r = run_case(name, opts, p, expected, student, imposter)
if nargin < 6, imposter = ''; end
fprintf('\n---- %s ----\n', name);
T = vsd_verify_transaction([], p, opts);
switch expected
    case 'VERIFIED', ok = T.Verified && strcmp(T.Student, student);
    case 'IMPOSTER', ok = strcmp(T.Decision, 'IMPOSTER') && strcmp(T.ImposterSuspect, imposter);
    case 'REFUSED',  ok = ~T.Verified;
    case 'REPLAY',   ok = strcmp(T.Decision, 'REPLAY');
    otherwise, ok = false;
end
imp = '';
if ~isempty(T.ImposterSuspect), imp = ['(likely imposter ' T.ImposterSuspect ')']; end
r = struct('Case', name, 'Decision', T.Decision, 'Student', T.Student, 'Imposter', imp, ...
    'Expected', expected, 'Pass', ok, 'Reason', T.Reason);
fprintf('=> %s %s %s\n', T.Decision, T.Student, imp);
end

function t = last_take(root, sid)
d = dir(fullfile(root, 'ID', sid, '*.wav'));
n = cellfun(@(s) str2double(regexprep(s, '\.wav$', '')), {d.name});
dn = dir(fullfile(root, 'Name', sid, '*.wav'));
m = cellfun(@(s) str2double(regexprep(s, '\.wav$', '')), {dn.name});
t = max(intersect(n(isfinite(n)), m(isfinite(m))));
end

function x = roll_from_digits(M, attacker, victim, c)
%ROLL_FROM_DIGITS The attacker's own voice saying the victim's roll number.
k = find(strcmp(M.Students, attacker), 1);
x = zeros(round(0.3*c.Fs), 1);
for ch = victim
    z = M.Digits{k}{ch - '0' + 1}(:);  z = z / (max(abs(z)) + 1e-9);
    x = [x; z; zeros(round((0.03 + 0.09*rand) * c.Fs), 1)]; %#ok<AGROW>
end
x = [x; zeros(round(0.3*c.Fs), 1)];
end

function y = loudspeaker(x, fs)
%LOUDSPEAKER Phone-speaker replay: 250 Hz-5 kHz band, soft clipping, small room, noise.
if size(x,2) > 1, x = mean(x,2); end
x = x(:) / (max(abs(x)) + 1e-9);
[b, a] = butter(4, [250 min(5000, 0.45*fs)] / (fs/2));
y = filter(b, a, x);
y = tanh(2.5 * y) / tanh(2.5);
h = zeros(round(0.25*fs), 1);  h(1) = 1;
tap = round([0.011 0.023 0.037 0.061 0.089] * fs);  h(tap) = [0.5 0.35 0.25 0.15 0.08];
h = h .* exp(-(0:numel(h)-1)' / (0.08*fs));
y = filter(h, 1, y);
y = 0.5 * y / (max(abs(y)) + 1e-9) + 0.003 * randn(size(y));
end

function delete_if_exists(f)
if exist(f, 'file') == 2, delete(f); end
end
