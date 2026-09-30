function test_meal_schedule_config()
%TEST_MEAL_SCHEDULE_CONFIG Unit tests for configurable meal hours in v4.1.4.
%   Validates persistent meal schedule loading, saving, input validation,
%   overlap detection, default restoration, and dining window integration.

fprintf('\n=== Running test_meal_schedule_config (v4.1.4) ===\n');

testDir = fileparts(mfilename('fullpath'));
tempCsv = fullfile(testDir, 'Test_MealSchedule_Temp.csv');
if isfile(tempCsv), delete(tempCsv); end

cleanupObj = onCleanup(@() cleanup_temp(tempCsv));

%% 1. Default schedule when file does not exist
fprintf('1. Testing default schedule behavior... ');
p = dsp_parameters();
p.mealScheduleFile = tempCsv; % does not exist yet
meals = load_meal_schedule(p);

assert(numel(meals) == 3, 'Expected 3 meal windows');
assert(strcmp(meals(1).Name, 'Breakfast'), 'Meal 1 should be Breakfast');
assert(isequal(meals(1).Start, [7 0]) && isequal(meals(1).End, [9 30]), 'Breakfast default mismatch');
assert(strcmp(meals(2).Name, 'Lunch'), 'Meal 2 should be Lunch');
assert(isequal(meals(2).Start, [12 0]) && isequal(meals(2).End, [14 30]), 'Lunch default mismatch');
assert(strcmp(meals(3).Name, 'Dinner'), 'Meal 3 should be Dinner');
assert(isequal(meals(3).Start, [19 0]) && isequal(meals(3).End, [21 30]), 'Dinner default mismatch');
fprintf('PASSED\n');

%% 2. Saving custom schedule and reloading
fprintf('2. Testing save and reload of custom meal hours... ');
customMeals = meals;
customMeals(1).Start = [6 30]; customMeals(1).End = [10 0];  % Breakfast 06:30 - 10:00
customMeals(2).Start = [11 30]; customMeals(2).End = [15 0]; % Lunch 11:30 - 15:00
customMeals(3).Start = [18 30]; customMeals(3).End = [22 0]; % Dinner 18:30 - 22:00

[okSave, saveErr] = save_meal_schedule(customMeals, tempCsv);
assert(okSave, 'save_meal_schedule failed: %s', saveErr);
assert(isfile(tempCsv), 'Custom schedule CSV was not created');

% Reload through load_meal_schedule
reloaded = load_meal_schedule(p);
assert(isequal(reloaded(1).Start, [6 30]) && isequal(reloaded(1).End, [10 0]), 'Custom Breakfast failed to reload');
assert(isequal(reloaded(2).Start, [11 30]) && isequal(reloaded(2).End, [15 0]), 'Custom Lunch failed to reload');
assert(isequal(reloaded(3).Start, [18 30]) && isequal(reloaded(3).End, [22 0]), 'Custom Dinner failed to reload');
fprintf('PASSED\n');

%% 3. Validation: start time must precede end time
fprintf('3. Testing start < end validation... ');
badMeals = customMeals;
badMeals(2).Start = [15 0];
badMeals(2).End = [11 30]; % Start after end
[isValid, errMsg] = validate_meal_schedule(badMeals);
assert(~isValid, 'validate_meal_schedule should reject start >= end');
assert(~isempty(errMsg), 'Expected descriptive error message');
fprintf('PASSED\n');

%% 4. Validation: hour (0-23) and minute (0-59) ranges
fprintf('4. Testing hour/minute range validation... ');
badRange = customMeals;
badRange(1).Start = [25 0]; % Invalid hour
[isValid, errMsg] = validate_meal_schedule(badRange);
assert(~isValid, 'validate_meal_schedule should reject hour > 23');

badRange = customMeals;
badRange(1).Start = [7 75]; % Invalid minute
[isValid, errMsg] = validate_meal_schedule(badRange);
assert(~isValid, 'validate_meal_schedule should reject minute > 59');
fprintf('PASSED\n');

