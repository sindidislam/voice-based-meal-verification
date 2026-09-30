function admin_show_schedule(fig, adminId, pass, view, message)
%ADMIN_SHOW_SCHEDULE Display the current meal service schedule in the Admin table.
%
%   ADMIN_SHOW_SCHEDULE(FIG, ADMINID, PASS, VIEW, MESSAGE) displays the
%   active meal windows, start/end times, and current open/closed status.

if nargin >= 3 && ~isempty(adminId) && ~isempty(pass)
    if ~admin_authorised(fig, adminId, pass, message), return; end
end

p = fig.UserData.params;
meals = p.meals;
if isempty(meals)
    meals = load_meal_schedule(p);
end

nowDt = datetime('now');
nowMin = hour(nowDt)*60 + minute(nowDt);

nMeals = numel(meals);
mealCol   = strings(nMeals, 1);
startCol  = strings(nMeals, 1);
endCol    = strings(nMeals, 1);
statusCol = strings(nMeals, 1);

for k = 1:nMeals
    sMin = meals(k).Start(1)*60 + meals(k).Start(2);
    eMin = meals(k).End(1)*60 + meals(k).End(2);
    isOpen = (nowMin >= sMin && nowMin < eMin);
    
    mealCol(k)  = string(meals(k).Name);
    startCol(k) = sprintf('%02d:%02d', meals(k).Start(1), meals(k).Start(2));
    endCol(k)   = sprintf('%02d:%02d', meals(k).End(1), meals(k).End(2));
    if isOpen
        statusCol(k) = "ACTIVE (OPEN NOW)";
    else
        statusCol(k) = "Closed";
    end
end

scheduleTable = table(mealCol, startCol, endCol, statusCol, ...
    'VariableNames', {'Meal', 'StartTime', 'EndTime', 'Status'});

view.Visible = 'on';
fig.UserData.adminCurrentView = 'schedule';
view.ColumnEditable = false;
view.CellEditCallback = [];
view.ColumnFormat = {};
view.ColumnWidth = 'auto';
view.Data = scheduleTable;
view.ColumnName = scheduleTable.Properties.VariableNames;

if nargin >= 5 && ~isempty(message) && isvalid(message)
    csvSource = 'MealSchedule.csv';
    if isfield(p, 'mealScheduleFile') && ~isempty(p.mealScheduleFile)
        csvSource = p.mealScheduleFile;
    end
    message.Text = sprintf('● Active Meal Schedule (Source: %s, Current time: %s).', ...
        csvSource, string(nowDt, 'HH:mm:ss'));
    message.FontColor = [0.05 0.40 0.05];
end
end
