function dlg = admin_configure_meal_hours(fig, adminId, pass, view, message)
%ADMIN_CONFIGURE_MEAL_HOURS Interactive dialog to configure meal service hours.
%
%   DLG = ADMIN_CONFIGURE_MEAL_HOURS(FIG, ADMINID, PASS, VIEW, MESSAGE)
%   verifies admin credentials and opens a modal configuration dialog where
%   an administrator can adjust Start and End hours/minutes for Breakfast,
%   Lunch, and Dinner.
%
%   New in v4.1.4: Proposal Goal 5 and modification 5 (CO4, CO5).

if ~admin_authorised(fig, adminId, pass, message)
    dlg = [];
    return;
end

p = fig.UserData.params;
currentMeals = p.meals;
if isempty(currentMeals)
    currentMeals = load_meal_schedule(p);
end

% Extract initial times
bIdx = find(strcmpi({currentMeals.Name}, 'Breakfast'), 1);
lIdx = find(strcmpi({currentMeals.Name}, 'Lunch'), 1);
dIdx = find(strcmpi({currentMeals.Name}, 'Dinner'), 1);

if isempty(bIdx), bStart = [7 0]; bEnd = [9 30]; else, bStart = currentMeals(bIdx).Start; bEnd = currentMeals(bIdx).End; end
if isempty(lIdx), lStart = [12 0]; lEnd = [14 30]; else, lStart = currentMeals(lIdx).Start; lEnd = currentMeals(lIdx).End; end
if isempty(dIdx), dStart = [19 0]; dEnd = [21 30]; else, dStart = currentMeals(dIdx).Start; dEnd = currentMeals(dIdx).End; end

% Window visibility matches parent (supports headless testing)
figVis = 'on';
if isprop(fig, 'Visible') && strcmp(fig.Visible, 'off')
    figVis = 'off';
end

parentPos = fig.Position;
dlgPos = [parentPos(1) + 120, parentPos(2) + 100, 580, 430];

dlg = uifigure('Name', 'Configure Meal Service Windows', ...
    'Tag', 'mealHoursDialog', ...
    'Position', dlgPos, ...
    'Visible', figVis);

g = uigridlayout(dlg, [7 6]);
g.RowHeight = {40, 26, 36, 36, 36, 32, 40};
g.ColumnWidth = {110, 75, 75, 40, 75, 75};
g.Padding = [20 18 20 18];

% Title
titleLbl = uilabel(g, 'Text', 'Configure Dining Service Hours (v4.1.4)', ...
    'FontSize', 15, 'FontWeight', 'bold');
titleLbl.Layout.Row = 1; titleLbl.Layout.Column = [1 6];

% Column Headers
subLbl = uilabel(g, 'Text', 'Start Time (HH:MM)                                      End Time (HH:MM)', ...
    'FontWeight', 'bold', 'FontColor', [0.35 0.35 0.35]);
subLbl.Layout.Row = 2; subLbl.Layout.Column = [2 6];

% Breakfast Row
bLbl = uilabel(g, 'Text', 'Breakfast', 'FontWeight', 'bold');
bLbl.Layout.Row = 3; bLbl.Layout.Column = 1;

bStartH = uispinner(g, 'Limits', [0 23], 'Value', round(bStart(1)), 'Tag', 'bStartH');
bStartH.Layout.Row = 3; bStartH.Layout.Column = 2;
bStartM = uispinner(g, 'Limits', [0 59], 'Value', round(bStart(2)), 'Tag', 'bStartM');
bStartM.Layout.Row = 3; bStartM.Layout.Column = 3;

to1 = uilabel(g, 'Text', 'to', 'HorizontalAlignment', 'center');
to1.Layout.Row = 3; to1.Layout.Column = 4;

bEndH = uispinner(g, 'Limits', [0 23], 'Value', round(bEnd(1)), 'Tag', 'bEndH');
bEndH.Layout.Row = 3; bEndH.Layout.Column = 5;
bEndM = uispinner(g, 'Limits', [0 59], 'Value', round(bEnd(2)), 'Tag', 'bEndM');
bEndM.Layout.Row = 3; bEndM.Layout.Column = 6;

