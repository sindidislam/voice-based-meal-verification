function [windowName, info] = meal_window_now(params, nowValue)
%MEAL_WINDOW_NOW Which meal service window a given instant falls in.
%
%   [WINDOWNAME, INFO] = MEAL_WINDOW_NOW(PARAMS, NOWVALUE) returns the name of
%   the meal window containing NOWVALUE, or '' if the instant is outside every
%   window.  NOWVALUE defaults to the current local time.
%
%   Proposal modification 5: dining hall business logic.  EEE 312 CO4 (design a
%   system that considers public health and societal context) and CO5 (ethics).
%
%   Windows come from PARAMS.meals, so Breakfast, Lunch and Dinner are data, not
%   code.  A hall that serves at different times changes one struct in
%   DSP_PARAMETERS and nothing else; the previous revision had 07-09, 12-14 and
%   17-19 written into the logging function, the GUI footer text and the
%   regression test as three independent copies of the same numbers, which is how
%   those three came to disagree.
%
%   INFO reports:
%     Index          position in PARAMS.meals, or 0 when outside a window.
%     MinuteOfDay    the instant reduced to minutes since midnight.
%     WindowStart /  window bounds in minutes since midnight.
%     WindowEnd
%     NextWindow     name of the next window to open today, or '' if none remain.
%     MinutesToNext  wait until that window opens, or NaN.
%     AllWindows     every window as a printable string, for status messages.
%
%   The half-open convention
%   ------------------------
%   A window is start <= t < end.  Making the upper bound exclusive means two
%   adjacent windows can never both contain the same minute, so a student who
%   arrives exactly as one window closes is served by exactly one of them.  With
%   an inclusive upper bound the boundary minute belongs to two windows at once
%   and the anti-double-dipping check could be satisfied twice.
%
%   See also LOG_MEAL_CSV, VERIFY_MEAL_WORKFLOW, DSP_PARAMETERS.

if nargin < 1 || isempty(params), params = dsp_parameters(); end
if nargin < 2 || isempty(nowValue), nowValue = datetime('now'); end

meals = params.meals;
minuteOfDay = hour(nowValue)*60 + minute(nowValue);

starts = zeros(numel(meals),1);
ends   = zeros(numel(meals),1);
descriptions = strings(numel(meals),1);
for k = 1:numel(meals)
    starts(k) = meals(k).Start(1)*60 + meals(k).Start(2);
    ends(k)   = meals(k).End(1)*60   + meals(k).End(2);
    descriptions(k) = sprintf('%s %02d:%02d-%02d:%02d', meals(k).Name, ...
        meals(k).Start(1), meals(k).Start(2), meals(k).End(1), meals(k).End(2));
end

index = find(minuteOfDay >= starts & minuteOfDay < ends, 1);

if isfield(params, 'demoMode24x7') && params.demoMode24x7 && isempty(index)
    windowName = 'Demo-Service';
    info = struct();
    info.MinuteOfDay = minuteOfDay;
    info.AllWindows = strjoin(descriptions, ', ');
    info.Starts = starts;
    info.Ends = ends;
    info.Index = 1;
    info.WindowStart = 0;
    info.WindowEnd = 1440;
    info.NextWindow = 'Demo-Service';
    info.MinutesToNext = 0;
    info.MinutesRemaining = max(0, 1440 - minuteOfDay);
    return;
end

info = struct();
info.MinuteOfDay = minuteOfDay;
info.AllWindows  = strjoin(descriptions, ', ');
info.Starts = starts;
info.Ends   = ends;

if isempty(index)
    windowName = '';
    info.Index = 0;
    info.WindowStart = NaN;
    info.WindowEnd = NaN;
    info.MinutesRemaining = NaN;
    upcoming = find(starts > minuteOfDay);
    if isempty(upcoming)
        info.NextWindow = '';
        info.MinutesToNext = NaN;
    else
        [~, soonest] = min(starts(upcoming));
        nextIdx = upcoming(soonest);
        info.NextWindow = meals(nextIdx).Name;
        info.MinutesToNext = starts(nextIdx) - minuteOfDay;
    end
    return;
end

windowName = meals(index).Name;
info.Index = index;
info.WindowStart = starts(index);
info.WindowEnd = ends(index);
info.NextWindow = '';
info.MinutesToNext = NaN;
info.MinutesRemaining = ends(index) - minuteOfDay;
end
