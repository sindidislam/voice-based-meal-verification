function report = run_all_experiments(options)
%RUN_ALL_EXPERIMENTS Reproducible retrospective recording-disjoint evaluation.
%   run_all_experiments() writes a NEW timestamped Results folder. Options:
%   Mode='full'|'smoke', OutputDir, Repeats=3, MakePlots=true,
%   SyntheticStress=true. No deployed parameters or business files are changed.
%   Take1=enrollment, take2=development, take3=final. Candidate and per-phrase
%   gate selection finish and are saved BEFORE final feature extraction.
if nargin<1, options=struct(); end
runClock=tic;
root=fileparts(mfilename('fullpath'));
o=struct('Mode','full','OutputDir',fullfile(root,'Results', ...
    ['experiments_' char(datetime('now','Format','yyyyMMdd_HHmmss_SSS'))]), ...
    'Repeats',3,'MakePlots',true,'SyntheticStress',true,'DatasetRoot',root);
fields=fieldnames(options);
for k=1:numel(fields)
    if ~isfield(o,fields{k}), error('experiment:unknownOption','Unknown option: %s',fields{k}); end
    o.(fields{k})=options.(fields{k});
end
o.Mode=validatestring(o.Mode,{'smoke','full'});
validateattributes(o.Repeats,{'numeric'},{'scalar','integer','positive'});
if ~isfolder(o.OutputDir), mkdir(o.OutputDir); end
if isfile(fullfile(o.OutputDir,'frozen_selection.mat'))
    error('experiment:existingRun','Choose a fresh OutputDir; existing evidence will not be overwritten.');
end
manifest=experiment_recording_split(o.DatasetRoot);
writetable(manifest,fullfile(o.OutputDir,'recording_manifest.csv'));
users=unique(manifest.Student,'stable');
train=manifest(manifest.Role=="enrollment",:);
development=manifest(manifest.Role=="development",:);
finalManifest=manifest(manifest.Role=="final_test",:);
p=dsp_parameters(false); catalog=experiment_variants(p);
count=numel(catalog); if strcmp(o.Mode,'smoke'), count=1; end
catalogRows=table([catalog.Name]',[catalog.Group]',[catalog.Change]', ...
    repmat("not_run_smoke",numel(catalog),1),'VariableNames',{'Variant','Group','Change','Status'});
catalogRows.Status(1:count)="measured_development";
writetable(catalogRows,fullfile(o.OutputDir,'candidate_catalog.csv'));
accuracy=table(); thresholds=table(); points=table(); timing=table(); distances=table();
quality=table(); agc=table(); noise=table(); vad=table(); liveness=table(); trials=table();
allParams=cell(count,1); devMetrics=cell(count,1); enrollment=cell(count,1);
bestKey=[Inf Inf]; selected=1;
fprintf('Experiment: %d students, %d candidates, %d timing repetitions.\n',numel(users),count,o.Repeats);
for v=1:count
    name=catalog(v).Name; q=catalog(v).Params;
    fprintf('Development %d/%d: %s\n',v,count,name);
    [enr,t1]=experiment_recordings(train,q,name,o.Repeats);
    [dev,t2]=experiment_recordings(development,q,name,o.Repeats);
    [id,nm,t3,d]=experiment_score_recordings(enr,dev,users,q,name,o.Repeats);
    [q,curve,point]=experiment_operating_points(id,nm,users,q);
    curve=addvars(curve,repmat(name,height(curve),1),'Before',1,'NewVariableNames','Variant');
    point=addvars(point,repmat(name,height(point),1),'Before',1,'NewVariableNames','Variant');
    thresholds=[thresholds;curve]; points=[points;point]; %#ok<AGROW>
    [a,tr]=measure_modes(id,nm,users,q,name,"development");
    accuracy=[accuracy;a]; trials=[trials;tr]; %#ok<AGROW>
    met=experiment_decision_metrics(id,nm,users,q,"ID+Name");
    key=[met.FalseAccepted,met.GenuineAttempts-met.GenuineAccepted];
    if lexless(key,bestKey), selected=v; bestKey=key; end
    devMetrics{v}=met; allParams{v}=q; enrollment{v}=enr;
    timing=[timing;t1;t2;t3]; distances=[distances;d]; %#ok<AGROW>
    [qu,ag,no,va,li]=diagnostic_tables([enr,dev],name,q);
    quality=[quality;qu]; agc=[agc;ag]; noise=[noise;no]; vad=[vad;va]; liveness=[liveness;li]; %#ok<AGROW>
