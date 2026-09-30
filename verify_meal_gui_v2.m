 function ok = verify_meal_gui_v2(verbose)
%VERIFY_MEAL_GUI_V2 Validate the privacy-focused v2 GUI without a microphone.
if nargin < 1, verbose = true; end
failures = {};
p = dsp_parameters();
p.logFile = [tempname '.csv'];
p.monthlyEntitlementFile = [tempname '.csv'];
cleanup = onCleanup(@() cleanup_files(p.logFile, p.monthlyEntitlementFile)); %#ok<NASGU>
fig = meal_verification_gui(p);
closeOnExit = onCleanup(@() close_if_valid(fig)); %#ok<NASGU>
findTag = @(tag) findobj(fig, 'Tag', tag);

check(~isempty(findTag('verifyCode')), 'public coupon field exists');
check(~isempty(findTag('verifyLiveBtn')), 'public voice verification button exists');
check(isempty(findTag('newEnrollBtn')), ...
    'New Enroll is not exposed on the public Verify Meal surface');
check(isempty(findTag('demoNameStudent')) || all(strcmp({findTag('demoNameStudent').Visible}, 'off')), ...
    'public identity selectors are hidden');
check(isempty(findTag('demoCouponStudent')) || all(strcmp({findTag('demoCouponStudent').Visible}, 'off')), ...
    'public coupon selectors are hidden');

id = findTag('adminId');
pass = findTag('adminPass');
message = findTag('adminMessage');
view = findTag('adminTable');
check(~isempty(id) && ~isempty(pass), 'admin ID and password fields exist');
check(strcmp(view.Visible, 'off'), 'private table starts locked');

id.Value = 'wrong';
pass.Value = 'wrong';
adminButton = findTag('adminUnlockBtn');
feval(adminButton.ButtonPushedFcn, adminButton, struct());
check(contains(lower(message.Text), 'incorrect'), 'wrong admin credentials are refused');

id.Value = 'admin';
pass.Value = 'admin';
feval(adminButton.ButtonPushedFcn, adminButton, struct());
check(strcmp(view.Visible, 'on'), 'correct admin credentials reveal private data view');
workspaceButton = findTag('adminWorkspaceBtn');
if isempty(workspaceButton)
    workspaceButton = findobj(fig, 'Type', 'uibutton', 'Text', 'Open DSP workspace');
end
if ~isempty(workspaceButton)
    feval(workspaceButton.ButtonPushedFcn, workspaceButton, struct());
    check(~isempty(findTag('adminExplorerTab')), 'admin unlock opens private DSP workspace');
    newEnroll = findTag('newEnrollBtn');
    check(~isempty(newEnroll), 'private DSP workspace provides a New Enroll button');
    if ~isempty(newEnroll)
        check(strcmp(newEnroll.Text, 'New Enroll'), ...
            'automated enrollment action has the requested label');
        check(~isempty(newEnroll.ButtonPushedFcn), ...
            'New Enroll button has an interactive callback');
        check(~isempty(findTag('enrolName')) && (~isempty(findTag('enrolCode')) || ~isempty(findTag('adminCouponCode'))) && ...
            ~isempty(findTag('enrolTakes')), ...
            'New Enroll uses the private name, coupon-code, and trial-count inputs');
        check(~isempty(findTag('enrolStudentId')), ...
            'private enrollment asks for a seven-digit Student ID');
        check(~isempty(findTag('enrolStopBtn')), ...
            'private enrollment provides an Instant Stop button');
        check(~isempty(findTag('enrolImportBtn')), ...
            'private enrollment offers folder import of prior recordings');
    end
    check(~isempty(findTag('verifyStopBtn')), 'public verify tab provides an Instant Stop button');
    check(~isempty(findTag('adminLockBtn')), 'admin tab provides a Lock button');
end

% The Student ID field is a private enrollment control, living under the admin
% Enrol tab and never on the public Verify Meal surface a queue can see.
sidField = findTag('enrolStudentId');
if ~isempty(sidField)
    enrolTab = ancestor(sidField, 'uitab');
    check(~isempty(enrolTab) && strcmp(enrolTab.Tag, 'adminEnrolTab'), ...
        'the Student ID field belongs to the admin Enrol tab, not the public surface');
end

if verbose
    if isempty(failures)
        fprintf('VERIFY_MEAL_GUI_V2: all checks passed.\n');
    else
        fprintf(2, 'VERIFY_MEAL_GUI_V2: %d check(s) failed.\n', numel(failures));
        fprintf(2, '  - %s\n', failures{:});
    end
end
ok = isempty(failures);

    function check(condition, description)
        if ~condition, failures{end+1} = description; end %#ok<AGROW>
    end
end

function cleanup_files(varargin)
for k = 1:nargin
    if isfile(varargin{k}), delete(varargin{k}); end
end
end

function close_if_valid(fig)
if ~isempty(fig) && isvalid(fig), close(fig); end
end