% Lunch Row
lLbl = uilabel(g, 'Text', 'Lunch', 'FontWeight', 'bold');
lLbl.Layout.Row = 4; lLbl.Layout.Column = 1;

lStartH = uispinner(g, 'Limits', [0 23], 'Value', round(lStart(1)), 'Tag', 'lStartH');
lStartH.Layout.Row = 4; lStartH.Layout.Column = 2;
lStartM = uispinner(g, 'Limits', [0 59], 'Value', round(lStart(2)), 'Tag', 'lStartM');
lStartM.Layout.Row = 4; lStartM.Layout.Column = 3;

to2 = uilabel(g, 'Text', 'to', 'HorizontalAlignment', 'center');
to2.Layout.Row = 4; to2.Layout.Column = 4;

lEndH = uispinner(g, 'Limits', [0 23], 'Value', round(lEnd(1)), 'Tag', 'lEndH');
lEndH.Layout.Row = 4; lEndH.Layout.Column = 5;
lEndM = uispinner(g, 'Limits', [0 59], 'Value', round(lEnd(2)), 'Tag', 'lEndM');
lEndM.Layout.Row = 4; lEndM.Layout.Column = 6;

% Dinner Row
dLbl = uilabel(g, 'Text', 'Dinner', 'FontWeight', 'bold');
dLbl.Layout.Row = 5; dLbl.Layout.Column = 1;

dStartH = uispinner(g, 'Limits', [0 23], 'Value', round(dStart(1)), 'Tag', 'dStartH');
dStartH.Layout.Row = 5; dStartH.Layout.Column = 2;
dStartM = uispinner(g, 'Limits', [0 59], 'Value', round(dStart(2)), 'Tag', 'dStartM');
dStartM.Layout.Row = 5; dStartM.Layout.Column = 3;

to3 = uilabel(g, 'Text', 'to', 'HorizontalAlignment', 'center');
to3.Layout.Row = 5; to3.Layout.Column = 4;

dEndH = uispinner(g, 'Limits', [0 23], 'Value', round(dEnd(1)), 'Tag', 'dEndH');
dEndH.Layout.Row = 5; dEndH.Layout.Column = 5;
dEndM = uispinner(g, 'Limits', [0 59], 'Value', round(dEnd(2)), 'Tag', 'dEndM');
dEndM.Layout.Row = 5; dEndM.Layout.Column = 6;

% Status message
statusMsg = uilabel(g, 'Text', 'Times are in 24-hour format (HH:MM). Windows cannot overlap.', ...
    'Tag', 'statusMsg', 'FontColor', [0.35 0.35 0.35]);
statusMsg.Layout.Row = 6; statusMsg.Layout.Column = [1 6];

% Buttons row
saveBtn = uibutton(g, 'Text', 'Save & Apply', 'Tag', 'saveMealHoursBtn', ...
    'FontWeight', 'bold', 'BackgroundColor', [0.85 0.94 0.85]);
saveBtn.Layout.Row = 7; saveBtn.Layout.Column = [1 2];

resetBtn = uibutton(g, 'Text', 'Reset to Defaults', 'Tag', 'resetMealHoursBtn', ...
    'BackgroundColor', [0.94 0.90 0.85]);
resetBtn.Layout.Row = 7; resetBtn.Layout.Column = [3 4];

cancelBtn = uibutton(g, 'Text', 'Cancel', 'Tag', 'cancelMealHoursBtn');
cancelBtn.Layout.Row = 7; cancelBtn.Layout.Column = [5 6];

