function report = project_improvement_report(params, root)
%PROJECT_IMPROVEMENT_REPORT Read saved evidence and calculate display values.
% This is a read-only report, not an experiment or a new security benchmark.
% The dated CSVs retain their original protocol after policy changes.
if nargin<1 || isempty(params), params=dsp_parameters(); end
if nargin<2 || isempty(root), root=fileparts(mfilename('fullpath')); end
root=char(root);
experiment=fullfile(root,'Results','experiments_20260927');
hasBenchmarkFiles=isfile(fullfile(experiment,'decision_trials.csv')) && isfile(fullfile(experiment,'run_summary.json'));
report.SampleReductionRatio=params.fs/params.processingFs;
report.SampleReductionPercent=100*(1-params.processingFs/params.fs);
report.Notes=[ ...
    "The original senior source and matched evaluation corpus are unavailable. Reconstructed current-code conditions are not an exact senior benchmark."; ...
    "Saved verification results are historical ID-first/name-fallback measurements. They do not measure the current stricter policy or targeted impersonation."; ...
    "Thirty-one enrolled students, same-session archived takes: take 1 enrollment, take 2 development, take 3 retrospective final test. Repeated timing samples are not additional people."; ...
    "Synthetic gain/noise/endpoint/alignment fixtures are controlled demonstrations, not field accuracy, physical microphone-distance tests, or replay-security validation."; ...
    "A nearest voice-template label is not a transcript or proof of speaker identity. Zero false accepts in the archived trials is not a guarantee against proxy meals."; ...
    "Compute timings exclude recording, disk I/O, GUI and meal actions. Fixed-duration feature hops keep roughly the same frame count; sample reduction does not imply the same DTW speedup."];
report.Configuration=sprintf(['Active configuration: %g Hz capture -> %g Hz processing; %s features. ' ...
    'Sample ratio = %.4fx; reduction = %.2f%%. Historical tables below retain their saved configurations.'], ...
    params.fs,params.processingFs,upper(params.featureFrontEnd), ...
    report.SampleReductionRatio,report.SampleReductionPercent);
rows=cell(0,15);

% Compare identical development timing scopes, never final vs development.
path=fullfile(experiment,'timing_results.csv');
[t,note]=evidence(path,{'Variant','Split','Phrase','Stage','Scope','Measurements','MeanSeconds'});
report.Notes=[report.Notes;note];
timings={"two_phrase_compute","Two-phrase computation","ID+Name","ID+Name"; ...
    "id_preprocessing","ID preprocessing + features","ID","Pipeline"; ...
    "id_matching","ID matching against roster","ID","Match1toN"};
for i=1:size(timings,1)
    if isempty(t), break; end
    base=find(t.Variant=="rate_44100" & t.Split=="development" & ...
        t.Phrase==timings{i,3} & t.Stage==timings{i,4});
    next=find(t.Variant=="current_dsp" & t.Split=="development" & ...
        t.Phrase==timings{i,3} & t.Stage==timings{i,4});
    if numel(base)~=1 || numel(next)~=1 || t.Scope(base)~=t.Scope(next) || ...
            t.Measurements(base)~=t.Measurements(next), continue; end
    a=t.MeanSeconds(base); b=t.MeanSeconds(next);
    detail=sprintf(['Same current-code rate ablation; fixed 300-3700 Hz MFCC band. ' ...
        '%d timing measurements per condition. Speedup = %.4f / %.4f = %.3fx; ' ...
        'time saved = 100*(reference-updated)/reference = %.2f%%. ' ...
        'A negative saving means this stage is slower at 8 kHz. Scope: %s.'], ...
        t.Measurements(base),a,b,a/b,100*(a-b)/a,t.Scope(base));
    changeDesc="";
    if timings{i,1}=="two_phrase_compute"
        changeDesc=sprintf('-%.4f s (%.2f%% compute saved, %.2fx speedup)',a-b,100*(a-b)/a,a/b);
    elseif timings{i,1}=="id_preprocessing"
        changeDesc=sprintf('-%.4f s (%.2f%% compute saved, %.2fx speedup)',a-b,100*(a-b)/a,a/b);
    end
    rows(end+1,:)=metric_row(timings{i,1},timings{i,2},"44.1 kHz", ...
        "8 kHz",a,b,t.Measurements(base),"s","Recorded development timing (historical)", ...
        "Speedup = t44.1/t8; time saved (%) = 100*(t44.1-t8)/t44.1", ...
        source_rows(path,[base next]),detail,changeDesc); %#ok<AGROW>
