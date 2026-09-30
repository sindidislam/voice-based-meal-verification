function admin_reset_meal_log(fig, adminId, pass, view, message)
%ADMIN_RESET_MEAL_LOG Operator prompt to reset today's or all meal log entries.
if ~admin_authorised(fig, adminId, pass, message), return; end
p = fig.UserData.params;
if ~isfile(p.logFile)
    message.Text = sprintf('No meal log file (%s) exists yet to reset.', p.logFile);
    message.FontColor = [0.35 0.35 0.35];
    return;
end

choice = uiconfirm(fig, ...
    sprintf(['Choose how to reset meal entries in %s:\n\n' ...
    '• "Reset today only": Clears today''s meal records so students can be served again today.\n' ...
    '• "Clear entire log": Deletes all serving history from the log.\n\n' ...
    'NOTE: Enrolled student voice profiles (Train/ID and Train/Name) will NOT be affected.'], p.logFile), ...
    'Reset Meal Log Data', ...
    'Options', {'Reset today only', 'Clear entire log', 'Cancel'}, ...
    'DefaultOption', 'Reset today only', ...
    'CancelOption', 'Cancel');

switch choice
    case 'Reset today only'
        todayStr = string(datetime('now'), 'yyyy-MM-dd');
        [nRemoved, nRemaining] = reset_meal_log_csv(p.logFile, 'today', todayStr);
        message.Text = sprintf('● Meal log reset: %d today''s record(s) removed (%d historical record(s) preserved). Voice profiles untouched.', ...
            nRemoved, nRemaining);
        message.FontColor = [0.05 0.40 0.05];
        if strcmp(view.Visible, 'on')
            data = readtable(p.logFile, 'TextType', 'string');
            view.Data = data;
            view.ColumnName = data.Properties.VariableNames;
        end
        
    case 'Clear entire log'
        [nRemoved, ~] = reset_meal_log_csv(p.logFile, 'all');
        message.Text = sprintf('● Entire meal log cleared (%d record(s) removed). Enrolled voice profiles are 100%% untouched.', ...
            nRemoved);
        message.FontColor = [0.05 0.40 0.05];
        if strcmp(view.Visible, 'on')
            data = readtable(p.logFile, 'TextType', 'string');
            view.Data = data;
            view.ColumnName = data.Properties.VariableNames;
        end
        
    otherwise
        message.Text = 'Meal log reset cancelled; no records were changed.';
        message.FontColor = [0.35 0.35 0.35];
end
end