% Callbacks
saveBtn.ButtonPushedFcn = @(~,~) save_action();
resetBtn.ButtonPushedFcn = @(~,~) reset_action();
cancelBtn.ButtonPushedFcn = @(~,~) delete(dlg);

    function save_action()
        newSchedule = struct( ...
            'Name', {'Breakfast', 'Lunch', 'Dinner'}, ...
            'Start', {[bStartH.Value, bStartM.Value], [lStartH.Value, lStartM.Value], [dStartH.Value, dStartM.Value]}, ...
            'End',   {[bEndH.Value, bEndM.Value], [lEndH.Value, lEndM.Value], [dEndH.Value, dEndM.Value]});
        
        [isValid, err] = validate_meal_schedule(newSchedule);
        if ~isValid
            statusMsg.Text = sprintf('Invalid: %s', err);
            statusMsg.FontColor = [0.70 0.05 0.05];
            return;
        end
        
        csvFile = 'MealSchedule.csv';
        if isfield(fig.UserData.params, 'mealScheduleFile') && ~isempty(fig.UserData.params.mealScheduleFile)
            csvFile = fig.UserData.params.mealScheduleFile;
        end
        
        [ok, saveErr] = save_meal_schedule(newSchedule, csvFile);
        if ~ok
            statusMsg.Text = sprintf('Save error: %s', saveErr);
            statusMsg.FontColor = [0.70 0.05 0.05];
            return;
        end
        
        % Update active parameters in main GUI
        fig.UserData.params.meals = newSchedule;
        
        % Refresh window indicator on Verify tab
        winLbl = findobj(fig, 'Tag', 'verifyWindow');
        if ~isempty(winLbl) && isvalid(winLbl)
            [mealName, winInfo] = meal_window_now(fig.UserData.params, datetime('now'));
            if isempty(mealName)
                if ~isfield(winInfo, 'NextWindow') || isempty(winInfo.NextWindow)
                    allWins = '';
                    if isfield(winInfo, 'AllWindows'), allWins = winInfo.AllWindows; end
                    winLbl.Text = sprintf('Closed. Windows: %s', allWins);
                else
                    minsToNext = 0;
                    if isfield(winInfo, 'MinutesToNext') && ~isnan(winInfo.MinutesToNext)
                        minsToNext = round(winInfo.MinutesToNext);
                    end
                    winLbl.Text = sprintf('Closed - %s opens in %d min', ...
                        winInfo.NextWindow, minsToNext);
                end
                winLbl.FontColor = [0.55 0.35 0.05];
            else
                minsRem = 60;
                if isfield(winInfo, 'MinutesRemaining') && ~isnan(winInfo.MinutesRemaining)
                    minsRem = round(winInfo.MinutesRemaining);
                elseif isfield(winInfo, 'WindowEnd') && isfield(winInfo, 'MinuteOfDay') && ~isnan(winInfo.WindowEnd)
                    minsRem = max(0, round(winInfo.WindowEnd - winInfo.MinuteOfDay));
                end
                winLbl.Text = sprintf('%s is open - %d min remaining', ...
                    mealName, minsRem);
                winLbl.FontColor = [0.05 0.40 0.05];
            end
        end
        
        % Refresh footer if present
        footerLbl = findobj(fig, 'Tag', 'guiFooter');
        if ~isempty(footerLbl) && isvalid(footerLbl)
            footerLbl.Text = footer_text(fig.UserData.params);
        end
        
        % Update admin status message
        if ~isempty(message) && isvalid(message)
            message.Text = sprintf(['● Meal hours updated: Breakfast %02d:%02d-%02d:%02d, ' ...
                'Lunch %02d:%02d-%02d:%02d, Dinner %02d:%02d-%02d:%02d (saved to %s).'], ...
                newSchedule(1).Start(1), newSchedule(1).Start(2), newSchedule(1).End(1), newSchedule(1).End(2), ...
                newSchedule(2).Start(1), newSchedule(2).Start(2), newSchedule(2).End(1), newSchedule(2).End(2), ...
                newSchedule(3).Start(1), newSchedule(3).Start(2), newSchedule(3).End(1), newSchedule(3).End(2), ...
                csvFile);
            message.FontColor = [0.05 0.40 0.05];
        end
        
        % Update admin table if visible
        if ~isempty(view) && isvalid(view) && strcmp(view.Visible, 'on')
            admin_show_schedule(fig, [], [], view, []);
        end
        
        delete(dlg);
    end

    function reset_action()
        bStartH.Value = 7; bStartM.Value = 0; bEndH.Value = 9; bEndM.Value = 30;
        lStartH.Value = 12; lStartM.Value = 0; lEndH.Value = 14; lEndM.Value = 30;
        dStartH.Value = 19; dStartM.Value = 0; dEndH.Value = 21; dEndM.Value = 30;
        statusMsg.Text = 'Default hours restored. Click "Save & Apply" to save.';
        statusMsg.FontColor = [0.05 0.35 0.65];
    end
end
