function n = vsd_adapt(sid, xid, fsid, xname, fsname, c)
%VSD_ADAPT Store a high-confidence live ID + name take as an adaptive template.
%
%   N = VSD_ADAPT(SID, XID, FSID, XNAME, FSNAME, C) is called by
%   VSD_VERIFY_TRANSACTION only after a transaction was VERIFIED with a large
%   safety margin (name score >= C.Adapt.MinPname, voice score >=
%   C.Adapt.MinVoice) AND the random-digit challenge was passed.  The two
%   recordings are written to
%       DataRoot/ID/<sid>/Adaptive/live_<timestamp>.wav
%       DataRoot/Name/<sid>/Adaptive/live_<timestamp>.wav
%   so that the next model update enrols the student's voice as heard through
%   the CURRENT counter microphone.  At most C.Adapt.MaxPerPhrase adaptive
%   takes are kept per phrase; older ones are moved to Adaptive/archive (never
%   deleted, so the admin can audit them).  N is the number of adaptive takes
%   now kept per phrase.
%
%   Why: a new microphone changes the channel H(w).  CMVN removes the mean of
%   log|H(w)| but not every non-linear effect; one or two genuine takes from
%   the new microphone close the remaining gap (measured: cross-microphone
%   genuine acceptance rises when a single same-mic take is enrolled).
%   Safety: adaptation requires a fresh challenge pass, so a replayed or
%   imposter recording cannot poison the profile.

n = 0;
if nargin < 6 || isempty(c), c = vsd_config(); end
if isempty(sid) || isempty(xid) || isempty(xname), return; end
stamp = datestr(now, 'yyyymmdd_HHMMSS');
pairs = {'ID', xid, fsid; 'Name', xname, fsname};
for k = 1:size(pairs,1)
    folder = fullfile(c.DataRoot, pairs{k,1}, sid, c.AdaptiveDir);
    if exist(folder,'dir') ~= 7, mkdir(folder); end
    x = pairs{k,2};  fs = pairs{k,3};
    if size(x,2) > 1, x = mean(x,2); end
    x = x(:) / max(1, max(abs(x)));             % never clip when writing
    audiowrite(fullfile(folder, sprintf('live_%s.wav', stamp)), x, fs, 'BitsPerSample', 16);
    w = dir(fullfile(folder, '*.wav'));
    [~, o] = sort([w.datenum], 'descend');
    w = w(o);
    if numel(w) > c.Adapt.MaxPerPhrase
        arch = fullfile(folder, 'archive');
        if exist(arch,'dir') ~= 7, mkdir(arch); end
        for j = c.Adapt.MaxPerPhrase+1:numel(w)
            movefile(fullfile(folder, w(j).name), fullfile(arch, w(j).name));
        end
    end
    n = min(numel(w), c.Adapt.MaxPerPhrase);
end
% flag the model as stale: the next transaction (or the admin button) updates
% only the two new files and the student's voice model
fid = fopen([c.ModelFile '.dirty'], 'w');
if fid > 0, fprintf(fid, '%s %s\n', sid, stamp); fclose(fid); end
end
