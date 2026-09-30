function ok = verify_coupon_registry_gate(verbose)
%VERIFY_COUPON_REGISTRY_GATE Focused regression for VERIFY_MEAL_WORKFLOW gate 5.
%
%   The admin-assigned monthly coupon registry is the SINGLE source of truth for
%   the fee/coupon gate: a typed code is validated only against that registry
%   (CONSUME_MONTHLY_COUPON, invoked by MONTHLY_FEE_ENTITLEMENT(...,'record')),
%   never against a static Train/ID/<id>/code.txt.  This file proves that on the
%   voice path.
%
%   Why this test exists
%   --------------------
%   VERIFY_DSP_PIPELINE's own workflow section SKIPS in this corpus -- only one
%   student (2206147) has Train/Coupon recordings, and its LOAD_TWO_STUDENTS needs
%   two enrollable students -- so VERIFY_MEAL_WORKFLOW's gate 5 is otherwise
%   unexercised here.  VERIFY_STUDENT_ID_WORKFLOW covers MANUAL_ENTRY_WORKFLOW's
%   gate 5; this covers the voice workflow's, with the one coupon-enrolled student.
%
%   Why identity is injected through IDFeatures, not NameFeatures
%   ------------------------------------------------------------
%   The first identification attempt matches the injected features against
%   Train/ID.  In this two-ID corpus the Name-phrase features of 2206147 land on
%   the WRONG student (2206148) below the runner-up margin, so feeding NameFeatures
%   refuses at 'match-id' and never reaches gate 5.  Feeding the student's own
%   Train/ID template (IDFeatures, the intended first-attempt test hook) resolves
%   confidently to 2206147, so every case below reaches the coupon gate the way a
%   real counter transaction does.  CouponFeatures are the student's own Train/Coupon
%   template so the cross-phrase agreement and coupon-distance sub-gates pass.
%
%   See also VERIFY_MEAL_WORKFLOW, MONTHLY_COUPON_REGISTRY, ASSIGN_MONTHLY_COUPON,
%   MONTHLY_FEE_ENTITLEMENT, VERIFY_DSP_PIPELINE.
if nargin < 1, verbose = true; end

p = dsp_parameters();
id = '2206147';

% Features exactly as VERIFY_DSP_PIPELINE enrols them (ENROL_TEMPLATE_FEATURES on
% the first enrollable take), so this trace is driven by files the deployed matcher
% would also load.
idFeat     = first_template(fullfile(p.trainIdFolder, id), p);
couponFeat = first_template(fullfile(p.trainNameFolder, id), p);
assert(~isempty(idFeat), 'no enrollable ID template for %s; corpus is incomplete', id);
assert(~isempty(couponFeat), 'no enrollable coupon template for %s; corpus is incomplete', id);

% A serving instant inside the Lunch window, built as VERIFY_DSP_PIPELINE does.
lunch = datetime(2026,3,5) + minutes(p.meals(2).Start(1)*60 + p.meals(2).Start(2) + 30);

goodCode  = '654321';  % 6 digits, assigned in the registry below.
wrongCode = '000000';  % 6 digits, well-formed, NOT assigned -> registry rejects.
malformed = '12ab';    % not 6 digits -> format check rejects.

% --- Case A: a registry-valid code is GRANTED -----------------------------
%   The grant comes from the registry alone (ASSIGN_MONTHLY_COUPON). There is no
%   code.txt holding this code on disk -- Train/ID/2206147/code.txt holds 123456,
%   not 654321 -- so a pass here is proof the static file no longer gates anything.
grantedA = run_gate(p, id, idFeat, couponFeat, goodCode, goodCode, lunch, false);
assert(grantedA.Granted, ...
    'a registry-valid coupon was refused at the %s gate: %s', grantedA.Stage, grantedA.Reason);
assert(strcmp(grantedA.Student, id), ...
    'gate 5 granted the wrong student: %s instead of %s', grantedA.Student, id);
