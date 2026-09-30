function [logged, message, info] = log_meal_csv(studentId, verificationInfo, params, nowValue)
%LOG_MEAL_CSV Record one served meal, refusing a second serving in the same window.
%
%   [LOGGED, MESSAGE, INFO] = LOG_MEAL_CSV(STUDENTNAME, VERIFICATIONINFO, PARAMS,
%   NOWVALUE) appends one row to PARAMS.logFile if and only if the current instant
%   falls inside a meal service window and that student has not already been
%   served in that window today.
%
%   NOWVALUE is optional and defaults to the current local time.  It exists so
%   that VERIFY_DSP_PIPELINE can test the window and duplicate rules at any hour
%   of the day without waiting for lunch.  A rule that can only be tested during
%   the two and a half hours it is active is a rule that does not get tested.
%
%   Proposal modification 5 and Goal 5.  EEE 312 CO4 (public health, societal
%   context) and CO5 (professional ethics).
%
%   What this function is for
%   -------------------------
%   The dining subsidy pays for one meal per student per sitting.  Voice
%   verification establishes WHO is at the counter; this function establishes
%   whether that person is entitled to a meal RIGHT NOW.  Those are two different
%   questions and keeping them in separate functions is what lets each be tested
%   on its own.  A student can be perfectly identified and still be refused --
%   because they already ate, or because it is half past four and no meal is being
%   served -- and the refusal is not a failure of the DSP.
%
%   Why the duplicate check reads the file rather than holding state in memory
%   -------------------------------------------------------------------------
%   The counter operator will close and reopen the application, and there may be
%   more than one counter.  The CSV on disk is the only thing both of those share,
%   so it has to be the authority.  Re-reading it on every transaction costs
%   milliseconds at hall scale and removes an entire class of bug in which the
%   in-memory record and the file disagree.
%
%   The columns
%   -----------
%   StudentID, StudentName, Date, Time, Meal, Method, NameDistance,
%   CouponDistance, Margin, IDDistance, IDMargin, NameMargin.
%   StudentID is the canonical seven-digit identity;
%   StudentName is display metadata read from the profile. Logs written by an
%   earlier version used a single StudentName column that actually held the
%   identity; those are still read (the duplicate check falls back to it).
%   The three numbers are written because a log that records only the decision
%   cannot be audited.  If a student disputes a refusal, or the group wants to
%   know what the distances looked like during the live demonstration, the
%   evidence has to have been recorded at the time.  This also supplies the
%   Technical Demonstration evidence the proposal's evaluation asks for.
%
%   See also MEAL_WINDOW_NOW, VERIFY_MEAL_WORKFLOW, DSP_PARAMETERS.

if nargin < 3 || isempty(params), params = dsp_parameters(); end
if nargin < 4 || isempty(nowValue), nowValue = datetime('now'); end
if nargin < 2 || isempty(verificationInfo), verificationInfo = struct(); end

studentId = strtrim(char(string(studentId)));

info = struct('Meal','','Date','','Time','','Duplicate',false, ...
    'OutsideWindow',false,'RowsBefore',0,'RowsAfter',0);

if isempty(studentId)
    logged = false;
    message = 'Not logged: no Student ID was supplied.';
    return;
end

% Display name is metadata: read it from the profile when the ID is canonical,
% but never let a missing profile stop a meal from being logged.
studentName = field_or(verificationInfo, 'StudentName', '');
if isempty(studentName)
    [canonicalId, idOk] = student_id_contract(studentId);
    if idOk
        meta = student_profile(params, canonicalId);
        studentName = meta.Name;
    end
end

% --- Rule 1: is a meal being served at all? --------------------------------
[mealName, windowInfo] = meal_window_now(params, nowValue);
if isempty(mealName)
    logged = false;
    info.OutsideWindow = true;
    if isempty(windowInfo.NextWindow)
        message = sprintf(['Not logged: no meal is being served now. ' ...
            'Service windows are %s.'], windowInfo.AllWindows);
    else
        message = sprintf(['Not logged: no meal is being served now. ' ...
            '%s opens in %d minutes. Service windows are %s.'], ...
            windowInfo.NextWindow, windowInfo.MinutesToNext, windowInfo.AllWindows);
    end
    return;
end
info.Meal = mealName;

dateText = string(nowValue, 'yyyy-MM-dd');
timeText = string(nowValue, 'HH:mm:ss');
info.Date = char(dateText);
info.Time = char(timeText);