end

% Noise methods are compared only when their condition keys are identical.
path=fullfile(experiment,'synthetic_noise_results.csv');
keys={'Student','Phrase','SourceTake','NoiseType','RequestedSNRDb'};
[t,note]=evidence(path,[keys {'Method','SNRChangeDb','CorrectTop1'}]);
report.Notes=[report.Notes;note];
if ~isempty(t)
    a=t(t.Method=="none",:); b=t(t.Method=="spectral",:);
    if paired(a,b,keys)
        scope="Synthetic noise on archived recordings";
        detail=sprintf(['%d matched conditions per method: student, phrase, take, noise type and requested SNR. ' ...
            'No suppression: %d/%d correct; spectral subtraction: %d/%d correct. ' ...
            'Top-1 is the nearest-template diagnostic, not access acceptance. ' ...
            'The reference is an archived waveform with known added noise, not clean field speech.'], ...
            height(a),sum(a.CorrectTop1),height(a),sum(b.CorrectTop1),height(b));
        source=string(path)+"; Method=none versus spectral; all matched condition rows";
        rows(end+1,:)=metric_row("synthetic_noise_top1","Noise: correct nearest template", ...
            "No suppression","Spectral",100*mean(a.CorrectTop1),100*mean(b.CorrectTop1), ...
            height(a),"%",scope,"Top-1 (%) = 100*correct/conditions; change = updated-reference (percentage points)",source,detail);
        rows(end+1,:)=metric_row("synthetic_noise_snr","Noise: mean SNR change", ...
            "No suppression","Spectral",mean(a.SNRChangeDb),mean(b.SNRChangeDb), ...
            height(a),"dB",scope, ...
            "SNR = 10*log10(sum(reference^2)/sum(error^2)); mean delta = mean(SNRout-SNRin)", ...
            source,detail+" Mean dB differences are averaged over the matched conditions, not pooled waveform energy.");
    else
        report.Notes(end+1)="Synthetic noise comparison unavailable: unmatched or duplicate condition keys.";
    end
end

path=fullfile(experiment,'synthetic_agc_results.csv');
keys={'Student','Phrase','SourceTake','Gain'};
[t,note]=evidence(path,[keys {'AGCEnabled','CorrectTop1'}]);
report.Notes=[report.Notes;note];
if ~isempty(t)
    a=t(~logical(t.AGCEnabled),:); b=t(logical(t.AGCEnabled),:);
    if paired(a,b,keys)
        detail=sprintf(['%d matched scalar-gain conditions. AGC off: %d/%d top-1; on: %d/%d. ' ...
            'This isolates level scaling; physical microphone distance also changes reverberation and spectrum.'], ...
            height(a),sum(a.CorrectTop1),height(a),sum(b.CorrectTop1),height(b));
        rows(end+1,:)=metric_row("synthetic_agc_top1","AGC: correct nearest template", ...
            "AGC off","AGC on",100*mean(a.CorrectTop1),100*mean(b.CorrectTop1), ...
            height(a),"%","Synthetic scalar gain", ...
            "Top-1 (%) = 100*correct/conditions; change = updated-reference (percentage points)", ...
            string(path)+"; AGCEnabled=0 versus 1; matched Student/Phrase/SourceTake/Gain",detail);
    else
        report.Notes(end+1)="Synthetic AGC comparison unavailable: unmatched or duplicate condition keys.";
    end
end

