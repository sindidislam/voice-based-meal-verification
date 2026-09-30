function stopped = interruptible_pause(durationSec, checkStopFcn)
%INTERRUPTIBLE_PAUSE Sleep in short slices, polling checkStopFcn for early stop.
%
%   stopped = interruptible_pause(durationSec, checkStopFcn)
%
%   durationSec  - total seconds to pause (double).
%   checkStopFcn - (optional) function handle @() returning true if stop requested.
%
%   Returns true if stop was requested during the duration, false otherwise.

if nargin < 2 || isempty(checkStopFcn)
    checkStopFcn = @() false;
end

stopped = false;
t0 = tic;
while toc(t0) < durationSec
    % Honor an already queued cancellation before a potentially busy GUI pump.
    try
        if checkStopFcn()
            stopped = true;
            return;
        end
    catch
        % Preserve the existing treatment of an unavailable stop source.
    end
    drawnow;
    % Event processing may itself dispatch the Stop callback.
    try
        if checkStopFcn()
            stopped = true;
            return;
        end
    catch
        % If stop check fails (e.g. invalid figure handle), treat as not stopped
    end
    pause(min(0.05, max(0.005, durationSec - toc(t0))));
end
end
