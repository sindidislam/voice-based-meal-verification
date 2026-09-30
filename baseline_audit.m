function summary = baseline_audit(sourceRoot, candidateRoots, outputRoot)
%BASELINE_AUDIT Reproduce preserved v4.1.4 without changing its enrollment.
% sourceRoot is REQUIRED and must be the immutable preserved project.
% candidateRoots are folders of independently retained WAVs (including 150).
% outputRoot is a separate results folder. No enrollment or business CSV is written.
% Labels are folder assertions, not independently verified speaker/transcript truth.
% Two query modes are reported: archived (the original stored-template gate) and
% live_replay (original live preprocessing applied offline to the same raw WAV).
% Every exact path AND byte-identical enrollment file is excluded as a query's
% own template. Five rows are emitted even when fewer than five users exist.

if nargin < 1 || isempty(sourceRoot)
    error('baseline_audit:sourceRequired','Pass the preserved source project explicitly.');
end
if nargin < 2, candidateRoots = {}; end
if nargin < 3, outputRoot = fullfile(fileparts(mfilename('fullpath')),'Results','audit_baseline'); end
sourceRoot = char(System.IO.Path.GetFullPath(char(sourceRoot)));
outputRoot = char(System.IO.Path.GetFullPath(char(outputRoot)));
assert(~strcmpi(outputRoot,sourceRoot) && ...
    ~startsWith(lower(outputRoot),[lower(sourceRoot) filesep]), ...
    'baseline_audit:preservation','Output must not be inside preserved source.');
if ~isfolder(outputRoot), mkdir(outputRoot); end
oldPwd = pwd; oldPath = path;
cleanup = onCleanup(@() restore_environment(oldPwd,oldPath)); %#ok<NASGU>
cd(sourceRoot); addpath(sourceRoot,'-begin');
clear dsp_parameters preprocess_audio preprocess_template_audio enrol_template_features
clear assess_recording_quality extract_features extract_mfcc_dsp dtw_distance_dsp voice_match_scores
core = {'dsp_parameters','preprocess_audio','preprocess_template_audio', ...
    'enrol_template_features','assess_recording_quality','extract_features', ...
    'extract_mfcc_dsp','dtw_distance_dsp','voice_match_scores', ...
    'rational_resample_audio','agc_normalize','spectral_subtract_noise','hybrid_endpoint_detect'};
for k=1:numel(core)
    assert(strcmpi(which(core{k}),fullfile(sourceRoot,[core{k} '.m'])), ...
        'baseline_audit:shadowed','Unexpected code resolution: %s',core{k});
end
p = dsp_parameters();
started = datetime('now','TimeZone','UTC');
sourceFiles = [dir(fullfile(sourceRoot,'*.m')); dir(fullfile(sourceRoot,'*.csv'))];
sourceManifest = table(strings(numel(sourceFiles),1),strings(numel(sourceFiles),1), ...
    'VariableNames',{'Path','SHA256'});
for k=1:numel(sourceFiles)
    sourceManifest.Path(k)=string(fullfile(sourceFiles(k).folder,sourceFiles(k).name));
    sourceManifest.SHA256(k)=hash_file(sourceManifest.Path(k));
end
writetable(sourceManifest,fullfile(outputRoot,'source_manifest.csv'));
fid=fopen(fullfile(outputRoot,'parameters.json'),'w');
fprintf(fid,'%s',jsonencode(p,PrettyPrint=true)); fclose(fid);

