function [nRemoved, nRemaining, dataOut] = reset_meal_log_csv(logFile, mode, targetDate)
%RESET_MEAL_LOG_CSV Reset today's entries or clear the meal log while keeping headers.
%
%   [nRemoved, nRemaining, dataOut] = reset_meal_log_csv(logFile, mode, targetDate)
%
%   logFile    - path to MealLog.csv (char/string).
%   mode       - 'today' (default) to remove only targetDate rows, or 'all' to clear all rows.
%   targetDate - (optional) string/char 'yyyy-MM-dd' for target date (defaults to today).
%
%   nRemoved   - number of rows removed from the CSV.
%   nRemaining - number of rows left in the CSV.
%   dataOut    - resulting table written to disk.

if nargin < 1 || isempty(logFile)
    p = dsp_parameters();
    logFile = p.logFile;
end
if nargin < 2 || isempty(mode)
    mode = 'today';
end
if nargin < 3 || isempty(targetDate)
    targetDate = string(datetime('now'), 'yyyy-MM-dd');
else
    targetDate = string(targetDate);
end

nRemoved = 0;
nRemaining = 0;
dataOut = table();

if ~isfile(logFile)
    return;
end

try
    data = readtable(logFile, 'TextType', 'string');
catch
    return;
end

switch lower(char(mode))
    case 'today'
        if ismember('Date', data.Properties.VariableNames)
            isToday = (data.Date == targetDate);
            nRemoved = sum(isToday);
            dataOut = data(~isToday, :);
        else
            dataOut = data;
        end
        nRemaining = height(dataOut);
        writetable(dataOut, logFile);
        
    case 'all'
        nRemoved = height(data);
        nRemaining = 0;
        dataOut = data([], :);
        writetable(dataOut, logFile);
        
    otherwise
        error('reset_meal_log_csv:InvalidMode', 'Mode must be ''today'' or ''all''.');
end
end
