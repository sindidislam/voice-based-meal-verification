function [ok, msg, suspect, info] = vsd_voice_veto(cand, xId, fsId, xName, fsName, c)
%VSD_VOICE_VETO GMM-UBM voice check for a student chosen by the legacy matcher.
%
%   [OK, MSG, SUSPECT] = VSD_VOICE_VETO(CAND, XID, FSID, XNAME, FSNAME, C)
%   scores the raw ID and name recordings with the v4.1.4_claude voice models
%   and refuses CAND when the voice is not his:
%     IMPOSTER  the best voice Y is another enrolled student, V(Y) - V(CAND)
%               >= C.ImpGap and V(Y) >= C.ImpMinVoice  -> SUSPECT = Y
%     VOICE     CAND is not among the C.ClearWin.VoiceRankMax best voices,
%               or V(CAND) < C.ClearWin.MinVoice
%   The legacy v4.1.4 matcher compares only the WORDS (DTW on MFCC) against
%   fixed limits, so a student who says a friend's roll number and name can be
%   accepted.  This veto adds the missing "who is speaking" evidence when the
%   legacy matcher is used (params.vsd.Enable = false).  If the models cannot
%   be loaded the veto is skipped (OK = true) and MSG says why.

if nargin < 6 || isempty(c), c = vsd_config(); end
ok = true;  suspect = '';  info = struct('V', [], 'Rank', NaN);
msg = 'Voice check (GMM-UBM) skipped: no recording available.';
if isempty(xId) || isempty(xName), return; end
try
    M = vsd_models(c);
    Uid = vsd_frontend(xId, fsId, c);
    Unm = vsd_frontend(xName, fsName, c);
    S = vsd_score_query(M, Uid, Unm, c);
    k = find(strcmp(S.Students, cand), 1);
    if isempty(k)
        msg = sprintf('Voice check skipped: %s has no voice model yet.', cand);
        return;
    end
    V = S.V;
    [~, vo] = sort(V, 'descend');
    vr = find(vo == k, 1);  Y = vo(1);
    info.V = V;  info.Rank = vr;
    rankMax = 3;  minV = -0.10;
    if isfield(c, 'ClearWin'), rankMax = c.ClearWin.VoiceRankMax;  minV = c.ClearWin.MinVoice; end
    if Y ~= k && V(Y) - V(k) >= c.ImpGap && V(Y) >= c.ImpMinVoice
        ok = false;  suspect = S.Students{Y};
        msg = sprintf(['IMPOSTER: the words matched %s but the VOICE belongs to enrolled student %s ' ...
            '(voice score %.2f vs %.2f). Access refused.'], cand, suspect, V(Y), V(k));
    elseif vr > rankMax || V(k) < minV
        ok = false;
        msg = sprintf(['Voice check failed: the voice is not %s''s (voice rank %d of %d, score %.2f). ' ...
            'Access refused; the student must speak himself.'], cand, vr, numel(V), V(k));
    else
        msg = sprintf('Voice check passed: %s is voice rank %d (score %.2f).', cand, vr, V(k));
    end
catch err
    msg = ['Voice check (GMM-UBM) unavailable: ' err.message];
end
end
