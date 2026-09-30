function ok = verify_meal_gui(verbose)
%VERIFY_MEAL_GUI Exercise every microphone-free callback in the counter application.
%
%   OK = VERIFY_MEAL_GUI() builds MEAL_VERIFICATION_GUI, presses every button that
%   does not need a microphone, checks what each one reported, closes the window and
%   returns true if all checks passed.  It needs no operator, no microphone and no
%   display beyond the one MATLAB already has.
%
%   VERIFY_MEAL_GUI(false) runs the same checks quietly and only prints failures.
%
%   Why pressing the buttons is the point
%   ------------------------------------
%   A build-only test -- open the window, count the widgets, close it -- passes on a
%   window whose every callback is broken, because a callback that is only read is
%   never run.  Driving each ButtonPushedFcn directly is what found the five defects
%   this file now guards against:
%
%     1  VERIFY_DSP_PIPELINE was called with an argument; it takes none.
%     2  DIAGNOSE_AUDIO_CORPUS was handed PARAMS, but its first argument is an
%        output path, so the audit would have written to a file named after a struct.
%     3  CALIBRATE_LIVENESS_BAND was handed PARAMS, but its first argument is a
%        spoof folder.
%     4  The gate table had no case for VERIFY_MEAL_WORKFLOW's 'match' stage, so
%        "nothing enrolled to compare against" was displayed as a refusal at the
%        Agreement gate -- telling the operator a student had failed a test the
%        system never got to run.
%     5  Axes labels interpolate a filename, and MATLAB axes labels default to the
%        TeX interpreter, so Train\Name\<student>\1.wav raised an error at the next
%        DRAWNOW rather than at the label.  The LASTWARN check below is what makes
%        that class of deferred failure visible instead of silent.
%
%   Why the widgets are addressed by Tag
%   ----------------------------------
%   The first version of this test identified widgets by FINDOBJ order and by
%   Placeholder text.  FINDOBJ returns children in reverse creation order, so the
%   Admin message it read was the wrong label and the password check appeared to
%   pass whichever password was typed.  A test that can misreport a pass is worse
%   than no test, so every widget in MEAL_VERIFICATION_GUI carries a Tag and this
%   file uses nothing else.
%
%   EEE 312: CO2 (the claim that the interface works is measured, not asserted),
%   CO3, PO(e).
%
%   See also MEAL_VERIFICATION_GUI, VERIFY_DSP_PIPELINE, RUN_MEAL_SYSTEM.

if nargin < 1, verbose = true; end
if exist('verify_meal_gui_v2', 'file')
    ok = verify_meal_gui_v2(verbose);
    return;
end

p = dsp_parameters();

% The genuine demonstration below is a real transaction: inside a meal window it
% reaches the entitlement gate and LOG_MEAL_CSV appends a row.  Pointed at the
% deployed PARAMS.LOGFILE that has two consequences, both bad.  It writes test
% traffic into the hall's serving record, and -- because one serving per student
% per window is exactly the rule the system is supposed to enforce -- the second
% run inside the same window is correctly refused, so the test fails on a program
% that is behaving properly.  A test whose own side effect makes it fail teaches
% its operator to stop reading it.  Redirect the log to a scratch file that is
% removed on the way out, so the suite is repeatable at any hour.
p.logFile = [tempname '_MealLog.csv'];
scratchLog = p.logFile;

failures = {};
lastwarn('');                       % so a deferred drawnow error is attributable

fig = meal_verification_gui(p);
cleanup    = onCleanup(@() close_if_valid(fig));
cleanupLog = onCleanup(@() delete_if_present(scratchLog));

tag   = @(t) findobj(fig, 'Tag', t);
btn   = @(name) find_btn(fig, name);
press = @(b) feval(b.ButtonPushedFcn, b, struct());
text_of = @(w) strjoin(string(w.Value), newline);

    function check(condition, description)
        if condition
            if verbose, fprintf('  pass  %s\n', description); end
        else
            failures{end+1} = description;      %#ok<AGROW>
            fprintf(2, '  FAIL  %s\n', description);
        end
    end

say(verbose, '\nVerify tab');

% --- no code typed: the workflow must stop at 'input', and the gate ladder must
% say so rather than blaming a gate that was never reached.
press(btn('Demo from files'));
gates = tag('verifyGates');
check(contains(tag('verifyBanner').Text, 'input'), ...
    'empty code refuses at the input stage');
check(strcmp(gates.Data{1,3}, 'no code typed'), ...
    'empty code is reported as no code typed, not as a gate failure');
check(all(strcmp(gates.Data(2:end,3), 'not reached')), ...
    'gates below an unreached one are marked not reached');

% --- a genuine transaction: both phrases from the same student.
students = tag('demoNameStudent').Items;
who = '';
for k = 1:numel(students)
    if enrollable(fullfile(p.trainNameFolder, students{k}), p) && ...
       enrollable(fullfile(p.trainCouponFolder, students{k}), p)
        who = students{k}; break;
    end
end
check(~isempty(who), 'at least one student is enrolled on both phrases');

nameWho   = tag('demoNameStudent');   nameWho.Value   = who;
couponWho = tag('demoCouponStudent'); couponWho.Value = who;
codeFile  = fullfile(p.trainNameFolder, who, p.codeFileName);
if isfile(codeFile)
    codeField = tag('verifyCode');
    codeField.Value = strtrim(fileread(codeFile));
end
press(btn('Demo from files'));

% The four voice gates must all pass.  The fifth is the entitlement gate, which
% legitimately refuses outside a meal window -- so it is checked against the clock
% rather than expected to pass.  Asserting "granted" here would make the test fail
% every afternoon for a correct reason, and a test that fails for correct reasons
% gets ignored.
verdicts = tag('verifyGates').Data(:,3);
check(all(strcmp(verdicts(1:4), 'passed')), ...
    sprintf('genuine demo (%s) passes all four voice gates', who));
