function [paid, message, info] = monthly_fee_entitlement(studentId, params, nowValue, action, verificationInfo)
%MONTHLY_FEE_ENTITLEMENT Read or administer the calendar-month dining roster.
%   CHECK reads membership. ASSIGN/ASSIGN_ADMIN register one enrolled ID;
%   ASSIGN_SELECTED registers a selection atomically; ASSIGN_ALL registers all
%   complete enrolled profiles. REMOVE removes only this calendar month's row.
%   The caller must authorize administration before mutation. Coupon-based
%   RECORD operations are retired and cannot grant an entitlement.
if nargin < 2 || isempty(params), params = dsp_parameters(); end
if nargin < 3 || isempty(nowValue), nowValue = datetime('now'); end
if nargin < 4 || isempty(action), action = 'check'; end
if nargin < 5 || isempty(verificationInfo), verificationInfo = struct(); end
fileName = entitlement_file(params);
info = struct('Student', '', 'Month', '', 'Paid', false, 'Recorded', false, ...
    'File', fileName, 'AddedIDs', {{}}, 'AlreadyAssignedIDs', {{}}, ...
    'AddedCount', 0, 'AlreadyAssignedCount', 0, 'RemovedCount', 0);
paid = false;
if ~isdatetime(nowValue) || ~isscalar(nowValue) || isnat(nowValue)
    message = 'A valid calendar date is required for monthly registration.';
    return;
end
monthText = string(nowValue,'yyyy-MM');
info.Month = char(monthText);
if ~(ischar(action) && isrow(action)) && ~(isstring(action) && isscalar(action) && ~ismissing(action))
    message = 'Invalid monthly roster operation.';
    return;
end
action = lower(strtrim(char(action)));
allowed = {'check','assign','assign_admin','assign_selected','assign_all','remove'};
if ~ismember(action,allowed)
    message = 'Unsupported monthly roster operation. Coupons are retired; use admin ID assignment.';
    return;
end

if strcmp(action,'assign_all')
    ids = list_enrolled_student_ids(params);
    valid = ~isempty(ids);
    validationMessage = 'No complete enrolled student profiles are available.';
else
    [ids,valid,validationMessage] = normalize_ids(studentId);
    if valid && ~strcmp(action,'assign_selected') && numel(ids)~=1
        valid = false;
        validationMessage = 'This operation requires one exact seven-digit Student ID.';
    end
end
if ~valid
    message = validationMessage;
    return;
end
if isscalar(ids), info.Student = ids{1}; end
isAssignment = ismember(action,{'assign','assign_admin','assign_selected','assign_all'});
if isAssignment
    enrolled = list_enrolled_student_ids(params);
    missingIds = ids(~ismember(ids,enrolled));
    if ~isempty(missingIds)
        message = sprintf('No complete ID and name enrollment exists for: %s. Nothing was assigned.',strjoin(missingIds,', '));
        return;
    end
end

try
    if isfile(fileName)
        data = read_entitlement_table(fileName);
    else
        data = empty_entitlement_table();
    end
catch err
    message = ['Could not read monthly roster: ' err.message];
    return;
end
current = strtrim(data.Month)==monthText;
assignedIds = cellstr(strtrim(data.Student(current)));
already = ismember(ids,assignedIds);

if strcmp(action,'check')
    paid = already(1);
    info.Paid = paid;
    if paid
        message = sprintf('%s is registered for dining in %s.',ids{1},char(monthText));
    else
        message = sprintf('%s is not registered for dining in %s. Please register in hall administration.',ids{1},char(monthText));
    end
    return;
end

if strcmp(action,'remove')
    matches = current & strtrim(data.Student)==string(ids{1});
    if ~any(matches)
        message = sprintf('Student %s is not on the %s dining roster.',ids{1},char(monthText));
        return;
    end
    try
        write_entitlement_table(data(~matches,:),fileName);
    catch err
        message = ['Could not remove student: ' err.message];
        return;
    end
    paid = true; % operation succeeded; membership itself is now false
    info.RemovedCount = nnz(matches);
    message = sprintf('Removed student %s from %s dining roster.',ids{1},char(monthText));
    return;
end

addedIds = ids(~already);
info.AlreadyAssignedIDs = ids(already);
info.AlreadyAssignedCount = nnz(already);
if isempty(addedIds)
    paid = true;
    info.Paid = true;
    message = sprintf('%d selected student(s) already registered for %s.',numel(ids),char(monthText));
    return;
