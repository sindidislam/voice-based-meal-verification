function ok = verify_student_id_contract(verbose)
%VERIFY_STUDENT_ID_CONTRACT Focused checks for the Student-ID identity contract.
%   Exercises STUDENT_ID_CONTRACT normalisation/validation and the canonical
%   STUDENT_PROFILE_PATHS layout. Returns true when every check passes; also
%   errors on failure so it can be run with `matlab -batch`.
if nargin < 1, verbose = true; end
failures = {};

p = dsp_parameters();

% --- ID normalisation and validation -------------------------------------
[id, good] = student_id_contract(' 2206147 ');
check(good && strcmp(id, '2206147'), 'trims whitespace and accepts seven digits');

[~, good] = student_id_contract('220614');
check(~good, 'six digits are rejected');

[~, good] = student_id_contract('22061478');
check(~good, 'eight digits are rejected');

[~, good] = student_id_contract('2206147a');
check(~good, 'non-numeric IDs are rejected');

[~, good] = student_id_contract('');
check(~good, 'empty IDs are rejected');

% --- Canonical path layout ------------------------------------------------
paths = student_profile_paths(p, '2206147');
check(strcmp(paths.Id, fullfile(p.trainIdFolder, '2206147')), 'ID root is Train/ID/<id>');
check(strcmp(paths.Name, fullfile(p.trainNameFolder, '2206147')), 'name root is Train/Name/<id>');
check(strcmp(paths.Coupon, fullfile(p.trainCouponFolder, '2206147')), 'coupon root is Train/Coupon/<id>');
check(strcmp(paths.Metadata, fullfile(paths.Id, 'profile.mat')), 'metadata sits inside the ID folder');

threw = false;
try
    student_profile_paths(p, 'nope');
catch
    threw = true;
end
check(threw, 'building paths from an invalid ID errors instead of returning one');

ok = isempty(failures);
if verbose
    if ok
        fprintf('VERIFY_STUDENT_ID_CONTRACT: all checks passed.\n');
    else
        fprintf(2, 'VERIFY_STUDENT_ID_CONTRACT: %d check(s) failed.\n', numel(failures));
        fprintf(2, '  - %s\n', failures{:});
    end
end
if ~ok
    error('verify_student_id_contract:failed', '%d check(s) failed.', numel(failures));
end

    function check(condition, description)
        if ~condition, failures{end+1} = description; end %#ok<AGROW>
    end
end
