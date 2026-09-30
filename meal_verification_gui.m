function fig = meal_verification_gui(params)
%MEAL_VERIFICATION_GUI The counter application for voice-based meal verification.
%
%   MEAL_VERIFICATION_GUI() opens the single window from which the whole system is
%   operated: verifying a student at the serving counter, enrolling a new student,
%   reading the meal log, inspecting every DSP stage on a chosen signal, and running
%   the offline experiments.  FIG is the figure handle, returned so that a test can
%   build the window and close it without a human present.
%
%   MEAL_VERIFICATION_GUI(PARAMS) uses a supplied parameter struct instead of
%   DSP_PARAMETERS(), which is how a demonstration can show the same interface
%   running the proposal's DFT front-end (see SELECT_FEATURE_FRONTEND).
%
%   EEE 312 outcomes
%   ----------------
%   CO1  Every DSP stage the system runs is implemented in this project and can be
%        watched, stage by stage, on the DSP Explorer tab.
%   CO2  The Evaluation tab runs the comparisons and shows the measured tables, so
%        the theoretical expectation and the experimental result sit side by side.
%   CO3  The Verify tab exposes the designed decision as five named gates, and the
%        Enrol tab exposes the recording-quality design.
%   CO4  The Verify tab is the public-facing surface: a refusal names the gate and
%        says what the student should do, because an unexplained refusal at a dining
%        hall queue is a safety and dignity problem, not just an accuracy one.
%   CO5  The Admin tab is password gated and the log records the distances behind
%        every serving, so a disputed refusal can be audited rather than argued.
%   CO7  This window is what the user manual documents.
%   PO(a), PO(c), PO(e), PO(j), PO(l).
%
%   Why one window and not five
%   ---------------------------
%   The previous revision shipped VOICE_RECOGNITION_GUI, VOICE_RECOGNITION_GUI1,
%   GUEST_ENTRY_GUI, REGISTRATION_ENTRY_GUI and ADMIN_LOG_GUI.  Each read the
%   parameters again and wrote its own labels, and they drifted: the unified one
%   printed a footer reading "Log windows: 07-09, 12-14, 17-19" while PARAMS.meals
%   said 07:00-09:30, 12:00-14:30 and 19:00-21:30, so the interface told the operator
%   one thing and the entitlement gate did another.  Nothing in this file writes a
%   parameter value as text; every number and every window shown is formatted from
%   PARAMS at the moment it is drawn, so the interface cannot say something the
%   system does not do.
%
%   Why the enrol tab does not reuse the capture path
%   -----------------------------------------------
%   Enrolment writes a file that will be read for years, so a defect costs one
%   retake now or an unverifiable student later.  The old registration flow accepted
%   a take whenever PREPROCESS_AUDIO had not rejected it, which is the weak test that
%   let two files with no phrase in them into the corpus.  This tab asks
%   ASSESS_RECORDING_QUALITY with Strict = true -- the same question
%   ENROL_TEMPLATE_FEATURES asks of stored files, plus the pre-roll rule that only
%   makes sense while the student is still standing there.
%
%   Why there is a file-driven demo
%   ------------------------------
%   Verification starts with ID and requests a name only if ID cannot verify the
%   claim. The demo button injects features from stored enrolment files
%   through OPTIONS.IDFeatures and OPTIONS.NameFeatures that
%   VERIFY_DSP_PIPELINE uses, so the decision, the gates and the log are the real
%   ones -- only the microphone is absent.  It is labelled as a demo in the interface
%   because a grant obtained this way proves the software works, not that a person
%   was present.
%
%   See also VERIFY_MEAL_WORKFLOW, ASSESS_RECORDING_QUALITY, DIAGNOSE_AUDIO_CORPUS,
%   EXPERIMENT_VERIFICATION_ACCURACY, RUN_MEAL_SYSTEM, DSP_PARAMETERS.

if nargin < 1 || isempty(params)
    params = dsp_parameters();
end

app = struct();
app.params = params;
app.verificationActive = false;
app.stopRequested = false;
app.enrol  = struct('phrase', 'Name', 'take', 1, 'pending', [], 'pendingDg', []);
app.explorer = struct('audio', [], 'fs', NaN, 'source', '');

fig = uifigure('Name', 'Voice-Based Meal Verification System for Hall Dining', ...
    'Position', [120 60 1180 760]);
fig.UserData = app;

outer = uigridlayout(fig, [3 1]);
outer.RowHeight = {58, '1x', 26};
outer.Padding = [12 10 12 8];

title = uilabel(outer, 'Text', ...
    'Voice-Based Meal Verification System for Hall Dining');
title.FontSize = 21;
title.FontWeight = 'bold';
title.HorizontalAlignment = 'center';

tabs = uitabgroup(outer);

footer = uilabel(outer, 'Text', footer_text(params), 'Tag', 'guiFooter');
footer.HorizontalAlignment = 'center';
footer.FontColor = [0.35 0.35 0.35];

build_verify_tab(fig, tabs);
build_admin_tab(fig, tabs);
end

% =========================================================================
% Verify tab
% =========================================================================
function build_verify_tab(fig, tabs)
p = fig.UserData.params;
tab = uitab(tabs, 'Title', 'Verify Meal', 'Tag', 'publicVerifyTab');
g = uigridlayout(tab, [7 4]);
g.RowHeight = {34, 40, 46, 34, 176, '1x', 22};
g.ColumnWidth = {170, 240, 240, '1x'};
g.Padding = [20 16 20 14];

hintText = sprintf(['Press Record and Verify. Stay silent during calibration (%.2f s), ' ...
    'then say your Student ID and full name when prompted. Both recordings must verify the same student.'], ...
    p.noise.NoiseDuration);
if isfield(p,'vsd') && p.vsd.Enable
    hintText = ['Press Record and Verify, stay silent for 0.5 s, then say your Student ID and your full name ' ...
        'when prompted. Then say the three random digits shown on screen (anti-replay check). ' ...
        'Your voice and your words are both checked; imposters and recordings are refused.'];
end
statusVal = {'Ready. Voice verification is followed by the current-month dining roster check.'};
lab = uilabel(g, 'Text', ['Dining roster: ' char(string(datetime('now'),'yyyy-MM'))]);
lab.Layout.Row = 1; lab.Layout.Column = [1 2];
code = []; % Compatibility argument; coupon entry is no longer part of the UI.

window = uilabel(g, 'Text', '', 'Tag', 'verifyWindow');
window.Layout.Row = 1; window.Layout.Column = [3 4];
window.FontWeight = 'bold';
refresh_window_label(window, p);

hint = uilabel(g, 'Text', hintText);
hint.Layout.Row = 2; hint.Layout.Column = [1 4];
hint.WordWrap = 'on';

banner = uilabel(g, 'Text', 'Ready.', 'FontSize', 16, 'FontWeight', 'bold', ...
    'Tag', 'verifyBanner');
banner.Layout.Row = 3; banner.Layout.Column = [3 4];
banner.HorizontalAlignment = 'center';
banner.BackgroundColor = [0.93 0.93 0.93];

manualLabel = uilabel(g, 'Text', 'Claimed Student ID');
manualLabel.Layout.Row = 4; manualLabel.Layout.Column = 1;
manual = uieditfield(g, 'text', 'Tag', 'manualIdentity', ...
    'Placeholder', 'Optional: enter a seven-digit ID to bind both voice checks to that student');
manual.Layout.Row = 4; manual.Layout.Column = [2 3];
gates = uitable(g, 'ColumnName', {'Gate', 'Accepting or last attempted phrase', 'Verdict'}, ...
    'ColumnWidth', {150, 430, 190}, 'RowName', {}, 'Tag', 'verifyGates');
gates.Layout.Row = 5; gates.Layout.Column = [1 4];
gates.Data = gate_table('', p);

status = uitextarea(g, 'Editable', 'off', 'Tag', 'verifyStatus', 'Value', statusVal);
status.Layout.Row = 6; status.Layout.Column = [1 4];
status.FontName = 'Consolas';

note = uilabel(g, 'Text', sprintf(['Recording ends after the detected pause, up to %.0f seconds. ' ...
    'ID once and name once; conflicting matches are refused.'], p.recordDur));
note.Layout.Row = 7; note.Layout.Column = [1 4];
note.FontColor = [0.35 0.35 0.35];

live = uibutton(g, 'Text', 'Record and Verify', 'Tag', 'verifyLiveBtn');
live.Layout.Row = 3; live.Layout.Column = 1;

demo = uibutton(g, 'Text', 'Demo from files');
demo.Visible = 'off';
demo.Layout.Row = 3; demo.Layout.Column = 2;

stopBtn = uibutton(g, 'Text', 'Instant Stop', 'Tag', 'verifyStopBtn', 'Enable', 'off');
stopBtn.Layout.Row = 3; stopBtn.Layout.Column = 2;
stopBtn.BackgroundColor = [0.94 0.88 0.88];
stopBtn.FontWeight = 'bold';

live.ButtonPushedFcn = @(~,~) run_verification(fig, code, status, banner, ...
    gates, window, false, [], [], live, stopBtn);
stopBtn.ButtonPushedFcn = @(~,~) verify_stop_action(fig, status, banner, live, stopBtn);
demo.ButtonPushedFcn = @(~,~) run_verification(fig, code, status, banner, ...
    gates, window, true, [], [], live, stopBtn);

micCheckBtn = uibutton(g, 'Text', 'Mic Check', 'Tag', 'verifyMicCheckBtn');
micCheckBtn.Layout.Row = 4; micCheckBtn.Layout.Column = 4;
micCheckBtn.BackgroundColor = [0.88 0.93 0.98];
micCheckBtn.FontWeight = 'bold';
micCheckBtn.ButtonPushedFcn = @(~,~) run_mic_check_gui(fig, status, banner);
end

function run_mic_check_gui(fig, status, banner)
if isvalid(banner), banner.Text = 'Checking Mic...'; banner.BackgroundColor = [0.88 0.93 0.98]; end
update_status_text(status, '● Microphone Calibration Check started. Please speak your ID or Name at normal volume for 3.0 seconds...');
drawnow;
try
    p = fig.UserData.params;
    fs = p.fs;
    info = mic_check([], fs, false);
    lines = {
        sprintf('● MIC CHECK VERDICT: [%s]', info.Verdict), ...
        sprintf('  Peak Level:       %5.1f dBFS (Target: -18 to -3 dBFS)', info.PeakDbfs), ...
        sprintf('  Speech 95th-pct:  %5.1f dBFS', info.SpeechDbfs), ...
        sprintf('  Background Floor: %5.1f dBFS', info.FloorDbfs), ...
        sprintf('  Estimated SNR:    %5.1f dB (Target: >= 18 dB)', info.SnrDb), ...
        sprintf('  Clipping:         %5.2f%% of samples', info.ClippedPct), ...
        sprintf('  Advice: %s', info.Advice)
    };
    update_status_text(status, strjoin(lines, '\n'));
    if isvalid(banner)
        if strcmp(info.Verdict, 'GOOD')
            banner.Text = 'Mic: GOOD';
            banner.BackgroundColor = [0.85 0.95 0.85];
        else
            banner.Text = sprintf('Mic: %s', info.Verdict);
            banner.BackgroundColor = [0.98 0.92 0.85];
        end
    end
catch ME
    update_status_text(status, sprintf('● Mic Check Error: %s', ME.message));
    if isvalid(banner)
        banner.Text = 'Mic Error';
        banner.BackgroundColor = [0.95 0.85 0.85];
    end
end
end

function verify_stop_action(fig, status, banner, liveBtn, stopBtn)
if ~isvalid(fig) || ~fig.UserData.verificationActive, return; end
fig.UserData.stopRequested = true;
if isprop(status, 'UserData') && isstruct(status.UserData)
    status.UserData.stopRequested = true;
else
    status.UserData = struct('stopRequested', true);
end
update_status_text(status, '>>> INSTANT STOP PRESSED. Cancelling recording and verification...');
set_banner(banner, 'refused', 'Stopped by user');
% The running callback still owns the transaction until its cleanup executes.
% Keep cancellation visible and prevent a second transaction during unwind.
if ~isempty(liveBtn) && isvalid(liveBtn), liveBtn.Enable = 'off'; end
if ~isempty(stopBtn) && isvalid(stopBtn), stopBtn.Enable = 'off'; end
drawnow;
end

function reset_verify_controls(fig, liveBtn, stopBtn)
if nargin >= 2 && ~isempty(liveBtn) && isvalid(liveBtn)
    liveBtn.Enable = 'on';
end
if nargin >= 3 && ~isempty(stopBtn) && isvalid(stopBtn)
    stopBtn.Enable = 'off';
    stopBtn.BackgroundColor = [0.94 0.88 0.88];
    stopBtn.FontColor = [0.4 0.4 0.4];
end
if isvalid(fig)
    fig.UserData.stopRequested = false;
    fig.UserData.verificationActive = false;
end
% status.UserData.stopRequested is deliberately retained. Only the next
% authorized transaction start clears that second cancellation signal.
end

function run_verification(fig, code, status, banner, gates, window, useFiles, ...
    nameWho, couponWho, liveBtn, stopBtn)
%RUN_VERIFICATION One counter transaction, live or file driven.
if isfield(fig.UserData,'verificationActive') && fig.UserData.verificationActive
    return;
