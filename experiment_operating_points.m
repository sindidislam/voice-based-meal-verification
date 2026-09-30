function [p,curve,selection] = experiment_operating_points(idInfo,nameInfo,users,p)
%EXPERIMENT_OPERATING_POINTS Select per-phrase gates on DEVELOPMENT only.
% Lexicographic objective: false accepts, genuine rejects, smaller threshold,
% larger observed margin. Candidates are measured distances/margins, not an
% asserted optimal setting. No test score or unknown-speaker data enters here.
curve=table(); selected=cell(2,5);
for k=1:2
    modes=["ID","Name"]; mode=modes(k);
    if k==1, infos=idInfo; else, infos=nameInfo; end
    % Every candidate must be valid for the shared decision contract. Ties
    % are not separation; derive margins from scores, never cached metadata.
    marginFloor=max(1+eps,p.dtwMarginRatio);
    d=[]; margins=marginFloor;
    for j=1:numel(infos)
        d=[d;infos{j}.Scores(:)]; %#ok<AGROW>
        info=infos{j};
        if isfield(info,'RunnerUpDistance') && isfinite(info.BestDistance) && ...
                isfinite(info.RunnerUpDistance) && info.RunnerUpDistance>info.BestDistance
            observed=info.RunnerUpDistance/max(info.BestDistance,eps);
            if isfinite(observed) && observed>=marginFloor, margins(end+1,1)=observed; end %#ok<AGROW>
        end
    end
    thresholds=unique([eps;d(isfinite(d) & d>0)]);
    margins=unique(margins); best=[Inf Inf Inf Inf]; chosen=[eps marginFloor]; rows=cell(0,8);
    % Validate each candidate once through the production policy. Re-running
    % every possible claim at every grid point costs O(grid*N^2) and made a
    % larger roster impractical. A query can accept only its single winner.
    n=numel(users); eligible=false(n,1); genuine=false(n,1);
    bestDistances=Inf(n,1); separation=NaN(n,1);
    permissive=p; permissive.idDtwThreshold=realmax; permissive.nameDtwThreshold=realmax;
    permissive.idMarginRatio=1+eps; permissive.nameMarginRatio=1+eps;
    for j=1:n
        info=infos{j};
        decision=speaker_verification_decision(info.BestUser,info,info,permissive);
        eligible(j)=decision.Verified && any(string(info.BestUser)==string(users));
        genuine(j)=strcmp(info.BestUser,char(users(j)));
        bestDistances(j)=info.BestDistance;
        separation(j)=info.RunnerUpDistance/max(info.BestDistance,eps);
    end
    for ti=1:numel(thresholds)
        for mi=1:numel(margins)
            accepted=eligible & bestDistances<=thresholds(ti) & separation>=margins(mi);
            falseAccepted=sum(accepted & ~genuine); genuineRejected=n-sum(accepted & genuine);
            key=[falseAccepted,genuineRejected,thresholds(ti),-margins(mi)];
            if lexless(key,best), best=key; chosen=[thresholds(ti),margins(mi)]; end
            rows(end+1,:)={mode,thresholds(ti),margins(mi),falseAccepted/(n*(n-1)),genuineRejected/n, ...
                falseAccepted,n*(n-1),n}; %#ok<AGROW>
        end
    end
    part=cell2table(rows,'VariableNames',{'Mode','Threshold','Margin','FAR','FRR','FalseAccepted','ImpostorAttempts','GenuineAttempts'});
    curve=[curve;part]; %#ok<AGROW>
    selected(k,:)={mode,chosen(1),chosen(2),best(1),best(2)};
    if k==1, p.idDtwThreshold=chosen(1); p.idMarginRatio=chosen(2);
    else, p.nameDtwThreshold=chosen(1); p.nameMarginRatio=chosen(2); end
end
selection=cell2table(selected,'VariableNames',{'Mode','Threshold','Margin','FalseAccepted','GenuineRejected'});
end

function yes=lexless(a,b)
first=find(a~=b,1); yes=~isempty(first) && a(first)<b(first);
end