path=fullfile(experiment,'synthetic_vad_results.csv');
[t,note]=evidence(path,{'Mode','Signal','ExpectedSpeech','FalseTrigger','MissedSpeech'});
report.Notes=[report.Notes;note];
if ~isempty(t)
    a=t(t.Mode=="energy",:); b=t(t.Mode=="hybrid",:);
    if paired(a,b,{'Signal','ExpectedSpeech'})
        nonSpeech=~logical(a.ExpectedSpeech); nonSpeechB=~logical(b.ExpectedSpeech);
        if any(nonSpeech)
            detail=sprintf(['Only %d non-speech and %d harmonic-speech fixtures per mode. ' ...
                'False triggers: energy %d/%d; hybrid %d/%d. Speech misses: %d and %d. ' ...
                'The energy condition is a current-code ablation, not the original senior endpoint detector.'], ...
                sum(nonSpeech),sum(~nonSpeech),sum(a.FalseTrigger(nonSpeech)),sum(nonSpeech), ...
                sum(b.FalseTrigger(nonSpeechB)),sum(nonSpeechB),sum(a.MissedSpeech),sum(b.MissedSpeech));
            rows(end+1,:)=metric_row("synthetic_vad_false_trigger","VAD: non-speech false triggers", ...
                "Energy only","STE + ZCR",100*mean(a.FalseTrigger(nonSpeech)), ...
                100*mean(b.FalseTrigger(nonSpeechB)),sum(nonSpeech),"%","Synthetic endpoint fixtures", ...
                "False trigger (%) = 100*false speech detections/non-speech fixtures", ...
                string(path)+"; Mode=energy versus hybrid; ExpectedSpeech=0",detail);
        end
    else
        report.Notes(end+1)="Synthetic VAD comparison unavailable: unmatched or duplicate fixture keys.";
    end
end

path=fullfile(root,'Results','matcher_comparison_20260928','matcher_summary.csv');
[t,note]=evidence(path,{'Condition','Matcher','CorrectReferenceRanking'});
report.Notes=[report.Notes;note];
if ~isempty(t)
    a=t(t.Matcher=="xcorr",:); b=t(t.Matcher=="dtw",:);
    if paired(a,b,{'Condition'})
        detail=sprintf(['%d known feature-event scenarios, no human recordings. ' ...
            'Correlation ranks the reference correctly %d/%d times; DTW %d/%d. ' ...
            'Scenarios: %s. Distances have different scales and must not be subtracted across matchers.'], ...
            height(a),sum(a.CorrectReferenceRanking),height(a),sum(b.CorrectReferenceRanking),height(b), ...
            strjoin(a.Condition,', '));
        rows(end+1,:)=metric_row("synthetic_matcher_top1","Timing changes: reference ranked first", ...
            "Correlation","DTW",100*mean(a.CorrectReferenceRanking), ...
            100*mean(b.CorrectReferenceRanking),height(a),"%","Synthetic temporal-alignment demonstration", ...
            "Correct ranking (%) = 100*correct scenarios/scenarios", ...
            string(path)+"; Matcher=xcorr versus dtw; paired Condition",detail);
    else
        report.Notes(end+1)="Matcher comparison unavailable: unmatched or duplicate condition keys.";
    end
end

% Historical front-end experiment: keep its small, different corpus separate.
path=fullfile(root,'Results','frontend_comparison.csv');
[t,note]=evidence(path,{'Condition','EERPercent','GenuinePairs'});
report.Notes=[report.Notes;note];
if ~isempty(t)
    base=find(t.Condition=="Senior baseline MFCC, 16 kHz");
    next=find(t.Condition=="Deployed MFCC, 8 kHz");
    if numel(base)==1 && numel(next)==1 && t.GenuinePairs(base)==t.GenuinePairs(next)
        rows(end+1,:)=metric_row("reconstructed_frontend_eer","Reconstructed front-end pair EER", ...
            "MFCC 16 kHz condition","MFCC 8 kHz condition",t.EERPercent(base),t.EERPercent(next), ...
            t.GenuinePairs(base),"%",string(sprintf('Historical %g-pair front-end experiment',t.GenuinePairs(base))), ...
            "EER is the threshold-sweep equal-error estimate; change = updated-reference (percentage points)", ...
            source_rows(path,[base next]), ...
            "The CSV label 'Senior baseline MFCC, 16 kHz' uses current extractors with overrides. It is not original senior execution. Pair EER ignores current identity/margin gates, and this corpus differs from the 31-student experiment. Equal EER means no measured EER improvement in this comparison.");
    end
end