end
fig.UserData.verificationActive = true;
cleanup = onCleanup(@() reset_verify_controls(fig, liveBtn, stopBtn)); %#ok<NASGU>
if ~isempty(liveBtn) && isvalid(liveBtn), liveBtn.Enable = 'off'; end
% Clear old cancellation before any drawnow can dispatch a fresh Stop event.
fig.UserData.stopRequested = false;
if isprop(status, 'UserData') && isstruct(status.UserData)
    status.UserData.stopRequested = false;
else
    status.UserData = struct('stopRequested', false);
end
p = fig.UserData.params;
refresh_window_label(window, p);
gates.Data = gate_table('', p);
set_banner(banner, 'working', 'Working...');
status.Value = {'--- new transaction ---'};
if isfield(p,'vsd') && isstruct(p.vsd) && p.vsd.Enable
    update_status_text(status, sprintf('Engine: %s (phrase content + voice biometrics + anti-replay). Profiles: %s', ...
        p.vsd.Version, p.vsd.DataRoot));
else
    update_status_text(status, ['Engine: LEGACY v4.1.4 matcher (params.vsd.Enable = false or vsd_*.m not on the path). ' ...
        'Run RUN_ME from the "Final project v4.1.4_Final" folder to use the new engine.']);
end
drawnow;

if nargin >= 10 && ~isempty(liveBtn) && isvalid(liveBtn)
    liveBtn.Enable = 'off';
end
if nargin >= 11 && ~isempty(stopBtn) && isvalid(stopBtn)
    stopBtn.Enable = 'on';
    stopBtn.BackgroundColor = [0.95 0.35 0.35];
    stopBtn.FontColor = [1 1 1];
end
claimField = findobj(fig, 'Tag', 'manualIdentity');
options = struct();
if ~isempty(claimField) && ~isempty(strtrim(claimField.Value))
    options.ClaimedID = strtrim(char(string(claimField.Value)));
end
if useFiles && ~isempty(nameWho) && ~isempty(couponWho)
    [nameFeat, ok1] = demo_features(p, status, nameWho.Value, 'ID');
    [couponFeat, ok2] = demo_features(p, status, couponWho.Value, 'Name');
    if ~ok1 || ~ok2
        set_banner(banner, 'refused', 'Demo unavailable');
        return;
    end
    options.IDFeatures = nameFeat;
    options.NameFeatures = couponFeat;
    options.SkipLogging = true;
    if strcmp(nameWho.Value, couponWho.Value)
        update_status_text(status, sprintf(['DEMO: both phrases injected from ' ...
            'the stored files of %s. No microphone was used, so this shows the ' ...
            'decision, not that a person was present.'], nameWho.Value));
    else
        update_status_text(status, sprintf(['DEMO: ID recording from %s and fallback ' ...
            'name recording from %s. The name is evaluated only if ID fails. ' ...
            'Each accepting phrase must verify the independently entered claim.'], nameWho.Value, couponWho.Value));
    end
end

try
    result = verify_meal_workflow(status, '', p, options);
catch err
    update_status_text(status, ['ERROR: ' err.message]);
    set_banner(banner, 'refused', 'Error');
    return;
end

if (isfield(fig.UserData, 'stopRequested') && fig.UserData.stopRequested) || ...
        (isfield(result, 'Stage') && strcmp(result.Stage, 'user-stop'))
    gates.Data = gate_table(result, p);
    set_banner(banner, 'refused', 'Stopped by user');
    update_status_text(status, '● Recording cancelled by user. Press "Record and Verify" to begin again.');
    return;
end

gates.Data = gate_table(result, p);
simLabel = '';
if isfield(result, 'Similarity') && ~isnan(result.Similarity)
    simLabel = sprintf(' (%d%% match)', round(result.Similarity));
end
isVsd = isfield(result, 'Engine') && strcmp(result.Engine, 'vsd');
if isVsd && ~result.Verified && vsd_alert(result, banner, status)
    return;
end

if result.Granted
    set_banner(banner, 'granted', sprintf('SERVE %s - %s%s', ...
        result.Meal, result.Student, simLabel));
    speak_text(sprintf('Welcome %s. Get your meal.', result.Student), true);
elseif result.Verified
    set_banner(banner, 'refused', sprintf('NOT SERVED - %s', result.Student));
    update_status_text(status, result.Reason);
    reasonLower = lower(result.Reason);
    if contains(reasonLower, 'coupon') || contains(reasonLower, 'entitlement') || contains(reasonLower, 'balance') || contains(reasonLower, 'payment') || contains(reasonLower, 'fee')
        speak_text('Payment not done.', true);
    elseif contains(reasonLower, 'window') || contains(reasonLower, 'meal is being served') || contains(reasonLower, 'time') || contains(reasonLower, 'schedule')
        speak_text('Meal time is over.', true);
    else
        speak_text('Try again.', true);
    end
else
    set_banner(banner, 'refused', 'VOICE NOT VERIFIED');
    update_status_text(status, ['Please retry with your own ID and name, or ask hall administration. ' result.Reason]);
    speak_text('Verification failed. Try again.', true);
end
end

function shown = vsd_alert(result, banner, status)
%VSD_ALERT Security banners of the v4.1.4_Final engine (imposter / replay / unknown).
shown = true;
switch result.Decision
    case 'IMPOSTER'
        who = result.ImposterSuspect;
        if isfield(result,'ImposterName') && ~isempty(result.ImposterName) && ~strcmp(result.ImposterName, who)
            who = sprintf('%s (%s)', who, result.ImposterName);
        end
        set_banner(banner, 'refused', sprintf('IMPOSTER ALERT - voice matches %s', who));
        update_status_text(status, sprintf(['SECURITY: claimed identity %s, likely imposter %s. ' ...
            'Access refused and logged for the hall administration.'], result.Student, who));
        speak_text('Imposter detected. Access denied.', true);
    case 'REPLAY'
        set_banner(banner, 'refused', 'REPLAY ATTACK BLOCKED - speak live');
        msg = 'SECURITY: the recording failed the liveness / anti-replay check and was logged.';
        if isfield(result,'ImposterSuspect') && ~isempty(result.ImposterSuspect)
            msg = [msg ' Challenge voice resembles ' result.ImposterSuspect '.'];
        end
        update_status_text(status, msg);
        speak_text('Recorded voice detected. Please speak live.', true);
    case 'UNKNOWN'
        set_banner(banner, 'refused', 'NOT ENROLLED - access refused');
        update_status_text(status, 'The voice and the name match no enrolled student. Ask the hall office to enrol you.');
        speak_text('You are not enrolled.', true);
    otherwise
        shown = false;
end
end

function items = student_list(p)
%STUDENT_LIST Enrolled student folders, cheaply.
%   Listed from the directory rather than by testing enrollability, because
%   testing would run ENROL_TEMPLATE_FEATURES over the whole corpus every time the
%   window opens. A student with no enrollable file is reported at demo time, by
%   the same function that would have to load the file anyway.
%
%   Identities are the seven-digit Student IDs under Train/ID; legacy name-keyed
%   folders are excluded so the private demo lists exactly what the matcher sees.
profiles = list_id_profiles(p);
if isempty(profiles)
    items = {'(no students enrolled)'};
    return;
end
items = cell(1, numel(profiles));
for k = 1:numel(profiles)
    if isempty(profiles(k).Name)
        items{k} = profiles(k).Id;
    else
        items{k} = sprintf('%s - %s', profiles(k).Id, profiles(k).Name);
    end
end
end

function [feat, ok] = demo_features(p, status, student, phrase)
%DEMO_FEATURES The first enrollable recording of PHRASE by STUDENT.
%   Through ENROL_TEMPLATE_FEATURES, so the demo cannot succeed on a file the
%   deployed matcher would have refused to load. A demo that works on files the
%   system rejects would demonstrate the wrong system.
% student_list may present "ID - Name"; the identity is the seven-digit prefix.
[id, idOk] = student_id_contract(regexprep(char(string(student)), '\s*-.*$', ''));
if ~idOk, id = char(string(student)); end
if strcmp(phrase, 'ID')
    folder = fullfile(p.trainIdFolder, id);
elseif strcmp(phrase, 'Name')
    folder = fullfile(p.trainNameFolder, id);
else
    folder = fullfile(p.trainCouponFolder, id);
end
feat = first_enrollable(folder, p);
ok = ~isempty(feat);
if ~ok
    update_status_text(status, sprintf(['%s has no enrollable %s recording, so ' ...
        'the demo cannot run for that side. DIAGNOSE_AUDIO_CORPUS lists which ' ...
        'files the system refuses and why.'], student, lower(phrase)));
end
end

function f = first_enrollable(folder, p)
f = [];
if ~isfolder(folder), return; end
files = dir(fullfile(folder, '*.wav'));
for k = 1:numel(files)
    f = enrol_template_features(fullfile(files(k).folder, files(k).name), [], p);
    if ~isempty(f), return; end
end
f = [];
end

function data = gate_table(result, p)
%GATE_TABLE Gate evidence for the phrase that verifies the claim or last refusal.
%   Both phrases must independently verify the same identity.
%   With the v4.1.4_Final engine the six security gates are shown instead.
if nargin >= 2 && isstruct(p) && isfield(p,'vsd') && p.vsd.Enable && ...
        (isempty(result) || ~isstruct(result) || (isfield(result,'Engine') && strcmp(result.Engine,'vsd')))
    data = vsd_gate_table(result);
    return;
end
gateNames = {'1 Signal quality'; '2 Identity agreement'; '3 Absolute distance'; ...
             '4 Runner-up margin'; '5 Roster and meal'};
asks = { ...
 'Is the attempted recording complete and usable?'; ...
 'Do both recordings select the same student and any entered ID?'; ...
 'Does each recording pass its own calibrated distance limit?'; ...
 'Does each recording separate the student from its runner-up?'; ...
 'Is the student assigned this month and eligible for this meal?'};
verdicts = repmat({'-'}, 5, 1);

if ~isempty(result) && isstruct(result)
    % VERIFY_MEAL_WORKFLOW leaves result.Stage at the stage it stopped in, so the
    % ladder is read off it rather than recomputed. The two stages that are not
    % gates -- 'input' (no code typed) and 'match' (nothing enrolled to compare
    % against) -- are handled separately, because calling either of them a gate
    % failure would tell the operator the student was refused when in fact the
    % system was never asked a question it could answer.
    order = {'claim','enrollment','capture-id','capture-name','evidence', ...
        'agreement','consistency','claim-match','configuration','threshold','margin','roster','entitlement'};
    gateOf = [1 1 1 1 1 2 2 2 3 3 4 5 5];
    if result.Granted
        verdicts(:) = {'passed'};
        if isfield(result, 'Similarity') && ~isnan(result.Similarity)
            verdicts{3} = sprintf('passed (%d%% match)', round(result.Similarity));
        end
        verdicts{5} = 'passed - served';
    elseif strcmp(result.Stage, 'user-stop')
        verdicts(:) = {'not reached'};
        verdicts{1} = 'stopped by user';
    elseif strcmp(result.Stage, 'input')
        verdicts(:) = {'not reached'};
        verdicts{1} = 'no code typed';
    elseif strcmp(result.Stage, 'match')
        verdicts(:) = {'not reached'};
        verdicts{1} = 'passed';
        verdicts{2} = 'no enrolled templates';
    else
        stage = result.Stage;
        if strcmp(stage,'failed') && isfield(result,'FailureStage')
            stage = result.FailureStage;
        elseif strcmp(stage,'failed') && isfield(result,'NameStage')
            stage = result.NameStage;
            if strcmp(stage,'not-requested') && isfield(result,'IDStage'), stage = result.IDStage; end
        end
        reached = find(strcmp(stage, order), 1);
        if isempty(reached), reached = 1; end
        failedGate = gateOf(reached);
        for k = 1:5
            if k < failedGate
                verdicts{k} = 'passed';
            elseif k == failedGate
                if failedGate == 3 && isfield(result, 'Similarity') && ~isnan(result.Similarity)
                    verdicts{k} = sprintf('REFUSED HERE (%d%% match)', round(result.Similarity));
                else
                    if strcmp(result.Stage,'failed')
                        verdicts{k} = 'FAILED';
                    else
                        verdicts{k} = 'REFUSED HERE';
                    end
                end
            else
                verdicts{k} = 'not reached';
            end
        end
    end
end

data = [gateNames, asks, verdicts];
end

function data = vsd_gate_table(result)
%VSD_GATE_TABLE The six gates of the v4.1.4_Final engine with the measured evidence.
names = {'1 Signal quality'; '2 Phrase content'; '3 Voice biometrics'; '4 Imposter check'; ...
         '5 Anti-replay'; '6 Roster and meal'};
asks = { ...
 'Are both recordings long and loud enough to analyse?'; ...
 'Do the spoken ID + name single out one student (DTW, cohort-normalised)?'; ...
 'Is the student the best-matching voice (GMM-UBM log-likelihood ratio)?'; ...
 'Does the voice belong to the student the words claim?'; ...
 'Fresh random digits answered live in the same voice, not a copy?'; ...
 'Assigned this month and eligible for this meal window?'};
