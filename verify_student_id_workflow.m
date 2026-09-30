function ok = verify_student_id_workflow(verbose)
%VERIFY_STUDENT_ID_WORKFLOW Focused checks for ID-first, Name-fallback verification.
%   Builds a temporary ID-keyed voice corpus from synthetic features so the
%   workflow can be exercised without a microphone, then asserts:
%     * a passing ID confirms the canonical seven-digit claim without Name;
%     * Name independently verifies the claim after failed ID evidence;
%     * a legacy name-only folder can never produce a result;
%     * manual entry cannot grant access without biometric evidence.
if nargin < 1, verbose = true; end
failures = {};

root = tempname;
cleanup = onCleanup(@() rm_if_present(root)); %#ok<NASGU>

p = dsp_parameters(false);
p.trainIdFolder     = fullfile(root, 'ID');
p.trainNameFolder   = fullfile(root, 'Name');
p.trainCouponFolder = fullfile(root, 'Coupon');
p.logFile                 = [tempname '.csv'];
p.monthlyEntitlementFile  = [tempname '.csv'];
p.monthlyCouponFile       = [tempname '.csv'];
fidCoupon = fopen(p.monthlyCouponFile, 'w'); if fidCoupon ~= -1, fclose(fidCoupon); end
fileCleanup = onCleanup(@() delete_if_present(p.logFile, p.monthlyEntitlementFile, p.monthlyCouponFile)); %#ok<NASGU>

% Two enrolled students, keyed by ID. We store real WAV takes so the matcher
% builds a template library, and reuse the extracted features as the "spoken"
% capture so a student always matches their own template most closely.
idA = '2206147';
idB = '3300000';
featById = struct();
featById.(sprintf('id_%s', idA)) = enrol_phrase(p, p.trainIdFolder, idA, 1.0);
featById.(sprintf('nm_%s', idA)) = enrol_phrase(p, p.trainNameFolder, idA, 2.0);
featById.(sprintf('id_%s', idB)) = enrol_phrase(p, p.trainIdFolder, idB, 3.0);
featById.(sprintf('nm_%s', idB)) = enrol_phrase(p, p.trainNameFolder, idB, 4.0);
student_profile(p, idA, 'Alice Example');
student_profile(p, idB, 'Bob Example');
find_best_voice_match('reset');

% A legacy name-only folder with no valid ID key.
legacyFolder = fullfile(p.trainNameFolder, 'Charlie');
mkdir(legacyFolder);
copyfile(fullfile(p.trainNameFolder, idA, '1.wav'), fullfile(legacyFolder, '1.wav'));
find_best_voice_match('reset');

opts = struct('SkipLogging', true, 'NowValue', datetime(2026,9,7,12,30,0), 'ClaimedID', idA);

% 1. A passing ID confirms the claim; Name need not be captured or scored.
o1 = opts; o1.IDFeatures = featById.(sprintf('id_%s', idA));
o1.NameFeatures = featById.(sprintf('nm_%s', idA));
r1 = verify_meal_workflow([], '', p, o1);
check(r1.Verified && strcmp(r1.Student, idA), 'ID verifies the canonical claim');
check(strcmp(r1.IdentifiedBy, 'id+name') && r1.NameCaptured, 'Both phrases are captured and verified');
check(strcmp(r1.StudentName, 'Alice Example'), 'display name comes from ID metadata');

% 2. Failed ID evidence invokes Name, which must independently confirm the claim.
o2 = opts;
o2.IDFeatures = 50 * ones(size(featById.(sprintf('id_%s', idA))));
o2.NameFeatures = featById.(sprintf('nm_%s', idA));
r2 = verify_meal_workflow([], '', p, o2);
check(~r2.Verified, ...
    'Failed ID evidence prevents fraudulent verification');
