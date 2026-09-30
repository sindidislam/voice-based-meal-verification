function R = vsd_decide(S, c, claimedId, M)
%VSD_DECIDE Fused identity decision, imposter identification and explanation.
%
%   R = VSD_DECIDE(S, C) turns the scores of VSD_SCORE_QUERY into a decision.
%   R = VSD_DECIDE(S, C, CLAIMEDID) binds the decision to a typed Student ID.
%
%   Two independent kinds of evidence:
%     WHAT was said  -> phrase scores P_id, P_name (text dependent, DTW)
%     WHO is speaking -> voice score V (text independent, GMM-UBM)
%
%   1. Candidate  c = argmax  F = 0.5 P_id + 1.0 P_name + 0.25 V
%   2. Gates for c (all must pass)
%        G1 quality   both phrases contain speech
%        G2 phrase    P_name(c) >= 0.07  and  P_id(c) >= -0.10
%        G3 voice     V(c) >= 0  and  c is the best-matching voice (rank 1)
%        G4 imposter  the phrases' claim X and the best voice Y agree
%      ...or the CLEAR-WINNER rule: P_name(c) >= 0.12, fused lead >= 0.08,
%      voice rank <= 3 and V(c) >= -0.10 (rank 1 far ahead of rank 2).
%   3. Imposter identification: if the phrases point to X but the voice of a
%      different enrolled student Y beats X by >= 0.15 (and V(Y) >= 0.20), the
%      attempt is refused as an IMPOSTER and Y is reported as the likely
%      person speaking.  If no enrolled voice or name matches, the speaker is
%      reported as UNKNOWN (not enrolled).
%
%   R fields: Decision ('VERIFIED','IMPOSTER','UNKNOWN','RETRY'), Verified,
%   Student, ClaimedByPhrase, ImposterSuspect, ImposterName, Pid, Pname, V,
%   VoiceRank, F, FMargin, Gates (struct of logicals), Stage, Reason.

if nargin < 2 || isempty(c), c = vsd_config(); end
if nargin < 3, claimedId = ''; end
if nargin < 4, M = []; end
st = S.Students;  N = numel(st);
R = struct('Decision','RETRY','Verified',false,'Student','','ClaimedByPhrase','', ...
    'ImposterSuspect','','ImposterName','','ImposterVoiceGap',NaN,'Pid',NaN,'Pname',NaN,'V',NaN, ...
    'VoiceRank',NaN,'F',NaN,'FMargin',NaN,'Stage','quality','Reason','', ...
    'Gates',struct('Quality',false,'Phrase',false,'Voice',false,'Imposter',false), ...
    'VoiceTop','','VoiceTopV',NaN,'Top3',{{}},'Rule','');
if N == 0
    R.Stage = 'enrollment'; R.Reason = 'No students are enrolled.'; return;
end
if ~S.HasName || ~S.HasID
    R.Stage = 'quality'; R.Reason = 'No usable speech in one of the recordings. Speak clearly after the beep and retry.';
    return;
end
R.Gates.Quality = true;
Pid = S.Pid;  Pn = S.Pname;  V = S.V;
F = c.WeightID * Pid + c.WeightName * Pn + c.Lambda * V;
[Fs, order] = sort(F, 'descend');
cidx = order(1);
claimIdx = [];
if ~isempty(claimedId)
    claimIdx = find(strcmp(st, claimedId), 1);
    if isempty(claimIdx)
        R.Stage = 'claim'; R.Reason = sprintf('Student %s is not enrolled.', claimedId); return;
    end
    cidx = claimIdx;