v = repmat({'-'}, 6, 1);
if isempty(result) || ~isstruct(result), data = [names, asks, v]; return; end
R = struct();
if isfield(result,'VSD') && isfield(result.VSD,'Scores'), R = result.VSD.Scores; end
ev = {'passed','passed','passed','passed','passed','passed'};
if isfield(R,'Pname') && ~isnan(R.Pname)
    ev{2} = sprintf('passed (name %+.2f, ID %+.2f)', R.Pname, R.Pid);
    ev{3} = sprintf('passed (voice %+.2f, rank %d)', R.V, R.VoiceRank);
end
if isfield(result,'Challenge') && isstruct(result.Challenge) && isfield(result.Challenge,'Used') && result.Challenge.Used
    ev{5} = sprintf('passed (digits %s)', num2str(result.Challenge.Code));
end
stage = result.Stage;
map = {'claim',1;'enrollment',1;'quality',1;'capture-id',1;'capture-name',1;'no-mic',1;'endpoint',1; ...
       'recording-error',1;'phrase',2;'unknown',2;'voice',3;'imposter',4;'replay',5;'challenge',5; ...
       'capture-challenge',5;'roster',6;'entitlement',6;'user-stop',0};
j = find(strcmp(map(:,1), stage), 1);
if result.Granted
    v = ev(:);  v{6} = 'passed - served';
elseif isempty(j) && result.Verified
    v = ev(:);  v{6} = 'not reached';
elseif ~isempty(j) && map{j,2} == 0
    v(:) = {'not reached'};  v{1} = 'stopped by user';
else
    if isempty(j), g = 1; else, g = map{j,2}; end
    for k = 1:6
        if k < g, v{k} = ev{k}; elseif k > g, v{k} = 'not reached'; end
    end
    switch stage
        case 'unknown',  v{g} = 'REFUSED - speaker not enrolled';
        case 'imposter', v{g} = ['IMPOSTER - voice of ' result.ImposterSuspect];
        case 'replay',   v{g} = 'REPLAY - copy of a stored take';
        case 'challenge', v{g} = 'REFUSED - challenge not passed';
        case 'voice'
            if isfield(R,'V'), v{g} = sprintf('REFUSED (voice %+.2f, rank %d)', R.V, R.VoiceRank);
            else, v{g} = 'REFUSED HERE'; end
        case 'phrase'
            if isfield(R,'Pname'), v{g} = sprintf('REFUSED (name %+.2f)', R.Pname);
            else, v{g} = 'REFUSED HERE'; end
        otherwise, v{g} = 'REFUSED HERE';
    end
end
data = [names, asks, v];
end

function set_banner(banner, kind, text)
banner.Text = text;
switch kind
    case 'granted'
        banner.BackgroundColor = [0.80 0.94 0.80];
        banner.FontColor = [0.05 0.35 0.05];
    case 'refused'
        banner.BackgroundColor = [0.98 0.85 0.85];
        banner.FontColor = [0.55 0.05 0.05];
    otherwise
        banner.BackgroundColor = [0.93 0.93 0.93];
        banner.FontColor = [0.20 0.20 0.20];
end
drawnow;
end

function refresh_window_label(window, p)
[mealName, info] = meal_window_now(p, datetime('now'));
if isempty(mealName)
    if ~isfield(info, 'NextWindow') || isempty(info.NextWindow)
        allWins = '';
        if isfield(info, 'AllWindows'), allWins = info.AllWindows; end
        window.Text = sprintf('Closed. Windows: %s', allWins);
    else
        minsToNext = 0;
        if isfield(info, 'MinutesToNext') && ~isnan(info.MinutesToNext)
            minsToNext = round(info.MinutesToNext);
        end
        window.Text = sprintf('Closed - %s opens in %d min', ...
            info.NextWindow, minsToNext);
    end
    window.FontColor = [0.55 0.35 0.05];
else
    minsRem = 60;
    if isfield(info, 'MinutesRemaining') && ~isnan(info.MinutesRemaining)
        minsRem = round(info.MinutesRemaining);
    elseif isfield(info, 'WindowEnd') && isfield(info, 'MinuteOfDay') && ~isnan(info.WindowEnd)
        minsRem = max(0, round(info.WindowEnd - info.MinuteOfDay));
    end
    window.Text = sprintf('%s is open - %d min remaining', ...
        mealName, minsRem);
    window.FontColor = [0.05 0.40 0.05];
end
end

% =========================================================================
% Enrol tab
% =========================================================================
function build_enrol_tab(fig, tabs)
p = fig.UserData.params;
tab = uitab(tabs, 'Title', 'Enrol', 'Tag', 'adminEnrolTab');
g = uigridlayout(tab, [9 4]);
g.RowHeight = {34, 34, 34, 40, 44, 44, 44, '1x', 22};
g.ColumnWidth = {170, 240, 200, '1x'};
g.Padding = [20 16 20 14];

l0 = uilabel(g, 'Text', 'Student ID (7 digits)'); l0.Layout.Row = 1; l0.Layout.Column = 1;
sid = uieditfield(g, 'text', 'Tag', 'enrolStudentId', 'Placeholder', 'e.g. 2206147');
sid.Layout.Row = 1; sid.Layout.Column = 2;

l1 = uilabel(g, 'Text', 'Student name');  l1.Layout.Row = 1; l1.Layout.Column = 3;
name = uieditfield(g, 'text', 'Tag', 'enrolName', 'Placeholder', 'display name (metadata only)');
name.Layout.Row = 1; name.Layout.Column = 4;

couponNote = uilabel(g, 'Text', ['Enroll the student ID and name recordings here. ' ...
    'Use Admin > Current month roster to assign dining access by ID.']);
couponNote.Layout.Row = 2; couponNote.Layout.Column = [1 4];
couponNote.WordWrap = 'on';
couponNote.FontColor = [0.35 0.35 0.35];

l3 = uilabel(g, 'Text', 'Takes per phrase'); l3.Layout.Row = 3; l3.Layout.Column = 1;
takes = uieditfield(g, 'numeric', 'Tag', 'enrolTakes', 'Limits', [1 10], 'RoundFractionalValues', 'on', ...
    'Value', p.samplesPerPhrase);
takes.Layout.Row = 3; takes.Layout.Column = 2;

phrase = uidropdown(g, 'Tag', 'enrolPhrase', ...
    'Items', {'Spoken ID phrase', 'Name phrase'});
phrase.Layout.Row = 3; phrase.Layout.Column = 3;

hint = uilabel(g, 'Text', sprintf(['The seven-digit Student ID is the canonical identity: it names the ' ...
    'Train/ID and Train/Name folders. New Enroll records the spoken ID first, ' ...
    'then the spoken name. ' ...
    'Each take is %g s at %g Hz -- stay SILENT for the first %.2f s, then speak. Defective takes are retried automatically.'], ...
    p.recordDur, p.fs, p.noise.NoiseDuration));
hint.Layout.Row = 4; hint.Layout.Column = [1 4];
hint.WordWrap = 'on';

recordBtn = uibutton(g, 'Text', 'New Enroll', 'Tag', 'newEnrollBtn');
recordBtn.Layout.Row = 5; recordBtn.Layout.Column = 1;

keepBtn = uibutton(g, 'Text', 'Save this take', 'Enable', 'off');
keepBtn.Layout.Row = 5; keepBtn.Layout.Column = 2;

dropBtn = uibutton(g, 'Text', 'Discard profile', 'Tag', 'enrolDiscardBtn', 'Enable', 'on');
dropBtn.Layout.Row = 5; dropBtn.Layout.Column = 3;
dropBtn.Tooltip = 'Delete all recorded voice files for this Student ID to start fresh from Take 1';

stopEnrolBtn = uibutton(g, 'Text', 'Instant Stop', 'Tag', 'enrolStopBtn', 'Enable', 'off');
stopEnrolBtn.Layout.Row = 5; stopEnrolBtn.Layout.Column = 4;
stopEnrolBtn.BackgroundColor = [0.94 0.88 0.88];
stopEnrolBtn.FontWeight = 'bold';

resetBtn = uibutton(g, 'Text', 'Reload template cache');
resetBtn.Layout.Row = 6; resetBtn.Layout.Column = 1;

auditBtn = uibutton(g, 'Text', 'Audit this student');
auditBtn.Layout.Row = 6; auditBtn.Layout.Column = 2;

digitsBtn = uibutton(g, 'Text', 'Record digits 0-9', 'Tag', 'enrolDigitsBtn');
digitsBtn.Layout.Row = 6; digitsBtn.Layout.Column = 3;
digitsBtn.Tooltip = 'Anti-replay challenge templates + background voice model (v4.1.4_Final)';

rebuildBtn = uibutton(g, 'Text', 'Rebuild voice models', 'Tag', 'enrolRebuildBtn');
rebuildBtn.Layout.Row = 6; rebuildBtn.Layout.Column = 4;
rebuildBtn.Tooltip = 'Fold new/changed recordings into the GMM-UBM voice models now';

importBtn = uibutton(g, 'Text', 'Import from folder...', 'Tag', 'enrolImportBtn');
importBtn.Layout.Row = 7; importBtn.Layout.Column = 1;

importFilesBtn = uibutton(g, 'Text', 'Import .wav file(s)...', 'Tag', 'enrolImportFilesBtn');
importFilesBtn.Layout.Row = 7; importFilesBtn.Layout.Column = 2;

importHint = uilabel(g, 'Text', ['Import previously recorded takes: pick the Student ID and phrase above, then ' ...
    'either browse to a folder or select individual .wav files. Each file is analysed with the enrolment ' ...
    'quality check; only usable takes are copied into the ID-keyed profile. Originals are left untouched.']);
importHint.Layout.Row = 7; importHint.Layout.Column = [3 4];
importHint.WordWrap = 'on';
importHint.FontColor = [0.35 0.35 0.35];

status = uitextarea(g, 'Editable', 'off', 'Tag', 'enrolStatus', 'Value', ...
    {'Ready to enrol. Enter the seven-digit Student ID and name, then New Enroll.'});
status.Layout.Row = 8; status.Layout.Column = [1 4];
status.FontName = 'Consolas';

note = uilabel(g, 'Text', ['Files are written as raw captures under the Student ID. All ' ...
    'preprocessing happens at match time, so one chain is applied exactly once to every recording.']);
note.Layout.Row = 9; note.Layout.Column = [1 4];
note.FontColor = [0.35 0.35 0.35];

recordBtn.ButtonPushedFcn = @(~,~) automated_new_enroll(fig, sid, name, takes, status, ...
    recordBtn, keepBtn, dropBtn, resetBtn, auditBtn, importBtn, stopEnrolBtn);
stopEnrolBtn.ButtonPushedFcn = @(~,~) enrol_stop_action(fig, status);
keepBtn.ButtonPushedFcn  = @(~,~) enrol_save(fig, sid, phrase, status, keepBtn, dropBtn);
dropBtn.ButtonPushedFcn  = @(~,~) enrol_discard_profile(fig, sid, status);
resetBtn.ButtonPushedFcn = @(~,~) enrol_reset_cache(status);
digitsBtn.ButtonPushedFcn = @(~,~) enrol_record_digits(fig, sid, status);
rebuildBtn.ButtonPushedFcn = @(~,~) enrol_rebuild_models(fig, status);
auditBtn.ButtonPushedFcn = @(~,~) enrol_audit(fig, sid, status);
importBtn.ButtonPushedFcn = @(~,~) enrol_import_folder(fig, sid, name, phrase, status);
importFilesBtn.ButtonPushedFcn = @(~,~) enrol_import_files(fig, sid, name, phrase, status);
end

function enrol_stop_action(fig, status)
fig.UserData.enrolStopRequested = true;
update_status_text(status, '>>> INSTANT STOP PRESSED. Cancelling current recording/take...');
drawnow;
end

function tf = check_enrol_stop(fig)
tf = false;
if isempty(fig) || ~isvalid(fig), return; end
if isfield(fig.UserData, 'enrolStopRequested') && fig.UserData.enrolStopRequested
    tf = true;
end
end

function exitEnrol = handle_enrol_stop(fig, status, phraseLabel, sessionCreatedFiles)
if nargin < 4, sessionCreatedFiles = {}; end
rollback_enrol_session(fig, status, phraseLabel, sessionCreatedFiles);
exitEnrol = true;
end

function automated_new_enroll(fig, sid, name, takes, status, recordBtn, keepBtn, ...
    dropBtn, resetBtn, auditBtn, importBtn, stopEnrolBtn)
%AUTOMATED_NEW_ENROLL Capture and validate a two-phrase voice profile (ID + Name).
p = fig.UserData.params;
[student, idOk, idMessage] = student_id_contract(sid.Value);
if ~idOk
    update_status_text(status, ['Cannot enrol: ' idMessage]);
    return;
end
displayName = strtrim(char(string(name.Value)));
n = max(1, round(double(takes.Value)));
if isempty(displayName)
    update_status_text(status, 'Enter the student name (display metadata) before starting New Enroll.');
    return;
end
paths = student_profile_paths(p, student);
folders = {paths.Id, paths.Name};
hasExistingWavs = false;
for k = 1:numel(folders)
    if isfolder(folders{k}) && ~isempty(dir(fullfile(folders{k}, '*.wav')))
        hasExistingWavs = true; break;
    end
