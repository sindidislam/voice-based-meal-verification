function [ok, failures] = test_v4_1_features()
%TEST_V4_1_FEATURES Validate all new features introduced in Final project v4.1:
%  1. Admin tab: Lock button at upper-right corner (Row 1, Column 5)
%  2. Admin tab: Table layout in bottom half (Row 5 with '1x' height)
%  3. Admin tab: Monthly payments, Corpus audit, Meal log, Coupon registry tables visible in bottom half
%  4. Verify tab: Instant Stop button (verifyStopBtn)
%  5. Enrol tab: Instant Stop button (enrolStopBtn)
%  6. Voice similarity percentage calculation and student detection message

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

p = dsp_parameters();
p.logFile = [tempname '_MealLog.csv'];
p.monthlyEntitlementFile = [tempname '_Entitlement.csv'];
p.monthlyCouponFile = [tempname '_CouponRegistry.csv'];
cleanup = onCleanup(@() cleanup_temp_files(p.logFile, p.monthlyEntitlementFile, p.monthlyCouponFile));

fig = meal_verification_gui(p);
closeOnExit = onCleanup(@() close_fig_safe(fig));

findTag = @(t) findobj(fig, 'Tag', t);

fprintf('\n--- 1. Testing Admin Tab Layout & Lock Button Position ---\n');
adminTab = findTag('adminTab');
check(~isempty(adminTab), 'Admin tab exists');

grid = findobj(adminTab, 'Type', 'uigridlayout');
check(~isempty(grid), 'Admin tab contains uigridlayout');
if ~isempty(grid)
    % Verify row height allocation: expanding row must be '1x' (bottom half allocated to table)
    has1x = any(cellfun(@(x) ischar(x) && strcmp(x, '1x'), grid.RowHeight));
    check(has1x, 'Admin grid has RowHeight "1x" (bottom half allocated to table)');
end

lockBtn = findTag('adminLockBtn');
check(~isempty(lockBtn), 'Lock button exists with Tag "adminLockBtn"');
if ~isempty(lockBtn)
    check(lockBtn.Layout.Row == 1 && lockBtn.Layout.Column == 5, ...
        'Lock button is positioned at upper-right corner (Row 1, Column 5)');
    check(strcmpi(lockBtn.Text, 'Lock'), 'Lock button is clearly labeled "Lock"');
end

tableWidget = findTag('adminTable');
check(~isempty(tableWidget), 'Admin table exists with Tag "adminTable"');
if ~isempty(tableWidget)
    check(tableWidget.Layout.Row >= 5 && isequal(tableWidget.Layout.Column, [1 5]), ...
        'Admin table occupies expanding row spanning all columns [1 5] (bottom half)');
    check(strcmp(tableWidget.Visible, 'off'), 'Admin table starts hidden/locked');
end

fprintf('\n--- 2. Testing Admin Authentication & Table Population ---\n');
adminId = findTag('adminId');
adminPass = findTag('adminPass');
unlockBtn = findTag('adminUnlockBtn');
adminMsg = findTag('adminMessage');

adminId.Value = 'admin';
adminPass.Value = 'admin';
feval(unlockBtn.ButtonPushedFcn, unlockBtn, struct());
check(strcmp(tableWidget.Visible, 'on'), 'Unlocking displays the table in the bottom half');

% Test Monthly Payments button
feesBtn = findobj(adminTab, 'Type', 'uibutton', 'Text', 'Monthly payments');
check(~isempty(feesBtn), 'Monthly payments button exists');
if ~isempty(feesBtn)
    feval(feesBtn.ButtonPushedFcn, feesBtn, struct());
    check(strcmp(tableWidget.Visible, 'on'), 'Monthly payments button activates table display');
end

% Test Coupon Registry button
couponBtn = findobj(adminTab, 'Type', 'uibutton', 'Text', 'Coupon registry');
check(~isempty(couponBtn), 'Coupon registry button exists');
if ~isempty(couponBtn)
    feval(couponBtn.ButtonPushedFcn, couponBtn, struct());
    check(strcmp(tableWidget.Visible, 'on'), 'Coupon registry button activates table display');
end

% Test Corpus Audit button
auditBtn = findobj(adminTab, 'Type', 'uibutton', 'Text', 'Corpus audit');
check(~isempty(auditBtn), 'Corpus audit button exists');
if ~isempty(auditBtn)
    feval(auditBtn.ButtonPushedFcn, auditBtn, struct());
    check(strcmp(tableWidget.Visible, 'on'), 'Corpus audit button activates table display');
end

% Test Lock button action
feval(lockBtn.ButtonPushedFcn, lockBtn, struct());
check(strcmp(tableWidget.Visible, 'off'), 'Lock button locks and hides the table');
check(isempty(adminId.Value) && isempty(adminPass.Value), 'Lock button clears credentials');

