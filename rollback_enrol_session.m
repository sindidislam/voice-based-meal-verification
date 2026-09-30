function nDeleted = rollback_enrol_session(fig, status, phraseLabel, sessionCreatedFiles)
%ROLLBACK_ENROL_SESSION Cancel enrollment immediately and delete partial takes.
%
%   nDeleted = rollback_enrol_session(fig, status, phraseLabel, sessionCreatedFiles)
%
%   Clears the stop flag, deletes any .wav files created during the interrupted
%   session, resets the template cache, and posts diagnostic status updates.

if ~isempty(fig)
    try
        if isprop(fig, 'UserData') && isvalid(fig)
            uData = fig.UserData;
            if isstruct(uData)
                uData.enrolStopRequested = false;
                fig.UserData = uData;
            end
        end
    catch
    end
end

if nargin < 3 || isempty(phraseLabel)
    phraseLabel = 'Voice';
end
if nargin < 4 || isempty(sessionCreatedFiles)
    sessionCreatedFiles = {};
end

update_status_text(status, sprintf('● INSTANT STOP PRESSED: %s enrollment cancelled immediately.', phraseLabel));

nDeleted = 0;
for f = 1:numel(sessionCreatedFiles)
    targetFile = char(sessionCreatedFiles{f});
    if isfile(targetFile)
        try
            delete(targetFile);
            nDeleted = nDeleted + 1;
        catch
        end
    end
end

if nDeleted > 0
    update_status_text(status, sprintf('  Cleaned up %d partial .wav take(s) recorded during this session.', nDeleted));
else
    update_status_text(status, '  In-progress take aborted before saving (no partial files written).');
end

find_best_voice_match('reset');
update_status_text(status, 'New Enroll session terminated completely. Ready to start from the beginning.');
end
