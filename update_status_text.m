function update_status_text(handle, message)
%UPDATE_STATUS_TEXT Report progress to a GUI text area, or to the console.
%
%   UPDATE_STATUS_TEXT(HANDLE, MESSAGE) prepends MESSAGE to the uitextarea
%   HANDLE, so the newest line is always the one the operator reads first.
%
%   UPDATE_STATUS_TEXT([], MESSAGE) prints to the command window instead.
%
%   Why the empty-handle case matters
%   --------------------------------
%   Every workflow in this system reports through this one function, so if it
%   required a live figure handle then none of those workflows could be run
%   without a GUI -- and a step that cannot be run headless cannot be covered by
%   VERIFY_DSP_PIPELINE or driven from a batch script.  Accepting [] is what lets
%   VERIFY_MEAL_WORKFLOW be tested end to end, including the window and
%   anti-double-dipping rules, at any hour and with no operator present.
%
%   A deleted handle is treated the same way.  The counter application can be
%   closed while a 3 s recording is still in progress, and a status update
%   arriving after that should not turn into an error dialog on top of a figure
%   that no longer exists.
%
%   See also VERIFY_MEAL_WORKFLOW, CAPTURE_VOICE_FEATURES.

message = char(string(message));

if isempty(handle) || ~isvalid_handle(handle)
    fprintf('%s\n', message);
    return;
end

try
    old = handle.Value;
    if ischar(old)
        old = {old};
    end
    handle.Value = [{message}; old];
    drawnow limitrate;
catch
    % The figure went away mid-transaction. Fall back to the console rather than
    % letting a cosmetic update abort a meal transaction.
    fprintf('%s\n', message);
end
end

% -------------------------------------------------------------------------
function tf = isvalid_handle(h)
tf = false;
try
    tf = isobject(h) && isvalid(h) && isprop(h, 'Value');
catch
    tf = false;
end
end
