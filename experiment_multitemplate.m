function [results,distances] = experiment_multitemplate(records,manifest,users,p)
%EXPERIMENT_MULTITEMPLATE Descriptive retrospective leave-one-take-out scores.
%   [RESULTS,DISTANCES]=experiment_multitemplate(RECORDS,MANIFEST,USERS,P)
%   reuses voice_match_scores with the supplied, fixed feature configuration.
%   RECORDS are experiment_recordings outputs. MANIFEST supplies Student,
%   Phrase, Path, Take and SHA256 provenance for each record. USERS is the
%   explicitly enrolled roster; challenge-only students are not enrolled.
%
%   Every query holds out its take number across ALL students for that phrase.
%   Exact normalized paths and SHA256 duplicates of the query are also excluded
%   across the library. The single baseline uses the earliest remaining take
%   (path order breaks ties); multi_mean and multi_median use all remaining
%   templates. No template is selected by its distance to the query.
%
%   RESULTS has one row per query/method; DISTANCES has one row per selected
%   template, including rejected/nonfinite comparisons as Inf. CandidateScore
%   is the production scorer's aggregate, repeated on that candidate's rows.
%   TemplateCount counts finite pair distances; LibraryTemplateCount also
%   includes unusable features. Genuine/ImpostorComparisons count finite
%   candidate scores, separately from Genuine/ImpostorTemplateComparisons.
%
%   This reuses enrollment/development/final takes retrospectively and MUST
%   NOT feed calibration or final model selection. There are no acceptance
%   decisions or parameter updates here. With three takes, each multi library
%   has two templates/student, so mean and median necessarily coincide.
if nargin<4 || isempty(p), p=dsp_parameters(); end
required={'Student','Phrase','Path','Take','SHA256'};
assert(istable(manifest) && all(ismember(required,manifest.Properties.VariableNames)), ...
    'experiment:missingProvenance','Manifest needs Student, Phrase, Path, Take and SHA256.');
assert(all(isfield(records,{'Student','Phrase','Path','Features'})), ...
    'experiment:invalidRecords','Records need Student, Phrase, Path and Features.');
users=string(users(:));
assert(numel(unique(users))==numel(users) && ~isempty(users), ...
    'experiment:invalidUsers','Users must be a nonempty unique enrolled roster.');
assert(all(isfinite(manifest.Take) & manifest.Take>0 & manifest.Take==fix(manifest.Take)), ...
    'experiment:invalidTake','Manifest takes must be positive integers.');
assert(all(~ismissing(string(manifest.SHA256)) & strlength(string(manifest.SHA256))>0), ...
    'experiment:missingProvenance','Every manifest recording needs a SHA256 value.');

% Match by student/phrase as well as path: a mislabeled same-path copy must
% still be excluded by the independent path guard below.
count=numel(records); paths=strings(count,1); students=paths; phrases=paths;
hashes=paths; takes=zeros(count,1);
manifestPaths=normalized_path(string(manifest.Path));
for i=1:count
    paths(i)=string(records(i).Path); students(i)=string(records(i).Student);
    phrases(i)=string(records(i).Phrase);
    ix=find(manifestPaths==normalized_path(paths(i)) & ...
        string(manifest.Student)==students(i) & string(manifest.Phrase)==phrases(i));
    assert(numel(ix)==1,'experiment:ambiguousProvenance', ...
        'Each record must match exactly one manifest student/phrase/path row: %s',paths(i));
    takes(i)=manifest.Take(ix); hashes(i)=lower(string(manifest.SHA256(ix)));
