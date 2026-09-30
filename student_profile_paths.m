function paths = student_profile_paths(params, studentId)
%STUDENT_PROFILE_PATHS Canonical folder and metadata paths for one Student ID.
%
%   PATHS = STUDENT_PROFILE_PATHS(PARAMS, STUDENTID) validates STUDENTID with
%   STUDENT_ID_CONTRACT and returns a struct of the four locations that make up
%   one student's record:
%
%     PATHS.Id       Train/ID/<id>       spoken Student-ID voice takes
%     PATHS.Name     Train/Name/<id>     spoken full-name voice takes (fallback)
%     PATHS.Coupon   Train/Coupon/<id>   spoken coupon-digit voice takes
%     PATHS.Metadata Train/ID/<id>/profile.mat   display name + enrolment notes
%
%   Every root is keyed by the seven-digit ID, never by the student's name, so
%   the name is free to change or repeat without moving any data. An invalid ID
%   raises an error rather than returning a path, because building a path from a
%   bad ID is exactly how one student's takes end up in another's folder.
%
%   See also STUDENT_ID_CONTRACT, STUDENT_PROFILE, LIST_ID_PROFILES.

if nargin < 1 || isempty(params)
    params = dsp_parameters();
end

[id, ok, message] = student_id_contract(studentId);
if ~ok
    error('student_profile_paths:invalidId', '%s', message);
end

paths = struct();
paths.Id       = fullfile(params.trainIdFolder, id);
paths.Name     = fullfile(params.trainNameFolder, id);
paths.Coupon   = fullfile(params.trainCouponFolder, id);
paths.Metadata = fullfile(paths.Id, 'profile.mat');
end
