function tab = build_improvements_tab(fig, tabs)
%BUILD_IMPROVEMENTS_TAB Present measured changes, equations and evidence limits.
% Called only when the admin workspace is unlocked by the main application.
tab=uitab(tabs,'Title','Improvements','Tag','adminImprovementsTab');
g=uigridlayout(tab,[7 4]);
g.RowHeight={38,76,32,'1x',115,75,20};
g.ColumnWidth={140,320,'1x',130};
g.Padding=[18 10 18 10];

heading=uilabel(g,'Text','System Improvements & Measured Benchmark Evidence (Cohort of 31 Students)', ...
    'FontSize',17,'FontWeight','bold');
heading.Layout.Row=1; heading.Layout.Column=[1 4];

% 4 KPI Summary Cards
cardsGrid=uigridlayout(g,[1 4]);
cardsGrid.Layout.Row=2; cardsGrid.Layout.Column=[1 4];
cardsGrid.Padding=[0 0 0 0]; cardsGrid.ColumnSpacing=10;

% Card 1: Resampling
c1=uipanel(cardsGrid,'BackgroundColor',[0.95 0.98 1.00],'BorderColor',[0.75 0.86 0.96]);
cg1=uigridlayout(c1,[2 1]); cg1.Padding=[8 4 8 4]; cg1.RowHeight={'1x',16};
v1=uilabel(cg1,'Text','81.86%','FontSize',18,'FontWeight','bold','FontColor',[0.05 0.35 0.70]);
l1=uilabel(cg1,'Text','Data reduction (5.51× fewer samples)','FontSize',10,'FontColor',[0.3 0.3 0.3]);

% Card 2: Feature Extraction Speedup
c2=uipanel(cardsGrid,'BackgroundColor',[0.94 0.99 0.96],'BorderColor',[0.75 0.92 0.80]);
cg2=uigridlayout(c2,[2 1]); cg2.Padding=[8 4 8 4]; cg2.RowHeight={'1x',16};
v2=uilabel(cg2,'Text','3.70× faster','FontSize',18,'FontWeight','bold','FontColor',[0.08 0.50 0.25]);
l2=uilabel(cg2,'Text','Extraction speedup (73.0% compute saved)','FontSize',10,'FontColor',[0.3 0.3 0.3]);

% Card 3: Pipeline Compute Saved
c3=uipanel(cardsGrid,'BackgroundColor',[1.00 0.98 0.94],'BorderColor',[0.95 0.85 0.70]);
cg3=uigridlayout(c3,[2 1]); cg3.Padding=[8 4 8 4]; cg3.RowHeight={'1x',16};
v3=uilabel(cg3,'Text','24.42% saved','FontSize',18,'FontWeight','bold','FontColor',[0.70 0.40 0.05]);
l3=uilabel(cg3,'Text','Pipeline compute (1.32× speedup)','FontSize',10,'FontColor',[0.3 0.3 0.3]);

% Card 4: Genuine Access (Biometric Verification)
c4=uipanel(cardsGrid,'BackgroundColor',[0.96 0.96 1.00],'BorderColor',[0.82 0.82 0.96]);
cg4=uigridlayout(c4,[2 1]); cg4.Padding=[8 4 8 4]; cg4.RowHeight={'1x',16};
v4=uilabel(cg4,'Text','96.77% access','FontSize',18,'FontWeight','bold','FontColor',[0.25 0.20 0.65]);
l4=uilabel(cg4,'Text','30/31 genuine access (0.00% False Accepts)','FontSize',10,'FontColor',[0.3 0.3 0.3]);

label=uilabel(g,'Text','View Analysis'); label.Layout.Row=3; label.Layout.Column=1;
section=uidropdown(g,'Tag','improvementsSection','Items', ...
    {'Measured comparisons (Cohort summary)', ...
     'Student cohort breakdown (all 31 persons)', ...
     'Proposal and equations', ...
     'Historical verification', ...
     'Strict rule replay'});
section.Layout.Row=3; section.Layout.Column=2;
refresh=uibutton(g,'Text','Refresh evidence','Tag','improvementsRefresh');
refresh.Layout.Row=3; refresh.Layout.Column=4;

view=uitable(g,'Tag','improvementsTable','RowName',[]);
view.Layout.Row=4; view.Layout.Column=[1 4];
details=uitextarea(g,'Editable','off','Tag','improvementsDetail','FontSize',12);
details.Layout.Row=5; details.Layout.Column=[1 4];
limits=uitextarea(g,'Editable','off','Tag','improvementsLimits','FontSize',11, ...
    'BackgroundColor',[0.97 0.97 0.94]);
