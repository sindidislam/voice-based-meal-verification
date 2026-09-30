function tables=experiment_report_tables(tables,catalog,freeze,users)
%EXPERIMENT_REPORT_TABLES Summarize measured rows without inventing evidence.
% Pair threshold curves deliberately exclude candidate/claim/margin gates.
% Decision FAR/FRR remains in accuracy_results and threshold_results.
tables.accuracy_results=label_modes(tables.accuracy_results);
tables.decision_trials=label_modes(tables.decision_trials);
tables.timing_results=timing_summary(tables.timing_raw,freeze);
tables.pair_threshold_results=pair_curves(tables.pair_distances);
tables.confusion_matrix=confusion_counts(tables.decision_trials,users);
tables.ablation_results=ablation(tables.accuracy_results,catalog,freeze);
groups=tables.ablation_results.Group;
tables.feature_results=tables.ablation_results(ismember(groups, ...
    ["MFCC derivatives","CMVN","Pitch","Spectral features","RASTA","Feature weights"]),:);
tables.dtw_results=tables.ablation_results(groups=="Constrained DTW",:);
tables.sampling_rate_results=tables.ablation_results( ...
    groups=="Resampling" | tables.ablation_results.Variant=="current_dsp",:);
tables.limitations=limitations(numel(users));
% The historical senior source/corpus has not been supplied. Keep a visible
% unavailable row rather than presenting a recreated energy VAD as its score.
a=tables.accuracy_results; absent=a(1,:);
absent.Variant="senior_baseline"; absent.Split="unavailable";
absent.Mode="ID+Name"; absent.Status="unavailable: original senior implementation/corpus absent";
absent.ModeLabel="Unavailable senior baseline";
for name=string(absent.Properties.VariableNames)
    if isnumeric(absent.(name)), absent.(name)(:)=NaN; end
end
tables.accuracy_results=[a;absent];
tables.system_comparison=tables.accuracy_results( ...
    (tables.accuracy_results.Split=="final_test" & ...
    ismember(tables.accuracy_results.Variant,["existing_policy","current_dsp","final_selected"]) & ...
    tables.accuracy_results.Mode=="ID+Name") | tables.accuracy_results.Variant=="senior_baseline",:);
end

function out=timing_summary(raw,freeze)
keys=unique(raw(:,{'Variant','Split','Phrase','Stage','Scope'}),'rows','stable');
rows=cell(height(keys),12);
for i=1:height(keys)
    k=keys(i,:); mask=raw.Variant==k.Variant & raw.Split==k.Split & ...
        raw.Phrase==k.Phrase & raw.Stage==k.Stage & raw.Scope==k.Scope;
    x=raw.Seconds(mask); x=x(isfinite(x) & x>=0);
    base=raw.Seconds(raw.Variant=="current_dsp" & raw.Split==k.Split & ...
        raw.Phrase==k.Phrase & raw.Stage==k.Stage & raw.Scope==k.Scope);
    base=base(isfinite(base) & base>=0); b=mean(base); m=mean(x);
    speed=NaN; saved=NaN;
    if b>0 && m>0, speed=b/m; saved=100*(b-m)/b; end
    rows(i,:)={k.Variant,k.Split,k.Phrase,k.Stage,k.Scope,numel(x), ...
        m,median(x),std(x),b,speed,saved};
end
out=cell2table(rows,'VariableNames',{'Variant','Split','Phrase','Stage','Scope', ...
    'Measurements','MeanSeconds','MedianSeconds','StdSeconds', ...
    'CurrentMeanSeconds','SpeedupVsCurrent','TimeSavedPercentVsCurrent'});
alias=out(out.Variant==freeze.Variant & out.Split=="final_test",:);
alias.Variant(:)="final_selected"; out=[out;alias];
end

function out=pair_curves(raw)
keys=unique(raw(:,{'Variant','Split','Phrase'}),'rows','stable'); rows=cell(0,10);
for i=1:height(keys)
    k=keys(i,:); sub=raw(raw.Variant==k.Variant & raw.Split==k.Split & raw.Phrase==k.Phrase,:);
    thresholds=unique([0;sub.Distance(isfinite(sub.Distance) & sub.Distance>=0)]);
    ng=sum(sub.Genuine); ni=sum(~sub.Genuine);
    for threshold=thresholds'
        pass=isfinite(sub.Distance) & sub.Distance>=0 & sub.Distance<=threshold;
        fa=sum(pass & ~sub.Genuine); fr=sum(~pass & sub.Genuine);
        rows(end+1,:)={k.Variant,k.Split,k.Phrase,threshold,ratio(fa,ni),ratio(fr,ng), ...
            ng,ni,fa,fr}; %#ok<AGROW>
    end
end
out=cell2table(rows,'VariableNames',{'Variant','Split','Phrase','Threshold', ...
    'PairFAR','PairFRR','GenuinePairs','ImpostorPairs','FalseAcceptedPairs','FalseRejectedPairs'});
end

function out=confusion_counts(trials,users)
keys=unique(trials(:,{'Variant','Split','Mode'}),'rows','stable'); rows=cell(0,7);
users=string(users(:)); outcomes=[users;"RETRY";"MULTIPLE CLAIMS"];
for i=1:height(keys)
    k=keys(i,:); sub=trials(trials.Variant==k.Variant & trials.Split==k.Split & trials.Mode==k.Mode,:);
    for s=1:numel(users)
        accepted=unique(sub.ClaimedStudent(sub.ActualStudent==users(s) & sub.Accepted));
        outcome="RETRY";
        if numel(accepted)>1, outcome="MULTIPLE CLAIMS";
        elseif numel(accepted)==1, outcome=accepted(1); end
        for j=1:numel(outcomes)
            rows(end+1,:)={k.Variant,k.Split,k.Mode,users(s),outcomes(j), ...
                double(outcome==outcomes(j)), ...
                "accepted claim set per source pair; multiple claims remain explicit"}; %#ok<AGROW>
        end
    end
