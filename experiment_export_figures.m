function manifest=experiment_export_figures(tables,freeze,currentRecords,finalRecords, ...
    enrollment,finalId,finalName,users,outputDir)
%EXPERIMENT_EXPORT_FIGURES Export measured MATLAB figures, or data without JVM.
% Missing experiments are listed as unavailable, never drawn as zero bars.
save(fullfile(outputDir,'figure_data.mat'),'tables','freeze','currentRecords', ...
    'finalRecords','enrollment','finalId','finalName','users');
titles=["Architecture and evidence boundary";"Sampling-rate candidates"; ...
    "Measured processing time";"Measured processing time saved"; ...
    "Archived-recording AGC RMS";"Synthetic gain and genuine DTW distance"; ...
    "Synthetic noise suppression waveform";"Synthetic noise suppression spectrum"; ...
    "Synthetic reference-relative SNR";"Current energy and STE+ZCR endpoint fixtures"; ...
    "MFCC feature representation";"Genuine and impostor pair distances"; ...
    "Development threshold curves";"Final claimed-identity outcome matrix"; ...
    "149/150 diagnostic evidence";"ID-only, Name-only and combined decisions"; ...
    "Liveness live versus replay";"Development ablation study"];
manifest=table((1:18)',titles,repmat("unavailable",18,1),strings(18,1),strings(18,1), ...
    'VariableNames',{'Figure','Title','Status','Path','Note'});
hasSynthetic=isfile(fullfile(outputDir,'synthetic_examples.mat'));
can=[true;sum(tables.sampling_rate_results.Status=="measured_development")>1;true;true;true; ...
    isfield(tables,'synthetic_agc_results');hasSynthetic;hasSynthetic;isfield(tables,'synthetic_noise_results'); ...
    isfield(tables,'synthetic_vad_results');~isempty(finalRecords);true;true;true; ...
    isfield(tables,'pair_distances') && all(ismember(["2206149","2206150"],string(users)));true;false;true];
manifest.Note(2)="Requires more than one measured sampling-rate candidate.";
manifest.Note(6:10)="Requires separate synthetic stress measurements; field-condition evidence is unavailable.";
manifest.Note(15)="Requires final 150 query distances to enrolled 149 and 150 references; full decisions are in the separate deployment audit.";
manifest.Note(17)="No labeled live/replay corpus: replay accuracy cannot be plotted.";
if ~usejava('jvm')
    manifest.Status(can)="data_saved_no_jvm";
    manifest.Path(can)="figure_data.mat";
    manifest.Note(can)="Graphics skipped: MATLAB JVM unavailable. Rerun experiment_export_figures from saved figure_data.mat in graphics-enabled MATLAB.";
    writetable(manifest,fullfile(outputDir,'figure_manifest.csv'));
    fprintf('Graphics skipped (no JVM); measurements saved in figure_data.mat.\n');
    return;
end
if hasSynthetic, synthetic=load(fullfile(outputDir,'synthetic_examples.mat')); else, synthetic=struct(); end
figDir=fullfile(outputDir,'figures'); if ~isfolder(figDir), mkdir(figDir); end
for i=find(can)'
    fig=[];
    try
        fig=figure('Visible','off','Color','w','Position',[80 80 1180 740], ...
            'Name',char(titles(i)),'DefaultAxesFontName','Arial','DefaultAxesFontSize',11, ...
            'DefaultTextInterpreter','none','DefaultAxesTickLabelInterpreter','none', ...
            'DefaultLegendInterpreter','none');
        draw_figure(i,tables,freeze,finalRecords,users,synthetic);
        filename=sprintf('%02d_%s.png',i,char(regexprep(lower(titles(i)),'[^a-z0-9]+','_')));
        exportgraphics(fig,fullfile(figDir,filename),'Resolution',180);
        manifest.Status(i)="exported"; manifest.Path(i)=string(fullfile('figures',filename));
        manifest.Note(i)="Measured data; scope and units are stated in the figure.";
    catch err
        manifest.Status(i)="export_failed"; manifest.Note(i)=string(err.message);
        warning('experiment:figureExport','Figure %d: %s',i,err.message);
    end
    if ~isempty(fig) && isgraphics(fig), close(fig); end
end
writetable(manifest,fullfile(outputDir,'figure_manifest.csv'));
end

