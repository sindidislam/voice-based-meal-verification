function export_case_evidence(auditDir)
%EXPORT_CASE_EVIDENCE Add reproducible DTW paths and current-policy challenge.
% Historical 150 recordings remain challenge-only. Nothing is enrolled/written
% to the meal/payment stores. This is not the unsaved original live incident.
projectRoot=fileparts(mfilename('fullpath'));
s=load(fullfile(auditDir,'baseline_snapshot.mat'));
oldPwd=pwd; oldPath=path;
cleanup=onCleanup(@()restore_environment(oldPwd,oldPath)); %#ok<NASGU>
cd(s.sourceRoot); addpath(s.sourceRoot,'-begin');
assert(strcmpi(which('dtw_distance_dsp'),fullfile(s.sourceRoot,'dtw_distance_dsp.m')));
opts=s.p.dtw; opts.ReturnPath=true;
pathRows={};
queries=find(s.labels=="2206150" & s.phrases=="ID");
for k=queries'
    for candidate=["2206148","2206149"]
        ix=find(s.labels==candidate & s.phrases=="ID" & s.roles=="enrollment");
        scores=Inf(numel(ix),1);
        for j=1:numel(ix)
            scores(j)=dtw_distance_dsp(s.features{ix(j),1},s.features{k,1},s.p.dtw);
        end
        [~,best]=min(scores); j=ix(best);
        [distance,detail]=dtw_distance_dsp(s.features{j,1},s.features{k,1},opts);
        assert(abs(distance-scores(best))<1e-10,'Path export changed distance.');
        pathRows{end+1}=struct('QueryPath',char(s.paths(k)), ...
            'Candidate',char(candidate),'TemplatePath',char(s.paths(j)), ...
            'Distance',distance,'Detail',detail); %#ok<AGROW>
    end
end
paths=vertcat(pathRows{:});
save(fullfile(auditDir,'case_dtw_paths.mat'),'paths','-v7');
st=load(fullfile(auditDir,'stage_snapshot.mat'));
plotRows=cell(numel(st.stageSnapshot),1);
for k=1:numel(st.stageSnapshot)
    row=st.stageSnapshot(k);
    [spectrum,frequency,time]=spectrogram(row.Denoised,hamming(256),192,512,row.ProcessingFs);
    row.SpectrogramDb=20*log10(max(abs(spectrum),eps));
    row.SpectrogramHz=frequency; row.SpectrogramSeconds=time;
    plotRows{k}=row;
end
plots=vertcat(plotRows{:});
save(fullfile(auditDir,'case_plot_data.mat'),'plots','-v7');
cd(projectRoot); path(oldPath); addpath(projectRoot,'-begin');
clear dsp_parameters dtw_distance_dsp preprocess_audio preprocess_template_audio
clear extract_features extract_mfcc_dsp voice_match_scores enrol_template_features assess_recording_quality
p=dsp_parameters(); find_best_voice_match('reset'); rows={};
ids=find(s.labels=="2206150" & s.phrases=="ID");
names=find(s.labels=="2206150" & s.phrases=="Name");
for k=1:numel(ids)
    [~,take]=fileparts(s.paths(ids(k)));
    nameIndex=[];
    for j=names'
        [~,nameTake]=fileparts(s.paths(j));
        if nameTake==take, nameIndex=j; break; end
    end
    assert(~isempty(nameIndex),'ID/name challenge pairing is missing.');
    a=enrol_template_features(s.paths(ids(k)),[],p);
    b=enrol_template_features(s.paths(nameIndex),[],p);
    [~,~,idInfo]=find_best_voice_match(p.trainIdFolder,a,p);
    [~,~,nameInfo]=find_best_voice_match(p.trainNameFolder,b,p);
    decision=speaker_verification_decision('2206150',idInfo,nameInfo,p);
    result=verify_meal_workflow([], '',p,struct('ClaimedID','2206150', ...
        'IDFeatures',a,'NameFeatures',b,'SkipLogging',true));
    assert(~result.Verified && ~result.Granted && isempty(result.Student));
    rows{end+1}=struct('ActualFolderLabel',"2206150",'Take',take, ...
        'IDCandidate',string(idInfo.BestUser),'NameCandidate',string(nameInfo.BestUser), ...
        'IDDistance',idInfo.BestDistance,'NameDistance',nameInfo.BestDistance, ...
        'IDMargin',idInfo.Margin,'NameMargin',nameInfo.Margin, ...
        'BiometricDecision',string(decision.Decision),'BiometricStage',string(decision.Stage), ...
        'WorkflowDecision',string(result.Decision),'WorkflowStage',string(result.Stage), ...
        'Verified',result.Verified,'Granted',result.Granted, ...
        'Evidence',"historical challenge; archive preprocessing; no 150 enrollment; unsaved live event unavailable"); %#ok<AGROW>
end
writetable(struct2table(vertcat(rows{:})),fullfile(auditDir,'current_150_challenge.csv'));
find_best_voice_match('reset');
fprintf('CASE_EVIDENCE_PASS: original DTW paths and all historical 150 claims refused.\n');
end

function restore_environment(folder,originalPath)
cd(folder); path(originalPath);
end