end
% This serial save is the boundary: no final WAV has been processed above.
freeze=struct('Variant',catalog(selected).Name,'Params',allParams{selected}, ...
    'Manifest',[train;development],'Roles',unique([train.Role;development.Role]), ...
    'SelectedIndex',selected,'SelectionObjective', ...
    "minimize false claims, then genuine rejects; ties retain first catalog entry", ...
    'CandidateCatalog',catalogRows,'Mode',string(o.Mode),'Timestamp',datetime('now'), ...
    'FinalExtractionStarted',false,'Retrospective',true);
save(fullfile(o.OutputDir,'frozen_selection.mat'),'freeze');
writetable(points,fullfile(o.OutputDir,'frozen_operating_points.csv'));
fprintf('Frozen selection: %s. Starting final-test extraction.\n',freeze.Variant);
finalRecords=struct([]); currentRecords=struct([]); finalId={}; finalName={};
% Only the frozen candidate and current DSP baseline are evaluated on final.
for v=unique([1 selected],'stable')
    name=catalog(v).Name; q=allParams{v};
    [test,t1]=experiment_recordings(finalManifest,q,name,o.Repeats);
    [id,nm,t2,d]=experiment_score_recordings(enrollment{v},test,users,q,name,o.Repeats);
    [a,tr]=measure_modes(id,nm,users,q,name,"final_test");
    accuracy=[accuracy;a]; trials=[trials;tr]; timing=[timing;t1;t2]; distances=[distances;d]; %#ok<AGROW>
    [qu,ag,no,va,li]=diagnostic_tables(test,name,q);
    quality=[quality;qu]; agc=[agc;ag]; noise=[noise;no]; vad=[vad;va]; liveness=[liveness;li]; %#ok<AGROW>
    if v==1
        currentRecords=test;
        [legacy,legacyTrials]=legacy_metrics(id,nm,users,p);
        accuracy=[accuracy;legacy]; trials=[trials;legacyTrials]; %#ok<AGROW>
    end
    if v==selected, finalRecords=test; finalId=id; finalName=nm; end
end
% A named alias identifies the frozen configuration, without rerunning/tuning.
aliases=accuracy(accuracy.Variant==freeze.Variant & accuracy.Split=="final_test",:);
aliases.Variant(:)="final_selected"; accuracy=[accuracy;aliases];
aliasTrials=trials(trials.Variant==freeze.Variant & trials.Split=="final_test",:);
aliasTrials.Variant(:)="final_selected"; trials=[trials;aliasTrials];
timing=paired_timing(timing);
report=struct('OutputDir',string(o.OutputDir),'FreezeRoles',freeze.Roles, ...
    'FinalTestRecordingCount',height(finalManifest),'Students',numel(users), ...
    'SelectedVariant',freeze.Variant,'Params',freeze.Params,'Options',o);
tables=struct('accuracy_results',accuracy,'threshold_results',thresholds, ...
    'timing_raw',timing,'pair_distances',distances,'quality_results',quality, ...
    'agc_results',agc,'noise_results',noise,'vad_results',vad,'liveness_results',liveness, ...
    'decision_trials',trials);
tables=experiment_report_tables(tables,catalogRows,freeze,users);
% Supplemental comparison occurs only after final evaluation and does not
% participate in model/threshold selection. Every query take is excluded.
fprintf('Supplemental multi-template leave-one-take-out comparison.\n');
[supplemental,~]=experiment_recordings(manifest,freeze.Params,freeze.Variant,1);
[tables.multitemplate_results,tables.multitemplate_distances]= ...
    experiment_multitemplate(supplemental,manifest,users,freeze.Params);
if o.SyntheticStress
    fprintf('Synthetic gain/noise/VAD stress (separate from recording evidence).\n');
    stress=experiment_synthetic_stress(train,development,users,p,o.OutputDir,o.MakePlots);
    fields=fieldnames(stress); for k=1:numel(fields), tables.(fields{k})=stress.(fields{k}); end
