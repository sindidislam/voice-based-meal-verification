function C = vsd_calibrate_challenge_voice(nCodes)
%VSD_CALIBRATE_CHALLENGE_VOICE Measure the voice check of the digit challenge.
%
%   C = VSD_CALIBRATE_CHALLENGE_VOICE() builds challenge answers from every
%   student's connected counting recording (Digits/<id>/<id>_digits_01.wav):
%     genuine  - student s answers codes as himself
%     attacker - student a answers codes while the claim is student s
%   and records, for the claimed student, the voice score gap
%       gap = max_j V(j) - V(s)
%   (0 when the claimed student is the best voice).  It also records the
%   DTW distance of every genuine answer to the claimed student's templates,
%   which calibrates the splice-attack floor (C.Challenge.MinDist).
%   Output: Results/claude_eval/challenge_voice_calibration.csv

if nargin < 1, nCodes = 3; end
if exist('OCTAVE_VERSION','builtin'), try, pkg load signal; catch, end, end
c = vsd_config();  M = vsd_models(c);  rng(11);
N = numel(M.Students);  root = c.DataRoot;
rows = zeros(0, 5);   % claimed, speaker, genuine?, gap, Dreq
seg = cell(1, N);
for s = 1:N
    try
        x = test_vsd_engine_answer(root, M.Students{s}, 0:9, M, c);   %#ok<NASGU>
        seg{s} = true;
    catch
        seg{s} = false;
    end
end
ok = find(cellfun(@(v) isequal(v, true), seg) & cellfun(@(D) all(~cellfun(@isempty, D)), M.Digits));
fprintf('%d students with a segmentable counting recording and isolated digits\n', numel(ok));
for s = ok
    for r = 1:nCodes
        code = randi([0 9], 1, 3);
        [g, d] = one(M, c, root, s, s, code);  rows(end+1,:) = [s s 1 g d]; %#ok<AGROW>
        a = ok(randi(numel(ok)));  while a == s, a = ok(randi(numel(ok))); end
        [g, d] = one(M, c, root, s, a, code);  rows(end+1,:) = [s a 0 g d]; %#ok<AGROW>
    end
    fprintf('.');
end
fprintf('\n');
G = rows(rows(:,3)==1, :);  A = rows(rows(:,3)==0, :);
fprintf('genuine gap percentiles 50/80/90/95: %s\n', mat2str(prctile(G(:,4), [50 80 90 95]), 3));
fprintf('attacker gap percentiles 5/10/20/50: %s\n', mat2str(prctile(A(:,4), [5 10 20 50]), 3));
fprintf('genuine Dreq min / 5th pct: %.2f / %.2f   attacker (content ok) Dreq median %.2f\n', min(G(:,5)), prctile(G(:,5),5), median(A(:,5)));
for gmax = [0.2 0.4 0.6 0.8 1.0]
    fprintf('rule gap < %.1f : genuine pass %.3f  attacker pass %.3f\n', gmax, mean(G(:,4) < gmax), mean(A(:,4) < gmax));
end
out = fullfile(fileparts(mfilename('fullpath')), 'Results', 'claude_eval', 'challenge_voice_calibration.csv');
if exist(fileparts(out),'dir') ~= 7, mkdir(fileparts(out)); end
fid = fopen(out, 'w'); fprintf(fid, 'claimed,speaker,genuine,voice_gap,D_requested\n');
for k = 1:size(rows,1)
    fprintf(fid, '%s,%s,%d,%.4f,%.4f\n', M.Students{rows(k,1)}, M.Students{rows(k,2)}, rows(k,3), rows(k,4), rows(k,5));
end
fclose(fid);
C = struct('rows', rows, 'students', {M.Students});
end

function [gap, dreq] = one(M, c, root, s, a, code)
x = test_vsd_engine_answer(root, M.Students{a}, code, M, c);
U = vsd_frontend(x, c.Fs, c);
L = vsd_gmm('llr', U.Speaker, M.Speaker, M.UBM);
V = zeros(size(L));
for j = 1:numel(L)
    o = L([1:j-1, j+1:end]);  o = sort(o(isfinite(o)), 'descend');
    V(j) = L(j) - mean(o(1:min(c.CohortSize, numel(o))));
end
gap = max(V) - V(s);
[~, info] = vsd_challenge('verify', U, code, M, s, c);
dreq = info.Dreq;
end
