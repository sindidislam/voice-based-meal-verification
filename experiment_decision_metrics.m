function [metrics,trials] = experiment_decision_metrics(idInfo,nameInfo,users,p,mode)
%EXPERIMENT_DECISION_METRICS Count every attempted claim, including failures.
% False claims use the impostor's OWN spoken ID/name: not targeted same-content
% impersonation. FAR=wrong-claim acceptances/N(N-1), FRR=own-claim rejects/N.
% ID+Name is the retained mode identifier for ID-first fallback. Each claim
% tries ID first, then Name if ID does not verify that claim. A conflicting
% pair can therefore accept two DIFFERENT claims; enumerate both honestly.
% WSAR uses the same false-claim denominator as FAR. ClosedSetWSAR counts
% actual students with at least one false claim accepted, divided by N.
% Top1Accuracy is a ranking diagnostic: raw usable ID BestUser for ID and
% ID+Name, raw usable Name BestUser for Name. It ignores acceptance gates and
% does not switch its ranking to Name when fallback verifies a claim.
% CorrectClaimIdentityErrors is the distinct claim-preservation invariant:
% a correct claimed ID cannot be replaced with a different candidate ID.
users=string(users(:)); n=numel(users); rows=cell(n*n,7); idx=0;
for s=1:n
    for c=1:n
        if mode=="ID+Name"
            decision=speaker_verification_decision(char(users(c)),idInfo{s},nameInfo{s},p);
            accepted=decision.Verified;
        elseif mode=="ID"
            accepted=single_accept(idInfo{s},users(c),p,'id');
        elseif mode=="Name"
            accepted=single_accept(nameInfo{s},users(c),p,'name');
        else
            error('experiment:unknownMode','Unknown evidence mode %s',mode);
        end
        idx=idx+1;
        rows(idx,:)={users(s),users(c),s==c,accepted,string(idInfo{s}.BestUser), ...
            string(nameInfo{s}.BestUser),"own-content claimed-identity trial"};
    end
end
trials=cell2table(rows,'VariableNames',{'ActualStudent','ClaimedStudent','Genuine','Accepted','IDCandidate','NameCandidate','TrialType'});
g=trials.Genuine; accepted=trials.Accepted;
ga=sum(accepted & g); fa=sum(accepted & ~g);
wrongStudents=numel(unique(trials.ActualStudent(accepted & ~g)));
idCandidate=strings(n,1); nameCandidate=strings(n,1);
for s=1:n
    idCandidate(s)=ranked_candidate(idInfo{s}); nameCandidate(s)=ranked_candidate(nameInfo{s});
end
if mode=="ID", candidate=idCandidate;
elseif mode=="Name", candidate=nameCandidate;
else, candidate=idCandidate;
end
metrics=struct('GenuineAttempts',n,'ImpostorAttempts',n*(n-1), ...
    'GenuineAccepted',ga,'FalseAccepted',fa,'GenuineAcceptance',ga/n, ...
    'Top1Accuracy',mean(candidate(:)==users),'FAR',ratio(fa,n*(n-1)), ...
    'FRR',1-ga/n,'WSAR',ratio(fa,n*(n-1)), ...
    'ClosedSetWrongAccepted',wrongStudents,'ClosedSetWSAR',ratio(wrongStudents,n), ...
    'CorrectClaimIdentityErrors',0);
end

function pass=single_accept(info,claim,p,phrase)
% Use the exact production validity, threshold and separation rules. Giving
% the same evidence and gates twice reduces fallback to a single-phrase gate.
threshold=value(p,[phrase 'DtwThreshold'],p.dtwThreshold);
margin=value(p,[phrase 'MarginRatio'],p.dtwMarginRatio);
p.idDtwThreshold=threshold; p.nameDtwThreshold=threshold;
p.idMarginRatio=margin; p.nameMarginRatio=margin;
decision=speaker_verification_decision(char(claim),info,info,p);
pass=decision.Verified;
end

function candidate=ranked_candidate(info)
candidate="";
if isfield(info,'BestUser') && isfield(info,'BestDistance') && ...
        isnumeric(info.BestDistance) && isreal(info.BestDistance) && ...
        isscalar(info.BestDistance) && isfinite(info.BestDistance) && info.BestDistance>=0
    candidate=string(info.BestUser);
end
end

function x=value(s,k,fallback)
x=fallback;
if isfield(s,k) && ~isempty(s.(k)), x=s.(k); end
end

function v=ratio(a,b)
if b==0, v=NaN; else, v=a/b; end
end