end
fields=fieldnames(tables);
for k=1:numel(fields), writetable(tables.(fields{k}),fullfile(o.OutputDir,[fields{k} '.csv'])); end
report.FigureStatus="disabled by MakePlots=false";
if o.MakePlots
    figureManifest=experiment_export_figures(tables,freeze,currentRecords,finalRecords, ...
        enrollment{selected},finalId,finalName,users,o.OutputDir);
    report.FigureStatus=unique(figureManifest.Status,'stable');
end
report.RuntimeSeconds=toc(runClock);
summary=struct('MatlabVersion',version,'MatlabRelease',version('-release'), ...
    'Computer',computer,'RuntimeSeconds',report.RuntimeSeconds, ...
    'CompletedAt',char(datetime('now','Format','yyyy-MM-dd HH:mm:ss')), ...
    'SelectedVariant',char(freeze.Variant),'SelectedParams',freeze.Params, ...
    'StudentCount',numel(users),'FinalTestRecordingCount',height(finalManifest), ...
    'DatasetRoot',char(o.DatasetRoot), ...
    'Mode',o.Mode,'Repeats',o.Repeats,'FigureStatus',report.FigureStatus, ...
    'Protocol',struct('Enrollment','take1','Development','take2','FinalTest','take3', ...
    'Retrospective',true,'ArchivedTemplatePreprocessing',true, ...
    'SelectionFrozenBeforeFinalExtraction',true,'FalseClaimContent','impostor own ID/name', ...
    'DecisionPolicy','ID-first independently gated Name fallback', ...
    'LiveMaximumAttempts',3,'EvaluationRoundsPerPair',1, ...
    'GenuineClaimDenominator',numel(users),'FalseClaimDenominator',numel(users)*(numel(users)-1)));
fid=fopen(fullfile(o.OutputDir,'run_summary.json'),'w');
if fid<0, error('experiment:summaryWrite','Cannot create run_summary.json.'); end
closer=onCleanup(@() fclose(fid));
fprintf(fid,'%s\n',jsonencode(summary,'PrettyPrint',true)); clear closer;
save(fullfile(o.OutputDir,'experiment_run.mat'),'report','freeze','catalog','tables');
fprintf('Results: %s\n',o.OutputDir);
end

function [a,trials]=measure_modes(id,nm,users,q,variant,split)
a=table(); trials=table();
for mode=["ID","Name","ID+Name"]
    [m,tr]=experiment_decision_metrics(id,nm,users,q,mode);
    row=struct2table(m); row=addvars(row,variant,split,mode,"measured", ...
        'Before',1,'NewVariableNames',{'Variant','Split','Mode','Status'});
    tr=addvars(tr,repmat(variant,height(tr),1),repmat(split,height(tr),1), ...
        repmat(mode,height(tr),1),'Before',1,'NewVariableNames',{'Variant','Split','Mode'});
    a=[a;row]; trials=[trials;tr]; %#ok<AGROW>
end
end

function [a,trials]=legacy_metrics(id,nm,users,p)
[a,trials]=measure_modes(id,nm,users,p,"existing_policy","final_test");
a=a(a.Mode=="ID+Name",:); trials=trials(trials.Mode=="ID+Name",:);
correct=0; wrong=0;
for k=1:numel(users)
    result=experiment_legacy_policy(id{k},nm{k},p);
    ix=trials.ActualStudent==users(k);
    trials.Accepted(ix)=result.Accepted & trials.ClaimedStudent(ix)==result.Student;
    correct=correct+(result.Accepted && result.Student==users(k));
    wrong=wrong+(result.Accepted && result.Student~=users(k));
end
a.GenuineAccepted=correct; a.FalseAccepted=wrong;
a.GenuineAcceptance=correct/numel(users); a.FRR=1-a.GenuineAcceptance;
a.FAR=wrong/a.ImpostorAttempts; a.WSAR=a.FAR;
a.ClosedSetWrongAccepted=wrong; a.ClosedSetWSAR=wrong/numel(users);
% Legacy policy is identity discovery; claim fields describe retrospective
% wrong-claim enumeration, not a claim gate present in the original workflow.
a.Top1Accuracy=NaN; a.CorrectClaimIdentityErrors=NaN;
end