%% 5. Validation: window overlap detection
fprintf('5. Testing window overlap detection... ');
overlapMeals = customMeals;
overlapMeals(1).End = [12 30]; % Breakfast ends 12:30, Lunch starts 11:30 -> OVERLAP!
[isValid, errMsg] = validate_meal_schedule(overlapMeals);
assert(~isValid, 'validate_meal_schedule should reject overlapping meal windows');
assert(contains(errMsg, 'overlap', 'IgnoreCase', true), 'Error message should mention overlap');
fprintf('PASSED\n');

%% 6. Integration with meal_window_now
fprintf('6. Testing integration with meal_window_now... ');
% At 11:45 AM:
% Under default schedule (Lunch starts 12:00): outside all windows ('')
% Under custom schedule (Lunch starts 11:30): inside Lunch!
testInstant = datetime(2026, 9, 9, 11, 45, 0);

defaultParams = dsp_parameters();
[winDefault, ~] = meal_window_now(defaultParams, testInstant);
assert(isempty(winDefault), 'Expected 11:45 AM to be outside default windows');

customParams = defaultParams;
customParams.meals = customMeals;
[winCustom, infoCustom] = meal_window_now(customParams, testInstant);
assert(strcmp(winCustom, 'Lunch'), 'Expected 11:45 AM to be Lunch under custom schedule');
assert(infoCustom.WindowStart == 11*60 + 30, 'Custom window start mismatch');
fprintf('PASSED\n');

%% 7. Reset to default schedule
fprintf('7. Testing reset to default schedule... ');
if isfile(tempCsv), delete(tempCsv); end
resetMeals = load_meal_schedule(p);
assert(isequal(resetMeals(2).Start, [12 0]), 'Reset did not restore default Lunch start 12:00');
fprintf('PASSED\n');

%% 8. GUI Integration: Admin tab Meal hours button & configuration
fprintf('8. Testing GUI Admin Meal hours button and callback... ');
guiFig = meal_verification_gui(p);
guiFig.Visible = 'off';
cleanupGui = onCleanup(@() cleanup_gui(guiFig, tempCsv));

% Locate admin controls
adminIdField = findobj(guiFig, 'Tag', 'adminId');
adminPassField = findobj(guiFig, 'Tag', 'adminPass');
adminMsg = findobj(guiFig, 'Tag', 'adminMessage');
adminHoursBtn = findobj(guiFig, 'Tag', 'adminMealHoursBtn');

assert(~isempty(adminHoursBtn), 'adminMealHoursBtn not found in Admin tab');

% Unauthorized test
adminIdField.Value = 'wrong';
adminPassField.Value = 'wrong';
admin_configure_meal_hours(guiFig, adminIdField, adminPassField, [], adminMsg);
assert(contains(adminMsg.Text, 'Incorrect admin ID or password', 'IgnoreCase', true), ...
    'Unauthorized click did not show auth error');

% Authorized test
adminIdField.Value = 'admin';
adminPassField.Value = 'admin';
dlg = admin_configure_meal_hours(guiFig, adminIdField, adminPassField, [], adminMsg);
assert(~isempty(dlg) && isvalid(dlg), 'admin_configure_meal_hours should create valid dialog');

% Test saving through dialog
bStartH = findobj(dlg, 'Tag', 'bStartH');
bStartH.Value = 6;
saveBtn = findobj(dlg, 'Tag', 'saveMealHoursBtn');
assert(~isempty(saveBtn), 'Save button not found in dialog');

% Execute save callback
saveBtn.ButtonPushedFcn(saveBtn, []);
assert(~isvalid(dlg), 'Dialog should close after successful save');
assert(guiFig.UserData.params.meals(1).Start(1) == 6, 'GUI params.meals did not update with new Breakfast hour');

delete(guiFig);
fprintf('PASSED\n');

fprintf('\n>>> ALL MEAL SCHEDULE CONFIG TESTS PASSED SUCCESSFULLY! <<<\n\n');
end

function cleanup_gui(fig, file)
if ~isempty(fig) && isvalid(fig)
    try delete(fig); catch; end
end
cleanup_temp(file);
end

function cleanup_temp(file)
if isfile(file)
    try delete(file); catch; end
end
end
