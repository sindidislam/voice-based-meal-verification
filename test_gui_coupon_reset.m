function ok = test_gui_coupon_reset()
%TEST_GUI_COUPON_RESET Verify multifunctional reset button and dedicated reset coupons button in GUI

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

fprintf('\n--- Testing GUI Coupon Reset Buttons & Multifunctionality ---\n');
fig = [];
cleanupFig = onCleanup(@() close_fig_safe(fig));

try
    fig = meal_verification_gui();
    drawnow;
    
    % Check buttons exist
    resetMealsBtn = findobj(fig, 'Tag', 'adminResetMealsBtn');
    resetCouponsBtn = findobj(fig, 'Tag', 'adminResetCouponsBtn');
    couponRegBtn = findobj(fig, 'Text', 'Coupon registry');
    unlockBtn = findobj(fig, 'Tag', 'adminUnlockBtn');
    adminId = findobj(fig, 'Tag', 'adminId');
    adminPass = findobj(fig, 'Tag', 'adminPass');
    
    check(~isempty(resetMealsBtn), 'adminResetMealsBtn exists');
    check(~isempty(resetCouponsBtn), 'adminResetCouponsBtn exists in Row 4 Col 4');
    check(contains(resetMealsBtn.Text, 'Reset meal log'), 'Initial resetMealsBtn text is "Reset meal log..."');
    
    % Authorize admin
    adminId.Value = 'admin';
    adminPass.Value = 'admin';
    
    % Click Coupon registry
    couponRegBtn.ButtonPushedFcn(couponRegBtn, []);
    drawnow;
    
    check(isfield(fig.UserData, 'adminCurrentView') && strcmp(fig.UserData.adminCurrentView, 'coupon_registry'), ...
        'adminCurrentView is now "coupon_registry"');
    check(contains(resetMealsBtn.Text, 'Reset coupon registry'), ...
        'resetMealsBtn dynamically switched text to "Reset coupon registry..."');
    
    % Click Unlock / meal log
    unlockBtn.ButtonPushedFcn(unlockBtn, []);
    drawnow;
    
    check(isfield(fig.UserData, 'adminCurrentView') && strcmp(fig.UserData.adminCurrentView, 'meal_log'), ...
        'adminCurrentView switched back to "meal_log"');
    check(contains(resetMealsBtn.Text, 'Reset meal log'), ...
        'resetMealsBtn dynamically switched text back to "Reset meal log..."');

catch err
    check(false, sprintf('GUI test error: %s', err.message));
end

if isempty(failures)
    fprintf('\n>>> ALL GUI COUPON RESET TESTS PASSED! <<<\n\n');
    ok = true;
else
    fprintf(2, '\n>>> %d CHECK(S) FAILED <<<\n\n', numel(failures));
    ok = false;
end
end

function close_fig_safe(fig)
if ~isempty(fig) && isvalid(fig), close(fig); end
end