function [quality,agc,noise,vad,liveness]=diagnostic_tables(records,variant,p)
qr=cell(0,12); ar=cell(0,10); nr=cell(0,9); vr=cell(0,13); lr=cell(0,11);
for i=1:numel(records)
    r=records(i); q=r.Quality; d=r.Diagnostics;
    base={variant,r.Role,r.Student,r.Phrase};
    qr(end+1,:)=[base,{r.Path,logical(value(q,'Usable',false)),string(value(q,'Reason','')), ...
        value(q,'AcRms',NaN),value(q,'ClippedFraction',NaN),value(q,'SpeechDuration',NaN), ...
        string(value(d,'TemplateMode','unavailable')),"retrospective recording"}]; %#ok<AGROW>
    ag=value(d,'Agc',struct());
    ar(end+1,:)=[base,{value(ag,'InputRms',NaN),value(ag,'OutputRms',NaN), ...
        value(ag,'Gain',NaN),logical(p.agc.Enable),NaN,"microphone distance unavailable"}]; %#ok<AGROW>
    no=value(d,'Noise',struct());
    nr(end+1,:)=[base,{string(value(no,'Method','unavailable')),logical(value(no,'Skipped',true)), ...
        NaN,NaN,"field SNR unavailable; no clean reference"}]; %#ok<AGROW>
    va=value(d,'Endpoint',struct()); fs=p.processingFs;
    vr(end+1,:)=[base,{logical(value(va,'HasSpeech',false)), ...
        (value(va,'StartSample',NaN)-1)/fs,value(va,'EndSample',NaN)/fs, ...
        value(va,'NumActiveFrames',NaN),value(va,'NumFrames',NaN),NaN,NaN,NaN, ...
        "unannotated recording; detection/miss/truncation rates unavailable"}]; %#ok<AGROW>
    li=value(d,'Liveness',struct());
    lr(end+1,:)=[base,{value(li,'LowEnergy',NaN),value(li,'FullEnergy',NaN), ...
        value(li,'Ratio',NaN),logical(value(li,'Rejected',true)), ...
        "unknown capture provenance","diagnostic_only","no live/replay labels; no spoof metric"}]; %#ok<AGROW>
end
quality=cell2table(qr,'VariableNames',{'Variant','Split','Student','Phrase','Path','Usable','Reason','AcRms','ClippedFraction','SpeechSeconds','TemplateMode','EvidenceType'});
agc=cell2table(ar,'VariableNames',{'Variant','Split','Student','Phrase','InputRms','OutputRms','Gain','AGCEnabled','MicrophoneDistanceCm','Status'});
noise=cell2table(nr,'VariableNames',{'Variant','Split','Student','Phrase','Method','Skipped','SNRBeforeDb','SNRAfterDb','Status'});
vad=cell2table(vr,'VariableNames',{'Variant','Split','Student','Phrase','HasSpeech','StartSeconds','EndSeconds','ActiveFrames','TotalFrames','DetectionRate','FalseTriggerRate','TruncatedSeconds','Status'});
liveness=cell2table(lr,'VariableNames',{'Variant','Split','Student','Phrase','LowBandEnergy','FullBandEnergy','Ratio','HeuristicRejected','CaptureLabel','Status','Limitation'});
end

function t=paired_timing(t)
v=unique(t.Variant,'stable'); rows=t([],:);
for variant=v'
    for split=["development","final_test"]
        sub=t(t.Variant==variant & t.Split==split & t.Stage=="Verification",:);
        for student=unique(sub.Student,'stable')'
            for rep=unique(sub.Repeat)'
                pair=sub(sub.Student==student & sub.Repeat==rep,:);
                if height(pair)==2
                    row=pair(1,:); row.Phrase="ID+Name"; row.Stage="ID+Name";
                    row.Seconds=sum(pair.Seconds); row.Scope="sum of two independently measured utterance processing times";
                    rows=[rows;row]; %#ok<AGROW>
                end
            end
        end
    end
end
t=[t;rows];
end

function yes=lexless(a,b)
first=find(a~=b,1); yes=~isempty(first) && a(first)<b(first);
end
function v=value(s,k,fallback)
v=fallback; if isfield(s,k), v=s.(k); end
end
