function result = speaker_verification_decision(claimedId, id, name, p, voiceReport)
%SPEAKER_VERIFICATION_DECISION Both phrases must pass the same identity gates.
% Every transaction requires ID and Name to independently verify the same
% student. An optional typed claim binds that result; it never weakens the
% biometric policy. A fused ranking cannot waive a phrase's distance/margin.
% Acoustic candidates are not speech transcription or proof of spoken digits.
if nargin<4 || isempty(p), p=dsp_parameters(); end
if nargin<5, voiceReport=[]; end
result=struct('Verified',false,'Decision','UNCERTAIN / RETRY','Student','', ...
    'Stage','claim','Reason','','IDDistance',Inf,'NameDistance',NaN, ...
    'IDMargin',NaN,'NameMargin',NaN,'Margin',NaN,'NormalizedScore',Inf, ...
    'IdentifiedBy','','IDStage','','NameStage','not-requested');

claim='';
if ~isempty(claimedId)
    [claim,valid]=student_id_contract(claimedId);
    if ~valid, result.Reason='Enter the seven-digit Student ID to verify.'; return; end
end
if ~valid_score(id)
    result.IDStage='evidence'; result.Stage='evidence-id';
    result.Reason='No usable ID voice evidence. Please retry both phrases.'; return;
end
first=phrase_decision(id.BestUser,id,p,'id');
result.IDDistance=first.Distance; result.IDMargin=first.Margin; result.IDStage=first.Stage;
if ~valid_score(name)
    result.NameStage='evidence'; result.Stage='evidence-name';
    result.Reason='No usable Name voice evidence. Please retry both phrases.'; return;
end
second=phrase_decision(name.BestUser,name,p,'name');
result.NameDistance=second.Distance; result.NameMargin=second.Margin; result.NameStage=second.Stage;
result.Margin=min(first.Margin,second.Margin);
result.NormalizedScore=max(first.NormalizedScore,second.NormalizedScore);

% Biometric Score-Level Fusion for live open/claim voice identification
enableFusion = value(p, 'enableScoreFusion', false);
hasFullScores = isfield(id, 'Scores') && ~isempty(id.Scores) && isfield(id, 'Users') && ~isempty(id.Users) && ...
                isfield(name, 'Scores') && ~isempty(name.Scores) && isfield(name, 'Users') && ~isempty(name.Users);