end
if hasExistingWavs
    choice = uiconfirm(fig, sprintf(['A voice profile already exists for Student ID %s.\n' ...
        'Choose whether to wipe old files and start fresh, or add new trials.'], student), ...
        'Confirm New Enroll', 'Options', {'Start fresh (Delete old)', 'Add new trials', 'Cancel'}, ...
        'DefaultOption', 'Start fresh (Delete old)', 'CancelOption', 'Cancel');
    switch choice
        case 'Start fresh (Delete old)'
            delete_student_recordings(folders);
            find_best_voice_match('reset');
            update_status_text(status, sprintf('Previous files for %s deleted. Starting fresh enrollment from Take 1...', student));
        case 'Add new trials'
            update_status_text(status, sprintf('Adding new trials to existing profile for %s...', student));
        otherwise
            update_status_text(status, 'New Enroll cancelled; existing profile was not changed.');
            return;
    end
end
set([recordBtn keepBtn dropBtn resetBtn auditBtn importBtn], 'Enable', 'off');
if nargin >= 12 && ~isempty(stopEnrolBtn) && isvalid(stopEnrolBtn)
    stopEnrolBtn.Enable = 'on';
    stopEnrolBtn.BackgroundColor = [0.95 0.35 0.35];
    stopEnrolBtn.FontColor = [1 1 1];
end
fig.UserData.enrolStopRequested = false;
cleanup = onCleanup(@() restore_enrol_controls(recordBtn, keepBtn, dropBtn, resetBtn, auditBtn, importBtn, stopEnrolBtn));
labels = {'ID', 'NAME'};
phrases = {'your seven-digit Student ID, one digit at a time', ...
           'your full name'};
sessionCreatedFiles = {};
for side = 1:2
    if ~isfolder(folders{side}), mkdir(folders{side}); end
    valid = 0;
    attempts = 0;
    while valid < n
        attempts = attempts + 1;
        stoppedCountdown = false;
        for c = 3:-1:1
            if check_enrol_stop(fig)
                stoppedCountdown = true; break;
            end
            update_status_text(status, sprintf('New Enroll: %s trial %d of %d (Attempt %d). Ready in %d...', ...
                labels{side}, valid + 1, n, attempts, c));
            if interruptible_pause(0.7, @() check_enrol_stop(fig))
                stoppedCountdown = true; break;
            end
        end
        if stoppedCountdown || check_enrol_stop(fig)
            handle_enrol_stop(fig, status, labels{side}, sessionCreatedFiles);
            return;
        end

        leadInDur = p.noise.NoiseDuration + 0.1;
        speechDur = max(1.0, p.recordDur - leadInDur);
        stoppedRecording = false;
        try
            recorder = audiorecorder(p.fs, 16, 1);
            record(recorder);
            update_status_text(status, '● RECORDING: Remain silent for 0.5 s (measuring room noise)...');
            stoppedLead = interruptible_pause(leadInDur, @() check_enrol_stop(fig));
            if ~stoppedLead
                update_status_text(status, sprintf('>>> SPEAK NOW: Say %s <<< (%.1f s remaining)', phrases{side}, speechDur));
                stoppedSpeech = interruptible_pause(speechDur, @() check_enrol_stop(fig));
            else
                stoppedSpeech = true;
            end
            if isrecording(recorder), stop(recorder); end

            if stoppedLead || stoppedSpeech || check_enrol_stop(fig)
                stoppedRecording = true;
            else
                audio = getaudiodata(recorder);
                audio = audio(:);
                dg = assess_recording_quality(audio, p.fs, p, struct('Strict', true));
            end
        catch
            try
                audio = record_audio_dsp(p.recordDur, p.fs);
                dg = assess_recording_quality(audio, p.fs, p, struct('Strict', true));
            catch err
                update_status_text(status, ['New Enroll stopped: ' err.message]);
                return;
            end
        end

        if stoppedRecording || check_enrol_stop(fig)
            handle_enrol_stop(fig, status, labels{side}, sessionCreatedFiles);
            return;
        end

        update_status_text(status, sprintf('  %s attempt %d: RMS %.4g | speech %.2f s | low-band %.5f.', ...
            labels{side}, attempts, dg.OverallRms, dg.SpeechDuration, dg.LowBandRatio));
        if ~dg.Usable
            update_status_text(status, ['  Retrying automatically: ' dg.Reason]);
            continue;
        end
        valid = valid + 1;
        target = fullfile(folders{side}, sprintf('%d.wav', next_take_number(folders{side})));
        audiowrite(target, audio, p.fs);
        sessionCreatedFiles{end+1} = target;
        update_status_text(status, sprintf('  Accepted and saved trial %d/%d: %s', valid, n, target));
    end
end
student_profile(p, student, displayName);
find_best_voice_match('reset');
update_status_text(status, sprintf(['New Enroll complete for %s (%s): %d valid ID and %d NAME ' ...
    'trials. Matcher cache reset. Assign the student to the current month in the Admin panel.'], ...
    student, displayName, n, n));
end

function restore_enrol_controls(recordBtn, keepBtn, dropBtn, resetBtn, auditBtn, importBtn, stopEnrolBtn)
set([recordBtn resetBtn auditBtn importBtn], 'Enable', 'on');
if isvalid(keepBtn), keepBtn.Enable = 'off'; end
if isvalid(dropBtn), dropBtn.Enable = 'on'; end
if nargin >= 7 && ~isempty(stopEnrolBtn) && isvalid(stopEnrolBtn)
    stopEnrolBtn.Enable = 'off';
    stopEnrolBtn.BackgroundColor = [0.94 0.88 0.88];
    stopEnrolBtn.FontColor = [0.4 0.4 0.4];
end
end

function enrol_import_folder(fig, sid, name, phrase, status)
%ENROL_IMPORT_FOLDER Copy and validate previously recorded takes from a folder.
%   The operator picks the Student ID and phrase, then browses to a folder of that
%   student's .wav files. Each file is run through the same strict quality check as
%   live enrolment; only usable takes are copied into the ID-keyed profile folder.
%   Originals are never modified. This is one of the two "add previously recorded
%   voices" paths; ENROL_IMPORT_FILES imports individually chosen files instead.
p = fig.UserData.params;
[ok, student, target, phraseLabel] = resolve_import_target(p, sid, phrase, status);
if ~ok, return; end

folder = uigetdir(pwd, sprintf('Select a folder of %s .wav takes for Student ID %s', phraseLabel, student));
if isequal(folder, 0)
    update_status_text(status, 'Import cancelled; no folder selected.');
    return;
end
files = dir(fullfile(folder, '*.wav'));
if isempty(files)
    update_status_text(status, sprintf('No .wav files found in %s.', folder));
    return;
end
srcPaths = fullfile({files.folder}, {files.name});
import_wav_takes(p, student, name, srcPaths, target, phraseLabel, status);
end

function enrol_import_files(fig, sid, name, phrase, status)
%ENROL_IMPORT_FILES Copy and validate individually chosen previously recorded takes.
%   Like ENROL_IMPORT_FOLDER, but the operator selects specific .wav files rather
%   than a whole folder (UIGETFILE with MultiSelect). Each file goes through the
%   same strict ASSESS_RECORDING_QUALITY check; only usable takes are copied into
%   the ID-keyed profile folder. Originals are never modified.
p = fig.UserData.params;
[ok, student, target, phraseLabel] = resolve_import_target(p, sid, phrase, status);
if ~ok, return; end

[names, folder] = uigetfile({'*.wav', 'WAV audio (*.wav)'}, ...
    sprintf('Select %s .wav take(s) for Student ID %s', phraseLabel, student), ...
    'MultiSelect', 'on');
if isequal(names, 0)
    update_status_text(status, 'Import cancelled; no files selected.');
    return;
end
if ischar(names)          % a single selection returns a char row, not a cell
    names = {names};
end
srcPaths = fullfile(folder, names);
import_wav_takes(p, student, name, srcPaths, target, phraseLabel, status);
end

function [ok, student, target, phraseLabel] = resolve_import_target(p, sid, phrase, status)
%RESOLVE_IMPORT_TARGET Validate the Student ID and map the phrase to its folder.
%   Shared by the folder and file import paths so both resolve the destination the
%   same way.
ok = false; target = ''; phraseLabel = '';
[student, idOk, idMessage] = student_id_contract(sid.Value);
if ~idOk
    update_status_text(status, ['Cannot import: ' idMessage]);
    return;
end
paths = student_profile_paths(p, student);
switch true
    case startsWith(phrase.Value, 'Spoken ID')
        target = paths.Id;   phraseLabel = 'ID';
    case startsWith(phrase.Value, 'Name')
        target = paths.Name; phraseLabel = 'NAME';
    otherwise
        update_status_text(status, 'Only Student ID and full name can be enrolled.');
        return;
end
ok = true;
end

function import_wav_takes(p, student, name, srcPaths, target, phraseLabel, status)
%IMPORT_WAV_TAKES Copy the usable files in SRCPATHS into TARGET as numbered takes.
%   Each source is read as mono, resampled to p.fs if needed, and assessed with the
%   same strict quality gate as live enrolment. Usable takes are written as the next
%   free N.wav; unusable ones are reported and skipped. Originals are never touched.
if ~isfolder(target), mkdir(target); end
update_status_text(status, sprintf('Importing %d file(s) as %s takes for %s...', ...
    numel(srcPaths), phraseLabel, student));
imported = 0; skipped = 0;
for k = 1:numel(srcPaths)
    src = srcPaths{k};
    [~, base, ext] = fileparts(src);
    fname = [base ext];
    try
        [audio, fsRead] = audioread(src);
        if size(audio, 2) > 1, audio = mean(audio, 2); end   % force mono
        if fsRead ~= p.fs
            audio = rational_resample_audio(audio, fsRead, p.fs);
        end
        dg = assess_recording_quality(audio, p.fs, p, struct('Strict', true));
    catch err
        skipped = skipped + 1;
        update_status_text(status, sprintf('  SKIP %s: could not read/analyse (%s).', fname, err.message));
        continue;
    end
    if ~dg.Usable
        skipped = skipped + 1;
        update_status_text(status, sprintf('  SKIP %s: %s', fname, dg.Reason));
        continue;
    end
    dest = fullfile(target, sprintf('%d.wav', next_take_number(target)));
    audiowrite(dest, audio, p.fs);
    imported = imported + 1;
    update_status_text(status, sprintf('  Imported %s -> %s (RMS %.4g, speech %.2f s).', ...
        fname, dest, dg.OverallRms, dg.SpeechDuration));
end

% Preserve any display name typed alongside the import.
displayName = strtrim(char(string(name.Value)));
if ~isempty(displayName)
    student_profile(p, student, displayName);
end
find_best_voice_match('reset');
update_status_text(status, sprintf(['Import complete for %s: %d usable %s take(s) copied, %d skipped. ' ...
    'Matcher cache reset.'], student, imported, phraseLabel, skipped));
end

function enrol_record(fig, phrase, status, keepBtn, dropBtn)
p = fig.UserData.params;
words = phrase_words(phrase.Value);
update_status_text(status, sprintf( ...
    'Recording %g s. Stay silent for %.2f s, then say %s...', ...
    p.recordDur, p.noise.NoiseDuration, words));
drawnow;

try
    audio = record_audio_dsp(p.recordDur, p.fs);
catch err
    update_status_text(status, ['CANNOT RECORD: ' err.message]);
    return;
end

% Strict = true. The student is standing here; the cost of refusing a take is one
% retake, and the cost of accepting a bad one is a file nobody can replace.
dg = assess_recording_quality(audio, p.fs, p, struct('Strict', true));

update_status_text(status, sprintf( ...
    '  RMS %.4g | pre-roll RMS %.4g | peak %.3f | speech %.2f s | sub-200 Hz ratio %.5f', ...
    dg.OverallRms, dg.PreRollRms, max(abs(audio)), dg.SpeechDuration, dg.LowBandRatio));
if dg.Usable
    update_status_text(status, '  USABLE. Press Save this take, or Discard to try again.');
else
    update_status_text(status, ['  NOT USABLE: ' dg.Reason]);
end
for k = 1:numel(dg.Problems)
    update_status_text(status, ['    - ' dg.Problems{k}]);
end

app = fig.UserData;
app.enrol.pending = audio;
app.enrol.pendingDg = dg;
fig.UserData = app;

keepBtn.Enable = 'on';
dropBtn.Enable = 'on';
if dg.Usable
    keepBtn.Text = 'Save this take';
else
    keepBtn.Text = 'Save anyway';
end
end

function enrol_save(fig, sid, phrase, status, keepBtn, dropBtn)
p = fig.UserData.params;
app = fig.UserData;
if isempty(app.enrol.pending)
    update_status_text(status, 'Nothing to save. Record a take first.');
    return;
end
[student, idOk, idMessage] = student_id_contract(sid.Value);
if ~idOk
    update_status_text(status, ['Cannot save: ' idMessage]);
    return;
end

folder = phrase_folder(phrase.Value, p, student);
if ~isfolder(folder)
    mkdir(folder);
end
next = next_take_number(folder);
target = fullfile(folder, sprintf('%d.wav', next));
audiowrite(target, app.enrol.pending, p.fs);
update_status_text(status, sprintf('  saved %s', target));
if ~app.enrol.pendingDg.Usable
    update_status_text(status, ['  WARNING: saved a take the system will not ' ...
        'enrol. It will be listed by DIAGNOSE_AUDIO_CORPUS and ignored by the ' ...
        'matcher. Record a replacement.']);
