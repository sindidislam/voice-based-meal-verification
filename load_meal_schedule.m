function meals = load_meal_schedule(params)
%LOAD_MEAL_SCHEDULE Load meal service windows from persistent CSV or defaults.
%
%   MEALS = LOAD_MEAL_SCHEDULE(PARAMS) reads the configured CSV file
%   (default: MealSchedule.csv). If the file exists and is valid, returns the
%   customized meal schedule. Otherwise, returns the calibrated default
%   schedule (Breakfast 07:00-09:30, Lunch 12:00-14:30, Dinner 19:00-21:30).
%
%   Fields of each struct element:
%     Name  - char string ('Breakfast', 'Lunch', 'Dinner')
%     Start - [hour minute], e.g. [7 0]
%     End   - [hour minute], e.g. [9 30]

defaultMeals = struct( ...
    'Name',  {'Breakfast', 'Lunch', 'Dinner'}, ...
    'Start', {[ 7  0], [12  0], [19  0]}, ...
    'End',   {[ 9 30], [14 30], [21 30]});

if nargin < 1 || isempty(params)
    csvFile = 'MealSchedule.csv';
elseif isfield(params, 'mealScheduleFile') && ~isempty(params.mealScheduleFile)
    csvFile = params.mealScheduleFile;
else
    csvFile = 'MealSchedule.csv';
end

if ~isfile(csvFile)
    meals = defaultMeals;
    return;
end

try
    t = readtable(csvFile, 'TextType', 'string');
    reqCols = {'Meal', 'StartHour', 'StartMinute', 'EndHour', 'EndMinute'};
    for c = reqCols
        if ~ismember(c{1}, t.Properties.VariableNames)
            warning('load_meal_schedule:missingColumn', ...
                'File %s is missing column %s. Using default schedule.', csvFile, c{1});
            meals = defaultMeals;
            return;
        end
    end
    
    nRows = height(t);
    if nRows == 0
        meals = defaultMeals;
        return;
    end
    
    meals = repmat(struct('Name', '', 'Start', [0 0], 'End', [0 0]), nRows, 1);
    for k = 1:nRows
        meals(k).Name  = char(string(t.Meal(k)));
        meals(k).Start = [double(t.StartHour(k)), double(t.StartMinute(k))];
        meals(k).End   = [double(t.EndHour(k)), double(t.EndMinute(k))];
    end
    
    [isValid, errMsg] = validate_meal_schedule(meals);
    if ~isValid
        warning('load_meal_schedule:invalidSchedule', ...
            'Schedule in %s is invalid (%s). Falling back to defaults.', csvFile, errMsg);
        meals = defaultMeals;
    end
catch ME
    warning('load_meal_schedule:readError', ...
        'Could not parse %s (%s). Using default schedule.', csvFile, ME.message);
    meals = defaultMeals;
end
end