check(r2.NameCaptured, 'Both phrases are recorded before decision');
o3=o1; o3.ClaimedID=idB;
r3=verify_meal_workflow([], '',p,o3);
check(~r3.Verified && isempty(r3.Student), ...
    'Neither phrase may substitute its nearest candidate for a different supplied claim');

% 3. A legacy name-keyed folder is invisible to the deployed matcher, so feeding
%    Charlie's own take never resolves to "Charlie" (or any identity here that
%    would collide). The matcher only returns seven-digit IDs.
[~, legacyUser] = find_best_voice_match(p.trainNameFolder, ...
    enrol_template_features(fullfile(legacyFolder, '1.wav'), [], p), p);
if ~isempty(legacyUser)
    [~, legacyResolvesToId] = student_id_contract(legacyUser);
    check(legacyResolvesToId, 'matcher never returns a non-ID folder as a match');
end
[~, legacyOk] = student_id_contract('Charlie');
check(~legacyOk, 'a legacy name folder is not a valid Student ID');

% 4. A typed ID and even an assigned coupon cannot replace speaker evidence.
%    The legacy manual entry point must refuse without consuming the coupon.
assign_monthly_coupon(idB, '123456', p, opts.NowValue);
registryBefore = fileread(p.monthlyCouponFile);
rm = manual_entry_workflow(idB, '123456', p, opts.NowValue, true);
check(strcmp(rm.Student, idB) && ~rm.Granted && ~rm.Logged, ...
    'manual entry refuses an enrolled ID without biometric evidence');
check(strcmp(fileread(p.monthlyCouponFile), registryBefore), ...
    'manual refusal does not consume an assigned coupon');
rbad = manual_entry_workflow('220614', '123456', p, opts.NowValue, true);
check(~rbad.Granted, 'manual entry refuses a six-digit ID');

ok = isempty(failures);
if verbose
    if ok
        fprintf('VERIFY_STUDENT_ID_WORKFLOW: all checks passed.\n');
    else
        fprintf(2, 'VERIFY_STUDENT_ID_WORKFLOW: %d check(s) failed.\n', numel(failures));
        fprintf(2, '  - %s\n', failures{:});
    end
end
if ~ok
    error('verify_student_id_workflow:failed', '%d check(s) failed.', numel(failures));
end

    function check(condition, description)
        if ~condition, failures{end+1} = description; end %#ok<AGROW>
    end
end

function feat = enrol_phrase(p, rootFolder, id, seed)
%ENROL_PHRASE Write three voiced takes for one phrase and return the features
%   of the first, so a test "capture" matches this student's own templates.
%   Uses SYNTH_VOICED_SIGNAL because it is built to survive the endpoint and
%   liveness gates that a plain sine tone fails; the seed shifts the formants so
%   different students/phrases land on distinguishable templates.
folder = fullfile(rootFolder, id);
if ~isfolder(folder), mkdir(folder); end
fs = p.fs;
% A half-second of silence in front gives the endpoint detector a noise floor
% to learn, matching how live captures are recorded.
lead = zeros(round(0.5*fs), 1);
formants = [500 1500 2500] + 90*seed;
for k = 1:3
    voiced = synth_voiced_signal(fs, 1.0, [110 150] + 4*seed, formants, 0.35);
    audio = [lead; voiced + 0.001*(k-1)];
    audiowrite(fullfile(folder, sprintf('%d.wav', k)), audio, fs);
end
feat = enrol_template_features(fullfile(folder, '1.wav'), [], p);
end

function write_code_file(p, id, digits)
folder = fullfile(p.trainIdFolder, id);
if ~isfolder(folder), mkdir(folder); end
fid = fopen(fullfile(folder, p.codeFileName), 'w');
fprintf(fid, '%s', digits);
fclose(fid);
end

function rm_if_present(folder)
if isfolder(folder), rmdir(folder, 's'); end
end

function delete_if_present(varargin)
for k = 1:nargin
    if isfile(varargin{k}), delete(varargin{k}); end
end
end