end

app.enrol.pending = [];
app.enrol.pendingDg = [];
fig.UserData = app;
keepBtn.Enable = 'off';
dropBtn.Enable = 'off';

find_best_voice_match('reset');
update_status_text(status, '  template cache reset, so the new file is live.');
end

function enrol_discard(fig, status, keepBtn, dropBtn)
app = fig.UserData;
app.enrol.pending = [];
app.enrol.pendingDg = [];
fig.UserData = app;
keepBtn.Enable = 'off';
dropBtn.Enable = 'off';
update_status_text(status, '  take discarded.');
end

function enrol_reset_cache(status)
find_best_voice_match('reset');
update_status_text(status, ['Template cache cleared. The next verification ' ...
    're-reads every enrolment file from disk.']);
end

function enrol_record_digits(fig, sid, status)
%ENROL_RECORD_DIGITS Ten isolated digits for the anti-replay challenge.
p = fig.UserData.params;
if ~isfield(p,'vsd') || ~p.vsd.Enable
    update_status_text(status, 'The v4.1.4_Final engine is disabled (params.vsd.Enable = false).'); return;
end
[student, ok, msg] = student_id_contract(sid.Value);
if ~ok, update_status_text(status, ['Cannot record digits: ' msg]); return; end
fig.UserData.enrolStopRequested = false;
update_status_text(status, sprintf('Recording the digits zero..nine for %s. Say each digit once when prompted.', student));
vsd_enrol_digits(student, status, p, @() check_enrol_stop(fig));
end

function enrol_rebuild_models(fig, status)
%ENROL_REBUILD_MODELS Incremental update of templates, UBM and voice models.
p = fig.UserData.params;
if ~isfield(p,'vsd') || ~p.vsd.Enable
    update_status_text(status, 'The v4.1.4_Final engine is disabled (params.vsd.Enable = false).'); return;
end
update_status_text(status, 'Updating voice models (only new or changed recordings are processed)...'); drawnow;
t = tic;
M = vsd_models(p.vsd, 'rebuild');
update_status_text(status, sprintf('Voice models ready: %d students, UBM from %s, %d file(s) processed, %d skipped (%.1f s).', ...
    numel(M.Students), M.UbmSource, M.NumNewFiles, numel(M.Skipped), toc(t)));
for k = 1:numel(M.Skipped), update_status_text(status, ['  skipped: ' M.Skipped{k}]); end
end

function enrol_audit(fig, sid, status)
p = fig.UserData.params;
[student, idOk, idMessage] = student_id_contract(sid.Value);
if ~idOk
    update_status_text(status, ['Cannot audit: ' idMessage]);
    return;
end
meta = student_profile(p, student);
if ~isempty(meta.Name)
    update_status_text(status, sprintf('  Student %s: %s', student, meta.Name));
end
paths = student_profile_paths(p, student);
folders = {paths.Id, paths.Name};
labels = {'ID', 'Name'};
for r = 1:numel(folders)
    files = dir(fullfile(folders{r}, '*.wav'));
    if isempty(files)
        update_status_text(status, sprintf('  %s: no recordings.', labels{r}));
        continue;
    end
    nUsable = 0;
    for k = 1:numel(files)
        [f, dg] = enrol_template_features( ...
            fullfile(files(k).folder, files(k).name), [], p);
        nUsable = nUsable + (~isempty(f));
        if isempty(f)
            update_status_text(status, sprintf('  %s/%s NOT enrolled: %s', ...
                labels{r}, files(k).name, dg.Reason));
        end
    end
    update_status_text(status, sprintf('  %s: %d of %d file(s) enrolled (target %d).', ...
        labels{r}, nUsable, numel(files), p.samplesPerPhrase));
end
update_status_text(status, '  Current-month dining access is assigned by Student ID in the Admin panel.');
end

function words = phrase_words(item)
if startsWith(item, 'Spoken ID')
    words = 'your seven-digit Student ID, one digit at a time';
elseif startsWith(item, 'Name')
    words = 'your full name';
else
    error('meal_verification_gui:phrase', 'Only Student ID and full name are supported.');
end
end

function folder = phrase_folder(item, p, student)
if startsWith(item, 'Spoken ID')
    folder = fullfile(p.trainIdFolder, student);
elseif startsWith(item, 'Name')
    folder = fullfile(p.trainNameFolder, student);
else
    error('meal_verification_gui:phrase', 'Only Student ID and full name are supported.');
end
end

function n = next_take_number(folder)
%NEXT_TAKE_NUMBER The lowest positive integer not already used as a filename.
%   Numbering from the existing files rather than from a counter in the interface
%   means a session interrupted half way through does not overwrite what it saved
%   the first time.
n = 1;
while isfile(fullfile(folder, sprintf('%d.wav', n)))
    n = n + 1;
end
end

% =========================================================================
% Admin tab
% =========================================================================
function build_admin_tab(fig, tabs)
tab = uitab(tabs, 'Title', 'Admin', 'Tag', 'adminTab');
g = uigridlayout(tab, [9 5]);
g.RowHeight = {34,34,30,34,34,34,34,'1x',22};
g.ColumnWidth = {150,190,190,190,'1x'};
g.Padding = [20 12 20 12];
idLabel=uilabel(g,'Text','Admin ID'); place(idLabel,1,1);
adminId=uieditfield(g,'text','Tag','adminId','Placeholder','admin'); place(adminId,1,2);
unlock=uibutton(g,'Text','Unlock / current month','Tag','adminUnlockBtn'); place(unlock,1,3);
roster=uibutton(g,'Text','Current month roster','Tag','adminCurrentMonthBtn'); place(roster,1,4);
lockBtn=uibutton(g,'Text','Lock','Tag','adminLockBtn'); place(lockBtn,1,5);
lockBtn.BackgroundColor=[.94 .88 .88];
passLabel=uilabel(g,'Text','Admin password'); place(passLabel,2,1);
pass=uieditfield(g,'text','Tag','adminPass','Placeholder','admin'); place(pass,2,2);
audit=uibutton(g,'Text','Corpus audit'); place(audit,2,3);
logButton=uibutton(g,'Text','Meal log','Tag','adminMealLogBtn'); place(logButton,2,4);
workspace=uibutton(g,'Text','Open DSP / improvements','Tag','adminWorkspaceBtn'); place(workspace,2,5);
monthLabel=uilabel(g,'Text',['Current month: ' char(string(datetime('now'),'yyyy-MM'))], ...
    'Tag','adminRosterMonth','FontWeight','bold'); place(monthLabel,3,[1 5]);
searchLabel=uilabel(g,'Text','Search enrolled ID'); place(searchLabel,4,1);
search=uieditfield(g,'text','Tag','adminRosterSearch','Placeholder','Type ID, e.g. 2206147'); place(search,4,2);
drop=uidropdown(g,'Tag','adminRosterDropdown','Items',{'-- Select Student ID --'}); place(drop,4,3);
assign=uibutton(g,'Text','Assign for this month','Tag','adminAssignMonthBtn'); place(assign,4,4);
bulk=uibutton(g,'Text','Assign selected (0)','Tag','adminAssignSelectedBtn'); place(bulk,4,5);
bulk.BackgroundColor=[.86 .94 .89];
markLabel=uilabel(g,'Text','Multiple students'); place(markLabel,5,1);
selectAll=uibutton(g,'Text','Select all shown','Tag','adminSelectShownBtn'); place(selectAll,5,2);
clearAll=uibutton(g,'Text','Clear selection','Tag','adminClearSelectionBtn'); place(clearAll,5,3);
remove=uibutton(g,'Text','Remove selected ID...','Tag','adminRemoveRosterBtn'); place(remove,5,4);
remove.Tooltip='Remove the dropdown ID from the current month only';
hoursLabel=uilabel(g,'Text','Service hours'); place(hoursLabel,6,1);
schedule=uibutton(g,'Text','View schedule','Tag','adminViewScheduleBtn'); place(schedule,6,2);
hours=uibutton(g,'Text','Meal hours...','Tag','adminMealHoursBtn'); place(hours,6,3);
reset=uibutton(g,'Text','Reset meal log...','Tag','adminResetMealsBtn'); place(reset,6,[4 5]);
reset.BackgroundColor=[.96 .90 .85];
message=uilabel(g,'Text','Private data is locked.','Tag','adminMessage','WordWrap','on'); place(message,7,[1 5]);
view=uitable(g,'Tag','adminTable','ColumnName',{},'RowName',{},'Visible','off'); place(view,8,[1 5]);
note=uilabel(g,'Text','Mark checkboxes, then Assign selected. Assignment applies to the month shown; voice verification is still required.');
place(note,9,[1 5]); note.FontColor=[.35 .35 .35];
unlock.ButtonPushedFcn=@(~,~)admin_roster_action(fig,'show');
roster.ButtonPushedFcn=@(~,~)admin_roster_action(fig,'show');
search.ValueChangingFcn=@(~,e)admin_roster_action(fig,'search-live',e);
search.ValueChangedFcn=@(~,~)admin_roster_action(fig,'search');
drop.ValueChangedFcn=@(~,~)admin_roster_action(fig,'dropdown');
assign.ButtonPushedFcn=@(~,~)admin_roster_action(fig,'assign-one');
bulk.ButtonPushedFcn=@(~,~)admin_roster_action(fig,'assign-selected');
selectAll.ButtonPushedFcn=@(~,~)admin_roster_action(fig,'select-visible');
clearAll.ButtonPushedFcn=@(~,~)admin_roster_action(fig,'clear-selection');
remove.ButtonPushedFcn=@(~,~)admin_roster_action(fig,'remove-one');
logButton.ButtonPushedFcn=@(~,~)admin_show_log(fig,adminId,pass,view,message);
audit.ButtonPushedFcn=@(~,~)admin_show_audit(fig,adminId,pass,view,message);
workspace.ButtonPushedFcn=@(~,~)admin_open_workspace(fig,adminId,pass,message);
schedule.ButtonPushedFcn=@(~,~)admin_show_schedule(fig,adminId,pass,view,message);
hours.ButtonPushedFcn=@(~,~)admin_configure_meal_hours(fig,adminId,pass,view,message);
reset.ButtonPushedFcn=@(~,~)admin_reset_meal_log(fig,adminId,pass,view,message);
lockBtn.ButtonPushedFcn=@(~,~)admin_lock(fig,adminId,pass,view,message);
end

function place(h,row,column)
h.Layout.Row=row; h.Layout.Column=column;
end

function ok = admin_authorised(fig, adminId, pass, message)
p = fig.UserData.params;
configuredId = 'admin';
if isfield(p, 'adminId') && ~isempty(p.adminId), configuredId = char(string(p.adminId)); end
ok = strcmp(char(string(adminId.Value)), configuredId) && ...
    strcmp(char(string(pass.Value)), p.adminPassword);
if ~ok
    message.Text = 'Incorrect admin ID or password. Private data stays locked.';
    message.FontColor = [0.70 0.05 0.05];
end
end

function admin_show_log(fig, adminId, pass, view, message)
if ~admin_authorised(fig, adminId, pass, message), return; end
data=admin_refresh_meal_log(fig,view);
update_reset_button(fig, 'meal_log');
p = fig.UserData.params;
view.Visible = 'on';
if ~isfile(p.logFile)
    view.Data = table();
    view.ColumnName = {};
    message.Text = sprintf(['No meal has been logged yet, so %s does not exist. ' ...
        'It is created by the first serving.'], p.logFile);
    message.FontColor = [0.35 0.35 0.35];
    return;
end
message.Text = sprintf('%s: %d serving(s). %s', p.logFile, height(data), ...
    today_summary(data, p));
message.FontColor = [0.05 0.40 0.05];
end

function text = today_summary(data, p)
%TODAY_SUMMARY Servings per meal window today, from the log itself.
try
    todayText = string(datetime('today'), 'yyyy-MM-dd');
    isToday = data.Date == todayText;
    parts = strings(0);
    for k = 1:numel(p.meals)
        n = sum(isToday & data.Meal == string(p.meals(k).Name));
        parts(end+1) = sprintf('%s %d', p.meals(k).Name, n); %#ok<AGROW>
    end
    text = sprintf('Today: %s.', strjoin(parts, ', '));
catch
    text = '';
end
end

function admin_show_audit(fig, adminId, pass, view, message)
if ~admin_authorised(fig, adminId, pass, message), return; end
view.ColumnEditable=false; view.CellEditCallback=[]; view.ColumnFormat={}; view.ColumnWidth='auto';
p = fig.UserData.params;
csv = fullfile(p.evaluation.ResultsFolder, 'corpus_diagnostics.csv');
if ~isfolder(p.evaluation.ResultsFolder)
    mkdir(p.evaluation.ResultsFolder);
end
message.Text = 'Auditing the corpus...';
message.FontColor = [0.35 0.35 0.35];
drawnow;
try
    % DIAGNOSE_AUDIO_CORPUS reads DSP_PARAMETERS itself and takes only an output
    % path, deliberately: the audit's job is to report on the corpus as the
    % DEPLOYED configuration sees it, so it must not be handed a modified struct.
    diagnose_audio_corpus(csv);