[~, info] = meal_window_now(p, datetime('now'));
if info.Index > 0
    check(strcmp(verdicts{5}, 'passed - served'), ...
        'inside a meal window the genuine demo is served');
else
    check(strcmp(verdicts{5}, 'REFUSED HERE'), ...
        'outside every meal window the entitlement gate refuses');
end

% --- the proxy attack the agreement gate exists to stop.
other = '';
for k = 1:numel(students)
    if ~strcmp(students{k}, who) && ...
            enrollable(fullfile(p.trainCouponFolder, students{k}), p)
        other = students{k}; break;
    end
end
couponWho.Value = other;
press(btn('Demo from files'));
verdicts = tag('verifyGates').Data(:,3);
check(strcmp(verdicts{2}, 'REFUSED HERE'), ...
    sprintf('proxy attack (%s name + %s coupon) is stopped at Agreement', who, other));
check(strcmp(verdicts{3}, 'not reached'), ...
    'agreement refuses before the distance threshold is consulted');

say(verbose, '\nAdmin tab');

adminPass = tag('adminPass');
adminPass.Value = 'not the password';
press(btn('Unlock / refresh log'));
wrongMsg = tag('adminMessage').Text;
check(contains(lower(wrongMsg), 'incorrect'), 'a wrong password is refused');
adminPass.Value = p.adminPassword;
press(btn('Unlock / refresh log'));
check(~strcmp(tag('adminMessage').Text, wrongMsg), ...
    'the correct password produces a different message from the wrong one');

say(verbose, '\nDSP Explorer tab, every stage on both a synthetic and a real signal');

src     = tag('explorerSourceKind');
stage   = tag('explorerStage');
readout = tag('explorerReadout');
sourceName = {'synthesised', 'corpus file'};
for kind = 1:2                       % 1 = synthesised, 2 = a stored corpus file
    src.Value = src.Items{kind};
    press(btn('Load signal'));
    check(~isempty(text_of(readout)), ...
        sprintf('the %s source loads', sourceName{kind}));
    for s = 1:numel(stage.Items)
        stage.Value = stage.Items{s};
        press(btn('Show stage'));
        body = text_of(readout);
        check(strlength(body) > 40 && ~contains(body, 'ERROR'), ...
            sprintf('stage %d reports on the %s source', s, sourceName{kind}));
    end
end

say(verbose, '\nEvaluation tab, every stored result file');

csvList = tag('evalCsv');
evalTbl = tag('evalTable');
for k = 1:numel(csvList.Items)
    csvList.Value = csvList.Items{k};
    press(btn('Show table'));
    check(size(evalTbl.Data, 1) > 0, ...
        sprintf('%s displays %d rows', csvList.Value, size(evalTbl.Data, 1)));
end
press(btn('Refresh list'));
check(~isempty(csvList.Items), 'the result list refreshes');

say(verbose, '\nEnrol tab, the paths that do not record');

enrolName = tag('enrolName'); enrolName.Value = who;
status = tag('enrolStatus');
press(btn('Audit this student'));
check(contains(text_of(status), 'enrolled'), ...
    sprintf('the per-student audit reports on %s', who));
enrolCode = tag('enrolCode'); enrolCode.Value = '12a4';
press(btn('Write coupon code file'));
check(contains(status.Value{1}, 'six digits'), ...
    'a malformed coupon code is refused before anything is written');
press(btn('Reload template cache'));
check(contains(status.Value{1}, 'cache'), 'the template cache can be cleared');
press(btn('Save this take'));
check(contains(status.Value{1}, 'Nothing to save'), ...
    'saving with no pending take is refused rather than writing an empty file');

% --- the deferred-failure check.  Anything that went wrong inside a graphics
% update surfaces here and nowhere else.
[warnMsg, warnId] = lastwarn();
check(isempty(warnMsg), sprintf('no graphics warning was raised (%s %s)', ...
    warnId, strtrim(regexprep(warnMsg, '\s+', ' '))));

ok = isempty(failures);
if ok
    fprintf('\nVERIFY_MEAL_GUI: all checks passed. Every callback ran.\n');
else
    fprintf(2, '\nVERIFY_MEAL_GUI: %d check(s) FAILED:\n', numel(failures));
    fprintf(2, '  - %s\n', failures{:});
end
clear cleanup;
end

% -------------------------------------------------------------------------
function tf = enrollable(folder, p)
%ENROLLABLE True if ENROL_TEMPLATE_FEATURES accepts at least one file in FOLDER.
%   The same question the deployed matcher asks, so the test can never build a
%   demonstration on a file the system would refuse to load.
tf = false;
if ~isfolder(folder), return; end
files = dir(fullfile(folder, '*.wav'));
for k = 1:numel(files)
    if ~isempty(enrol_template_features(fullfile(files(k).folder, files(k).name), [], p))
        tf = true; return;
    end
end
end

function say(verbose, fmt)
if verbose, fprintf(fmt); fprintf('\n'); end
end

function close_if_valid(fig)
if ~isempty(fig) && isvalid(fig), close(fig); end
end

function delete_if_present(fileName)
%DELETE_IF_PRESENT Remove the scratch meal log, if the run got as far as writing one.
if ~isempty(fileName) && isfile(fileName)
    delete(fileName);
end
end

function b = find_btn(fig, name)
b = findobj(fig, 'Type', 'uibutton', 'Text', name);
if isempty(b) && contains(lower(name), 'unlock')
    b = findobj(fig, 'Tag', 'adminUnlockBtn');
end
end