assert(grantedA.MonthlyPaid, 'a granted transaction did not record the monthly payment');
assert(grantedA.Logged && strcmp(grantedA.Meal, p.meals(2).Name), ...
    'the served meal was recorded as "%s", expected %s', grantedA.Meal, p.meals(2).Name);

% --- Case B: a well-formed but unassigned code is REFUSED at 'code' --------
%   000000 is 6 digits, so it passes the format check and is rejected only by the
%   registry (CONSUME_MONTHLY_COUPON). The stage must be 'code', not 'entitlement':
%   the registry mismatch is a coupon failure, not a closed-hours failure.
wrongB = run_gate(p, id, idFeat, couponFeat, goodCode, wrongCode, lunch, true);
assert(~wrongB.Granted && strcmp(wrongB.Stage, 'code'), ...
    'a registry-invalid coupon was refused at the %s gate, expected code', wrongB.Stage);
assert(strcmp(wrongB.Student, id), ...
    'the wrong-code transaction lost the identification it had already made');

% --- Case C: a malformed code is REFUSED at 'code' ------------------------
%   12ab fails the 6-digit format check before the registry is consulted.
malformedC = run_gate(p, id, idFeat, couponFeat, goodCode, malformed, lunch, true);
assert(~malformedC.Granted && strcmp(malformedC.Stage, 'code'), ...
    'a malformed coupon reached the %s gate, expected code', malformedC.Stage);

ok = true;
if verbose
    fprintf('VERIFY_COUPON_REGISTRY_GATE: all checks passed.\n');
    fprintf('  ok  registry-valid %s granted for %s and logged as %s (no matching code.txt)\n', ...
        goodCode, id, grantedA.Meal);
    fprintf('  ok  registry-invalid %s refused at stage ''code''\n', wrongCode);
    fprintf('  ok  malformed %s refused at stage ''code''\n', malformed);
end
end

% -------------------------------------------------------------------------
function result = run_gate(p, id, idFeat, couponFeat, assignCode, typedCode, nowValue, skipLogging)
%RUN_GATE One gate-5 transaction against fresh, isolated registry/entitlement/log
%   files, with identity injected via IDFeatures so it resolves confidently to ID.
q = p;
q.monthlyEntitlementFile = [tempname '.csv'];
q.monthlyCouponFile      = [tempname '.csv'];
q.logFile                = [tempname '.csv'];
q.verificationLogFile    = [tempname '.csv'];
% Deleted when this object goes out of scope, including on an assertion failure.
cleanup = onCleanup(@() delete_if_present(q.logFile, q.monthlyEntitlementFile, q.monthlyCouponFile, q.verificationLogFile)); %#ok<NASGU>

% The admin assigns the month's coupon; the registry is the only source of truth.
[assigned, msg] = assign_monthly_coupon(id, assignCode, q, nowValue);
assert(assigned, 'test admin could not assign coupon %s: %s', assignCode, msg);

find_best_voice_match('reset');
options = struct('NowValue', nowValue, 'ClaimedID', id, 'IDFeatures', idFeat, ...
    'NameFeatures', couponFeat, 'SkipLogging', false);
result = verify_meal_workflow([], typedCode, q, options);
end

function f = first_template(folder, p)
%FIRST_TEMPLATE Features from the first enrollable WAV in FOLDER, or [].
%   Through ENROL_TEMPLATE_FEATURES so the file chosen is one the deployed matcher
%   would also have loaded (same helper as VERIFY_DSP_PIPELINE).
f = [];
files = dir(fullfile(folder, '*.wav'));
for k = 1:numel(files)
    f = enrol_template_features(fullfile(files(k).folder, files(k).name), [], p);
    if ~isempty(f)
        return;
    end
end
end

function delete_if_present(varargin)
for k = 1:nargin
    if isfile(varargin{k}), delete(varargin{k}); end
end
end