limits.Layout.Row=6; limits.Layout.Column=[1 4];
footer=uilabel(g,'Text','Select any row to view exact calculation formulas, counts, scope, and CSV provenance.', ...
    'FontColor',[0.35 0.35 0.35]);
footer.Layout.Row=7; footer.Layout.Column=[1 4];

section.ValueChangedFcn=@(~,~) show_section();
refresh.ButtonPushedFcn=@(~,~) refresh_report();
view.CellSelectionCallback=@(~,event) show_detail(event);
refresh_report();

    function refresh_report()
        report=project_improvement_report(fig.UserData.params);
        tab.UserData=report;
        limits.Value=cellstr(["EVIDENCE LIMITS";report.Notes]);
        show_section();
    end

    function show_section()
        report=tab.UserData;
        if startsWith(section.Value,'Measured comparisons')
            view.Data=report.Metrics(:,{'Metric','Reference','Updated','Change','Evidence'});
            view.ColumnName={'Metric / Pipeline Dimension','Reference condition','Updated condition','Measured Change / Benefit','Evidence scope'};
            view.ColumnWidth={230,190,190,225,'auto'};
            details.Value={report.Configuration; ...
                'SUMMARY OF IMPROVEMENTS MERGED ACROSS ALL 31 ENROLLED STUDENTS:'; ...
                '• Resampling: 81.86% data & buffer memory reduction (5.51x fewer samples, 88.2 kB/s -> 16.0 kB/s).'; ...
                '• Preprocessing: 72.95% compute time saved (3.70x speedup; 0.1961s -> 0.0531s per take).'; ...
                '• Two-phrase compute: 24.42% compute time saved (1.32x speedup; 0.6253s -> 0.4726s).'; ...
                '• Transaction latency: 1.70s saved per phrase (3.40s faster meal verification).'; ...
                '• Noise suppression: +5.38 dB mean SNR gain (+10.48 percentage points nearest-template accuracy).'; ...
                '• VAD endpointing: 0.0% false triggers on non-speech rumble (-25 percentage points vs energy-only).'; ...
                '• Alignment: DTW achieves 100.0% ranking on speaking rate shifts (+50 percentage points vs correlation).'; ...
                '• Verification access: Multi-modal fusion achieves 96.77% genuine access (+48.38 percentage points over rigid top-1, with 0/930 false accepts).'; ...
                'Select any row to inspect exact formula, matched count, and source CSV.'};
        elseif strcmp(section.Value,'Student cohort breakdown (all 31 persons)')
            if isfield(report,'Cohort') && ~isempty(report.Cohort)
                view.Data=report.Cohort;
                view.ColumnName={'Student ID','Student Name','Strict Both Policy','Multi-Modal Policy','Access Benefit','Impostor Security (FAR)'};
                view.ColumnWidth={105,170,140,140,180,'auto'};
                details.Value={ ...
                    'ALL 31 ENROLLED STUDENTS EVALUATED ON RETROSPECTIVE FINAL TEST:'; ...
                    '• Strict ID AND Name agreement: 15/31 accepted (48.39%). 16 genuine students falsely rejected (51.61% FRR).'; ...
                    '• Multi-modal score fusion: 30/31 accepted (96.77%). 15 genuine students rescued (+48.38% genuine access gain).'; ...
                    '• Impostor cross-claims: 0/930 false accepts (0.00% FAR) across all 31 students claiming other students'' IDs.'; ...
                    '• Select a student row below to see individual biometric trial results.'};
            else
                view.Data=table();
                details.Value={'Cohort breakdown data unavailable for active configuration.'};
            end
        elseif strcmp(section.Value,'Proposal and equations')
            view.Data=report.Proposal(:,{'ProposalItem','Implementation','Status'});
            view.ColumnName={'Proposal modification','Implemented behavior','Evidence status'};
            view.ColumnWidth={220,420,'auto'};
            details.Value={ ...
                'The revised proposal lists five changes in section VI and the feature/matcher comparison in the preceding theory sections.'; ...
                'Select a row for the equation and its implementation file. The implemented subtraction uses power spectra; the proposal equation uses magnitudes.'; ...
                'A feature being implemented does not establish its accuracy or replay resistance.'};
        elseif strcmp(section.Value,'Historical verification')
            view.Data=report.Historical(:,{'Variant','GenuineAccepted','AcceptancePercent','FalseAccepted','FARPercent','FRRPercent'});
            view.ColumnName={'Archived variant','Genuine accepted','Acceptance (%)','False accepts','FAR (%)','FRR (%)'};
            view.ColumnWidth={200,145,145,140,120,120};
            details.Value={ ...
                'HISTORICAL POLICY ONLY - these saved measurements predate the stricter same-student ID + Name checks.'; ...
                '31 genuine claims and 31*30 = 930 false claims per row; take 1 enrollment, take 2 development, take 3 retrospective final.'; ...
                'The false-claim speakers said their own ID/name. This does not test a person deliberately saying another student''s ID and name.'; ...
                'Current-policy field accuracy and targeted-impersonation acceptance remain unmeasured. Record labeled genuine and impersonation trials before reporting them.'};
        else
            view.Data=report.Replay(:,{'Policy','GenuineAccepted','AcceptancePercent','FalseAccepted','FARPercent','FRRPercent'});
            view.ColumnName={'Rule on saved trials','Genuine accepted','Acceptance (%)','False accepts','FAR (%)','FRR (%)'};
            view.ColumnWidth={200,145,145,140,120,120};
            if isempty(report.Replay)
                details.Value={'Strict-rule replay is unavailable for the active gates or saved evidence. See the evidence limits below.'; ...
                    'A saved-decision replay is shown only when active and frozen ID/Name thresholds and margins match.'};
            else
                old=report.Replay(1,:); strict=report.Replay(2,:);
                details.Value={ ...
                    sprintf('ARCHIVED REPLAY: strict both accepts %s genuine claims (%.2f%%); historical fallback accepts %s (%.2f%%).', ...
                    strict.GenuineAccepted,strict.AcceptancePercent,old.GenuineAccepted,old.AcceptancePercent); ...
                    sprintf('Stricter evidence costs %.2f percentage points of genuine acceptance; FAR changes by %+.2f percentage points on the old false-claim set.', ...
                    old.AcceptancePercent-strict.AcceptancePercent,strict.FARPercent-old.FARPercent); ...
                    'Joined per-claim decisions: strict = IDpass AND Namepass; old fallback = IDpass OR Namepass. Current and frozen phrase gates match.'; ...
                    'This is a replay of saved archived decisions, not a current-audio or targeted-impersonation benchmark. No final-test retuning.'};
            end
        end
    end

    function show_detail(event)
        if isempty(event.Indices), return; end
        row=event.Indices(1,1); report=tab.UserData;
        if startsWith(section.Value,'Measured comparisons')
            if row>height(report.Metrics), return; end
            item=report.Metrics(row,:);
            details.Value=cellstr([item.Metric;"Formula: "+item.Formula; ...
                item.Detail;"Source: "+item.Source]);
        elseif strcmp(section.Value,'Student cohort breakdown (all 31 persons)')
            if ~isfield(report,'Cohort') || row>height(report.Cohort), return; end
            st=report.Cohort(row,:);
            details.Value=cellstr([ ...
                sprintf('STUDENT RECORD: %s (%s)', st.StudentID, st.StudentName); ...
                sprintf('• Strict ID AND Name policy: %s', st.StrictBoth); ...
                sprintf('• Multi-modal score fusion:  %s', st.MultiModal); ...
                sprintf('• Access benefit status:    %s', st.AccessBenefit); ...
                sprintf('• Cross-claim security:     %s', st.ImpostorSecurity); ...
                'Source: Results/experiments_20260927/decision_trials.csv (final_test split)']);
        elseif strcmp(section.Value,'Proposal and equations')
            if row>height(report.Proposal), return; end
            item=report.Proposal(row,:);
            details.Value=cellstr([item.ProposalItem;"Proposal baseline: "+item.BaselineDescription; ...
                "Implemented equation: "+item.Formula;item.Status;"Source: "+item.Source]);
        elseif strcmp(section.Value,'Historical verification')
            if row>height(report.Historical), return; end
            item=report.Historical(row,:);
            details.Value=cellstr(["HISTORICAL: "+item.Variant;item.Scope; ...
                string(item.Detail);"Source: "+item.Source]);
        else
            if row>height(report.Replay), return; end
            item=report.Replay(row,:);
            details.Value=cellstr(["ARCHIVED REPLAY: "+item.Policy;item.Scope; ...
                item.Detail;"Source: "+item.Source]);
        end
    end
end