enrollment = dir(fullfile(sourceRoot,'Train','**','*.wav'));
paths=string(fullfile({enrollment.folder},{enrollment.name}))';
roles=repmat("enrollment",numel(paths),1);
for k=1:numel(candidateRoots)
    found=dir(fullfile(char(candidateRoots{k}),'**','*.wav'));
    paths=[paths; string(fullfile({found.folder},{found.name}))']; %#ok<AGROW>
    roles=[roles; repmat("candidate_only",numel(found),1)]; %#ok<AGROW>
end
[paths,ix]=unique(paths,'stable'); roles=roles(ix);
N=numel(paths); hashes=strings(N,1); phrases=strings(N,1); labels=strings(N,1);
for k=1:N
    hashes(k)=hash_file(paths(k));
    tok=regexp(char(paths(k)),'[\\/]Train[\\/](ID|Name|Coupon)[\\/]([^\\/]+)[\\/]','tokens','once');
    assert(~isempty(tok),'baseline_audit:layout','Unrecognized phrase/label path: %s',paths(k));
    phrases(k)=string(tok{1}); labels(k)=string(tok{2});
end
[~,keep,canonical]=unique(hashes,'stable');
inventory=table(paths,roles,phrases,labels,hashes,canonical, ...
    'VariableNames',{'Path','Role','Phrase','FolderLabel','SHA256','UniqueRecordingIndex'});
writetable(inventory,fullfile(outputRoot,'inventory_all_paths.csv'));
paths=paths(keep); roles=roles(keep); phrases=phrases(keep); labels=labels(keep); hashes=hashes(keep);
N=numel(paths);
assert(all(roles(labels=="2206150")=="candidate_only"), ...
    'baseline_audit:enrollment','2206150 unexpectedly occurs in preserved enrollment.');

features=cell(N,2); quality=cell(N,1); diagnostics=cell(N,2); audioOut=cell(N,2);
measureRows=cell(N*2,1); modes=["archived","live_replay"];
for k=1:N
    [raw,fs]=audioread(paths(k));
    [features{k,1},quality{k}]=enrol_template_features(raw,fs,p);
    [~,~,diagnostics{k,1}]=preprocess_template_audio(raw,fs,p);
    audioOut{k,1}=quality{k}.Audio;
    [audioOut{k,2},fo,diagnostics{k,2}]=preprocess_audio(raw,fs,p);
    if ~diagnostics{k,2}.Rejected && diagnostics{k,2}.Endpoint.HasSpeech
        features{k,2}=extract_features(audioOut{k,2},fo,p);
    end
    mono=raw(:); first=mono(1:min(numel(mono),round(fs*p.noise.NoiseDuration)));
    for m=1:2
        dg=diagnostics{k,m}; ep=dg.Endpoint;
        speechDur=max(0,(ep.EndSample-ep.StartSample+1)/p.processingFs);
        leadRms=sqrt(mean(first.^2)); fullRms=sqrt(mean(mono.^2));
        row=struct('RecordingIndex',k,'Path',paths(k),'Role',roles(k), ...
            'Phrase',phrases(k),'FolderLabel',labels(k),'Mode',modes(m), ...
            'InputFs',fs,'Channels',size(raw,2),'RawDuration',size(raw,1)/fs, ...
            'RawRms',fullRms,'RawPeak',max(abs(mono)),'DCOffset',mean(mono), ...
            'ClippedFraction',quality{k}.ClippedFraction,'ClippedRun',quality{k}.ClippedRun, ...
            'PreRollRms',leadRms,'LeadToFullRmsRatio',leadRms/(fullRms+eps), ...
            'SpeechDuration',speechDur,'TrimmedFraction',1-speechDur/(size(raw,1)/fs), ...
            'EndpointStartSeconds',(ep.StartSample-1)/p.processingFs, ...
            'EndpointEndSeconds',ep.EndSample/p.processingFs, ...
            'FeatureFrames',size(features{k,m},2),'FeatureDimensions',size(features{k,m},1), ...
            'LowFrequencyRatio',dg.LowFrequencyRatio, ...
            'ProcessingRejected',dg.Rejected,'FeaturesAvailable',~isempty(features{k,m}), ...
            'QualityReason',string(quality{k}.Reason),'Stage',string(dg.Stage), ...
            'Reason',string(dg.Reason),'TemplateMode',string(getfield_or(dg,'TemplateMode','live')), ...
            'EndpointEstimator',string(getfield_or(ep,'Estimator','none')), ...
            'EnergyThreshold',getfield_or(ep,'EnergyThreshold',NaN), ...
            'RejectedLowZcrFrames',getfield_or(ep,'RejectedLowZcr',NaN), ...
            'RejectedHighZcrFrames',getfield_or(ep,'RejectedHighZcr',NaN));
        measureRows{(k-1)*2+m}=row;
    end
    fprintf('Feature audit %d/%d: %s %s %s\n',k,N,phrases(k),labels(k),paths(k));
end
mStruct = vertcat(measureRows{:}); measurements = struct2table(mStruct(:));
writetable(measurements,fullfile(outputRoot,'quality_diagnostics.csv'));
save(fullfile(outputRoot,'baseline_snapshot.mat'),'p','started','sourceRoot','sourceManifest', ...
    'paths','roles','phrases','labels','hashes','features','quality','diagnostics','audioOut','inventory','-v7');

topRows={}; distanceRows={}; outcomeRows={};
for k=1:N
    enrolled=find(roles=="enrollment" & phrases==phrases(k));
    users=unique(labels(enrolled));
    for m=1:2
        lib=struct('Users',users,'Templates',{cell(numel(users),1)});
        directMeans=Inf(numel(users),1);
        for u=1:numel(users)
            indices=enrolled(labels(enrolled)==users(u)); bucket={}; dists=[];
            for j=indices'
                excluded=strcmpi(paths(k),paths(j)) || hashes(k)==hashes(j);
                dist=Inf;
                if ~excluded
                    bucket{end+1}=features{j,1}; %#ok<AGROW>
                    if ~isempty(features{k,m}) && ~isempty(features{j,1})
                        dist=dtw_distance_dsp(features{j,1},features{k,m},p.dtw);
                    end
                    if isfinite(dist), dists(end+1)=dist; end %#ok<AGROW>
                end
                distanceRows{end+1}=struct('RecordingIndex',k,'Path',paths(k),'Mode',modes(m), ...
                    'Phrase',phrases(k),'FolderLabel',labels(k),'Candidate',users(u), ...
                    'TemplateIndex',j,'TemplatePath',paths(j),'ExcludedSameRecording',excluded, ...
                    'TemplateUsable',~isempty(features{j,1}),'Distance',dist); %#ok<AGROW>
            end
            lib.Templates{u}=bucket;
            if ~isempty(dists), directMeans(u)=mean(dists); end
        end
        [bestDist,bestUser,info]=voice_match_scores(lib,features{k,m},p);
        if ~isempty(info.Scores)
            finite=isfinite(directMeans);
            assert(isequal(finite,isfinite(info.Scores)) && all(abs(directMeans(finite)-info.Scores(finite))<1e-10), ...
                'baseline_audit:scoring','Original scorer differs from template distance means.');
        end
        [scores,order]=sort(directMeans);
        hasMatch=isfinite(bestDist) && bestDist<=p.dtwThreshold;
        runnerIn=isfinite(info.RunnerUpDistance) && info.RunnerUpDistance<=p.dtwThreshold;
        confident=hasMatch && (~runnerIn || info.Margin>=p.dtwMarginRatio);
        outcomeRows{end+1}=struct('RecordingIndex',k,'Path',paths(k),'Role',roles(k), ...
            'Phrase',phrases(k),'FolderLabel',labels(k),'Mode',modes(m), ...
            'LabelEnrolled',any(users==labels(k)),'QueryUsable',~isempty(features{k,m}), ...
            'Winner',string(bestUser),'BestDistance',bestDist,'RunnerUp',string(info.RunnerUpUser), ...
            'RunnerUpDistance',info.RunnerUpDistance,'MarginRatio',info.Margin, ...
            'DistanceThreshold',p.dtwThreshold,'RequiredMargin',p.dtwMarginRatio, ...
            'BaselineConfident',confident,'FolderLabelTop1',string(bestUser)==labels(k), ...
            'ConfidenceRule',"original ID standalone gate; no name/coupon/business transaction"); %#ok<AGROW>
        for rank=1:5
            candidate=""; score=Inf;
            if rank<=numel(order) && isfinite(scores(rank))
                candidate=users(order(rank)); score=scores(rank);
            end
            topRows{end+1}=struct('RecordingIndex',k,'Path',paths(k),'Role',roles(k), ...
                'Phrase',phrases(k),'FolderLabel',labels(k),'Mode',modes(m), ...
                'Rank',rank,'Candidate',candidate,'Score',score, ...
                'Available',strlength(candidate)>0); %#ok<AGROW>
        end
    end
    fprintf('Ranking audit %d/%d\n',k,N);
end
tStruct = vertcat(topRows{:}); top5 = struct2table(tStruct(:));
dStruct = vertcat(distanceRows{:}); distances = struct2table(dStruct(:));
oStruct = vertcat(outcomeRows{:}); outcomes = struct2table(oStruct(:));
writetable(top5,fullfile(outputRoot,'top5.csv'));
writetable(distances,fullfile(outputRoot,'template_distances.csv'));
writetable(outcomes,fullfile(outputRoot,'outcomes.csv'));
assert(height(top5)==N*2*5 && all(isinf(distances.Distance(distances.ExcludedSameRecording))), ...
    'baseline_audit:contract','Top-five completeness or self-exclusion failed.');

% Export every plotted sample/mask before rendering. This also permits plotting
% the MATLAB-generated diagnostics in a separate low-memory process with -nojvm.
target=find(ismember(labels,["2206149","2206150"]) & phrases=="ID");
stageRows=cell(numel(target),1); stageIndex=0;
for k=target'
    [raw,fs]=audioread(paths(k));
    [resampled,fo]=rational_resample_audio(raw(:),fs,p.processingFs,p.resample);
    [gainAudio,~]=agc_normalize(resampled,p.agc);
    [denoised,~]=spectral_subtract_noise(gainAudio,fo,p.noise);
    stageIndex=stageIndex+1;
    stageRows{stageIndex}=struct('RecordingIndex',k,'Path',char(paths(k)), ...
        'Label',char(labels(k)),'Take',get_name(paths(k)),'InputFs',fs,'ProcessingFs',fo, ...
        'Raw',raw,'Resampled',resampled,'Agc',gainAudio,'Denoised',denoised, ...
        'Endpoint',diagnostics{k,2}.Endpoint,'ArchivedEndpoint',diagnostics{k,1}.Endpoint, ...
        'ArchivedFeatures',features{k,1},'LiveFeatures',features{k,2}); %#ok<AGROW>
end
stageSnapshot=vertcat(stageRows{:});
save(fullfile(outputRoot,'stage_snapshot.mat'),'stageSnapshot','-v7');

% Figures preserve the measurements, rather than decorating a claimed diagnosis.
if usejava('jvm')
f=figure('Visible','off','Position',[40 40 1300 850]);
tiledlayout(numel(target),2,'TileSpacing','compact');
for k=target'
    [raw,fs]=audioread(paths(k));
    nexttile; plot((0:numel(raw)-1)/fs,raw(:),'Color',[.35 .35 .4]); hold on;
    ep=diagnostics{k,1}.Endpoint;
    xline((ep.StartSample-1)/p.processingFs,'g'); xline(ep.EndSample/p.processingFs,'r');
    title(sprintf('%s ID %s | raw, stored endpoint',labels(k),get_name(paths(k))),'Interpreter','none');
    ylabel('amplitude'); xlim([0 size(raw,1)/fs]);
    nexttile; imagesc(features{k,1}); axis xy;
    title(sprintf('MFCC: %d frames, %.2f s retained',size(features{k,1},2),numel(audioOut{k,1})/p.processingFs));
    ylabel('coefficient');
end
xlabel('frame / seconds');
exportgraphics(f,fullfile(outputRoot,'id_149_150_waveforms_features.png'),'Resolution',140); close(f);

f=figure('Visible','off','Position',[40 40 1300 800]); tiledlayout(2,1);
for m=1:2
    nexttile; rows=outcomes.Phrase=="ID" & outcomes.Mode==modes(m);
    o=outcomes(rows,:); bar(categorical(compose('%s #%d',o.FolderLabel,o.RecordingIndex)), ...
        [o.BestDistance,o.RunnerUpDistance]); hold on; yline(p.dtwThreshold,'r--','threshold');
    title(sprintf('Original baseline %s: nearest two ID distances; self excluded',modes(m)),'Interpreter','none');
    ylabel('mean DTW distance'); legend('winner','runner-up','Location','bestoutside');
end
exportgraphics(f,fullfile(outputRoot,'id_ranked_distances.png'),'Resolution',140); close(f);

% Per-file STFT and VAD expose whether a discriminating suffix is retained.
for k=target'
    [raw,fs]=audioread(paths(k));
    [resampled,fo]=rational_resample_audio(raw(:),fs,p.processingFs,p.resample);
    [gainAudio,~]=agc_normalize(resampled,p.agc);
    [denoised,~]=spectral_subtract_noise(gainAudio,fo,p.noise);
    ep=diagnostics{k,2}.Endpoint;
    f=figure('Visible','off','Position',[40 40 1100 850]); tiledlayout(4,1,'TileSpacing','compact');
    nexttile; plot((0:numel(raw)-1)/fs,raw(:)); title(sprintf('%s ID %s: raw WAV',labels(k),get_name(paths(k))),'Interpreter','none');
    nexttile; spectrogram(denoised,hamming(256),192,512,fo,'yaxis'); title('Live-route denoised spectrogram');
    nexttile; t=(0:numel(ep.Energy)-1)*p.endpoint.HopDuration;
    plot(t,ep.Energy); hold on; yline(ep.EnergyThreshold,'r--');
    stairs(t,double(ep.ActiveMask)*max(ep.Energy),'Color',[.1 .6 .1]);
    xline((ep.StartSample-1)/fo,'g'); xline(ep.EndSample/fo,'r');
    title('Endpoint energy, threshold, retained mask');
    nexttile; plot(t,ep.Zcr); hold on; yline(ep.ZcrLow,'r--'); yline(ep.ZcrHigh,'r--');
    title('Zero-crossing rate and admitted band'); xlabel('seconds');
    exportgraphics(f,fullfile(outputRoot,sprintf('diagnostic_%s_ID_%s.png',labels(k),get_name(paths(k)))),'Resolution',140); close(f);
end
else
    fprintf('No JVM: stage_snapshot.mat is ready for external rendering of MATLAB diagnostics.\n');
end

for k=1:height(sourceManifest)
    assert(hash_file(sourceManifest.Path(k))==sourceManifest.SHA256(k), ...
        'baseline_audit:sourceMutation','Preserved code/config changed during run.');
end
for k=1:N
    assert(hash_file(paths(k))==hashes(k),'baseline_audit:audioMutation','Input audio changed during run.');
end
summary=struct('StartedUTC',string(started),'FinishedUTC',string(datetime('now','TimeZone','UTC')), ...
    'MatlabVersion',version,'SourceRoot',sourceRoot,'OutputRoot',outputRoot, ...
    'PathCount',height(inventory),'UniqueRecordings',N,'EnrollmentRecordings',sum(roles=="enrollment"), ...
    'CandidateRecordings',sum(roles=="candidate_only"),'Top5Rows',height(top5), ...
    'TemplateDistanceRows',height(distances),'SourceAndAudioHashesUnchanged',true, ...
    'LabelProvenance','Folder names only; no independent speaker/transcript adjudication', ...
    'ExactLiveIncidentReproduced',false);
fid=fopen(fullfile(outputRoot,'run_summary.json'),'w');
fprintf(fid,'%s',jsonencode(summary,PrettyPrint=true)); fclose(fid);
disp(summary);
fprintf('BASELINE_AUDIT_CONTRACT_PASS: five rows/query/mode, exact self exclusion, original scorer agreement, immutable inputs.\n');
end

function restore_environment(oldPwd,oldPath)
cd(oldPwd); path(oldPath);
end

function value = getfield_or(s,key,fallback)
if isfield(s,key), value=s.(key); else, value=fallback; end
end

function name=get_name(file)
[~,name,~]=fileparts(file); name=char(name);
end

function value=hash_file(file)
fid=fopen(char(file),'rb'); assert(fid>=0,'baseline_audit:read','Cannot read %s',file);
cleanup=onCleanup(@() fclose(fid)); %#ok<NASGU>
bytes=fread(fid,Inf,'*uint8');
digest=System.Security.Cryptography.SHA256.Create();
hashed=uint8(digest.ComputeHash(bytes)); digest.Dispose();
value=string(lower(reshape(dec2hex(hashed,2)',1,[])));
end