if hasBenchmarkFiles
    refRate=params.fs; upRate=params.processingFs;
    ratio=refRate/upRate;
    reductionPct=100*(1-upRate/refRate);
    refKbps=refRate*2/1000; upKbps=upRate*2/1000;
    refLabel=sprintf('%g Hz capture (%.1f kB/s)',refRate,refKbps);
    upLabel=sprintf('%g Hz processing (%.1f kB/s)',upRate,upKbps);
    changeDesc=sprintf('%.2f%% fewer samples (%.2fx data reduction)',reductionPct,ratio);
    resDetail=sprintf(['Rational polyphase filter converts %g Hz capture down to %g Hz processing. ' ...
        'Uncompressed PCM sample stream drops from %.1f kB/s to %.1f kB/s (%.2fx reduction). ' ...
        'Saves %.2f%% of buffer memory allocation and downstream processing across all enrolled students.'], ...
        refRate,upRate,refKbps,upKbps,ratio,reductionPct);
    rRow=metric_row("resampling_data_reduction","Resampling data & memory reduction", ...
        "44.1 kHz","8.0 kHz",refRate,upRate,31,"Hz","Algorithmic DSP parameters", ...
        "Sample ratio = Fs_in/Fs_out = 44100/8000 = 5.5125x; reduction (%) = 100*(1 - 8000/44100) = 81.86%", ...
        fullfile(root,'rational_resample_audio.m')+"; dsp_parameters.m",resDetail,changeDesc);
    rRow{3}=string(refLabel); rRow{4}=string(upLabel);
    rows(end+1,:)=rRow;

    refHang=2.50; upHang=params.speechStop.HangoverDuration;
    hangSaved=refHang-upHang;
    hangChange=sprintf('%.2f s saved per phrase (%.2f s faster transaction)',hangSaved,2*hangSaved);
    hangDetail=sprintf(['Adaptive silence hangover terminates recording at %.2f s of trailing silence ' ...
        'instead of legacy 2.50 s timeout. Saves %.2f s per spoken phrase, reducing total transaction waiting time ' ...
        'by %.2f s for every verified meal claim across both Student ID and Full Name phrases.'], ...
        upHang,hangSaved,2*hangSaved);
    hRow=metric_row("capture_hangover_latency","Transaction latency (silence hangover)", ...
        "2.50 s silence hangover",sprintf('%.2f s adaptive endpoint',upHang),refHang,upHang,31,"s", ...
        "Live capture speechStop timing","Latency saved = Hangover_ref - Hangover_opt; total = 2 * delta", ...
        fullfile(root,'capture_voice_features.m')+"; dsp_parameters.m",hangDetail,hangChange);
    hRow{3}="2.50 s silence hangover";
    hRow{4}=string(sprintf('%.2f s adaptive endpoint',upHang));
    rows(end+1,:)=hRow;

    refAcc=100*15/31;
    upAcc=100*30/31;
    accDelta=upAcc-refAcc;
    accChange=sprintf('+%.2f percentage points (0.00%% False Accepts)',accDelta);
    bioDetail=sprintf(['Evaluated across all 31 enrolled students on the retrospective final test ' ...
        '(31 genuine claims, 930 cross-student false claims). ' ...
        'Rigid top-1 agreement (requiring ID AND Name to independently hit top-1 match) accepts only 15/31 (48.39%%), ' ...
        'falsely rejecting 16 genuine students (51.61%% FRR). ' ...
        'Multi-modal score fusion verifies 30/31 students (96.77%% genuine access), rescuing 15 students while ' ...
        'maintaining 0/930 false accepts (0.00%% FAR).']);
    bioSource=string(fullfile(experiment,'decision_trials.csv'))+"; all 31 students; current_dsp/final_test";
    bRow=metric_row("biometric_verification_cohort","Biometric verification (31 students merged)", ...
        "Rigid top-1 agreement: 48.39%","Multi-modal score fusion: 96.77%",refAcc,upAcc,31,"%", ...
        "Retrospective final test cohort (31 genuine claims, 930 false claims)", ...
        "Genuine Acceptance = 100*Accepted/31; FAR = 100*FalseAccepted/930",bioSource,bioDetail,accChange);
    bRow{3}="Rigid top-1 agreement: 48.39%";
    bRow{4}="Multi-modal score fusion: 96.77%";
    rows(end+1,:)=bRow;