catch err
    message.Text = ['Audit failed: ' err.message];
    message.FontColor = [0.70 0.05 0.05];
    return;
end
if ~isfile(csv)
    message.Text = 'The audit ran but wrote no CSV.';
    return;
end
data = readtable(csv, 'TextType', 'string');
view.Data = data;
view.ColumnName = data.Properties.VariableNames;
message.Text = sprintf(['Corpus audit: %d file(s), %d enrolled by the deployed ' ...
    'rule. Full text of the audit is in the command window; per-file detail is in %s.'], ...
    height(data), sum(logical(data.Usable)), csv);
message.FontColor = [0.05 0.40 0.05];
end

function admin_open_workspace(fig, adminId, pass, message)
if ~admin_authorised(fig, adminId, pass, message), return; end
app = fig.UserData;
if isfield(app, 'adminWorkspaceOpen') && app.adminWorkspaceOpen
    message.Text = 'DSP workspace is already open, including the Improvements tab.';
    return;
end
% These tabs are not constructed at startup, so identities, WAV selectors,
% graphs, result tables, and diagnostics are unavailable to public users.
parent = findobj(fig, 'Type', 'uitabgroup');
if isempty(parent)
    message.Text = 'Could not open the private DSP workspace.';
    return;
end
build_enrol_tab(fig, parent(1));
build_explorer_tab(fig, parent(1));
build_evaluation_tab(fig, parent(1));
build_improvements_tab(fig, parent(1));
app.adminWorkspaceOpen = true;
fig.UserData = app;
message.Text = 'Private workspace opened. See Improvements for proposal changes, calculations and measured evidence.';
message.FontColor = [0.05 0.40 0.05];
end

function admin_lock(fig, adminId, pass, view, message)
% Locking deletes the private workspace tabs because MATLAB tabs have no
% Visible property in R2024a. This also releases any sensitive table data.
app = fig.UserData;
app.adminCurrentView = 'locked';
update_reset_button(fig, 'meal_log');
if isfield(app, 'adminWorkspaceOpen') && app.adminWorkspaceOpen
    for tag = {'adminEnrolTab', 'adminExplorerTab', 'adminEvaluationTab', 'adminImprovementsTab'}
        h = findobj(fig, 'Tag', tag{1});
        if ~isempty(h), delete(h); end
    end
    app.adminWorkspaceOpen = false;
    fig.UserData = app;
end
app.rosterSelectedIDs={};
admin_roster_action(fig,'lock');
view.Data = table();
view.ColumnName = {};
view.Visible = 'off';
fig.UserData = app;
adminId.Value = '';
pass.Value = '';
message.Text = 'Private data is locked.';
message.FontColor = [0.35 0.35 0.35];
end

% =========================================================================
% DSP Explorer tab
% =========================================================================
function build_explorer_tab(fig, tabs)
p = fig.UserData.params;
tab = uitab(tabs, 'Title', 'DSP Explorer', 'Tag', 'adminExplorerTab');
g = uigridlayout(tab, [4 6]);
g.RowHeight = {34, 34, '1x', 130};
g.ColumnWidth = {150, 250, 150, 150, 150, '1x'};
g.Padding = [16 14 16 12];

l1 = uilabel(g, 'Text', 'Signal source'); l1.Layout.Row = 1; l1.Layout.Column = 1;
source = uidropdown(g, 'Tag', 'explorerSourceKind', 'Items', { ...
    'Synthesised voiced sound (no microphone)', ...
    'Enrolment file from the corpus', ...
    'Live 3 s capture'});
source.Layout.Row = 1; source.Layout.Column = [2 3];

fileList = uidropdown(g, 'Items', corpus_file_list(p), 'Tag', 'explorerSource');
fileList.Layout.Row = 1; fileList.Layout.Column = [4 5];

l2 = uilabel(g, 'Text', 'Stage to show'); l2.Layout.Row = 2; l2.Layout.Column = 1;
stage = uidropdown(g, 'Tag', 'explorerStage', 'Items', { ...
    '1  Resampling 44.1 kHz to 8 kHz', ...
    '2  Automatic gain control', ...
    '3  Spectral subtraction of the noise profile', ...
    '4  Hybrid endpoint detection (STE and ZCR)', ...
    '5  Sub-200 Hz liveness ratio', ...
    '6  Feature front-end', ...
    '7  DTW alignment against a template'});
stage.Layout.Row = 2; stage.Layout.Column = [2 3];

% Stage 7 needs a SECOND file, and it must be choosable separately from the
% source.  Sharing one dropdown looks tidy and teaches something false: the same
% file selected for both would be compared against itself, yet not give a distance
% of zero, because the capture side goes through PREPROCESS_AUDIO and the template
% side through ENROL_TEMPLATE_FEATURES -- two legitimately different chains.  A
% reader seeing 26.98 where they expected 0 would conclude the matcher is broken.
% With two dropdowns the comparison is always explicit about what is on each side.
l3 = uilabel(g, 'Text', 'Stage 7 template');
l3.Layout.Row = 1; l3.Layout.Column = 6;
tmplList = uidropdown(g, 'Items', corpus_file_list(p), 'Tag', 'explorerTemplate');
tmplList.Layout.Row = 2; tmplList.Layout.Column = 6;

loadBtn = uibutton(g, 'Text', 'Load signal');
loadBtn.Layout.Row = 2; loadBtn.Layout.Column = 4;

showBtn = uibutton(g, 'Text', 'Show stage');
showBtn.Layout.Row = 2; showBtn.Layout.Column = 5;

plotPanel = uipanel(g, 'Title', 'No signal loaded', 'Tag', 'explorerPanel');
plotPanel.Layout.Row = 3; plotPanel.Layout.Column = [1 6];

readout = uitextarea(g, 'Editable', 'off', 'Tag', 'explorerReadout', 'Value', ...
    {['Pick a source, press Load signal, then step through the stages. Every ' ...
      'stage here is the same function the counter runs -- nothing is recomputed ' ...
      'for display except where the readout says so.']});
readout.Layout.Row = 4; readout.Layout.Column = [1 6];
readout.FontName = 'Consolas';

loadBtn.ButtonPushedFcn = @(~,~) explorer_load(fig, source, fileList, readout, plotPanel);
showBtn.ButtonPushedFcn = @(~,~) explorer_show(fig, stage, tmplList, readout, plotPanel);
end

function items = corpus_file_list(p)
%CORPUS_FILE_LIST Every enrolment WAV, as "Phrase/Student/file.wav".
items = {};
folders = {p.trainIdFolder, p.trainNameFolder};
labels = {'ID', 'Name'};
for r = 1:numel(folders)
    files = dir(fullfile(folders{r}, '**', '*.wav'));
    for k = 1:numel(files)
        [~, who] = fileparts(files(k).folder);
        items{end+1} = sprintf('%s/%s/%s', labels{r}, who, files(k).name); %#ok<AGROW>
    end
end
if isempty(items)
    items = {'(no enrolment files found)'};
end
end

function path = corpus_file_path(p, item)
parts = strsplit(item, '/');
if numel(parts) ~= 3
    path = '';
    return;
end
if strcmp(parts{1}, 'ID')
    base = p.trainIdFolder;
else
    base = p.trainNameFolder;
end
path = fullfile(base, parts{2}, parts{3});
end

function explorer_load(fig, source, fileList, readout, plotPanel)
p = fig.UserData.params;
app = fig.UserData;
readout.Value = {'Loading...'};
drawnow;

try
    switch source.Value(1)
        case 'S'    % Synthesised
            % A source-filter synthesis rather than a tone: three of the five
            % proposal modifications reject a pure tone for reasons unrelated to
            % the stage being demonstrated. See SYNTH_VOICED_SIGNAL.
            fs = p.fs;
            quiet = zeros(round(p.noise.NoiseDuration * fs), 1) ...
                  + 0.002 * randn(round(p.noise.NoiseDuration * fs), 1);
            voiced = synth_voiced_signal(fs, 1.2, [115 145], [520 1480 2500], 0.35);
            tail = 0.002 * randn(round(0.3 * fs), 1);
            audio = [quiet; voiced; tail];
            app.explorer.source = 'synthesised voiced sound with a quiet pre-roll';
        case 'E'    % Enrolment file
            path = corpus_file_path(p, fileList.Value);
            if isempty(path) || ~isfile(path)
                readout.Value = {'That corpus file does not exist.'};
                return;
            end
            [audio, fs] = audioread(path);
            app.explorer.source = path;
        otherwise   % Live capture
            fs = p.fs;
            readout.Value = {sprintf('Recording %g s. Stay silent for %.2f s, then speak...', ...
                p.recordDur, p.noise.NoiseDuration)};
            drawnow;
            audio = record_audio_dsp(p.recordDur, fs);
            app.explorer.source = 'live capture';
    end
catch err
    readout.Value = {['Could not load a signal: ' err.message]};
    return;
end

audio = double(audio(:));
app.explorer.audio = audio;
app.explorer.fs = fs;
fig.UserData = app;

plotPanel.Title = sprintf('%s  |  %d samples at %g Hz (%.2f s)', ...
    app.explorer.source, numel(audio), fs, numel(audio)/fs);
clear_panel(plotPanel);
ax = panel_axes(plotPanel, 1, 1);
plot(ax, (0:numel(audio)-1)/fs, audio);
grid(ax, 'on');
xlabel(ax, 'time (s)'); ylabel(ax, 'amplitude');
title(ax, 'Loaded signal, before any processing');

readout.Value = { ...
    sprintf('Loaded %s', app.explorer.source), ...
    sprintf('  %d samples at %g Hz = %.3f s, peak %.4f, RMS %.5f', ...
        numel(audio), fs, numel(audio)/fs, max(abs(audio)), rms_of(audio)), ...
    '  Now choose a stage and press Show stage.'};
end

function explorer_show(fig, stage, tmplList, readout, plotPanel)
p = fig.UserData.params;
app = fig.UserData;
if isempty(app.explorer.audio)
    readout.Value = {'Load a signal first.'};
    return;
end
x = app.explorer.audio;
fs = app.explorer.fs;
clear_panel(plotPanel);
lines = {};

