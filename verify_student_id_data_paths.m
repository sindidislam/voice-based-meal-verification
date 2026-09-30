function ok = verify_student_id_data_paths(verbose)
%VERIFY_STUDENT_ID_DATA_PATHS Focused checks for ID-canonical meal data.
%   Confirms the meal log is keyed on a StudentID column, that a display name is
%   carried alongside as metadata, that the duplicate-serving rule is enforced
%   per ID, and that old StudentName-only logs are still read.
if nargin < 1, verbose = true; end
failures = {};

p = dsp_parameters();
root = tempname;
p.trainIdFolder     = fullfile(root, 'ID');
p.trainNameFolder   = fullfile(root, 'Name');
p.trainCouponFolder = fullfile(root, 'Coupon');
p.logFile                = [tempname '.csv'];
p.monthlyEntitlementFile = [tempname '.csv'];
p.monthlyCouponFile      = [tempname '.csv'];
cleanup = onCleanup(@() cleanup_all(root, p.logFile, p.monthlyEntitlementFile, p.monthlyCouponFile)); %#ok<NASGU>

id = '2206147';
student_profile(p, id, 'Alice Example');
noon = datetime(2026, 9, 7, 12, 30, 0);

% A served meal writes a StudentID column and the display name as metadata.
info = struct('Method', 'Voice', 'StudentName', 'Alice Example');
[logged, ~] = log_meal_csv(id, info, p, noon);
check(logged, 'a meal logs for a canonical Student ID');
dataOpts = detectImportOptions(p.logFile, 'TextType', 'string');
dataOpts = setvartype(dataOpts, 'StudentID', 'string');
data = readtable(p.logFile, dataOpts);
check(ismember('StudentID', data.Properties.VariableNames), 'log has a StudentID column');
check(strcmp(strtrim(char(data.StudentID(1))), id), 'the StudentID value is the seven-digit ID');
check(ismember('StudentName', data.Properties.VariableNames) && ...
    strcmp(char(data.StudentName(1)), 'Alice Example'), 'display name is stored as metadata');

% The duplicate rule is enforced on the ID.
[loggedAgain, msg] = log_meal_csv(id, info, p, noon);
check(~loggedAgain && contains(lower(msg), 'already served'), 'a second serving in the same window is refused by ID');

% Monthly coupon assignment/consumption is keyed on the ID.
[assignOk] = assign_monthly_coupon(id, '654321', p, noon);
check(assignOk, 'a monthly coupon assigns to a Student ID');
reg = readtable(p.monthlyCouponFile, 'TextType', 'string');
check(any(strcmp(strtrim(string(reg.Student)), id)), 'the coupon registry records the ID as the student');

% A legacy StudentName-only log is still read for the duplicate check.
legacyLog = [tempname '.csv'];
legacyCleanup = onCleanup(@() delete_if_present(legacyLog)); %#ok<NASGU>
legacy = table(string(id), string("2026-09-07"), string("12:30:00"), string("Lunch"), ...
    'VariableNames', {'StudentName','Date','Time','Meal'});
writetable(legacy, legacyLog);
pLegacy = p; pLegacy.logFile = legacyLog;
[loggedLegacy, msgLegacy] = log_meal_csv(id, info, pLegacy, noon);
check(~loggedLegacy && contains(lower(msgLegacy), 'already served'), ...
    'an old StudentName-only log still blocks a duplicate by ID');

ok = isempty(failures);
if verbose
    if ok
        fprintf('VERIFY_STUDENT_ID_DATA_PATHS: all checks passed.\n');
    else
        fprintf(2, 'VERIFY_STUDENT_ID_DATA_PATHS: %d check(s) failed.\n', numel(failures));
        fprintf(2, '  - %s\n', failures{:});
    end
end
if ~ok
    error('verify_student_id_data_paths:failed', '%d check(s) failed.', numel(failures));
end

    function check(condition, description)
        if ~condition, failures{end+1} = description; end %#ok<AGROW>
    end
end

function cleanup_all(root, varargin)
if isfolder(root), rmdir(root, 's'); end
delete_if_present(varargin{:});
end

function delete_if_present(varargin)
for k = 1:nargin
    if isfile(varargin{k}), delete(varargin{k}); end
end
end
