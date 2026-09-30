function tables=experiment_synthetic_stress(train,development,users,p,outputDir,makePlots) %#ok<INUSD>
%EXPERIMENT_SYNTHETIC_STRESS Controlled perturbations, NEVER field evidence.
% Uses enrollment/development only; does not select features or thresholds.
% Reference-relative SNR treats an archived waveform (including its existing
% noise) as the reference. It is not a clean-speech or measured field SNR.
assert(all(train.Role=="enrollment") && all(development.Role=="development"), ...
    'experiment:stressLeakage','Synthetic stress accepts enrollment/development only.');
oldRng=rng; restoreRng=onCleanup(@() rng(oldRng)); rng(312,'twister'); %#ok<NASGU>
users=string(users(:)); ar=cell(0,14); nr=cell(0,17);
for enabled=[false true]
    q=p; q.agc.Enable=enabled;
    libs=enrollment_libraries(train,users,q);
    for i=1:height(development)
        row=development(i,:); [x,fs]=read_mono(row.Path);
        library=libs{1+double(row.Phrase=="Name")};
        for gain=[.1 .3 1]
            scaled=gain*x; [~,ag]=agc_normalize(scaled,q.agc);
            [f,dg]=enrol_template_features(scaled,fs,q);
            [genuine,impostor,correct]=scores(library,f,row.Student,q);
            ar(end+1,:)={row.Student,row.Phrase,row.Take,gain,enabled, ...
                ag.InputRms,ag.OutputRms,ag.Gain,genuine,impostor,correct, ...
                logical(dg.Usable),"synthetic gain", ...
                "scalar attenuation; no physical distance; archived preprocessing"}; %#ok<AGROW>
        end
    end
end
% Suppression is measured on a constructed noise-only pre-roll. The archived
% speech segment is the reference. The exact same noise realization is used
% for all three suppression methods in a condition.
q=p; q.noise.Method='none'; q.noise.Enable=false;
libs=enrollment_libraries(train,users,q); example=struct();
for i=1:height(development)
    row=development(i,:); [x,fsIn]=read_mono(row.Path);
    [x,fs]=rational_resample_audio(x,fsIn,p.processingFs,p.resample);
    x=x-mean(x); pre=round((p.noise.NoiseDuration+2*p.noise.FrameDuration)*fs);
    clean=[zeros(pre,1);x;zeros(round(.15*fs),1)]; segment=pre+(1:numel(x));
    referenceFeatures=extract_features(x,fs,p);
    library=libs{1+double(row.Phrase=="Name")};
    for noiseType=["white","lowpass_colored","sparse_impulses"]
        z=randn(size(clean));
        if noiseType=="lowpass_colored", z=filter(1,[1 -.92],z); end
        if noiseType=="sparse_impulses"
            z=z.*(rand(size(z))<.01);
            if ~any(z(segment)), z(segment(round(end/2)))=1; end
        end
        for requested=[5 15]
            noise=z*sqrt(mean(x.^2)/(mean(z(segment).^2)*10^(requested/10)));
            noisy=clean+noise; inputSnr=snr_relative(x,noisy(segment));
            for method=["none","spectral","wiener"]
                opts=p.noise; opts.Enable=true; opts.Method=char(method);
                [y,~]=spectral_subtract_noise(noisy,fs,opts);
                outputSnr=snr_relative(x,y(segment));
                f=extract_features(y(segment),fs,p);
                stability=dtw_distance_dsp(referenceFeatures,f,p.dtw);
                [query,dg]=enrol_template_features(y(segment),fs,q);
                [genuine,impostor,correct]=scores(library,query,row.Student,q);
                nr(end+1,:)={row.Student,row.Phrase,row.Take,noiseType,method,requested, ...
                    inputSnr,outputSnr,outputSnr-inputSnr,stability,genuine,impostor, ...
                    correct,logical(dg.Usable),"synthetic additive noise", ...
                    "archived waveform reference; known added noise; not field SNR",312}; %#ok<AGROW>
                if i==1 && noiseType=="white" && requested==5
                    example.Fs=fs; example.Reference=clean; example.Noisy=noisy;
                    example.(char(method))=y; example.SpeechSamples=segment;
                    example.Student=row.Student; example.Phrase=row.Phrase;
                end
            end
        end
    end
