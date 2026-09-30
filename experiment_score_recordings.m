function [idInfo,nameInfo,timing,distances] = experiment_score_recordings(enrollment,queries,users,p,variant,repeats)
%EXPERIMENT_SCORE_RECORDINGS Same production scorer, fixed enrollment library.
users=string(users(:)); n=numel(users); idInfo=cell(n,1); nameInfo=cell(n,1);
timeRows=cell(0,8); distanceRows=cell(0,7);
for phrase=["ID","Name"]
    library=struct('Users',users,'Templates',{cell(n,1)});
    for s=1:n
        ix=find([enrollment.Student]==users(s) & [enrollment.Phrase]==phrase);
        library.Templates{s}={enrollment(ix).Features};
    end
    for s=1:n
        ix=find([queries.Student]==users(s) & [queries.Phrase]==phrase,1);
        query=queries(ix);
        for rep=1:repeats
            clock=tic; [~,~,info]=voice_match_scores(library,query.Features,p); matching=toc(clock);
            timeRows(end+1,:)={variant,query.Role,users(s),phrase,rep,"Match1toN",matching,"one query vs all enrolled students"}; %#ok<AGROW>
            timeRows(end+1,:)={variant,query.Role,users(s),phrase,rep,"Verification", ...
                query.PipelineSeconds(min(rep,end))+matching,"measured pipeline + 1-to-N; no capture/UI/network"}; %#ok<AGROW>
            clock=tic; dtw_distance_dsp(library.Templates{s}{1},query.Features,p.dtw); dtwSeconds=toc(clock);
            timeRows(end+1,:)={variant,query.Role,users(s),phrase,rep,"DTW",dtwSeconds,"one genuine pair; measured separately"}; %#ok<AGROW>
        end
        if numel(info.Scores)~=n, info.Scores=Inf(n,1); info.Users=users; end
        if phrase=="ID", idInfo{s}=info; else, nameInfo{s}=info; end
        for c=1:n
            distanceRows(end+1,:)={variant,query.Role,phrase,users(s),users(c),s==c,info.Scores(c)}; %#ok<AGROW>
        end
    end
end
timing=cell2table(timeRows,'VariableNames',{'Variant','Split','Student','Phrase','Repeat','Stage','Seconds','Scope'});
distances=cell2table(distanceRows,'VariableNames',{'Variant','Split','Phrase','ActualStudent','CandidateStudent','Genuine','Distance'});
end