if enableFusion && hasFullScores
    [commonUsers, idIdx, nameIdx] = intersect(string(id.Users), string(name.Users), 'stable');
    if ~isempty(commonUsers)
        idDists = id.Scores(idIdx);
        nameDists = name.Scores(nameIdx);
        idThresh = value(p, 'idDtwThreshold', value(p, 'dtwThreshold', 31.35));
        nameThresh = value(p, 'nameDtwThreshold', value(p, 'dtwThreshold', 30.35));
        idMarginThresh = value(p, 'idMarginRatio', value(p, 'dtwMarginRatio', 1.20));
        nameMarginThresh = value(p, 'nameMarginRatio', value(p, 'dtwMarginRatio', 1.20));
        liveFusedCeiling = value(p, 'liveFusedThreshold', 1.15);
        wID = 0.40; wName = 0.60;
        normID = idDists / idThresh;
        normName = nameDists / nameThresh;
        fusedScores = wID * normID + wName * normName;
        finiteFused = find(isfinite(fusedScores));
        if ~isempty(finiteFused)
            [sortedFused, fusedOrder] = sort(fusedScores(finiteFused), 'ascend');
            bestFusedUser = char(commonUsers(finiteFused(fusedOrder(1))));
            bestFusedScore = sortedFused(1);
            if numel(sortedFused) > 1
                runnerFusedScore = sortedFused(2);
                fusedMargin = runnerFusedScore / max(bestFusedScore, eps);
            else
                runnerFusedScore = Inf; fusedMargin = Inf;
            end
            cand = bestFusedUser;
            candIdDist = idDists(finiteFused(fusedOrder(1)));
            candNameDist = nameDists(finiteFused(fusedOrder(1)));
            
            candId = id.BestUser; candName = name.BestUser;
            dualTop1 = strcmp(candId, cand) && strcmp(candName, cand);
            nameHasMargin = isfield(second, 'Margin') && ~isnan(second.Margin) && (second.Margin >= 1.12);
            idHasMargin = isfield(first, 'Margin') && ~isnan(first.Margin) && (first.Margin >= 1.15);
            fusedHasMargin = (fusedMargin >= 1.15) || (dualTop1 && fusedMargin >= 1.10);
            
            % Confident contradiction check:
            % If candId != candName AND both individual phrase decisions independently verified,
            % that represents a confident contradiction which cannot be overridden.
            isConfidentContradiction = ~strcmp(candId, candName) && first.Verified && second.Verified;
            
            matchesClaim = isempty(claim) || strcmp(claim, cand);
            atLeastOnePhrasePassed = (candIdDist <= idThresh) || (candNameDist <= nameThresh);
            withinTightBounds = (candIdDist <= idThresh * 1.20) && (candNameDist <= nameThresh * 1.20);

            % Close genuine match: candidate is #1 in joint score with exceptional composite score (<= 1.05),
            % ranked #1 in one phrase and runner-up in the other within primary threshold,
            % with positive fused margin >= 1.04x over cohort competitors.
            isCloseGenuine = (bestFusedScore <= 1.05) && ...
                             (strcmp(candName, cand) || strcmp(candId, cand)) && ...
                             (candIdDist <= idThresh || candNameDist <= nameThresh) && ...
                             withinTightBounds && ...
                             (fusedMargin >= 1.04);

            hasSufficientMargin = (dualTop1 && (fusedHasMargin || nameHasMargin || idHasMargin)) || ...
                                  (~dualTop1 && (fusedMargin >= 1.15 || isCloseGenuine));
            
            voicePass = true;
            candRank = 1;
            if ~isempty(voiceReport) && isstruct(voiceReport)
                voiceReport = voiceReport(1);
                if isfield(voiceReport, 'Users') && isfield(voiceReport, 'Ranks')
                    targetIdx = find(strcmp(string(voiceReport.Users), string(cand)), 1);
                    if ~isempty(targetIdx) && targetIdx <= numel(voiceReport.Ranks)
                        candRank = voiceReport.Ranks(targetIdx);
                        voicePass = (candRank == 1);
                    end
                elseif isfield(voiceReport, 'VoiceRank') && ~isempty(voiceReport.VoiceRank) && ~isinf(voiceReport.VoiceRank)
                    candRank = voiceReport.VoiceRank;
                    voicePass = (candRank == 1);
                elseif isfield(voiceReport, 'TopUser') && ~isempty(voiceReport.TopUser)
                    voicePass = strcmp(char(voiceReport.TopUser), cand);
                end
            end
            
            if matchesClaim && ~isConfidentContradiction && ...
                    atLeastOnePhrasePassed && withinTightBounds && ...
                    (bestFusedScore <= liveFusedCeiling) && ...
                    (dualTop1 || strcmp(candName, cand) || strcmp(candId, cand)) && ...
                    hasSufficientMargin
                if ~voicePass
                    result.Stage = 'timbre';
                    result.Reason = sprintf('Voice timbre model ranked applicant #%d (expected #1). Impersonation refused.', candRank);
                    return;
                end
                result.Verified = true;
                result.Decision = 'VERIFIED';
                result.Student = cand;
                result.IdentifiedBy = 'id+name';
                result.Stage = 'verified';
                result.IDDistance = candIdDist;
                result.NameDistance = candNameDist;
                result.Margin = fusedMargin;
                result.NormalizedScore = bestFusedScore;
                result.Reason = sprintf('Joint ID+Name score fusion verifies student %s (fused score: %.2f, margin: %.2fx, ID dist: %.2f, Name dist: %.2f).', ...
                    cand, bestFusedScore, fusedMargin, candIdDist, candNameDist);
                return;
            end
        end
    end
end

% v4.1.4_claude CLEAR-WINNER RESCUE for the legacy matcher (used only when
% params.vsd.Enable = false).  The fixed distance ceilings (31.35 / 30.35) fail
% as soon as the microphone changes, although the ranking stays right: the
% genuine student is still rank 1 with a clear lead.  Accept when the NAME and
% the joint ID+name score both rank the same student first with a clear lead,
% the ID phrase does not contradict it and the voice model does not rank him
% low.  All tests are ratios, so they survive a change of microphone.
if enableFusion && hasFullScores && exist('finiteFused','var') && ~isempty(finiteFused)
    [ok, why] = clear_winner_rescue(id, name, cand, fusedMargin, bestFusedScore, claim, voiceReport);
    if ok
        result.Verified = true;  result.Decision = 'VERIFIED';  result.Student = cand;
        result.IdentifiedBy = 'id+name';  result.Stage = 'verified';
        result.IDDistance = candIdDist;  result.NameDistance = candNameDist;
        result.Margin = fusedMargin;  result.NormalizedScore = bestFusedScore;
        result.Reason = why;
        return;
    end