fprintf('\n--- 3. Testing Instant Stop Button on Verify Meal Tab ---\n');
verifyStopBtn = findTag('verifyStopBtn');
check(~isempty(verifyStopBtn), 'Instant Stop button exists on Verify tab with Tag "verifyStopBtn"');
if ~isempty(verifyStopBtn)
    check(verifyStopBtn.Layout.Row == 3 && verifyStopBtn.Layout.Column == 2, ...
        'Instant Stop button is placed in Row 3, Column 2 next to Record and Verify');
    check(strcmp(verifyStopBtn.Enable, 'off'), 'Instant Stop button starts disabled while idle');
    check(~isempty(verifyStopBtn.ButtonPushedFcn), 'Instant Stop button has an interactive callback');
end

verifyLiveBtn = findTag('verifyLiveBtn');
check(~isempty(verifyLiveBtn), 'Record and Verify button exists');

fprintf('\n--- 4. Testing Instant Stop Button on Enrol Tab ---\n');
% Unlock and open DSP workspace to access Enrol tab
adminId.Value = 'admin';
adminPass.Value = 'admin';
workspaceBtn = findTag('adminWorkspaceBtn');
check(~isempty(workspaceBtn), 'Open DSP workspace button exists');
if ~isempty(workspaceBtn)
    feval(workspaceBtn.ButtonPushedFcn, workspaceBtn, struct());
    enrolTab = findTag('adminEnrolTab');
    check(~isempty(enrolTab), 'Admin Enrol tab opened');
    
    enrolStopBtn = findTag('enrolStopBtn');
    check(~isempty(enrolStopBtn), 'Instant Stop button exists on Enrol tab with Tag "enrolStopBtn"');
    if ~isempty(enrolStopBtn)
        check(enrolStopBtn.Layout.Row == 5 && enrolStopBtn.Layout.Column == 4, ...
            'Enrol Instant Stop button is positioned in Row 5, Column 4');
        check(strcmp(enrolStopBtn.Enable, 'off'), 'Enrol Instant Stop starts disabled while idle');
        check(~isempty(enrolStopBtn.ButtonPushedFcn), 'Enrol Instant Stop has an interactive callback');
    end
end

fprintf('\n--- 5. Testing Two-Utterance Student Verification ---\n');
% Run verify_student_id_workflow which exercises DTW matching, similarity % output, and candidate detection
okWorkflow = verify_student_id_workflow(false);
check(okWorkflow, 'verify_student_id_workflow passes with claim and two-utterance gates');

fprintf('\n--- 6. Testing Mandatory Name Evidence & Conservative Margins ---\n');
okDisambig = test_id_margin_disambiguation();
check(okDisambig, 'test_id_margin_disambiguation prevents ID-only acceptance and weak margins');

fprintf('\n--- 7. Testing Interruptible Pause Utility (Enroll Stop/Countdown Support) ---\n');
okPause = test_interruptible_pause();
check(okPause, 'test_interruptible_pause passes and is accessible from GUI and enrollment callbacks');

fprintf('\n--- 8. Testing Discard Profile & Instant Stop Rollback (v4.1.2) ---\n');
okDiscardStop = test_enrol_discard_and_stop();
check(okDiscardStop, 'test_enrol_discard_and_stop passes with Discard profile button and instant stop cleanup');

fprintf('\n--- 9. Testing Meal Log Reset (Today / All) in Admin Panel (v4.1.3) ---\n');
okResetMeal = test_reset_meal_log();
check(okResetMeal, 'test_reset_meal_log passes with today vs all meal log resets');

fprintf('\n--- 10. Testing Admin Configurable Meal Hours & Schedule (v4.1.4) ---\n');
try
    test_meal_schedule_config();
    check(true, 'test_meal_schedule_config passes with persistent CSV, validation, and GUI controls');
catch ME
    check(false, sprintf('test_meal_schedule_config failed: %s', ME.message));
end

fprintf('\n--- 11. Testing Coupon Registry Reset & Multifunctional GUI Reset (v4.1.4) ---\n');
okResetCoupon = test_reset_coupon_registry();
check(okResetCoupon, 'test_reset_coupon_registry passes with unconsume, student delete, and all clear modes');
okGuiCoupon = test_gui_coupon_reset();
check(okGuiCoupon, 'test_gui_coupon_reset passes with multifunctional reset button and dedicated reset coupons button');

fprintf('\n--- 12. Testing Direct Student ID Monthly Roster & Search Dropdown (v4.1.4) ---\n');
okRoster = test_monthly_roster_system();
check(okRoster, 'test_monthly_roster_system passes with ID search, dropdown, assign all, and direct dining gates');

if isempty(failures)
    fprintf('\n>>> ALL V4.1.4 REQUIREMENTS VERIFIED SUCCESSFULLY! <<<\n\n');
    ok = true;
else
    fprintf(2, '\n>>> %d CHECK(S) FAILED <<<\n\n', numel(failures));
    ok = false;
end
end

function cleanup_temp_files(varargin)
for k = 1:nargin
    if isfile(varargin{k}), delete(varargin{k}); end
end
end

function close_fig_safe(fig)
if ~isempty(fig) && isvalid(fig), close(fig); end
end