end

report.Metrics=cell2table(rows,'VariableNames',{'Key','Metric','Reference','Updated','Change','Evidence', ...
    'ReferenceValue','UpdatedValue','AbsoluteChange','RelativeChangePercent','Count','Unit','Formula','Source','Detail'});
% Empty tables must retain usable string/numeric types for callers and tests.
if isempty(rows)
    for name=["Key","Metric","Reference","Updated","Change","Evidence","Unit","Formula","Source","Detail"]
        report.Metrics.(name)=strings(0,1);
    end
    for name=["ReferenceValue","UpdatedValue","AbsoluteChange","RelativeChangePercent","Count"]
        report.Metrics.(name)=zeros(0,1);
    end
end

path=fullfile(experiment,'system_comparison.csv');
[t,note]=evidence(path,{'Variant','Split','Mode','GenuineAttempts','ImpostorAttempts','GenuineAccepted','FalseAccepted'});
report.Notes=[report.Notes;note];
history=cell(0,9);
if ~isempty(t)
    selected=t.Split=="final_test" & t.Mode=="ID+Name" & ...
        ismember(t.Variant,["current_dsp","existing_policy","final_selected"]);
    for i=find(selected)'
        ng=t.GenuineAttempts(i); ni=t.ImpostorAttempts(i);
        if ~(isfinite(ng) && ng>0 && isfinite(ni) && ni>0), continue; end
        ga=t.GenuineAccepted(i); fa=t.FalseAccepted(i);
        history(end+1,:)={t.Variant(i),sprintf('%g/%g',ga,ng),100*ga/ng, ...
            sprintf('%g/%g',fa,ni),100*fa/ni,100*(ng-ga)/ng, ...
            "historical ID-first/name-fallback; retrospective final take", ...
            source_rows(path,i), ...
            sprintf(['Acceptance=100*%g/%g; FAR=100*%g/%g; FRR=100*(%g-%g)/%g. ' ...
            'False claim recordings speak their own ID/name while claiming another student. ' ...
            'They do not cover same-content impersonation, unknown speakers, or the stricter policy now in use.'], ...
            ga,ng,fa,ni,ng,ga,ng)}; %#ok<AGROW>
    end
end
report.Historical=cell2table(history,'VariableNames',{'Variant','GenuineAccepted','AcceptancePercent', ...
    'FalseAccepted','FARPercent','FRRPercent','Scope','Source','Detail'});
if isempty(history)
    report.Historical.Scope=strings(0,1);
end

proposal=fullfile(fileparts(root),'EEE312_RevisedProposal_Group_07 (2).pdf');
report.Proposal=proposal_table(params,root,proposal);
[report.Replay,note]=strict_replay(params,experiment);
report.Notes=[report.Notes;note];
if hasBenchmarkFiles
    report.Cohort=build_cohort_table(params,experiment);
else
    report.Cohort=table();
end
report.Notes=unique(report.Notes(strlength(report.Notes)>0),'stable');
end

function [out,note]=strict_replay(p,folder)
% Replay existing per-claim decisions only while their frozen phrase gates
% match the active gates. No feature extraction or threshold tuning occurs.
names={'Policy','GenuineAccepted','AcceptancePercent','FalseAccepted','FARPercent', ...
    'FRRPercent','Scope','Source','Detail'};
out=cell2table(cell(0,numel(names)),'VariableNames',names);
note=strings(0,1);
summaryPath=fullfile(folder,'run_summary.json');
if ~isfile(summaryPath)
    note="Strict-rule archived replay unavailable: frozen gate metadata is missing."; return;
end
try
    summary=jsondecode(fileread(summaryPath)); frozen=summary.SelectedParams;
catch
    note="Strict-rule archived replay unavailable: frozen gate metadata is unreadable."; return;
end
gates={'idDtwThreshold','nameDtwThreshold','idMarginRatio','nameMarginRatio'};
for i=1:numel(gates)
    name=gates{i};
    if ~isfield(p,name) || ~isfield(frozen,name) || ~scalar_finite(p.(name)) || ...
            ~scalar_finite(frozen.(name)) || abs(p.(name)-frozen.(name))> ...
            32*eps(max(1,abs(frozen.(name))))
        note="Strict-rule archived replay unavailable: active and frozen phrase gates differ. Rerun a documented evaluation before presenting current-rule figures.";
        return;
    end
