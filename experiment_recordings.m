function [records,timing] = experiment_recordings(manifest,p,variant,repeats)
%EXPERIMENT_RECORDINGS Use the production archive-quality and feature gate.
records=struct('Student',{},'Phrase',{},'Role',{},'Path',{},'Features',{}, ...
    'Quality',{},'Diagnostics',{},'RawRms',{},'ProcessedRms',{},'PipelineSeconds',{});
timeRows=cell(0,8);
for i=1:height(manifest)
    [x,fs]=audioread(manifest.Path(i));
    if size(x,2)>1, x=mean(x,2); end
    durations=zeros(repeats,1);
    for rep=1:repeats
        clock=tic; [f,dg]=enrol_template_features(x,fs,p); durations(rep)=toc(clock);
        diag=struct();
        if isfield(dg,'Preprocess'), diag=dg.Preprocess; end
        if isfield(diag,'Timings')
            stages=fieldnames(diag.Timings);
            for j=1:numel(stages)
                timeRows(end+1,:)={variant,manifest.Role(i),manifest.Student(i),manifest.Phrase(i), ...
                    rep,string(stages{j}),diag.Timings.(stages{j}),"archive preprocessing"}; %#ok<AGROW>
            end
        end
        timeRows(end+1,:)={variant,manifest.Role(i),manifest.Student(i),manifest.Phrase(i), ...
            rep,"Pipeline",durations(rep),"quality + preprocessing + features; no disk/capture"}; %#ok<AGROW>
        if ~isempty(f)
            clock=tic; extract_features(dg.Audio,dg.Fs,p); featureSeconds=toc(clock);
            timeRows(end+1,:)={variant,manifest.Role(i),manifest.Student(i),manifest.Phrase(i), ...
                rep,"MFCC",featureSeconds,"independent repeated dispatcher measurement"}; %#ok<AGROW>
        end
    end
    processed=NaN;
    if isfield(dg,'Audio') && ~isempty(dg.Audio), processed=sqrt(mean(dg.Audio.^2)); end
    records(end+1)=struct('Student',manifest.Student(i),'Phrase',manifest.Phrase(i), ...
        'Role',manifest.Role(i),'Path',manifest.Path(i),'Features',f,'Quality',dg, ...
        'Diagnostics',diag,'RawRms',sqrt(mean(x.^2)),'ProcessedRms',processed, ...
        'PipelineSeconds',durations); %#ok<AGROW>
end
timing=cell2table(timeRows,'VariableNames',{'Variant','Split','Student','Phrase','Repeat','Stage','Seconds','Scope'});
end