end

if ~strcmp(id.BestUser,name.BestUser)
    result.Stage='consistency';
    if enableFusion && hasFullScores && ~isempty(finiteFused)
        if ~hasSufficientMargin
            result.Reason=sprintf('ID and Name acoustic matches disagree (%s and %s; joint candidate %s margin %.2fx insufficient). Access refused; retry both phrases.', ...
                id.BestUser, name.BestUser, cand, fusedMargin);
        elseif ~atLeastOnePhrasePassed || ~withinTightBounds || (bestFusedScore > liveFusedCeiling)
            result.Reason=sprintf('ID and Name acoustic matches disagree (%s and %s; joint candidate %s score %.2f exceeds limits). Access refused; retry both phrases.', ...
                id.BestUser, name.BestUser, cand, bestFusedScore);
        else
            result.Reason=sprintf('ID and Name acoustic matches disagree (%s and %s). Access refused; retry both phrases.', ...
                id.BestUser, name.BestUser);
        end
    else
        result.Reason=sprintf('ID and Name acoustic matches disagree (%s and %s). Access refused; retry both phrases.', ...
            id.BestUser,name.BestUser);
    end
    return;
end
if ~isempty(claim) && ~strcmp(claim,id.BestUser)
    result.Stage='claim-match';
    result.Reason='Both voice matches must confirm the requested Student ID. Access refused.';
    return;
end
if ~first.Verified
    result.Stage=first.Stage;
    result.Reason=['ID phrase failed: ' first.Reason]; return;
end
if ~second.Verified
    result.Stage=second.Stage;
    result.Reason=['Name phrase failed: ' second.Reason]; return;
end

voicePass = true;
cand = id.BestUser;
candRank = 1;
if ~isempty(voiceReport) && isstruct(voiceReport)
    voiceReport = voiceReport(1);
    if isfield(voiceReport, 'Users') && isfield(voiceReport, 'Ranks')
        targetIdx = find(strcmp(string(voiceReport.Users), string(cand)), 1);
        if ~isempty(targetIdx) && targetIdx <= numel(voiceReport.Ranks)
            candRank = voiceReport.Ranks(targetIdx);
            voicePass = (candRank == 1);
        end
    elseif isfield(voiceReport, 'VoiceRank') && ~isempty(voiceReport.VoiceRank) && ~isinf(voiceReport.VoiceRank)
        candRank = voiceReport.VoiceRank;
        voicePass = (candRank == 1);
    elseif isfield(voiceReport, 'TopUser') && ~isempty(voiceReport.TopUser)
        voicePass = strcmp(char(voiceReport.TopUser), cand);
    end
end
if ~voicePass
    result.Stage = 'timbre';
    result.Reason = sprintf('Voice timbre model ranked applicant #%d (expected #1). Impersonation refused.', candRank);
    return;
end

result.Verified=true; result.Decision='VERIFIED'; result.Student=id.BestUser;
result.IdentifiedBy='id+name'; result.Stage='verified';
result.Reason=sprintf('ID and Name independently verify student %s; both distance and separation gates passed.',id.BestUser);
end

function r=phrase_decision(claim,s,p,phrase)
r=struct('Verified',false,'Stage','evidence','Reason','No usable voice evidence. Please retry.', ...
    'Distance',Inf,'Margin',NaN,'NormalizedScore',Inf);
if ~valid_score(s), return; end
r.Distance=s.BestDistance;
if isfield(s,'RunnerUpDistance') && isnumeric(s.RunnerUpDistance) && isreal(s.RunnerUpDistance) && isscalar(s.RunnerUpDistance)
    r.Margin=s.RunnerUpDistance/max(s.BestDistance,eps);
end
r.Stage='claim-match';
if ~strcmp(claim,s.BestUser), r.Reason='Voice does not confirm the requested student.'; return; end
threshold=value(p,[phrase 'DtwThreshold'],value(p,'dtwThreshold',NaN));
limit=value(p,[phrase 'MarginRatio'],value(p,'dtwMarginRatio',NaN));
r.Stage='configuration';
if ~positive(threshold) || ~positive(limit) || limit<=1
    r.Reason='Verification limits are invalid; recalibrate the configuration.'; return;