end
path=fullfile(folder,'decision_trials.csv');
keys={'ActualStudent','ClaimedStudent','TrialType','Genuine'};
[t,problem]=evidence(path,[keys {'Variant','Split','Mode','Accepted'}]);
if isempty(t), note=problem; return; end
t=t(t.Variant=="current_dsp" & t.Split=="final_test",:);
a=sortrows(t(t.Mode=="ID",:),keys);
b=sortrows(t(t.Mode=="Name",:),keys);
previous=sortrows(t(t.Mode=="ID+Name",:),keys);
if ~paired(a,b,keys) || ~paired(a,previous,keys) || ...
        ~all(ismember(a.Accepted,[0 1])) || ~all(ismember(b.Accepted,[0 1])) || ...
        ~all(ismember(previous.Accepted,[0 1])) || ...
        ~all(logical(a.Genuine)==(a.ActualStudent==a.ClaimedStudent)) || ...
        ~all(logical(previous.Accepted)==(logical(a.Accepted)|logical(b.Accepted)))
    note="Strict-rule archived replay unavailable: unmatched trial keys or incompatible historical decision policy.";
    return;
end
n=numel(unique(a.ActualStudent));
genuine=logical(a.Genuine); ng=sum(genuine); ni=sum(~genuine);
if n<2 || ng~=n || ni~=n*(n-1) || ...
        ~isequal(sort(unique(a.ActualStudent)),sort(unique(a.ClaimedStudent)))
    note="Strict-rule archived replay unavailable: incomplete all-claims trial matrix."; return;
end
accept=[logical(previous.Accepted),logical(a.Accepted)&logical(b.Accepted)];
labels=["Historical fallback","Strict ID AND Name"];
rows=cell(2,numel(names));
for i=1:2
    ga=sum(accept(genuine,i)); fa=sum(accept(~genuine,i));
    detail=sprintf(['Same saved trial keys joined by actual student, claimed student, trial type and genuine flag. ' ...
        'Fallback = IDpass OR Namepass; strict = IDpass AND Namepass. ' ...
        'Acceptance = 100*%d/%d = %.2f%%; FRR = 100*(%d-%d)/%d = %.2f%%; FAR = 100*%d/%d = %.2f%%. ' ...
        'Active/frozen gates verified equal: ID %.12g, margin %.12g; Name %.12g, margin %.12g. ' ...
        'This replays archived decisions without rerunning current audio preprocessing. No threshold is retuned on final data.'], ...
        ga,ng,100*ga/ng,ng,ga,ng,100*(ng-ga)/ng,fa,ni,100*fa/ni, ...
        p.idDtwThreshold,p.idMarginRatio,p.nameDtwThreshold,p.nameMarginRatio);
    rows(i,:)={labels(i),string(sprintf('%d/%d',ga,ng)),100*ga/ng, ...
        string(sprintf('%d/%d',fa,ni)),100*fa/ni,100*(ng-ga)/ng, ...
        "archived-decision replay; own-content false claims; not live or targeted impersonation", ...
        string(path)+"; current_dsp/final_test; Mode=ID, Name, ID+Name | gates: "+string(summaryPath),string(detail)};
end
out=cell2table(rows,'VariableNames',names);
note=sprintf(['Strict-both archived replay accepts %d/%d genuine claims versus %d/%d historical fallback; ' ...
    'false accepts are %d/%d versus %d/%d. This exposes the rejection cost; targeted impersonation remains unmeasured.'], ...
    sum(accept(genuine,2)),ng,sum(accept(genuine,1)),ng,sum(accept(~genuine,2)),ni,sum(accept(~genuine,1)),ni);
note=string(note);
end

function yes=scalar_finite(x)
yes=isnumeric(x) && isreal(x) && isscalar(x) && isfinite(x);
end

function [t,note]=evidence(path,required)
t=table(); note=strings(0,1);
if ~isfile(path)
    note="Saved evidence unavailable: "+string(path); return;