end
tables.synthetic_agc_results=cell2table(ar,'VariableNames', ...
    {'Student','Phrase','SourceTake','Gain','AGCEnabled','InputRms','OutputRms', ...
    'AppliedGain','GenuineDistance','NearestImpostorDistance','CorrectTop1','Usable','EvidenceType','Limitation'});
tables.synthetic_noise_results=cell2table(nr,'VariableNames', ...
    {'Student','Phrase','SourceTake','NoiseType','Method','RequestedSNRDb','InputSNRDb', ...
    'OutputSNRDb','SNRChangeDb','ReferenceFeatureDistance','GenuineDistance', ...
    'NearestImpostorDistance','CorrectTop1','Usable','EvidenceType','Limitation','Seed'});
[tables.synthetic_vad_results,vadExamples]=vad_fixtures(p);
if ~isfolder(outputDir), mkdir(outputDir); end
save(fullfile(outputDir,'synthetic_examples.mat'),'example','vadExamples');
end

function libs=enrollment_libraries(train,users,p)
libs=cell(2,1); phrases=["ID","Name"];
for ph=1:2
    library=struct('Users',users,'Templates',{cell(numel(users),1)});
    for s=1:numel(users)
        rows=train(train.Student==users(s) & train.Phrase==phrases(ph),:);
        assert(height(rows)==1,'experiment:stressEnrollment','Expected one take1 template per phrase.');
        [x,fs]=read_mono(rows.Path); library.Templates{s}={enrol_template_features(x,fs,p)};
    end
    libs{ph}=library;
end
end

function [genuine,impostor,correct]=scores(library,f,student,p)
[~,~,info]=voice_match_scores(library,f,p);
genuine=Inf; impostor=Inf; correct=false;
if numel(info.Scores)==numel(library.Users)
    ix=library.Users==student; genuine=info.Scores(ix); impostor=min(info.Scores(~ix));
    correct=~isempty(info.BestUser) && string(info.BestUser)==student && isfinite(info.BestDistance);
end
end

function [t,examples]=vad_fixtures(p)
fs=p.processingFs; n=round(2.5*fs); time=(0:n-1)'/fs;
first=round(.7*fs)+1; last=round(1.8*fs); mask=false(n,1); mask(first:last)=true;
tone=.12*(sin(2*pi*140*time)+.45*sin(2*pi*280*time)+.2*sin(2*pi*700*time));
voiced=tone.*mask; rumble=.15*sin(2*pi*12*time).*mask;
impulse=zeros(n,1); impulse(round(fs))=.9;
noise=.04*randn(n,1); fixtures={zeros(n,1),voiced,rumble,impulse,noise};
names=["silence","voiced_harmonics","low_frequency_rumble","single_impulse","stationary_white_noise"];
rows=cell(0,13); examples=struct('Fs',fs,'Time',time,'Signals',{fixtures},'Names',names,'SpeechMask',mask);
for i=1:numel(fixtures)
    expected=i==2;
    for mode=["energy","hybrid"]
        opts=p.endpoint; opts.Mode=char(mode); opts.ZcrReferenceFs=8000;
        [~,d]=hybrid_endpoint_detect(fixtures{i},fs,opts);
        start=NaN; stop=NaN; retained=NaN; truncated=NaN;
        if d.HasSpeech, start=(d.StartSample-1)/fs; stop=d.EndSample/fs; end
        if expected
            overlap=0;
            if d.HasSpeech, overlap=max(0,min(last,d.EndSample)-max(first,d.StartSample)+1); end
            retained=overlap/(last-first+1); truncated=(last-first+1-overlap)/fs;
        end
        rows(end+1,:)={mode,names(i),expected,logical(d.HasSpeech),start,stop,retained, ...
            logical(~expected && d.HasSpeech),logical(expected && ~d.HasSpeech),truncated, ...
            "synthetic endpoint fixture", ...
            "known inserted harmonic interval; no human speech annotations or field classes",312}; %#ok<AGROW>
    end
end
t=cell2table(rows,'VariableNames',{'Mode','Signal','ExpectedSpeech','HasSpeech', ...
    'StartSeconds','EndSeconds','RetainedSpeechFraction','FalseTrigger','MissedSpeech', ...
    'SpeechTruncationSeconds','EvidenceType','Limitation','Seed'});
end

function [x,fs]=read_mono(path)
[x,fs]=audioread(path); if size(x,2)>1, x=mean(x,2); end
x=double(x(:));
end

function value=snr_relative(reference,signal)
value=10*log10(sum(reference.^2)/max(sum((signal-reference).^2),realmin));
end