newRow = table(string(studentId), string(studentName), dateText, timeText, string(mealName), ...
    string(field_or(verificationInfo, 'Method', 'Voice')), ...
    field_or(verificationInfo, 'NameDistance', NaN), ...
    field_or(verificationInfo, 'CouponDistance', NaN), ...
    field_or(verificationInfo, 'Margin', NaN), ...
    field_or(verificationInfo, 'IDDistance', NaN), ...
    field_or(verificationInfo, 'IDMargin', NaN), ...
    field_or(verificationInfo, 'NameMargin', NaN), ...
    'VariableNames', {'StudentID','StudentName','Date','Time','Meal','Method', ...
                      'NameDistance','CouponDistance','Margin','IDDistance','IDMargin','NameMargin'});

logFile = params.logFile;

if isfile(logFile)
    try
        data = read_log_table(logFile);
    catch exception
        logged = false;
        message = sprintf('Not logged: could not read %s (%s).', logFile, exception.message);
        return;
    end

    % The identity column is StudentID in current logs and StudentName in
    % logs written before the ID migration (where it held the identity value).
    hasId = ismember('StudentID', data.Properties.VariableNames);
    identityColumn = 'StudentID';
    if ~hasId && ismember('StudentName', data.Properties.VariableNames)
        identityColumn = 'StudentName';
    end
    if ~all(ismember({'Date','Meal'}, data.Properties.VariableNames)) || ...
            ~ismember(identityColumn, data.Properties.VariableNames)
        logged = false;
        message = sprintf(['Not logged: %s does not have the expected columns. ' ...
            'Move it aside and a new log will be started.'], logFile);
        return;
    end

    info.RowsBefore = height(data);

    % --- Rule 2: one serving per student per window per day ----------------
    % Matching is on the recorded Meal name rather than on the recorded time.
    % Deriving the window from the stored timestamp, as the previous revision
    % did, means that changing the service hours retroactively reinterprets
    % history: yesterday's 13:00 lunch becomes "no window" and the duplicate
    % check silently stops working on old rows. Storing the decision makes the
    % log a record of what was decided, which is what an audit needs.
    if params.oneMealPerWindow
        % An all-digit ID column can be read back as a numeric column, so
        % normalise to trimmed strings before comparing.
        loggedIds = strtrim(string(data.(identityColumn)));
        duplicate = strcmpi(loggedIds, string(studentId)) & ...
                    data.Date == dateText & ...
                    strcmpi(data.Meal, string(mealName));
        if any(duplicate)
            firstServed = data.Time(find(duplicate, 1));
            logged = false;
            info.Duplicate = true;
            message = sprintf(['Not logged: %s was already served %s today at %s. ' ...
                'One meal per student per sitting.'], studentId, mealName, firstServed);
            return;
        end
    end

    data = align_and_append(data, newRow);
else
    data = newRow;
end

try
    writetable(data, logFile);
    logged = true;
    info.RowsAfter = height(data);
    message = sprintf('%s logged for %s at %s.', mealName, studentId, info.Time);
catch exception
    logged = false;
    message = sprintf('Not logged: could not write %s (%s).', logFile, exception.message);
end
end

% -------------------------------------------------------------------------
function data = read_log_table(logFile)
%READ_LOG_TABLE Read the meal log, keeping identity columns as text.
%   An all-digit Student ID would otherwise be imported as a number, which
%   drops leading zeros and breaks a strict string match against the ID.
opts = detectImportOptions(logFile, 'TextType', 'string');
for name = {'StudentID', 'StudentName'}
    if ismember(name{1}, opts.VariableNames)
        opts = setvartype(opts, name{1}, 'string');
    end
end
data = readtable(logFile, opts);
end

function value = field_or(s, name, default)
%FIELD_OR Read a field if present, otherwise return a default.
if isstruct(s) && isfield(s, name) && ~isempty(s.(name))
    value = s.(name);
else
    value = default;
end
end

function data = align_and_append(data, newRow)
%ALIGN_AND_APPEND Add a row to a table that may predate the current columns.
%
%   An existing log written by an earlier version has fewer columns. Rather than
%   refuse to log a meal because of a schema change -- which would stop the
%   counter working -- missing columns are added with empty values and the row is
%   appended. Losing a column of diagnostics from old rows is acceptable; losing
%   the ability to serve lunch is not.
missing = setdiff(newRow.Properties.VariableNames, data.Properties.VariableNames);
for k = 1:numel(missing)
    name = missing{k};
    if isnumeric(newRow.(name))
        data.(name) = NaN(height(data), 1);
    else
        data.(name) = strings(height(data), 1);
    end
end
extra = setdiff(data.Properties.VariableNames, newRow.Properties.VariableNames);
for k = 1:numel(extra)
    name = extra{k};
    if isnumeric(data.(name))
        newRow.(name) = NaN;
    else
        newRow.(name) = "";
    end
end
data = [data; newRow(:, data.Properties.VariableNames)];
end