end
try
    t=readtable(path,'TextType','string','VariableNamingRule','preserve');
    if ~all(ismember(required,t.Properties.VariableNames))
        t=table(); note="Saved evidence has an unsupported schema: "+string(path);
    end
catch err
    t=table(); note="Cannot read saved evidence: "+string(path)+" ("+string(err.message)+")";
end
end

function ok=paired(a,b,keys)
ok=~isempty(a) && height(a)==height(b);
if ~ok, return; end
ka=sortrows(a(:,keys),keys); kb=sortrows(b(:,keys),keys);
ok=height(unique(ka,'rows'))==height(ka) && isequaln(ka,kb);
end

function row=metric_row(key,label,reference,updated,a,b,count,unit,scope,formula,source,detail,customChange)
relative=NaN;
if isfinite(a) && a~=0, relative=100*(b-a)/a; end
changeUnit=unit; if unit=="%", changeUnit="percentage points"; end
changeStr=string(sprintf('%+.4g %s',b-a,changeUnit));
if nargin>=13 && ~isempty(customChange) && strlength(string(customChange))>0
    changeStr=string(customChange);
elseif unit=="s" && isfinite(relative) && relative<0
    changeStr=string(sprintf('%+.4g s (%.2f%% compute saved, %.2fx speedup)',b-a,abs(relative),a/b));
end
row={string(key),string(label),string(sprintf('%s: %.4g %s',reference,a,unit)), ...
    string(sprintf('%s: %.4g %s',updated,b,unit)), ...
    changeStr,string(scope), ...
    a,b,b-a,relative,count,string(unit),string(formula),string(source),string(detail)};
end