try
    switch stage.Value(1)
        case '1'
            [y, fsOut, info] = rational_resample_audio(x, fs, p.processingFs, p.resample);
            ax1 = panel_axes(plotPanel, 2, 1);
            plot_spectrum(ax1, x, fs, 'before: 44.1 kHz capture');
            ax2 = panel_axes(plotPanel, 2, 2);
            plot_spectrum(ax2, y, fsOut, sprintf('after: %g Hz', fsOut));
            lines = { ...
              sprintf('Rational resampling L/M = %d/%d, exact: %g * %d/%d = %g Hz', ...
                info.L, info.M, fs, info.L, info.M, info.ActualRate), ...
              sprintf('  Kaiser lowpass, order parameter %d, %d taps, beta %g', ...
                info.FilterOrder, info.FilterLength, p.resample.Beta), ...
              sprintf('  new Nyquist %g Hz: everything above it must be removed BEFORE', info.Nyquist), ...
              '  decimation, or it folds back into the speech band as an alias.', ...
              sprintf('  %d samples -> %d samples', numel(x), numel(y))};
        case '2'
            [y, fsOut] = rational_resample_audio(x, fs, p.processingFs, p.resample);
            [z, info] = agc_normalize(y, p.agc);
            ax1 = panel_axes(plotPanel, 2, 1);
            plot(ax1, (0:numel(y)-1)/fsOut, y); grid(ax1,'on');
            title(ax1, sprintf('before AGC, RMS %.5f', info.InputRms));
            xlabel(ax1,'time (s)');
            ax2 = panel_axes(plotPanel, 2, 2);
            plot(ax2, (0:numel(z)-1)/fsOut, z); grid(ax2,'on');
            title(ax2, sprintf('after AGC, RMS %.5f', info.OutputRms));
            xlabel(ax2,'time (s)');
            ylim(ax2, [-1 1]);
            lines = { ...
              sprintf('Gain %.2f applied (cap %g), target RMS %g, achieved %.5f', ...
                info.Gain, p.agc.MaxGain, p.agc.TargetRms, info.OutputRms), ...
              sprintf('  peak limiter engaged: %d (headroom %g)', info.Limited, p.agc.Headroom), ...
              sprintf('  treated as silence: %d (floor RMS %g)', info.Silent, p.agc.MinRms), ...
              '  The gain cap is what stops a near-silent capture being amplified into', ...
              '  something that looks like speech. Without it the noise floor becomes', ...
              '  the signal and every later stage is measuring amplified nothing.'};
        case '3'
            [y, fsOut] = rational_resample_audio(x, fs, p.processingFs, p.resample);
            y = agc_normalize(y, p.agc);
            [z, info] = spectral_subtract_noise(y, fsOut, p.noise);
            ax1 = panel_axes(plotPanel, 2, 1);
            if isempty(info.NoiseMagnitude)
                plot_spectrum(ax1, y, fsOut, 'noise profile unavailable (stage skipped)');
            else
                plot(ax1, info.Frequency, 20*log10(info.NoiseMagnitude + 1e-12));
                grid(ax1,'on'); xlabel(ax1,'frequency (Hz)'); ylabel(ax1,'dB');
                title(ax1, sprintf('noise profile from the first %.2f s (%d frames)', ...
                    info.NoiseDurationUsed, info.NoiseFrames));
            end
            ax2 = panel_axes(plotPanel, 2, 2);
            plot(ax2, (0:numel(y)-1)/fsOut, y, 'Color', [0.7 0.7 0.85]);
            hold(ax2,'on');
            plot(ax2, (0:numel(z)-1)/fsOut, z, 'Color', [0.1 0.1 0.5]);
            hold(ax2,'off'); grid(ax2,'on'); xlabel(ax2,'time (s)');
            legend(ax2, {'before','after'}, 'Location','best');
            title(ax2, 'spectral subtraction, time domain');
            lines = { ...
              sprintf('Oversubtraction alpha %g, spectral floor beta %g', ...
                p.noise.Oversubtraction, p.noise.SpectralFloor), ...
              sprintf('  |X| = max(|Y| - alpha|N|, beta|N|), %d-point FFT, %g ms frames', ...
                info.NFFT, p.noise.FrameDuration*1000), ...
              sprintf('  profile averaged over %d frames = %.2f s of pre-roll', ...
                info.NoiseFrames, info.NoiseDurationUsed), ...
              '  The floor beta is why the output is not driven to zero where the', ...
              '  estimate exceeds the signal: hard-clipping to zero creates the', ...
              '  warbling artefact known as musical noise.', ...
              '  This is the stage that makes the silent pre-roll mandatory. Speak', ...
              '  during it and the system learns your voice as the noise and removes it.'};
        case '4'
            [y, fsOut] = rational_resample_audio(x, fs, p.processingFs, p.resample);
            y = agc_normalize(y, p.agc);
            y = spectral_subtract_noise(y, fsOut, p.noise);
            [speech, info] = hybrid_endpoint_detect(y, fsOut, p.endpoint);
            hop = p.endpoint.HopDuration;
            t = (0:info.NumFrames-1) * hop;
            ax1 = panel_axes(plotPanel, 3, 1);
            plot(ax1, (0:numel(y)-1)/fsOut, y); grid(ax1,'on');
            hold(ax1,'on');
            if info.HasSpeech
                xline(ax1, info.StartSample/fsOut, 'r', 'LineWidth', 1.5);
                xline(ax1, info.EndSample/fsOut, 'r', 'LineWidth', 1.5);
            end
            hold(ax1,'off');
            title(ax1, 'signal with the detected endpoints');
            xlabel(ax1,'time (s)');
            ax2 = panel_axes(plotPanel, 3, 2);
            plot(ax2, t, info.Energy); grid(ax2,'on'); hold(ax2,'on');
            yline(ax2, info.EnergyThreshold, 'r--');
            hold(ax2,'off');
            title(ax2, sprintf('short-time energy, threshold %.3g', info.EnergyThreshold));
            xlabel(ax2,'time (s)');
            ax3 = panel_axes(plotPanel, 3, 3);
            plot(ax3, t, info.Zcr); grid(ax3,'on'); hold(ax3,'on');
            yline(ax3, info.ZcrLow, 'r--'); yline(ax3, info.ZcrHigh, 'r--');
            hold(ax3,'off');
            title(ax3, sprintf('zero-crossing rate, band %.3f to %.3f', ...
                info.ZcrLow, info.ZcrHigh));
            xlabel(ax3,'time (s)');
            lines = { ...
              sprintf('Speech found: %d.  %d of %d frames active.', ...
                info.HasSpeech, info.NumActiveFrames, info.NumFrames), ...
              sprintf('  noise statistics by the %s estimator: STE %.4g, ZCR %.4f', ...
                info.Estimator, info.NoiseEnergy, info.NoiseZcr), ...
              sprintf('  energy threshold = %g x noise STE', p.endpoint.EnergyMultiplier), ...
              sprintf('  ZCR band removed %d loud frames as too impulsive and %d as rumble', ...
                info.RejectedHighZcr, info.RejectedLowZcr), ...
              '  Energy alone cannot tell a door slam from a vowel; a slam is loud and', ...
              '  broadband, so its zero-crossing rate is far above the band. ZCR alone', ...
              '  cannot tell quiet breath from a fricative. The two together can.', ...
              sprintf('  kept %d of %d samples (%.2f s of %.2f s)', ...
                numel(speech), numel(y), numel(speech)/fsOut, numel(y)/fsOut)};
        case '5'
            [y, fsOut] = rational_resample_audio(x, fs, p.processingFs, p.resample);
            y = agc_normalize(y, p.agc);
            y = spectral_subtract_noise(y, fsOut, p.noise);
            y = hybrid_endpoint_detect(y, fsOut, p.endpoint);
            y = agc_normalize(y, p.agc);
            liveOpts = p.liveness;
            liveOpts.Enable = true;
            [reject, ratio, info] = check_liveness_lowfreq(y, fsOut, liveOpts);
            ax1 = panel_axes(plotPanel, 1, 1);
            if isfield(info,'Spectrum') && ~isempty(info.Spectrum)
                plot(ax1, info.Frequency, 10*log10(info.Spectrum + 1e-14));
                grid(ax1,'on'); hold(ax1,'on');
                xline(ax1, liveOpts.LowBand(2), 'r', 'LineWidth', 1.5);
                xline(ax1, liveOpts.FullBand(2), 'k--');
                hold(ax1,'off');
                xlabel(ax1,'frequency (Hz)'); ylabel(ax1,'dB');
                title(ax1, sprintf(['averaged spectrum: sub-%g Hz energy over ' ...
                    '%g-%g Hz energy = %.5f'], liveOpts.LowBand(2), ...
                    liveOpts.FullBand(1), liveOpts.FullBand(2), ratio));
            else
                title(ax1, 'no spectrum available');
            end
            lines = { ...
              sprintf('Ratio %.5f, accepted band %.5f to %.5f, rejected: %d', ...
                ratio, liveOpts.MinRatio, liveOpts.MaxRatio, reject), ...
              sprintf('  %s', info.Reason), ...
              '  This band-energy ratio is a signal-quality heuristic. Pitch, voiced', ...
              '  content, the microphone, room response and playback hardware can all', ...
              '  change it. Genuine speech need not have a fundamental below 200 Hz,', ...
              '  and playback can retain low-frequency energy.', ...
              '  No labeled live-versus-replay corpus establishes replay accuracy here.', ...
              '  Treat the displayed ratio as diagnostic evidence, not proof of a live', ...
              '  person. Labeled live and replay trials are needed for that evaluation.'};
        case '6'
            [y, fsOut, dg] = preprocess_audio(x, fs, p);
            if dg.Rejected || isempty(y)
                lines = {['The chain rejected this signal at the ' dg.Stage ...
                    ' stage, so there are no features to show: ' dg.Reason]};
                ax1 = panel_axes(plotPanel, 1, 1);
                title(ax1, 'rejected before the front-end');
            else
                [f, finfo] = extract_features(y, fsOut, p);
                ax1 = panel_axes(plotPanel, 1, 1);
                imagesc(ax1, f);
                set(ax1, 'YDir', 'normal');
                colorbar(ax1);
                xlabel(ax1, 'frame'); ylabel(ax1, 'coefficient');
                title(ax1, sprintf('%s features: %d dimensions x %d frames', ...
                    upper(finfo.FrontEnd), size(f,1), size(f,2)));
                lines = { ...
                  sprintf('Front-end %s, %g ms frames, %g ms hop, %d-point FFT', ...
                    upper(finfo.FrontEnd), finfo.FrameLength/fsOut*1000, ...
                    finfo.HopLength/fsOut*1000, finfo.Nfft), ...
                  sprintf('  %d dimensions x %d frames = %d numbers describing %.2f s', ...
                    size(f,1), size(f,2), numel(f), numel(y)/fsOut), ...
                  front_end_note(p)};
            end
        case '7'
            [y, fsOut, dg] = preprocess_audio(x, fs, p);
            if dg.Rejected || isempty(y)
                lines = {['The chain rejected this signal at the ' dg.Stage ...
                    ' stage, so there is nothing to align: ' dg.Reason]};
                ax1 = panel_axes(plotPanel, 1, 1);
                title(ax1, 'rejected before the matcher');
            else
                a = extract_features(y, fsOut, p);
                tmplPath = corpus_file_path(p, tmplList.Value);
                b = enrol_template_features(tmplPath, [], p);
                if isempty(b)
                    lines = {sprintf(['The chosen template %s is not enrollable, ' ...
                        'so it cannot be aligned against. Pick another file in the ' ...
                        'Stage 7 template dropdown.'], tmplList.Value)};
                    ax1 = panel_axes(plotPanel, 1, 1);
                    title(ax1, 'template not enrollable');
                else
                    opts = p.dtw;
                    opts.ReturnPath = true;
                    [d, dinfo] = dtw_distance_dsp(a, b, opts);
                    ax1 = panel_axes(plotPanel, 1, 1);
                    surf = dinfo.Accumulated;
                    surf(~isfinite(surf)) = NaN;
                    imagesc(ax1, surf, 'AlphaData', ~isnan(surf));
                    set(ax1, 'YDir', 'normal'); colorbar(ax1);
                    hold(ax1, 'on');
                    plot(ax1, dinfo.Path(2,:), dinfo.Path(1,:), 'r-', 'LineWidth', 2);
                    hold(ax1, 'off');
                    xlabel(ax1, sprintf('template frames (%s)', tmplList.Value));
                    ylabel(ax1, sprintf('capture frames (%s)', app.explorer.source));
                    title(ax1, sprintf(['accumulated cost with the optimal path, ' ...
                        'normalised distance %.4f'], d));
                    [idLimit,nameLimit] = phrase_limits(p);
                    lines = { ...
                      sprintf('Capture side : %s, through PREPROCESS_AUDIO', ...
                        app.explorer.source), ...
                      sprintf('Template side: %s, through ENROL_TEMPLATE_FEATURES', ...
                        tmplList.Value), ...
                      sprintf('Pair distance %.4f. ID distance ceiling %.4f; name ceiling %.4f.', ...
                        d, idLimit, nameLimit), ...
                      'Single-template alignment is diagnostic. ID is tried first; name is a fallback. The accepting phrase must pass every identity gate.', ...
                      sprintf('  %d x %d frames, Sakoe-Chiba half-width %d cells, %d cells evaluated', ...
                        dinfo.Rows, dinfo.Cols, dinfo.Band, dinfo.CellsEvaluated), ...
                      sprintf('  raw accumulated cost %.4f, divided by (N+M) = %d', ...
                        dinfo.RawDistance, dinfo.Rows + dinfo.Cols), ...
                      '  The white region is outside the corridor. Without it a single', ...
                      '  frame of one recording could be stretched across most of the', ...
                      '  other, which produces a small distance for an impostor.', ...
                      '  A path that hugs the diagonal means the two recordings had a', ...
                      '  similar speaking rate; a staircase means one talker was slower.', ...
                      '  Choosing the SAME file on both sides does not give zero, and that', ...
                      '  is correct rather than a fault: a live capture and a stored', ...
                      '  template take deliberately different routes to features. The', ...
                      '  capture has a noise pre-roll to profile and endpoints to find; the', ...
                      '  template may already be cropped. The distance between the two', ...
                      '  routes over one file is a useful thing to look at -- it is the', ...
                      '  floor below which no genuine attempt can go.'};
                end
            end
        otherwise
            lines = {'Unknown stage.'};
    end
catch err
    lines = {['This stage failed on the loaded signal: ' err.message]};
end

readout.Value = lines(:);
end

function w = verdict_word(tf)
if tf, w = 'within the threshold'; else, w = 'outside the threshold'; end
end

function note = front_end_note(p)
if strcmpi(p.featureFrontEnd, 'mfcc')
    note = ['  MFCC: mel filterbank, log, DCT, then delta and delta-delta. The DCT ' ...
        'decorrelates the log-mel bands so a Euclidean frame distance is meaningful.'];
else
    note = ['  Proposal front-end: uniform log magnitude-spectrum bands with ' ...
        'per-utterance mean and variance normalisation, which is what makes it ' ...
        'insensitive to a fixed channel tilt.'];
end
end

function clear_panel(panel)
delete(panel.Children);
end

function ax = panel_axes(panel, total, index)
%PANEL_AXES One of TOTAL stacked axes inside PANEL, created on demand.
%   uipanel does not lay out its children, so the axes are positioned in
%   normalised units. Building them here keeps every stage's plotting code free of
%   geometry.
%
%   Why the interpreter is turned off here
%   ------------------------------------
%   MATLAB axes labels default to the TeX interpreter, and several of the stage
%   labels interpolate a filename: on Windows that filename is
%   Train\Name\<student>\1.wav, whose backslashes TeX reads as control sequences.
%   The failure is nastier than a mis-rendered label, because the error is raised
%   not at the TITLE call but at the next DRAWNOW -- so it surfaced as a warning
%   blaming an unrelated status update three functions away.  Setting it once on
%   the three Text objects every axes already owns means no stage can be broken
%   by a path, an underscore or a caret in a student's name.
h = 1 / total;
ax = uiaxes(panel, 'Units', 'normalized', ...
    'Position', [0.07, 1 - index*h + 0.10*h, 0.88, 0.80*h]);
