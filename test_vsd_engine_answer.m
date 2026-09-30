function x = test_vsd_engine_answer(root, sid, code, M, c)
%TEST_VSD_ENGINE_ANSWER Live-like challenge answer for offline tests.
%   Digits of CODE are cut from the student's connected counting recording
%   Train/Digits/<id>/<id>_digits_01.wav (a different recording from the
%   isolated digit templates the challenge is checked against) and joined
%   with random 30-120 ms pauses and loudness.
f = fullfile(root, 'Digits', sid, sprintf('%s_digits_01.wav', sid));
[y, fs] = audioread(f);
if size(y,2) > 1, y = mean(y,2); end
U = vsd_frontend(y, fs, c);  y8 = U.Audio8k;  sp = U.Speech(:)';
segs = zeros(0,2);  s = [];  gap = 0;  e = 0;
for t = 1:numel(sp)
    if sp(t)
        if isempty(s), s = t; end
        gap = 0;  e = t;
    elseif ~isempty(s)
        gap = gap + 1;
        if gap > 12, segs(end+1,:) = [s e]; s = []; gap = 0; end %#ok<AGROW>
    end
end
if ~isempty(s), segs(end+1,:) = [s e]; end
segs = segs(segs(:,2) - segs(:,1) >= 8, :);
H = round(c.HopMs * 1e-3 * c.Fs);
cut = @(a, b) y8(max(1,(a-1)*H-240+1):min(numel(y8),(b+1)*H+240));
k = find(strcmp(M.Students, sid), 1);
if size(segs,1) ~= 10 || isempty(k)
    error('test_vsd_engine_answer:segments', ...
        'The counting recording of %s does not split into 10 digits (%d segments).', sid, size(segs,1));
else
    order = 0:9;
    alt = [1:9 0];
    dA = 0; dB = 0;
    for j = 1:10
        q = vsd_frontend(cut(segs(j,1), segs(j,2)), c.Fs, c);
        tA = vsd_frontend(M.Digits{k}{order(j)+1}, c.Fs, c);  tB = vsd_frontend(M.Digits{k}{alt(j)+1}, c.Fs, c);
        dA = dA + vsd_dtw(q.Content, tA.Content, c.DtwBand);  dB = dB + vsd_dtw(q.Content, tB.Content, c.DtwBand);
    end
    if dB < dA, order = alt; end
    parts = cell(1, numel(code));
    for j = 1:numel(code)
        i = find(order == code(j), 1);
        parts{j} = cut(segs(i,1), segs(i,2));
    end
end
x = zeros(round(0.3*c.Fs), 1);
for j = 1:numel(parts)
    z = parts{j}(:);  z = z / (max(abs(z)) + 1e-9) * (0.6 + 0.4*rand);
    x = [x; z; zeros(round((0.03 + 0.09*rand) * c.Fs), 1)]; %#ok<AGROW>
end
x = [x; zeros(round(0.3*c.Fs), 1)];
end