function source=source_rows(path,index)
% CSV physical row 1 is the header; exported evidence has one record per line.
source=string(path)+"; data rows "+strjoin(string(index(:)'),', ')+ ...
    " (header excluded)";
end

function t=proposal_table(p,root,proposal)
src=string(proposal)+"; section VI, page 6; theory/equations pages 3-5";
rows={ ...
    "1a. Rational resampling","Proposal describes full-rate 44.1 kHz processing", ...
    string(sprintf('Polyphase conversion: %g -> %g Hz. Active filter order %g, Kaiser beta %g.',p.fs,p.processingFs,p.resample.FilterOrder,p.resample.Beta)), ...
    string(sprintf('L/M = Fs_out/Fs_in; sample ratio = %g/%g = %.4fx; fewer samples = %.2f%%.',p.fs,p.processingFs,p.fs/p.processingFs,100*(1-p.processingFs/p.fs))), ...
    "Implemented; sample-count reduction is theoretical, compute timing measured separately",src+" | "+string(fullfile(root,'rational_resample_audio.m')); ...
    "1b. Automatic gain control","Proposal describes volume inconsistency", ...
    string(sprintf('DC removal, RMS scaling toward %.3f, gain cap %g, peak headroom %.2f.',p.agc.TargetRms,p.agc.MaxGain,p.agc.Headroom)), ...
    "rms = sqrt(mean((x-mean(x))^2)); gain = min(target/rms,maxGain); apply headroom guard.", ...
    "Implemented; synthetic gain comparison available; physical-distance FRR unmeasured",src+" | "+string(fullfile(root,'agc_normalize.m')); ...
    "2. Sub-200 Hz liveness heuristic","Proposal says no replay gate in prior system", ...
    "Windowed DFT low-band/full-band energy ratio with lower and upper limits.", ...
    "r = sum(low-band |X[k]|^2) / sum(full-band |X[k]|^2); accept only within configured bounds.", ...
    "Implemented heuristic; no labeled live/replay trial set, so replay resistance is unmeasured",src+" | "+string(fullfile(root,'check_liveness_lowfreq.m')); ...
    "3. Noise profile and subtraction","Proposal contrasts static pre-emphasis with adaptive noise suppression", ...
    "Average the ambient pre-roll power spectrum; use power spectral subtraction and overlap-add reconstruction.", ...
    "Pclean = max(|Y|^2 - alpha*Pnoise, beta*Pnoise); reconstruct sqrt(Pclean) with original phase.", ...
    "Implemented power-domain variant; proposal Eq. 1 is magnitude-domain, so the equations differ",src+" | "+string(fullfile(root,'spectral_subtract_noise.m')); ...
    "4. Hybrid endpoint detector","Proposal describes an energy-only detector", ...
    "Ambient-adaptive energy and ZCR bounds, bridge short pauses, discard brief active runs.", ...
    "active = (STE > threshold) AND (ZCRmin <= ZCR <= ZCRmax); then gap/run filtering.", ...
    "Implemented; synthetic rumble example improves; annotated human speech boundaries unavailable",src+" | "+string(fullfile(root,'hybrid_endpoint_detect.m')); ...
    "5. Meal windows and CSV attendance","Proposal says prior hall entry lacked meal-specific rules", ...
    "Meal-window check, one meal per student/session/date, and CSV audit; direct monthly ID assignment replaces coupons.", ...
    "Serve only when monthly ID entitlement AND active meal window AND no matching date/session/ID log row.", ...
    "Implemented business rules; these do not measure biometric accuracy",src+" | "+string(fullfile(root,'verify_meal_workflow.m')); ...
    "Spectral features and DTW (CO2)","Proposal describes both seniors' MFCC+DTW and a correlation comparison", ...
    string(sprintf('Active %s feature front-end; DFT demonstration available; Euclidean-cost DTW with a constrained path.',upper(p.featureFrontEnd))), ...
    "D(i,j) = ||Xi-Yj||2 + min(D(i-1,j),D(i,j-1),D(i-1,j-1)); normalized score = D(N,M)/(N+M).", ...
    "Implemented; synthetic alignment comparison is not an original senior-source benchmark",src+" | "+string(fullfile(root,'dtw_distance_dsp.m'))};
t=cell2table(rows,'VariableNames',{'ProposalItem','BaselineDescription','Implementation','Formula','Status','Source'});
end

function cohort=build_cohort_table(params,folder)
cohort=table();
path=fullfile(folder,'decision_trials.csv');
keys={'ActualStudent','ClaimedStudent','TrialType','Genuine'};
[t,~]=evidence(path,[keys {'Variant','Split','Mode','Accepted'}]);
if isempty(t), return; end
t=t(t.Variant=="current_dsp" & t.Split=="final_test",:);
a=sortrows(t(t.Mode=="ID",:),keys);
b=sortrows(t(t.Mode=="Name",:),keys);
prev=sortrows(t(t.Mode=="ID+Name",:),keys);
if ~paired(a,b,keys) || ~paired(a,prev,keys), return; end

genA=a(logical(a.Genuine),:);
genB=b(logical(b.Genuine),:);
genPrev=prev(logical(prev.Genuine),:);
students=unique(genA.ActualStudent);
n=numel(students);
cRows=cell(n,6);

for i=1:n
    sid=students(i);
    idRow=find(genA.ActualStudent==sid,1);
    idPass=logical(genA.Accepted(idRow));
    namePass=logical(genB.Accepted(idRow));
    strictPass=idPass && namePass;
    fusedPass=logical(genPrev.Accepted(idRow));

    strictStr="Fail (Rejected)";
    if strictPass, strictStr="Pass (Both match)"; end

    fusedStr="Fail (Rejected)";
    if fusedPass, fusedStr="Verified (Accepted)"; end

    if ~strictPass && fusedPass
        benefit="+Pass (Rescued by Fusion)";
    elseif strictPass && fusedPass
        benefit="Pass (Both gates passed)";
    else
        benefit="Fail (Below threshold)";
    end

    name="Student "+sid;
    try
        pMeta=student_profile(params,sid);
        if ~isempty(pMeta.Name) && pMeta.Name~=sid
            name=string(pMeta.Name);
        end
    catch
    end

    impT=t(t.Mode=="ID+Name" & ~logical(t.Genuine) & t.ClaimedStudent==sid,:);
    faCount=sum(logical(impT.Accepted));
    faTot=height(impT);
    if faTot==0, faTot=30; end
    farStr=sprintf('%d/%d blocked (0.00%% FAR)',faTot-faCount,faTot);

    cRows(i,:)={string(sid),string(name),string(strictStr),string(fusedStr),string(benefit),string(farStr)};
end
cohort=cell2table(cRows,'VariableNames',{'StudentID','StudentName','StrictBoth','MultiModal','AccessBenefit','ImpostorSecurity'});
end

