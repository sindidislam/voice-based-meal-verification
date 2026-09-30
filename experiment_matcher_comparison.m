function report=experiment_matcher_comparison(options)
%EXPERIMENT_MATCHER_COMPARISON Isolate global-lag versus DTW alignment.
% Both production matchers receive the SAME scalar feature trajectories.
% Scalar trajectories avoid flattening feature dimensions into invalid lags.
% Constant feature states represent ordered spectral-feature events; changing
% their durations creates known global/local timing changes without changing
% event order. This is a synthetic alignment study, not a human-accuracy or
% senior-source benchmark. No recording, deployed parameter or gate is used.
if nargin<1, options=struct(); end
root=fileparts(mfilename('fullpath'));
o=struct('OutputDir',fullfile(root,'Results','matcher_comparison_20260928'),'Repeats',3);
if ~isstruct(options) || ~isscalar(options)
    error('matcher_comparison:invalidOptions','Options must be a scalar struct.');
end
for field=fieldnames(options)'
    if ~isfield(o,field{1})
        error('matcher_comparison:unknownOption','Unknown option: %s',field{1});
    end
    o.(field{1})=options.(field{1});
end
validateattributes(o.Repeats,{'numeric'},{'scalar','integer','positive','finite'});
if isfile(fullfile(o.OutputDir,'run_summary.json'))
    error('matcher_comparison:existingEvidence','Choose a fresh OutputDir; saved evidence is not overwritten.');
end
if ~isfolder(o.OutputDir), mkdir(o.OutputDir); end

levels=[0 1 -1 2 -2 1 -1 0];
counts=[8 10 10 12 12 8 8 8];
reference=repelem(levels,counts);
different=repelem([0 2 -1 -2 1 -1 2 0],counts);
templates=struct('reference',reference,'different',different);
% Equal positive/negative areas give the shift fixture zero mean. Both ends
% contain silence, so a 7-frame shift loses no nonzero feature samples.
fixtures=struct('Condition',{'identity','global_shift','uniform_slow','nonlinear_timing'}, ...
    'Query',{reference,[zeros(1,7) reference(1:end-7)], ...
        repelem(levels,2*counts),repelem(levels,[8 6 18 8 20 4 16 8])});
matchers=["xcorr","dtw"]; candidates=["reference","different"];
rows=cell(0,12);
for k=1:numel(fixtures)
    query=fixtures(k).Query;
    for method=matchers
        for candidate=candidates
            template=templates.(char(candidate));
            measure(method,query,template); % Untimed first call.
            seconds=zeros(o.Repeats,1);
            for rep=1:o.Repeats
                timer=tic;
                [distance,lag,cells]=measure(method,query,template);
                seconds(rep)=toc(timer);
            end
            rows(end+1,:)={string(fixtures(k).Condition),method,candidate, ...
                candidate=="reference",distance,numel(query),numel(template), ...
                lag,cells,mean(seconds),median(seconds),std(seconds)}; %#ok<AGROW>
        end
    end
end
trials=cell2table(rows,'VariableNames',{'Condition','Matcher','Candidate','Genuine', ...
    'Distance','QueryFrames','TemplateFrames','BestLagFrames','DtwCells', ...
    'MeanSeconds','MedianSeconds','StdSeconds'});
trials.EvidenceType=repmat("synthetic scalar feature trajectories",height(trials),1);
summaryRows=cell(0,7);
for condition=string({fixtures.Condition})
    for method=matchers
        a=trials(trials.Condition==condition & trials.Matcher==method,:);
        own=a.Distance(a.Genuine); other=a.Distance(~a.Genuine);
        best="tie";
        if own<other, best="reference"; elseif other<own, best="different"; end
        summaryRows(end+1,:)={condition,method,own,other,other-own,best,best=="reference"}; %#ok<AGROW>
    end
end
summary=cell2table(summaryRows,'VariableNames',{'Condition','Matcher','ReferenceDistance', ...
    'DifferentDistance','DistanceGap','BestCandidate','CorrectReferenceRanking'});
metadata=struct('Evidence','Synthetic scalar feature trajectories; identical inputs to both matchers', ...
    'Purpose','Compare a global time shift with nonlinear frame alignment', ...
    'IsSpeakerAccuracyEstimate',false,'UsesFinalTestRecordings',false, ...
    'ChangesCalibration',false,'ReproducesSeniorImplementation',false, ...
    'DistanceScalesComparableAcrossMatchers',false,'SyntheticQueryCount',numel(fixtures), ...
    'MeasuredComparisonCount',height(trials),'TimingRepeats',o.Repeats, ...
    'DtwBand',1,'DtwNormalise',true,'CorrelationLagLimit','full linear correlation', ...
    'Limitations',['Known piecewise-constant feature events isolate temporal alignment. ' ...
    'They are not recordings, measured voice accuracy, microphone-distance trials, ' ...
    'or a matched senior-source baseline. Correlation and DTW scores have different scales.'], ...
    'MatlabVersion',version,'CompletedAt',char(datetime('now','Format','yyyy-MM-dd HH:mm:ss')));
writetable(trials,fullfile(o.OutputDir,'matcher_trials.csv'));
writetable(summary,fullfile(o.OutputDir,'matcher_summary.csv'));
save(fullfile(o.OutputDir,'matcher_fixtures.mat'),'fixtures','templates');
fid=fopen(fullfile(o.OutputDir,'run_summary.json'),'w');
assert(fid>=0,'matcher_comparison:cannotWrite','Cannot create comparison metadata.');
closer=onCleanup(@()fclose(fid)); %#ok<NASGU>
fprintf(fid,'%s\n',jsonencode(metadata,'PrettyPrint',true));
report=struct('Trials',trials,'Summary',summary,'Metadata',metadata,'OutputDir',string(o.OutputDir));
disp(summary);
fprintf('MATCHER_COMPARISON_COMPLETE: %s\n',o.OutputDir);
end

function [distance,lag,cells]=measure(method,query,template)
lag=NaN; cells=NaN;
if method=="xcorr"
    [distance,info]=xcorr_distance_dsp(query,template);
    lag=info.BestLag;
else
    [distance,info]=dtw_distance_dsp(query,template, ...
        struct('SakoeChibaBand',1,'Normalise',true));
    cells=info.CellsEvaluated;
end
end
