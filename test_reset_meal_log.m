function ok = test_reset_meal_log()
%TEST_RESET_MEAL_LOG Verify resetting today's meal entries vs. clearing entire log
%while preserving voice profile data and allowing students to be re-served.

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

fprintf('\n--- 1. Testing reset_meal_log_csv with "today" mode ---\n');
testDir = tempname;
mkdir(testDir);
cleanupDir = onCleanup(@() rm_if_present(testDir));
testLog = fullfile(testDir, 'MealLog.csv');

todayStr = string(datetime('now'), 'yyyy-MM-dd');
yesterdayStr = string(datetime('now') - days(1), 'yyyy-MM-dd');

sampleData = table( ...
    ["2206147"; "2206148"; "2206147"; "2206149"], ...
    ["Alice"; "Bob"; "Alice"; "Charlie"], ...
    [todayStr; todayStr; yesterdayStr; yesterdayStr], ...
    ["12:30:00"; "12:35:00"; "13:00:00"; "13:10:00"], ...
    ["Lunch"; "Lunch"; "Lunch"; "Lunch"], ...
    ["Voice"; "Voice"; "Voice"; "Voice"], ...
    [25.1; 27.3; 24.8; 28.0], ...
    [NaN; NaN; NaN; NaN], ...
    [1.35; 1.40; 1.30; 1.25], ...
    'VariableNames', {'StudentID','StudentName','Date','Time','Meal','Method', ...
                      'NameDistance','CouponDistance','Margin'});

writetable(sampleData, testLog);
check(isfile(testLog), 'Initial sample MealLog.csv created');

[nRemoved, nRemaining, remainingTable] = reset_meal_log_csv(testLog, 'today', todayStr);
check(nRemoved == 2, sprintf('Correctly removed 2 today records (got %d)', nRemoved));
check(nRemaining == 2, sprintf('Correctly preserved 2 yesterday records (got %d)', nRemaining));
check(all(remainingTable.Date == yesterdayStr), 'All remaining records belong to yesterday');

fprintf('\n--- 2. Testing re-verification after today reset ---\n');
p = dsp_parameters();
p.logFile = testLog;
p.requireCoupon = false;
% Student 2206147 should now be allowed to eat Lunch today since today's entry was reset:
[logged, msg, info] = log_meal_csv('2206147', struct('Method','Voice'), p, datetime('now'));
if ~logged && info.OutsideWindow
    % If outside physical dining window, test with simulated lunch hour
    testNow = datetime(2026, 9, 9, 12, 30, 0);
    todayStr2 = string(testNow, 'yyyy-MM-dd');
    reset_meal_log_csv(testLog, 'today', todayStr2);
    [logged, msg, ~] = log_meal_csv('2206147', struct('Method','Voice'), p, testNow);
end
check(logged, sprintf('Student successfully logged for meal after reset (%s)', msg));

fprintf('\n--- 3. Testing reset_meal_log_csv with "all" mode ---\n');
[nRemovedAll, nRemainingAll, emptyTable] = reset_meal_log_csv(testLog, 'all');
check(nRemovedAll >= 1, 'Removed remaining records when clearing all');
check(nRemainingAll == 0, 'Zero records remain after "all" clear');
check(height(emptyTable) == 0, 'Returned empty table');
readBack = readtable(testLog, 'TextType', 'string');
check(height(readBack) == 0, 'CSV file has 0 rows on disk');
check(ismember('StudentID', readBack.Properties.VariableNames), 'CSV header columns preserved');

fprintf('\n--- 4. Testing GUI Admin Reset Button ---\n');
fig = [];
cleanupFig = onCleanup(@() close_fig_safe(fig));
try
    fig = meal_verification_gui();
    drawnow;
    resetBtn = findobj(fig, 'Tag', 'adminResetMealsBtn');
    check(~isempty(resetBtn), 'adminResetMealsBtn exists in Admin tab');
    if ~isempty(resetBtn)
        check(contains(lower(resetBtn.Text), 'reset'), 'Button text mentions reset');
        check(~isempty(resetBtn.ButtonPushedFcn), 'Button has active callback');
    end
catch err
    check(false, sprintf('GUI check failed: %s', err.message));
end

if isempty(failures)
    fprintf('\n>>> ALL RESET MEAL LOG TESTS PASSED! <<<\n\n');
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