end
out=cell2table(rows,'VariableNames',{'Variant','Split','Mode','ActualStudent','Outcome','Count','Scope'});
out=label_modes(out);
end

function out=ablation(accuracy,catalog,freeze)
rows=cell(height(catalog),12);
for i=1:height(catalog)
    a=accuracy(accuracy.Variant==catalog.Variant(i) & accuracy.Split=="development" & accuracy.Mode=="ID+Name",:);
    values={NaN,NaN,NaN,NaN,NaN};
    if ~isempty(a), values={a.GenuineAcceptance,a.FAR,a.FRR,a.WSAR,a.Top1Accuracy}; end
    rows(i,:)=[{catalog.Variant(i),catalog.Group(i),catalog.Change(i),catalog.Status(i), ...
        "development",catalog.Variant(i)==freeze.Variant},values, ...
        {"ID-first fallback; recording-disjoint retrospective; own-content false claims"}];
end
out=cell2table(rows,'VariableNames',{'Variant','Group','Change','Status','Split', ...
    'Selected','GenuineAcceptance','FAR','FRR','WSAR','Top1Accuracy','Scope'});
end

function t=limitations(studentCount)
rows={ ...
    "Dataset size","limited",string(sprintf('%d enrolled students; one recording per phrase per split. Same-session takes do not establish field accuracy.',studentCount)); ...
    "Evaluation design","retrospective","Take1 enrollment, take2 development, take3 final; recordings were inspected previously, so final is not untouched prospective validation."; ...
    "Archive preprocessing","limited","All roles use enrol_template_features with archived-template preprocessing and lenient quality; clipped or cropped legacy audio may be retained. These are not live microphone accuracy measurements."; ...
    "False claims","limited","Impostors speak their own ID/name and claim another enrolled student; same-content impersonation and unknown-speaker trials are unavailable."; ...
    "Decision policy","defined","Mode ID+Name means ID-first fallback: try ID for the supplied claim, then independently gated Name if ID fails. Conflicting phrases may accept two different enumerated claims. MULTIPLE CLAIMS is one source-pair outcome, not a selected identity."; ...
    "Denominators","defined","Per variant/split/mode: N genuine claims and N(N-1) false claims. FAR and WSAR divide wrong accepted claims by N(N-1); ClosedSetWrongAccepted counts actual students with at least one false claim accepted, and ClosedSetWSAR divides that count by N. CorrectClaimIdentityErrors is the separate no-reassignment invariant. Pair FAR/FRR ignores identity/margin gates and is reported separately."; ...
    "Top-1 ranking","defined","Top1Accuracy is the raw usable ID best candidate for ID and ID-first fallback, and the raw usable Name best candidate for Name-only. Invalid evidence has no ranked candidate. This diagnostic ignores thresholds/margins and does not replace ID ranking when Name fallback succeeds."; ...
    "Senior baseline","unavailable","Original senior source and matched evaluation data are absent. Energy-only mode is a current-code ablation, not a measured senior baseline."; ...
    "Microphone distance","unavailable","No measured capture-distance labels. Synthetic scalar gains are not physical microphone distances."; ...
    "Field noise","unavailable","No quiet/fan/cafeteria/background-speech/impact condition labels or clean reference. Field SNR and condition-specific accuracy are unavailable."; ...
    "VAD ground truth","unavailable","Archived recordings have no speech-boundary annotations; speech detection, misses and truncation rates cannot be inferred. Separate synthetic fixtures have known boundaries."; ...
    "Replay security","unavailable","No labeled live/replay captures. Low-frequency heuristic outputs are diagnostics and do not establish replay resistance."; ...
    "Multi-template enrollment","supplemental","Separate retrospective leave-one-take-out scores compare one vs two enrollment templates after final evaluation; they do not select deployed thresholds."; ...
    "Historical recordings","diagnostic only","Prior unsaved live incidents cannot be reconstructed. Historical challenges are separate from any newly supplied VSD enrollment recordings."; ...
    "Synthetic stress","synthetic only","Deterministic gain, additive-noise and endpoint fixtures characterize controlled perturbations; they are not field-condition or replay evidence."; ...
    "Timing scope","limited","MATLAB wall times exclude capture, disk I/O, GUI, network and business actions. ID+Name timing sums both separately measured utterances: the full fallback path, not expected latency when ID passes immediately. Repeats characterize compute variation, not new speakers."; ...
    "Deployment","unchanged","Selected experimental parameters are saved in results only; no deployed thresholds or student/business/audio files are changed."};
t=cell2table(rows,'VariableNames',{'Topic','Status','Limitation'});
end

function t=label_modes(t)
t.ModeLabel=strings(height(t),1);
t.ModeLabel(t.Mode=="ID")="ID only";
t.ModeLabel(t.Mode=="Name")="Name only";
t.ModeLabel(t.Mode=="ID+Name")="ID-first fallback";
if ismember('Variant',t.Properties.VariableNames)
    t.ModeLabel(t.Variant=="existing_policy")="Preserved legacy policy";
end
end

function x=ratio(a,b)
x=NaN; if b>0, x=a/b; end
end
