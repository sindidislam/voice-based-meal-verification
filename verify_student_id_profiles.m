function ok = verify_student_id_profiles(verbose)
%VERIFY_STUDENT_ID_PROFILES Focused checks for ID-keyed profile enumeration.
%   Builds a temporary Train tree with one valid seven-digit profile and one
%   legacy name-keyed folder, then asserts LIST_ID_PROFILES returns only the ID
%   profile and that STUDENT_PROFILE round-trips the display name without using
%   it as a key.
if nargin < 1, verbose = true; end
failures = {};

root = tempname;
cleanup = onCleanup(@() rm_if_present(root)); %#ok<NASGU>

p = dsp_parameters();
p.trainIdFolder     = fullfile(root, 'ID');
p.trainNameFolder   = fullfile(root, 'Name');
p.trainCouponFolder = fullfile(root, 'Coupon');

% One complete ID-keyed profile: a spoken-ID take plus metadata.
idFolder = fullfile(p.trainIdFolder, '2206147');
mkdir(idFolder);
audiowrite(fullfile(idFolder, '1.wav'), 0.1 * sin(1:800)', 8000);
student_profile(p, '2206147', 'Alice Example');

% A legacy name-keyed folder that must never be treated as an identity.
legacy = fullfile(p.trainIdFolder, 'Alice');
mkdir(legacy);
audiowrite(fullfile(legacy, '1.wav'), 0.1 * sin(1:800)', 8000);

% An ID folder with no recordings yet: an incomplete profile.
mkdir(fullfile(p.trainIdFolder, '3300000'));

profiles = list_id_profiles(p);
ids = {profiles.Id};
check(isequal(ids, {'2206147'}), 'only the complete seven-digit profile is listed');
check(~any(strcmp(ids, 'Alice')), 'legacy name folder is excluded as an identity');
check(~any(strcmp(ids, '3300000')), 'an ID folder with no takes is not yet a profile');

meta = student_profile(p, '2206147');
check(strcmp(meta.Name, 'Alice Example'), 'display name round-trips from metadata');
check(strcmp(meta.Id, '2206147'), 'metadata reports the canonical ID');

ok = isempty(failures);
if verbose
    if ok
        fprintf('VERIFY_STUDENT_ID_PROFILES: all checks passed.\n');
    else
        fprintf(2, 'VERIFY_STUDENT_ID_PROFILES: %d check(s) failed.\n', numel(failures));
        fprintf(2, '  - %s\n', failures{:});
    end
end
if ~ok
    error('verify_student_id_profiles:failed', '%d check(s) failed.', numel(failures));
end

    function check(condition, description)
        if ~condition, failures{end+1} = description; end %#ok<AGROW>
    end
end

function rm_if_present(folder)
if isfolder(folder)
    rmdir(folder, 's');
end
end
