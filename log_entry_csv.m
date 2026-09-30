function [logged, message, windowName] = log_entry_csv(userName, userType, guestCount, logFile, nowValue)
%LOG_ENTRY_CSV Append one entry during an allowed local-time window.
if nargin < 4 || isempty(logFile), logFile = 'Log.csv'; end
if nargin < 5 || isempty(nowValue), nowValue = datetime('now'); end
if nargin < 3 || isempty(guestCount), guestCount = 0; end
if nargin < 2 || isempty(userType), userType = 'User'; end
userName = strtrim(char(string(userName)));
windowName = '';
if isempty(userName)
    logged = false;
    message = 'Logging rejected: empty UserName.';
    return;
end
minuteOfDay = hour(nowValue)*60 + minute(nowValue);
starts = [7 12 17]*60;
ends = [9 14 19]*60;
names = {'Morning','Afternoon','Evening'};
windowIndex = find(minuteOfDay >= starts & minuteOfDay < ends,1);
if isempty(windowIndex)
    logged = false;
    message = 'Logging rejected: outside the three valid time windows.';
    return;
end
windowName = names{windowIndex};
dateText = string(nowValue,'yyyy-MM-dd');
timeText = string(nowValue,'HH:mm:ss');
newRow = table(string(userName),dateText,timeText,string(userType),double(guestCount), ...
    'VariableNames',{'UserName','Date','Time','UserType','GuestCount'});
if isfile(logFile)
    try
        data = readtable(logFile,'TextType','string');
        required = {'UserName','Date','Time','UserType','GuestCount'};
        if ~isequal(data.Properties.VariableNames,required)
            logged = false;
            message = 'Logging rejected: Log.csv must contain exactly the required five headers.';
            return;
        end
        existingWindow = strings(height(data),1);
        for row = 1:height(data)
            parts = sscanf(char(data.Time(row)),'%d:%d:%d');
            if numel(parts) >= 2
                existingMinute = parts(1)*60 + parts(2);
                index = find(existingMinute >= starts & existingMinute < ends,1);
                if ~isempty(index), existingWindow(row) = string(names{index}); end
            end
        end
        duplicate = strcmpi(strtrim(data.UserName),string(userName)) & ...
            data.Date == dateText & strcmpi(existingWindow,string(windowName));
        if any(duplicate)
            logged = false;
            message = sprintf('Logging rejected: %s is already logged in the %s window.',userName,windowName);
            return;
        end
        data = [data;newRow];
    catch exception
        logged = false;
        message = ['Logging failed while reading Log.csv: ' exception.message];
        return;
    end
else
    data = newRow;
end
try
    writetable(data,logFile);
    logged = true;
    message = sprintf('Entry logged for %s in the %s window.',userName,windowName);
catch exception
    logged = false;
    message = ['Logging failed while writing Log.csv: ' exception.message];
end
end
