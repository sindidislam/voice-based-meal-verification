function result=experiment_legacy_policy(idInfo,nameInfo,p)
%EXPERIMENT_LEGACY_POLICY Preserved v4.1.4 biometric policy, not meal access.
% Source: original verify_meal_workflow.m lines 153-192 and 303-317.
% Reproduces single successful attempt, with all GUI/coupon/log side effects absent.
result=struct('Accepted',false,'Student',"",'UsedPhrase',"Name");
[hasId,runnerId,inId]=evidence(idInfo,p.dtwThreshold);
if hasId && (~runnerId || ~inId || idInfo.Margin>=p.dtwMarginRatio)
    result.Accepted=true; result.Student=string(idInfo.BestUser); result.UsedPhrase="ID"; return;
end
ambiguous=strings(0,1);
if hasId && inId && idInfo.Margin<p.dtwMarginRatio
    ambiguous=[string(idInfo.BestUser);string(idInfo.RunnerUpUser)];
end
[hasName,runnerName,inName]=evidence(nameInfo,p.dtwThreshold);
confirmed=any(string(nameInfo.BestUser)==ambiguous);
if hasName && (confirmed || ~runnerName || ~inName || nameInfo.Margin>=p.dtwMarginRatio)
    result.Accepted=true; result.Student=string(nameInfo.BestUser);
end
end

function [has,runner,in]=evidence(info,threshold)
has=~isempty(info.BestUser) && isfinite(info.BestDistance) && info.BestDistance<=threshold;
runner=isfield(info,'RunnerUpUser') && ~isempty(info.RunnerUpUser) && ...
    isfield(info,'RunnerUpDistance') && isfinite(info.RunnerUpDistance);
in=runner && info.RunnerUpDistance<=threshold;
end