function draw_figure(i,t,f,records,users,s)
switch i
    case 1
        axis([0 1 0 1]); axis off;
        text(.05,.93,'Voice-based meal verification: implemented evidence path','FontSize',19,'FontWeight','bold');
        boxes={.06,.61,'Archived take1','Enrollment templates';.37,.61,'ID once, first','Quality → DSP → MFCC → DTW'; ...
            .37,.30,'Name once, if ID fails','Quality → DSP → MFCC → DTW'; ...
            .72,.46,'Accepting phrase','Claim + distance + runner-up margin'};
        for k=1:size(boxes,1)
            x=boxes{k,1}; y=boxes{k,2}; rectangle('Position',[x y .25 .16], ...
                'Curvature',.05,'FaceColor',[.91 .95 .98],'EdgeColor',[.15 .35 .52],'LineWidth',1.5);
            text(x+.125,y+.105,boxes{k,3},'HorizontalAlignment','center','FontWeight','bold','FontSize',12);
            text(x+.125,y+.045,boxes{k,4},'HorizontalAlignment','center','FontSize',9);
        end
        text(.06,.245,'ID success ends verification; otherwise Name once. If Name also fails: FAILED.','FontSize',11);
        text(.06,.19,'Live capture: ambient-adaptive speech end, up to 8 seconds. No microphone accuracy measured here.','FontSize',11);
        text(.06,.15,"Frozen candidate: "+f.Variant,'FontSize',12,'FontWeight','bold');
        text(.06,.11,'take1 enrollment → take2 selection → freeze → take3 final. Retrospective archived recordings.','FontSize',11);
        text(.06,.05,'Senior original source absent. Live microphone and replay performance are not established.','FontSize',11,'Color',[.55 .2 .1]);
    case 2
        a=t.sampling_rate_results; a=a(a.Status=="measured_development",:);
        metric_bars(a.Variant,100*[a.GenuineAcceptance a.FAR a.FRR], ...
            sprintf('Rate candidates: development decisions (%d genuine, %d false claims each)', ...
                numel(users),numel(users)*(numel(users)-1)), ...
            'Candidate; wideband row also changes the MFCC band','Rate (%)',{'Genuine accepted','False claims accepted','Genuine rejected'});
    case {3,4}
        a=t.timing_results; a=a(a.Split=="final_test" & a.Stage=="ID+Name",:);
        if i==3
            bar(categorical(a.Variant,a.Variant),1000*a.MeanSeconds,'FaceColor',[.2 .46 .65]); hold on;
            errorbar(1:height(a),1000*a.MeanSeconds,1000*a.StdSeconds,'k.','LineWidth',1.4);
            labels('Measured ID + Name processing: mean ± SD','Frozen final-test configuration','Processing time (ms)');
        else
            metric_bars(a.Variant,a.TimeSavedPercentVsCurrent, ...
                'Measured compute time saved relative to current DSP','Final-test configuration','Time saved (%)',{});
            yline(0,'k-');
        end
    case 5
        a=t.agc_results; a=a(a.Variant==f.Variant & a.Split=="final_test",:);
        metric_bars(a.Student+" "+a.Phrase,[a.InputRms a.OutputRms], ...
            'Archived-recording capture AGC: measured RMS','Student and phrase','RMS amplitude (normalized PCM)',{'Before AGC','After AGC'});
    case 6
        a=t.synthetic_agc_results; gains=unique(a.Gain); values=zeros(numel(gains),2);
        for j=1:numel(gains)
            for enabled=0:1
                x=a.GenuineDistance(a.Gain==gains(j) & a.AGCEnabled==logical(enabled));
                x=x(isfinite(x)); values(j,enabled+1)=mean(x);
            end
        end
        metric_bars(string(gains),values,'Synthetic attenuation: genuine DTW distance (finite scores)', ...
            'Applied scalar gain (unitless; not microphone distance)','DTW distance (feature units)',{'AGC off','AGC on'});
    case 7
        x=s.example; time=(0:numel(x.Reference)-1)'/x.Fs;
        tiledlayout(3,1,'TileSpacing','compact');
        nexttile; plot(time,x.Reference,'Color',[.15 .4 .6]); labels('Archived reference waveform','Time (s)','Amplitude');
        nexttile; plot(time,x.Noisy,'Color',[.65 .3 .12]); labels('Added synthetic white noise: 5 dB relative SNR','Time (s)','Amplitude');
        nexttile; plot(time,x.spectral); hold on; plot(time,x.wiener);
        labels('Measured suppression output (synthetic condition)','Time (s)','Amplitude'); legend('Spectral subtraction','Wiener');
    case 8
        x=s.example; idx=x.SpeechSamples; n=2^nextpow2(numel(idx)); hz=(0:n/2)'*x.Fs/n;
        names=["Reference","Noisy","spectral","wiener"]; hold on;
        for name=names
            y=x.(char(name)); amp=abs(fft(y(idx),n))/numel(idx);
            plot(hz,20*log10(max(amp(1:n/2+1),1e-10)),'LineWidth',1.1);
        end
        labels('Synthetic white-noise condition: measured amplitude spectra','Frequency (Hz)','Magnitude (dB re amplitude 1)');
        legend('Archived reference','Noisy reference','Spectral subtraction','Wiener','Location','best');
    case 9
        a=t.synthetic_noise_results; types=unique(a.NoiseType,'stable'); methods=["none","spectral","wiener"];
        tiledlayout(1,2,'TileSpacing','compact');
        for target=[5 15]
            nexttile; values=zeros(numel(types),3);
            for k=1:numel(types)
                for j=1:3, values(k,j)=mean(a.OutputSNRDb(a.NoiseType==types(k) & a.Method==methods(j) & a.RequestedSNRDb==target)); end
            end
            metric_bars(types,values,sprintf('Added noise: %g dB input',target), ...
                'Synthetic noise generator','Output SNR relative to archived waveform (dB)',cellstr(methods));
        end
    case 10
        a=t.synthetic_vad_results; names=unique(a.Signal,'stable'); values=zeros(numel(names),2);
        for k=1:numel(names)
            values(k,1)=a.HasSpeech(a.Signal==names(k) & a.Mode=="energy");
            values(k,2)=a.HasSpeech(a.Signal==names(k) & a.Mode=="hybrid");
        end
        metric_bars(names,values,'Current-code endpoint tests: synthetic fixtures; original senior source absent', ...
            'Known synthetic signal','Speech trigger (0=no, 1=yes)',{'Energy only','STE + ZCR'}); ylim([0 1.15]);
    case 11
        index=find(arrayfun(@(r) ~isempty(r.Features),records),1);
        if isempty(index), error('experiment:noFeatures','No usable final feature matrix to display.'); end
        r=records(index); imagesc(r.Features); axis xy; colorbar;
        labels("Measured final features: "+r.Student+" "+r.Phrase+" / "+f.Variant, ...
            'Feature frame index','Feature dimension index');
    case 12
        tiledlayout(1,2,'TileSpacing','compact');
        for phrase=["ID","Name"]
            nexttile; a=t.pair_distances;
            a=a(a.Variant==f.Variant & a.Split=="final_test" & a.Phrase==phrase,:);
            histogram(a.Distance(a.Genuine & isfinite(a.Distance)),'Normalization','probability','FaceAlpha',.6); hold on;
            histogram(a.Distance(~a.Genuine & isfinite(a.Distance)),'Normalization','probability','FaceAlpha',.6);
            labels([phrase+": final pair distances"; ...
                sprintf('%d/%d genuine, %d/%d impostor finite',sum(a.Genuine & isfinite(a.Distance)), ...
                    sum(a.Genuine),sum(~a.Genuine & isfinite(a.Distance)),sum(~a.Genuine))], ...
                'DTW distance (feature units)','Fraction of finite pairs'); legend('Genuine','Impostor');
        end
    case 13
        tiledlayout(2,2,'TileSpacing','compact');
        for phrase=["ID","Name"]
            nexttile; a=t.pair_threshold_results;
            a=a(a.Variant==f.Variant & a.Split=="development" & a.Phrase==phrase,:);
            plot(a.Threshold,100*a.PairFAR,'LineWidth',1.8); hold on; plot(a.Threshold,100*a.PairFRR,'LineWidth',1.8);
            labels(phrase+": pair threshold only (no identity gate)",'DTW threshold (feature units)','Pair error rate (%)'); legend('Pair FAR','Pair FRR');
        end
        for phrase=["ID","Name"]
            nexttile; a=t.threshold_results; margin=f.Params.idMarginRatio;
            if phrase=="Name", margin=f.Params.nameMarginRatio; end
            a=a(a.Variant==f.Variant & a.Mode==phrase & a.Margin==margin,:);
            plot(a.Threshold,100*a.FAR,'LineWidth',1.8); hold on; plot(a.Threshold,100*a.FRR,'LineWidth',1.8);
            labels(phrase+": claim and frozen margin gates",'DTW threshold (feature units)','Decision error rate (%)'); legend('False-claim FAR','Genuine FRR');
        end
    case 14
        a=t.confusion_matrix; a=a(a.Variant=="final_selected" & a.Split=="final_test" & a.Mode=="ID+Name",:);
        outcomes=[string(users(:));"RETRY";"MULTIPLE CLAIMS"]; values=zeros(numel(users),numel(outcomes));
        for j=1:numel(users)
            for k=1:numel(outcomes), values(j,k)=sum(a.Count(a.ActualStudent==users(j) & a.Outcome==outcomes(k))); end
        end
        imagesc(values,[0 1]); colormap([1 1 1;.14 .42 .64]); colorbar;
        xticks(1:numel(outcomes)); xticklabels(outcomes); yticks(1:numel(users)); yticklabels(users);
        for j=1:numel(users)
            for k=1:numel(outcomes), text(k,j,string(values(j,k)),'HorizontalAlignment','center','FontWeight','bold'); end
        end
        labels('ID-first fallback: accepted claims for each source pair', ...
            'Accepted claim, retry, or multiple claims','Actual student');
    case 15
        tiledlayout(1,2,'TileSpacing','compact');
        candidates=["2206149";"2206150"];
        for phrase=["ID","Name"]
            nexttile; a=t.pair_distances;
            a=a(a.Variant==f.Variant & a.Split=="final_test" & ...
                a.ActualStudent=="2206150" & a.Phrase==phrase,:);
            distances=zeros(2,1);
            for j=1:2
                match=a(a.CandidateStudent==candidates(j),:);
                assert(height(match)==1 && isfinite(match.Distance), ...
                    'experiment:missing150Distance','A measured final 149/150 distance is unavailable.');
                distances(j)=match.Distance;
            end
            limit=f.Params.idDtwThreshold;
            if phrase=="Name", limit=f.Params.nameDtwThreshold; end
            metric_bars(candidates,distances,"Actual 2206150: "+phrase+" final take3", ...
                'Enrolled reference student','DTW distance (feature units)',{});
            yline(limit,'--',sprintf('Phrase ceiling %.4f',limit), ...
                'Color',[.65 .25 .12],'LineWidth',1.5,'LabelHorizontalAlignment','left');
            for j=1:2
                text(j,distances(j),sprintf('%.3f',distances(j)), ...
                    'HorizontalAlignment','center','VerticalAlignment','bottom');
            end
            ylim([0 max([distances;limit])*1.2]);
        end
        sgtitle({'Final 150 vs 149 distance diagnostics', ...
            'Verification also requires the claimed identity to win and pass its runner-up margin.'}, ...
            'FontSize',13,'Interpreter','none');
    case 16
        a=t.accuracy_results; a=a(a.Variant=="final_selected" & a.Split=="final_test",:);
        modeLabels=a.Mode; modeLabels(modeLabels=="ID+Name")="ID-first fallback";
        metric_bars(modeLabels,100*[a.GenuineAcceptance a.FAR a.FRR], ...
            sprintf('Frozen final decisions: %d genuine / %d false claims per mode', ...
                a.GenuineAttempts(1),a.ImpostorAttempts(1)), ...
            'Utterance evidence mode','Rate (%)',{'Genuine accepted','False claims accepted','Genuine rejected'});
    case 18
        a=t.ablation_results; a=a(a.Status=="measured_development",:);
        metric_bars(a.Variant,100*[a.GenuineAcceptance a.FAR], ...
            'Development ablations: selection evidence, not final-test estimates', ...
            'Declared candidate','Rate (%)',{'Genuine accepted','False claims accepted'});
end
end

function metric_bars(names,values,titleText,xText,yText,legendText)
names=string(names(:)); bar(categorical(names,names),values,'grouped');
labels(titleText,xText,yText); xtickangle(28);
if ~isempty(legendText), legend(legendText,'Location','best'); end
end

function labels(titleText,xText,yText)
title(titleText,'FontSize',14,'FontWeight','bold','Interpreter','none');
xlabel(xText,'Interpreter','none'); ylabel(yText,'Interpreter','none');
grid on; box off;
end
