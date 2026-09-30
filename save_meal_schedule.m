function [ok, errMsg] = save_meal_schedule(meals, csvFile)
%SAVE_MEAL_SCHEDULE Save configured meal service windows to persistent CSV.
%
%   [OK, ERRMSG] = SAVE_MEAL_SCHEDULE(MEALS, CSVFILE) validates the MEALS
%   struct array and writes it to CSVFILE. If CSVFILE is omitted, defaults to
%   'MealSchedule.csv'.
%
%   Returns:
%     OK     - true if successfully written, false on validation/write error
%     ERRMSG - explanatory text if failed, empty on success

ok = false;
errMsg = '';

if nargin < 2 || isempty(csvFile)
    csvFile = 'MealSchedule.csv';
end

[isValid, valErr] = validate_meal_schedule(meals);
if ~isValid
    errMsg = valErr;
    return;
end

try
    fid = fopen(csvFile, 'w');
    if fid == -1
        errMsg = sprintf('Could not open file "%s" for writing.', csvFile);
        return;
    end
    
    fprintf(fid, 'Meal,StartHour,StartMinute,EndHour,EndMinute\n');
    for k = 1:numel(meals)
        sHour = round(meals(k).Start(1));
        sMin  = round(meals(k).Start(2));
        eHour = round(meals(k).End(1));
        eMin  = round(meals(k).End(2));
        fprintf(fid, '%s,%d,%d,%d,%d\n', meals(k).Name, sHour, sMin, eHour, eMin);
    end
    fclose(fid);
    
    ok = true;
    errMsg = '';
catch ME
    if exist('fid', 'var') && fid ~= -1
        fclose(fid);
    end
    errMsg = sprintf('Error writing meal schedule: %s', ME.message);
end
end