end
pathKeys=normalized_path(paths);
scope="retrospective_leave_one_take_out";
methods=["single","multi_mean","multi_median"];
resultRows=cell(0,25); distanceRows=cell(0,17);
for queryIndex=find(ismember(students,users))'
    query=records(queryIndex); actual=students(queryIndex); phrase=phrases(queryIndex);
    eligible=ismember(students,users) & phrases==phrase & takes~=takes(queryIndex) & ...
        pathKeys~=pathKeys(queryIndex) & hashes~=hashes(queryIndex);
    for method=methods
        q=p; q.templateAggregation='mean';
        if method=="multi_median", q.templateAggregation='median'; end
        library=struct('Users',users,'Templates',{cell(numel(users),1)});
        indices=cell(numel(users),1);
        for candidate=1:numel(users)
            ix=find(eligible & students==users(candidate));
            if ~isempty(ix)
                ordering=table(takes(ix),paths(ix),'VariableNames',{'Take','Path'});
                [~,order]=sortrows(ordering,{'Take','Path'}); ix=ix(order);
                if method=="single", ix=ix(1); end
            end
            indices{candidate}=ix;
            library.Templates{candidate}={records(ix).Features};
        end
        [bestDistance,bestUser,info]=voice_match_scores(library,query.Features,q);
        scores=Inf(numel(users),1);
        if numel(info.Scores)==numel(users), scores=info.Scores(:); end
        genuine=users==actual; finite=isfinite(scores);
        genuinePairs=0; impostorPairs=0; libraryCount=0;
        for candidate=1:numel(users)
            ix=indices{candidate}; libraryCount=libraryCount+numel(ix);
            for templateIndex=ix(:)'
                % Measure individual template scores with the same scorer,
                % retaining its dimension/empty-feature rejection behavior.
                one=struct('Users',users(candidate),'Templates',{{{records(templateIndex).Features}}});
                pairDistance=voice_match_scores(one,query.Features,q);
                if isfinite(pairDistance)
                    genuinePairs=genuinePairs+genuine(candidate);
                    impostorPairs=impostorPairs+~genuine(candidate);
                end
                distanceRows(end+1,:)={scope,method,actual,phrase,paths(queryIndex), ...
                    hashes(queryIndex),takes(queryIndex),users(candidate),genuine(candidate), ...
                    paths(templateIndex),hashes(templateIndex),takes(templateIndex), ...
                    phrases(templateIndex),pairDistance,scores(candidate),numel(ix),isfinite(pairDistance)}; %#ok<AGROW>
            end
        end
        genuineDistance=scores(genuine); nearestImpostor=min(scores(~genuine));
        if isempty(nearestImpostor), nearestImpostor=Inf; end
        status="measured";
        if isempty(query.Features) || any(~isfinite(query.Features(:)))
            status="query_features_unavailable";
        elseif ~any(finite & genuine)
            status="genuine_templates_unavailable";
        elseif sum(finite)<2
            status="insufficient_competition";
        elseif ~all(finite)
            status="partial_library";
        end
        resultRows(end+1,:)={scope,method,actual,phrase,paths(queryIndex),hashes(queryIndex), ...
            takes(queryIndex),string(bestUser),bestDistance,genuineDistance,nearestImpostor, ...
            info.Margin,string(bestUser)==actual && isfinite(bestDistance),numel(users), ...
            sum(finite),genuinePairs+impostorPairs,libraryCount,genuinePairs,impostorPairs, ...
            sum(finite & genuine),sum(finite & ~genuine),status,string(query.Role), ...
            sum(phrases==phrase & pathKeys==pathKeys(queryIndex)), ...
            sum(phrases==phrase & hashes==hashes(queryIndex))}; %#ok<AGROW>
    end
end
results=cell2table(resultRows,'VariableNames',{'Scope','Method','ActualStudent','Phrase', ...
    'QueryPath','QuerySHA256','QueryTake','PredictedStudent','BestDistance','GenuineDistance', ...
    'NearestImpostorDistance','Margin','Top1Correct','StudentCount','ScoredStudentCount', ...
    'TemplateCount','LibraryTemplateCount','GenuineTemplateComparisons','ImpostorTemplateComparisons', ...
    'GenuineComparisons','ImpostorComparisons','Status','OriginalRole','SamePathRecordCount','SameHashRecordCount'});
distances=cell2table(distanceRows,'VariableNames',{'Scope','Method','ActualStudent','Phrase', ...
    'QueryPath','QuerySHA256','QueryTake','CandidateStudent','Genuine','TemplatePath', ...
    'TemplateSHA256','TemplateTake','TemplatePhrase','TemplateDistance','CandidateScore', ...
    'CandidateTemplateCount','FiniteTemplateComparison'});
end

function paths=normalized_path(paths)
% Windows paths are case-insensitive; accept either separator in provenance.
paths=lower(replace(string(paths),'\','/'));
end
