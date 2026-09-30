function [isValid, errMsg] = validate_meal_schedule(meals)
%VALIDATE_MEAL_SCHEDULE Validate meal service window structure and time bounds.
%
%   [ISVALID, ERRMSG] = VALIDATE_MEAL_SCHEDULE(MEALS) checks that:
%     1. MEALS is a non-empty struct array with Name, Start, and End fields.
%     2. Each Start and End is [Hour Minute] with 0 <= Hour <= 23 and 0 <= Minute <= 59.
%     3. For each meal, Start time is strictly earlier than End time.
%     4. No two meal windows overlap in time (using half-open intervals [start, end)).
%
%   Proposal modification 5: dining hall business logic. EEE 312 CO4 / CO5.

isValid = false;
errMsg = '';

if isempty(meals) || ~isstruct(meals)
    errMsg = 'Meal schedule must be a non-empty struct array.';
    return;
end

requiredFields = {'Name', 'Start', 'End'};
for f = requiredFields
    if ~isfield(meals, f{1})
        errMsg = sprintf('Meal struct array is missing required field "%s".', f{1});
        return;
    end
end

nMeals = numel(meals);
startsMin = zeros(nMeals, 1);
endsMin   = zeros(nMeals, 1);

for k = 1:nMeals
    mealName = char(string(meals(k).Name));
    if isempty(mealName)
        errMsg = sprintf('Meal %d has an empty name.', k);
        return;
    end
    
    st = meals(k).Start;
    et = meals(k).End;
    
    if ~isnumeric(st) || numel(st) ~= 2 || any(~isfinite(st)) || ...
       ~isnumeric(et) || numel(et) ~= 2 || any(~isfinite(et))
        errMsg = sprintf('Meal "%s" must have 2-element numeric [Hour Minute] for Start and End.', mealName);
        return;
    end
    
    sHour = round(st(1)); sMin = round(st(2));
    eHour = round(et(1)); eMin = round(et(2));
    
    if sHour < 0 || sHour > 23 || sMin < 0 || sMin > 59
        errMsg = sprintf('Meal "%s" start time (%02d:%02d) is outside valid range (00:00 to 23:59).', ...
            mealName, sHour, sMin);
        return;
    end
    
    if eHour < 0 || eHour > 23 || eMin < 0 || eMin > 59
        errMsg = sprintf('Meal "%s" end time (%02d:%02d) is outside valid range (00:00 to 23:59).', ...
            mealName, eHour, eMin);
        return;
    end
    
    startTotal = sHour * 60 + sMin;
    endTotal   = eHour * 60 + eMin;
    
    if startTotal >= endTotal
        errMsg = sprintf('Meal "%s" start time (%02d:%02d) must be strictly earlier than end time (%02d:%02d).', ...
            mealName, sHour, sMin, eHour, eMin);
        return;
    end
    
    startsMin(k) = startTotal;
    endsMin(k)   = endTotal;
end

% Check for window overlaps
% Sort by start time
[sortedStarts, sortIdx] = sort(startsMin);
sortedEnds   = endsMin(sortIdx);
sortedNames  = {meals(sortIdx).Name};

for k = 1:(nMeals - 1)
    if sortedStarts(k + 1) < sortedEnds(k)
        name1 = char(string(sortedNames{k}));
        name2 = char(string(sortedNames{k + 1}));
        h1e = floor(sortedEnds(k) / 60); m1e = mod(sortedEnds(k), 60);
        h2s = floor(sortedStarts(k + 1) / 60); m2s = mod(sortedStarts(k + 1), 60);
        errMsg = sprintf('Meal window overlap detected: %s ends at %02d:%02d but %s starts earlier at %02d:%02d.', ...
            name1, h1e, m1e, name2, h2s, m2s);
        return;
    end
end

isValid = true;
errMsg = '';
end