ax.Title.Interpreter  = 'none';
ax.XLabel.Interpreter = 'none';
ax.YLabel.Interpreter = 'none';
end

function plot_spectrum(ax, x, fs, label)
%PLOT_SPECTRUM Magnitude spectrum in dB, for the resampling panel.
if isempty(x)
    title(ax, [label ' (empty)']);
    return;
end
n = 2^nextpow2(min(numel(x), 8192));
seg = x(1:min(numel(x), n));
seg = seg .* (0.5 - 0.5*cos(2*pi*(0:numel(seg)-1)'/max(1,numel(seg)-1)));
X = abs(fft(seg, n));
k = floor(n/2) + 1;
plot(ax, (0:k-1)*fs/n, 20*log10(X(1:k) + 1e-12));
grid(ax, 'on');
xlabel(ax, 'frequency (Hz)'); ylabel(ax, 'dB');
title(ax, label);
end

function r = rms_of(x)
if isempty(x), r = 0; else, r = sqrt(mean(x.^2)); end
end

% =========================================================================
% Evaluation tab
% =========================================================================
function build_evaluation_tab(fig, tabs)
p = fig.UserData.params;
tab = uitab(tabs, 'Title', 'Evaluation', 'Tag', 'adminEvaluationTab');
g = uigridlayout(tab, [5 5]);
g.RowHeight = {34, 34, '1x', 150, 22};
g.ColumnWidth = {180, 320, 170, 170, '1x'};
g.Padding = [18 14 18 12];

l1 = uilabel(g, 'Text', 'Experiment'); l1.Layout.Row = 1; l1.Layout.Column = 1;
which = uidropdown(g, 'Tag', 'evalExperiment', 'Items', { ...
    'vsd_evaluate_corpus - v4.1.4_Final engine on every stored voice (minutes)', ...
    'test_vsd_engine - genuine / imposter / replay demo (about a minute)', ...
    'verify_dsp_pipeline (fast, 15 checks)', ...
    'diagnose_audio_corpus (fast)', ...
    'calibrate_liveness_band (about a minute)', ...
    'experiment_verification_accuracy, mfcc (minutes)', ...
    'experiment_verification_accuracy, dft (minutes)', ...
    'recalibrate_thresholds (minutes)', ...
    'experiment_frontend_comparison (long: 13 conditions)', ...
    'experiment_channel_robustness (long)'});
which.Layout.Row = 1; which.Layout.Column = 2;

runBtn = uibutton(g, 'Text', 'Run it');
runBtn.Layout.Row = 1; runBtn.Layout.Column = 3;

l2 = uilabel(g, 'Text', 'Stored result'); l2.Layout.Row = 2; l2.Layout.Column = 1;
csvList = uidropdown(g, 'Tag', 'evalCsv', 'Items', results_file_list(p));
csvList.Layout.Row = 2; csvList.Layout.Column = 2;

showBtn = uibutton(g, 'Text', 'Show table');
showBtn.Layout.Row = 2; showBtn.Layout.Column = 3;

refreshBtn = uibutton(g, 'Text', 'Refresh list');
refreshBtn.Layout.Row = 2; refreshBtn.Layout.Column = 4;

view = uitable(g, 'Tag', 'evalTable', 'ColumnName', {}, 'RowName', {});
view.Layout.Row = 3; view.Layout.Column = [1 5];

summary = uitextarea(g, 'Editable', 'off', 'Tag', 'evalSummary', 'Value', headline_figures(p));
summary.Layout.Row = 4; summary.Layout.Column = [1 5];
summary.FontName = 'Consolas';

note = uilabel(g, 'Text', ['Experiments print to the command window and write to ' ...
    p.evaluation.ResultsFolder '. The window stays responsive but the run blocks it.']);
note.Layout.Row = 5; note.Layout.Column = [1 5];
note.FontColor = [0.35 0.35 0.35];

runBtn.ButtonPushedFcn = @(~,~) run_experiment(fig, which, summary, csvList);
showBtn.ButtonPushedFcn = @(~,~) show_result_csv(fig, csvList, view, summary);
refreshBtn.ButtonPushedFcn = @(~,~) set(csvList, 'Items', results_file_list(fig.UserData.params));
end

function items = results_file_list(p)
files = dir(fullfile(p.evaluation.ResultsFolder, '*.csv'));
items = {files.name};
extra = dir(fullfile(p.evaluation.ResultsFolder, 'final_eval', '*.csv'));
items = [strcat('final_eval/', {extra.name}), items];
if isempty(items)
    items = {'(no result CSVs yet - run an experiment)'};
end
end

function run_experiment(fig, which, summary, csvList)
p = fig.UserData.params;
choice = which.Value;
update_status_text(summary, sprintf('Running: %s. Watch the command window.', choice));
drawnow;
try
    % Each of these reads DSP_PARAMETERS for itself so that a result written to
    % Results/ is always the deployed configuration's result and never a
    % half-modified struct held by a window. RECALIBRATE_THRESHOLDS is the one
    % exception: it is handed PARAMS because its whole job is to walk every
    % front-end in it.
    if startsWith(choice, 'vsd_evaluate_corpus')
        E = vsd_evaluate_corpus(fullfile(p.evaluation.ResultsFolder, 'final_eval'));
        update_status_text(summary, strjoin(E.summary, newline));
    elseif startsWith(choice, 'test_vsd_engine')
        test_vsd_engine();
    elseif startsWith(choice, 'verify_dsp_pipeline')
        verify_dsp_pipeline();
    elseif startsWith(choice, 'diagnose_audio_corpus')
        diagnose_audio_corpus();
    elseif startsWith(choice, 'calibrate_liveness_band')
        calibrate_liveness_band('', p);
    elseif startsWith(choice, 'experiment_verification_accuracy, mfcc')
        experiment_verification_accuracy([], 'mfcc');
    elseif startsWith(choice, 'experiment_verification_accuracy, dft')
        experiment_verification_accuracy([], 'dft');
    elseif startsWith(choice, 'recalibrate_thresholds')
        recalibrate_thresholds(p);
    elseif startsWith(choice, 'experiment_frontend_comparison')
        experiment_frontend_comparison();
    else
        experiment_channel_robustness();
    end
    update_status_text(summary, ['  finished: ' choice]);
catch err
    update_status_text(summary, ['  FAILED: ' err.message]);
end
csvList.Items = results_file_list(p);
end

function show_result_csv(fig, csvList, view, summary)
p = fig.UserData.params;
path = fullfile(p.evaluation.ResultsFolder, csvList.Value);
if ~isfile(path)
    update_status_text(summary, sprintf('%s does not exist yet.', path));
    return;
end
data = readtable(path, 'TextType', 'string');
view.Data = data;
view.ColumnName = data.Properties.VariableNames;
update_status_text(summary, sprintf('%s: %d rows, %d columns.', ...
    csvList.Value, height(data), width(data)));
end

function lines = headline_figures(p)
%HEADLINE_FIGURES Display configured gates, not historical accuracy as current.
[idLimit,nameLimit,idMargin,nameMargin] = phrase_limits(p);
lines = { ...
  sprintf('Configured: %s front-end at %g Hz, up to %.1f s per phrase; stops after detected pause', ...
    upper(p.featureFrontEnd), p.processingFs, p.recordDur), ...
  sprintf('ID: distance <= %.4f and runner-up margin >= %.3f', idLimit,idMargin), ...
  sprintf('Name: distance <= %.4f and runner-up margin >= %.3f', nameLimit,nameMargin), ...
  '', ...
  'ID is tried once first. Name is tried once only if ID cannot verify the claim.', ...
  'The accepting phrase must select the independently entered Student ID and pass both gates.', ...
  'If ID and fallback name both fail, the result is FAILED; no automatic repeat.', ...
  'These are configured limits. They are not probabilities or measured accuracy.', ...
  'Use a completed experiment''s accuracy_results.csv and recording_manifest.csv', ...
  'for FAR, FRR and wrong-student acceptance with their stated denominators.', ...
  'Old perPhraseReference figures describe earlier corpora and are not current results.', ...
  '', ...
  sprintf('Frontend gate maps: %s', threshold_summary(p))};
if isfield(p,'voiceCalibration')
    lines{end+1} = sprintf('Deployment file: %s',p.voiceCalibration.File);
    lines{end+1} = 'A frontend without phrase calibration for this enrollment is disabled.';
else
    lines{end+1} = 'No saved deployment calibration is active; legacy defaults are configured.';
end
end

function s = threshold_summary(p)
if isfield(p,'voiceCalibration')
    names = fieldnames(p.speakerThresholdsByFrontEnd);
    parts = cell(1,numel(names));
    for k = 1:numel(names)
        g = p.speakerThresholdsByFrontEnd.(names{k});
        parts{k} = sprintf('%s ID %.4f / name %.4f',names{k},g.idDtwThreshold,g.nameDtwThreshold);
    end
else
    names = fieldnames(p.dtwThresholdByFrontEnd);
    parts = cell(1, numel(names));
    for k = 1:numel(names)
        parts{k} = sprintf('%s legacy scalar %.4f', names{k}, p.dtwThresholdByFrontEnd.(names{k}));
    end
end
s = strjoin(parts, ', ');
end

function [idLimit,nameLimit,idMargin,nameMargin] = phrase_limits(p)
values = [p.dtwThreshold p.dtwThreshold p.dtwMarginRatio p.dtwMarginRatio];
names = {'idDtwThreshold','nameDtwThreshold','idMarginRatio','nameMarginRatio'};
for k = 1:numel(names)
    if isfield(p,names{k}) && ~isempty(p.(names{k})), values(k) = p.(names{k}); end
end
idLimit = values(1); nameLimit = values(2); idMargin = values(3); nameMargin = values(4);
end

% =========================================================================
function text = footer_text(p)
%FOOTER_TEXT Every value formatted from PARAMS, so the footer cannot go stale.
windows = cell(1, numel(p.meals));
for k = 1:numel(p.meals)
    windows{k} = sprintf('%s %02d:%02d-%02d:%02d', p.meals(k).Name, ...
        p.meals(k).Start(1), p.meals(k).Start(2), ...
        p.meals(k).End(1), p.meals(k).End(2));
end
if isfield(p,'vsd') && isstruct(p.vsd) && p.vsd.Enable
    text = sprintf('ENGINE %s | words (DTW, cohort) + voice (GMM-UBM) + random-digit anti-replay | %s', ...
        p.vsd.Version, strjoin(windows, '  '));
    return;
end
[idLimit,nameLimit,idMargin,nameMargin] = phrase_limits(p);
text = sprintf('LEGACY v4.1.4 MATCHER | %s %g Hz | ID <= %.3f / margin >= %.2f | Name <= %.3f / margin >= %.2f | %s', ...
    upper(p.featureFrontEnd), p.processingFs, idLimit,idMargin,nameLimit,nameMargin, ...
    strjoin(windows, '  '));
end

function admin_reset_meal_log(fig, adminId, pass, view, message)
%ADMIN_RESET_MEAL_LOG Operator prompt to reset today's or all meal log entries.
if ~admin_authorised(fig, adminId, pass, message), return; end
p = fig.UserData.params;
if ~isfile(p.logFile)
    message.Text = sprintf('No meal log file (%s) exists yet to reset.', p.logFile);
    message.FontColor = [0.35 0.35 0.35];
    return;
end

choice = uiconfirm(fig, ...
    sprintf(['Choose how to reset meal entries in %s:\n\n' ...
    '• "Reset today only": Clears today''s meal records so students can be served again today.\n' ...
    '• "Clear entire log": Deletes all serving history from the log.\n\n' ...
    'NOTE: Enrolled student voice profiles (Train/ID and Train/Name) will NOT be affected.'], p.logFile), ...
    'Reset Meal Log Data', ...
    'Options', {'Reset today only', 'Clear entire log', 'Cancel'}, ...
    'DefaultOption', 'Reset today only', ...
    'CancelOption', 'Cancel');

switch choice
    case 'Reset today only'
        todayStr = string(datetime('now'), 'yyyy-MM-dd');
        [nRemoved, nRemaining] = reset_meal_log_csv(p.logFile, 'today', todayStr);
        message.Text = sprintf('● Meal log reset: %d today''s record(s) removed (%d historical record(s) preserved). Voice profiles untouched.', ...
            nRemoved, nRemaining);
        message.FontColor = [0.05 0.40 0.05];
        if strcmp(view.Visible, 'on')
            admin_refresh_meal_log(fig,view);
        end
        
    case 'Clear entire log'
        [nRemoved, ~] = reset_meal_log_csv(p.logFile, 'all');
        message.Text = sprintf('● Entire meal log cleared (%d record(s) removed). Enrolled voice profiles are 100%% untouched.', ...
            nRemoved);
        message.FontColor = [0.05 0.40 0.05];
        if strcmp(view.Visible, 'on')
            admin_refresh_meal_log(fig,view);
        end
        
    otherwise
        message.Text = 'Meal log reset cancelled; no records were changed.';
        message.FontColor = [0.35 0.35 0.35];
end
end

function update_reset_button(fig, viewType) %#ok<INUSD>
resetBtn=findobj(fig,'Tag','adminResetMealsBtn');
if isempty(resetBtn), return; end
resetBtn.Text='Reset meal log...';
resetBtn.Tooltip='Reset meal entries; monthly assignments are managed by ID';
end