end
[~, vorder] = sort(V, 'descend');
vrank = find(vorder == cidx, 1);
R.Student = st{cidx};  R.Pid = Pid(cidx);  R.Pname = Pn(cidx);  R.V = V(cidx);
R.VoiceRank = vrank;  R.F = F(cidx);
others = F;  others(cidx) = -Inf;  R.FMargin = F(cidx) - max(others);
R.VoiceTop = st{vorder(1)};  R.VoiceTopV = V(vorder(1));
R.Top3 = st(order(1:min(3,N)));
% what the phrases claim (content only)
[~, X] = max(Pid + Pn);
if ~isempty(claimIdx), X = claimIdx; end
R.ClaimedByPhrase = st{X};
Y = vorder(1);
R.Gates.Phrase = (Pn(cidx) >= c.MinPname) && (Pid(cidx) >= c.MinPid);
R.Gates.Voice  = (V(cidx) >= c.MinVoice) && (vrank <= c.VoiceRankMax);
isImp = (Y ~= X) && (V(Y) - V(X) >= c.ImpGap) && (V(Y) >= c.ImpMinVoice);
R.Gates.Imposter = ~isImp;
if isImp
    R.Decision = 'IMPOSTER';  R.Stage = 'imposter';
    R.ImposterSuspect = st{Y};  R.ImposterVoiceGap = V(Y) - V(X);
    R.ImposterName = st{Y};
    if ~isempty(M) && isfield(M,'Names'), R.ImposterName = M.Names{Y}; end
    R.Student = st{X};
    R.Reason = sprintf(['IMPOSTER ALERT: the spoken ID/name claim student %s, but the VOICE ' ...
        'belongs to enrolled student %s (voice score %.2f vs %.2f). Access refused.'], ...
        st{X}, st{Y}, V(Y), V(X));
    return;
end
cw = isfield(c,'ClearWin') && c.ClearWin.Enable;
if cw
    cw = Pn(cidx) >= c.ClearWin.MinPname && R.FMargin >= c.ClearWin.MinFMargin && ...
         vrank <= c.ClearWin.VoiceRankMax && V(cidx) >= c.ClearWin.MinVoice && Pid(cidx) >= c.MinPid;
end
if ~(R.Gates.Phrase && R.Gates.Voice) && cw
    R.Decision = 'VERIFIED';  R.Verified = true;  R.Stage = 'verified';  R.Rule = 'clear-winner';
    R.Gates.Phrase = true;  R.Gates.Voice = true;
    R.Reason = sprintf(['Student %s verified (clear winner): name phrase %.2f is %.2fx closer than the ' ...
        'nearest rivals, fused lead %.2f over rank 2, voice rank %d (%.2f).'], st{cidx}, Pn(cidx), ...
        exp(Pn(cidx)), R.FMargin, vrank, V(cidx));
    return;
end
if R.Gates.Phrase && R.Gates.Voice
    R.Decision = 'VERIFIED';  R.Verified = true;  R.Stage = 'verified';  R.Rule = 'standard';
    R.Reason = sprintf(['Student %s verified: name phrase %.2f (>= %.2f), ID phrase %.2f, ' ...
        'voice %.2f (rank %d), fused margin %.2f.'], st{cidx}, Pn(cidx), c.MinPname, Pid(cidx), ...
        V(cidx), vrank, R.FMargin);
    return;
end
if max(V) < c.MinVoice && max(Pn) < c.MinPname
    R.Decision = 'UNKNOWN';  R.Stage = 'unknown';
    R.Reason = ['Neither the voice nor the spoken name matches any enrolled student. ' ...
        'The speaker appears to be NOT ENROLLED. Access refused.'];
    return;
end
R.Decision = 'RETRY';
if ~R.Gates.Phrase
    R.Stage = 'phrase';
    R.Reason = sprintf(['The spoken name/ID do not single out one student clearly (name %.2f, ' ...
        'need %.2f). Please say your full name and roll number clearly and retry.'], Pn(cidx), c.MinPname);
else
    R.Stage = 'voice';
    R.Reason = sprintf(['The phrases match %s but the voice evidence is weak (voice %.2f, rank %d). ' ...
        'Retry closer to the microphone; if it persists ask the admin to add a take on this microphone.'], ...
        st{cidx}, V(cidx), vrank);
end
end