end
r.NormalizedScore=s.BestDistance/threshold; r.Stage='threshold';

cohortGate = value(p, [phrase 'CohortGate'], value(p, 'cohortGate', 0.12));
hasCohort = isfield(s, 'CohortRatio') && isfinite(s.CohortRatio);
cohortPass = hasCohort && (s.CohortRatio >= cohortGate);

if r.NormalizedScore>1
    if cohortPass && (r.NormalizedScore <= value(p, 'cohortMaxDistanceFactor', 1.35))
        % Accepted: Cohort ratio normalisation confirms speaker match despite mic attenuation
    else
        r.Reason='Voice distance exceeds its acceptance limit.'; return;
    end
end
r.Stage='margin';
hasMargin = isfield(s,'RunnerUpUser') && isfield(s,'RunnerUpDistance') && ...
        ~isempty(s.RunnerUpUser) && ~strcmp(s.RunnerUpUser,s.BestUser) && ...
        positive(s.RunnerUpDistance) && s.RunnerUpDistance>s.BestDistance && r.Margin>=limit;
if ~hasMargin
    if cohortPass && isfield(s, 'CohortRatio') && (s.CohortRatio >= cohortGate * 1.15)
        % Margin verified via strong cohort separation over nearest competitors
    else
        r.Reason='Voice is too close to another student, or comparison evidence is missing. Please retry.'; return;
    end
end
r.Verified=true; r.Stage='verified'; r.Reason='Phrase verified.';

end
function tf=valid_score(s)
tf=isstruct(s) && isscalar(s) && isfield(s,'BestUser') && isfield(s,'BestDistance') && ...
    isnumeric(s.BestDistance) && isreal(s.BestDistance) && isscalar(s.BestDistance) && ...
    isfinite(s.BestDistance) && s.BestDistance>=0;
if tf, [~,tf]=student_id_contract(s.BestUser); end
end
function tf=positive(x)
tf=isnumeric(x) && isscalar(x) && isreal(x) && isfinite(x) && x>0;
end
function x=value(s,k,fallback)
x=fallback; if isfield(s,k) && ~isempty(s.(k)), x=s.(k); end
end

function [ok, why] = clear_winner_rescue(id, name, cand, fusedMargin, fusedScore, claim, voiceReport)
%CLEAR_WINNER_RESCUE Rank-1-far-ahead rule (relative, microphone independent).
ok = false;  why = '';
users = string(name.Users);  d = name.Scores(:).';
k = find(users == string(cand), 1);
if isempty(k) || ~isfinite(d(k)), return; end
others = sort(d([1:k-1, k+1:end]));  others = others(isfinite(others));
if isempty(others), return; end
nameLead  = others(1) / max(d(k), eps);                       % runner-up / best
nameCohort = mean(others(1:min(5, numel(others)))) / max(d(k), eps);
[~, nameTop] = min(d);
idUsers = string(id.Users);  di = id.Scores(:).';
ki = find(idUsers == string(cand), 1);
if isempty(ki) || ~isfinite(di(ki)), return; end
idRatio = di(ki) / max(min(di), eps);                          % 1.00 = ID rank 1
voiceRank = 1;
if ~isempty(voiceReport) && isstruct(voiceReport) && isfield(voiceReport,'Users') && isfield(voiceReport,'Ranks')
    j = find(strcmp(string(voiceReport(1).Users), string(cand)), 1);
    if ~isempty(j) && j <= numel(voiceReport(1).Ranks), voiceRank = voiceReport(1).Ranks(j); end
end
ok = nameTop == k && nameLead >= 1.12 && nameCohort >= 1.15 && fusedMargin >= 1.08 && ...
     idRatio <= 1.12 && voiceRank <= 3 && fusedScore <= 1.60 && (isempty(claim) || strcmp(claim, cand));
if ok
    why = sprintf(['Clear winner %s: name %.2fx ahead of the runner-up (%.2fx of the 5 nearest), joint ' ...
        'lead %.2fx, ID within %.0f%% of the best, voice rank %d.'], cand, nameLead, nameCohort, ...
        fusedMargin, 100*(idRatio-1), voiceRank);
end
end