end
newRows = array2table(repmat("",numel(addedIds),width(data)), ...
    'VariableNames',data.Properties.VariableNames);
newRows.Student = string(addedIds(:));
newRows.Month(:) = monthText;
newRows.PaidDate(:) = string(nowValue,'yyyy-MM-dd');
newRows.PaidTime(:) = string(nowValue,'HH:mm:ss');
newRows.Method(:) = string(field_or(verificationInfo,'Method','Admin-Roster'));
try
    write_entitlement_table([data;newRows],fileName);
catch err
    message = ['Could not register students: ' err.message];
    return;
end
paid = true;
info.Paid = true;
info.Recorded = true;
info.AddedIDs = addedIds;
info.AddedCount = numel(addedIds);
message = sprintf('Assigned %d student(s) for %s; %d already registered.', ...
    info.AddedCount,char(monthText),info.AlreadyAssignedCount);
end

function [ids,ok,message] = normalize_ids(value)
ids = {};
ok = false;
message = 'Select at least one enrolled seven-digit Student ID.';
if ischar(value) && (isrow(value) || isempty(value))
    values = {value};
elseif isstring(value) && isvector(value)
    values = cellstr(value(:));
elseif iscell(value) && (isvector(value) || isempty(value))
    values = value(:);
else
    return;
end
if isempty(values), return; end
for k = 1:numel(values)
    item = values{k};
    if ~(ischar(item) && isrow(item)) && ~(isstring(item) && isscalar(item) && ~ismissing(item))
        message = 'Every selection must be an exact seven-digit Student ID.';
        return;
    end
    item = strtrim(char(item));
    if numel(item)~=7 || any(item<'0' | item>'9')
        message = 'Every selection must be an exact seven-digit Student ID; partial searches cannot be assigned.';
        return;
    end
    ids{end+1} = item; %#ok<AGROW>
end
ids = unique(ids,'stable');
ok = true;
end

function data = read_entitlement_table(fileName)
required = {'Student','Month','PaidDate','PaidTime','Method'};
opts = detectImportOptions(fileName,'TextType','string','VariableNamingRule','preserve');
if ~all(ismember(required,opts.VariableNames))
    error('monthly_fee_entitlement:InvalidSchema','Invalid monthly entitlement schema in %s.',fileName);
end
% Treat all columns as text, preserving IDs and historical extension columns.
opts = setvartype(opts,opts.VariableNames,'string');
data = readtable(fileName,opts);
if any(ismissing(data.Student) | ismissing(data.Month))
    error('monthly_fee_entitlement:InvalidRows','Monthly roster contains a missing identity or month.');
end
months = cellstr(strtrim(data.Month));
if any(cellfun(@(s) isempty(regexp(s,'^\d{4}-(0[1-9]|1[0-2])$','once')),months))
    error('monthly_fee_entitlement:InvalidRows','Monthly roster contains an invalid calendar month.');
end
end

function data = empty_entitlement_table()
data = table(strings(0,1),strings(0,1),strings(0,1),strings(0,1),strings(0,1), ...
    'VariableNames',{'Student','Month','PaidDate','PaidTime','Method'});
end

function write_entitlement_table(data,fileName)
if isfolder(fileName)
    error('monthly_fee_entitlement:InvalidDestination','The monthly roster destination is a directory, not a CSV file.');
end
folder = fileparts(fileName);
if isempty(folder), folder = pwd; end
if ~isfolder(folder), mkdir(folder); end
temporary = [tempname(folder) '.csv'];
cleanup = onCleanup(@() delete_temporary(temporary));
writetable(data,temporary);
[ok,message] = movefile(temporary,fileName,'f');
if ~ok, error('monthly_fee_entitlement:WriteFailed','%s',message); end
end

function delete_temporary(fileName)
if isfile(fileName), delete(fileName); end
end

function fileName = entitlement_file(params)
if isfield(params,'monthlyEntitlementFile') && ~isempty(params.monthlyEntitlementFile)
    fileName = char(params.monthlyEntitlementFile);
else
    fileName = fullfile(fileparts(mfilename('fullpath')),'MonthlyFeeEntitlement.csv');
end
end

function value = field_or(s,name,default)
value = default;
if isstruct(s) && isfield(s,name) && ~isempty(s.(name))
    candidate = string(s.(name));
    if isscalar(candidate) && ~ismissing(candidate), value = candidate; end
end
end
