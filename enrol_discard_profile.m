function enrol_discard_profile(fig, sid, status)
%ENROL_DISCARD_PROFILE Delete all enrolled voice recordings for this student ID to start fresh.
p = fig.UserData.params;
[student, idOk, idMessage] = student_id_contract(sid.Value);
if ~idOk
    update_status_text(status, ['Cannot discard profile: ' idMessage]);
    return;
end

paths = student_profile_paths(p, student);
folders = {paths.Id, paths.Name, paths.Coupon};
hasFiles = false;
for k = 1:numel(folders)
    if isfolder(folders{k}) && ~isempty(dir(fullfile(folders{k}, '*.wav')))
        hasFiles = true;
        break;
    end
end

if ~hasFiles
    update_status_text(status, sprintf('No voice recordings found for Student ID %s to discard.', student));
    return;
end

choice = uiconfirm(fig, ...
    sprintf('Are you sure you want to delete ALL voice recordings for Student ID %s and start fresh from the beginning?', student), ...
    'Discard Enrolled Profile', ...
    'Options', {'Delete and start fresh', 'Cancel'}, ...
    'DefaultOption', 'Delete and start fresh', ...
    'CancelOption', 'Cancel');

if strcmp(choice, 'Delete and start fresh')
    nDeleted = delete_student_recordings(folders);
    find_best_voice_match('reset');
    update_status_text(status, sprintf('● DISCARDED: %d voice recording(s) for Student ID %s deleted.', nDeleted, student));
    update_status_text(status, '  Profile reset completely. You can now press "New Enroll" to record fresh from Take 1.');
else
    update_status_text(status, 'Discard cancelled; existing recordings were preserved.');
end
end
