function ok = test_enrol_discard_and_stop()
%TEST_ENROL_DISCARD_AND_STOP Verify Discard profile button functionality,
%instant stop 1-click termination, and session .wav cleanup.

failures = {};
check = @(cond, msg) record_check(cond, msg);

    function record_check(cond, msg)
        if cond
            fprintf('  PASS: %s\n', msg);
        else
            fprintf(2, '  FAIL: %s\n', msg);
            failures{end+1} = msg;
        end
    end

fprintf('\n--- 1. Testing GUI Discard Button Configuration ---\n');
fig = [];
try
    fig = meal_verification_gui();
    cleanupFig = onCleanup(@() close_fig_safe(fig));
    drawnow;
    adminId = findobj(fig, 'Tag', 'adminId');
    adminPass = findobj(fig, 'Tag', 'adminPass');
    workspaceBtn = findobj(fig, 'Tag', 'adminWorkspaceBtn');
    if ~isempty(adminId) && ~isempty(adminPass) && ~isempty(workspaceBtn)
        adminId.Value = 'admin';
        adminPass.Value = 'admin';
        feval(workspaceBtn.ButtonPushedFcn, workspaceBtn, struct());
    end
    drawnow;
    discardBtn = findobj(fig, 'Tag', 'enrolDiscardBtn');
    stopBtn    = findobj(fig, 'Tag', 'enrolStopBtn');
    
    check(~isempty(discardBtn), 'enrolDiscardBtn exists in GUI');
    if ~isempty(discardBtn)
        check(strcmp(discardBtn.Enable, 'on'), 'Discard profile button starts enabled when idle');
        check(contains(lower(discardBtn.Text), 'discard'), 'Discard button text indicates discard/reset');
        check(~isempty(discardBtn.ButtonPushedFcn), 'Discard button has active callback');
    end
    
    check(~isempty(stopBtn), 'enrolStopBtn exists in GUI');
    if ~isempty(stopBtn)
        check(strcmp(stopBtn.Enable, 'off'), 'Instant Stop button starts disabled when idle');
    end
catch err
    check(false, sprintf('GUI launch check failed: %s', err.message));
end

fprintf('\n--- 2. Testing Student Recordings Deletion Helper ---\n');
testDir = fullfile(tempname, 'ID', '9999999');
mkdir(testDir);
cleanupDir = onCleanup(@() rm_if_present(fileparts(fileparts(testDir))));

% Create 3 dummy wav files
fs = 8000;
dummyAudio = zeros(fs, 1);
audiowrite(fullfile(testDir, '1.wav'), dummyAudio, fs);
audiowrite(fullfile(testDir, '2.wav'), dummyAudio, fs);
audiowrite(fullfile(testDir, '3.wav'), dummyAudio, fs);

check(numel(dir(fullfile(testDir, '*.wav'))) == 3, 'Created 3 dummy .wav files in test profile');

delete_student_recordings({testDir});
check(numel(dir(fullfile(testDir, '*.wav'))) == 0, 'delete_student_recordings successfully deleted all .wav files');

fprintf('\n--- 3. Testing Session Rollback on Instant Stop ---\n');
sessionFile1 = fullfile(testDir, '1.wav');
sessionFile2 = fullfile(testDir, '2.wav');
audiowrite(sessionFile1, dummyAudio, fs);
audiowrite(sessionFile2, dummyAudio, fs);
check(isfile(sessionFile1) && isfile(sessionFile2), 'Session files created');

mockFig = uifigure('Visible', 'off');
cleanupMock = onCleanup(@() close_fig_safe(mockFig));
mockFig.UserData = struct('enrolStopRequested', true);
mockStatus = [];
rollback_enrol_session(mockFig, mockStatus, 'ID', {sessionFile1, sessionFile2});

check(~isfile(sessionFile1) && ~isfile(sessionFile2), 'rollback_enrol_session deleted all session files');
check(~mockFig.UserData.enrolStopRequested, 'rollback_enrol_session cleared enrolStopRequested flag');

if isempty(failures)
    fprintf('\n>>> ALL ENROLL DISCARD & STOP TESTS PASSED! <<<\n\n');
    ok = true;
else
    fprintf(2, '\n>>> %d CHECK(S) FAILED <<<\n\n', numel(failures));
    ok = false;
end
end

function close_fig_safe(fig)
if ~isempty(fig) && isvalid(fig), close(fig); end
end

function rm_if_present(folder)
if isfolder(folder), rmdir(folder, 's'); end
end
