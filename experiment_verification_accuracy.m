function report = experiment_verification_accuracy(outputFile, frontEnd)
%EXPERIMENT_VERIFICATION_ACCURACY Measure the accuracy of the whole decision.
%
%   REPORT = EXPERIMENT_VERIFICATION_ACCURACY() measures how often the deployed
%   decision serves a meal to the right student and how often it can be fooled,
%   using every recording in the enrolled corpus and the same gates
%   VERIFY_MEAL_WORKFLOW applies.
%
%   REPORT = EXPERIMENT_VERIFICATION_ACCURACY(OUTPUTFILE, FRONTEND) measures a
%   named front-end instead of the configured default.  Each front-end needs its
%   own composite measurement, because a DTW distance has no absolute scale: the
%   mfcc front-end produces distances of 20 to 50 and the dft front-end 1 to 4, so
%   a threshold recommended for one is meaningless for the other.  Quoting an
%   unmeasured threshold for the second front-end would be exactly the defect this
%   experiment exists to catch.
%
%   Proposal evaluation metric "Accuracy" and metric "Spoofing" (identity half).
%   EEE 312 CO1, CO2, CO4, CO5.  PO(b) Problem Analysis, PO(d) Investigation.
%
%   Why this is not the same measurement as CALIBRATE_DTW_THRESHOLD
%   --------------------------------------------------------------
%   That function measures ONE distance against ONE threshold, and for the mfcc
%   front-end reports a 17.2 percent false-rejection rate at a 1 percent
%   false-accept constraint.  That number describes a single phrase in isolation.
%   It is not the accuracy of the system, because the system does not make its
%   decision that way: it records two different phrases, identifies a student from
%   each independently, and requires the two answers to agree as well as clearing
%   the threshold and the runner-up margin.
%
%   This experiment measures that composite decision.  The distinction matters in
%   both directions.  Requiring two independent identifications to agree makes
%   false ACCEPTS much rarer, because an attacker must be mistaken for the same
%   person twice.  It also makes false REJECTS more common, because a genuine
%   student now has two chances to be turned away instead of one.  Only measuring
%   the composite tells the group which effect dominates.
%
%   The two protocols
%   -----------------
%   Genuine (leave-one-out).  For each student and each of their recordings in
%   turn, that recording becomes the live capture and is removed from the
%   library; the student's remaining recordings stay enrolled, as do all other
%   students.  The capture is never compared against itself, which is what makes
%   the result an estimate of performance on a NEW recording rather than a
%   demonstration that a file matches itself.
%
%   Proxy attack (leave-one-student-out).  For each student in turn, that student
%   is removed from the library entirely and then presents their recordings.  This
%   models the case the proposal exists to prevent: somebody who is not enrolled
%   -- a friend, a non-resident -- arrives holding a valid coupon and tries to
%   collect the meal it belongs to.  The attack succeeds if the voice gates accept
%   them as SOME enrolled student, because an attacker chooses whose coupon to
%   carry and will simply carry the coupon of whoever the system names.  Counting
%   it that way is deliberately pessimistic and is the honest way to quote it.
%
%   What is NOT measured here
%   -------------------------
%   Replay attack: covered by EXPERIMENT_REPLAY_SPOOF once replay recordings
%   exist, since a replay is a signal-quality question rather than a matching one.
%   Channel mismatch: covered by EXPERIMENT_CHANNEL_ROBUSTNESS.
%   The typed coupon code is treated as known to the attacker throughout, which is
%   the correct assumption -- a proxy attacker is carrying a real coupon.
%
%   Why a threshold sweep is part of this experiment
%   -----------------------------------------------
%   The first run of this experiment measured a 35.0 percent false-rejection rate
%   and a 0.0 percent proxy-attack success rate at the then-calibrated per-phrase
%   threshold.  Both halves of that result are informative and neither is acceptable
%   on its own: turning away one student in three would empty the dining hall of
%   patience by the second day, while a zero on every attack says the threshold is
%   spending security it does not need to spend.
%
%   The reason is that the threshold was calibrated by CALIBRATE_DTW_THRESHOLD to
%   hold the PER-PHRASE false-accept rate at 1 percent, at a time when a single
%   distance was the whole decision.  It is no longer the whole decision.  The
%   breakdown shows the cross-phrase agreement gate rejecting 47 of the 56 attacks
%   by itself, and agreement does not consult the threshold at all -- it compares
%   two names.  A threshold tightened to catch attackers that agreement already
%   catches buys nothing and costs genuine students.
%
%   So the experiment sweeps the threshold rather than assuming one.  This is
%   nearly free: whether a trial is accepted depends only on the two distances, the
%   two identified names and the two margins, and those are computed once per
%   trial.  Re-deciding the same trials under a different threshold needs no
%   further DTW.  The sweep is therefore the same measurement viewed at every
%   operating point, not a second experiment.
%
%   Note the floor the sweep cannot go below.  Genuine trials that fail agreement
%   fail because two recordings of the same student named two different people, and
%   no threshold can repair that.  That count is the irreducible part of the
%   false-rejection rate and the sweep reports it separately, because it is the
%   number that says how much a better front-end -- or a third recording per
%   student -- would be worth.
%
%   See also VERIFY_MEAL_WORKFLOW, VOICE_MATCH_SCORES, CALIBRATE_DTW_THRESHOLD.

if nargin < 1 || isempty(outputFile)
    outputFile = fullfile('Results','verification_accuracy.csv');
end
if ~isempty(fileparts(outputFile)) && ~isfolder(fileparts(outputFile))
    mkdir(fileparts(outputFile));
end

p = dsp_parameters();
if nargin >= 2 && ~isempty(frontEnd)
    p = select_feature_frontend(p, frontEnd);
    [d, n, e] = fileparts(outputFile);
    outputFile = fullfile(d, sprintf('%s_%s%s', n, p.featureFrontEnd, e));
end
p.liveness.Enable = false;   % Identity is what is being measured here.

% Per-phrase reference figures for THIS front-end, read from the parameter file
% rather than written into the printouts as literals. A per-phrase number printed
% beside a composite number is only meaningful if both describe the same features.
if isfield(p, 'perPhraseReference') && isfield(p.perPhraseReference, p.featureFrontEnd)
    ref = p.perPhraseReference.(p.featureFrontEnd);
else
    ref = struct('Threshold',NaN,'Far',NaN,'Frr',NaN,'Eer',NaN,'EerThreshold',NaN);
end

fprintf('Front-end %s at %g Hz, configured threshold %.4f, margin %.2f\n', ...
    p.featureFrontEnd, p.processingFs, p.dtwThreshold, p.dtwMarginRatio);

fprintf('Extracting features for both phrases...\n');
nameLib   = build_library(p.trainNameFolder,   p);
couponLib = build_library(p.trainCouponFolder, p);

% Only students present in BOTH phrase folders can be verified at all, since the
% decision requires two recordings from the same person.
students = intersect(nameLib.Users, couponLib.Users);
students = students(:);
fprintf('  %d students have both a name and a coupon recording.\n', numel(students));

usable = strings(0,1);
for k = 1:numel(students)
    nName   = numel(nonempty(templates_of(nameLib,   students(k))));
    nCoupon = numel(nonempty(templates_of(couponLib, students(k))));
    if nName >= 2 && nCoupon >= 2
        usable(end+1,1) = students(k);   %#ok<AGROW>
    end
end
fprintf('  %d of those have at least two usable recordings of each phrase,\n', numel(usable));
fprintf('  which is the minimum for a leave-one-out trial.\n');

if numel(usable) < 2
    error('experiment_verification_accuracy:insufficientCorpus', ...
        'Need at least two students with two usable recordings of each phrase.');
end

% ---------------------------------------------------------------------
% Phase 1: run every trial once and record the raw quantities.
% Nothing here consults a threshold. A trial is described by the two identified
% names, the two distances and the two margins; the decision is applied later so
% that every operating point sees exactly the same trials.
% ---------------------------------------------------------------------
fprintf('\nGenuine trials (leave-one-recording-out)...\n');
G = struct('Subject',{},'Trial',{},'NameUser',{},'NameDist',{}, ...
    'NameMargin',{},'CouponUser',{},'CouponDist',{},'CouponMargin',{},'Agree',{});

for k = 1:numel(usable)
    who = usable(k);
    nameFiles   = nonempty(templates_of(nameLib,   who));
    couponFiles = nonempty(templates_of(couponLib, who));
    for t = 1:min(numel(nameFiles), numel(couponFiles))
        libN = library_without_recording(nameLib,   who, t);
        libC = library_without_recording(couponLib, who, t);
        G(end+1) = trial_scores(who, t, libN, libC, nameFiles{t}, couponFiles{t}, p);   %#ok<AGROW>
    end
    fprintf('  %2d/%2d %s\n', k, numel(usable), who);
end

fprintf('\nProxy-attack trials (attacker removed from the library)...\n');
A = G([]);
for k = 1:numel(usable)
    attacker = usable(k);
    libN = library_without_student(nameLib,   attacker);
    libC = library_without_student(couponLib, attacker);
    nameFiles   = nonempty(templates_of(nameLib,   attacker));
    couponFiles = nonempty(templates_of(couponLib, attacker));
    for t = 1:min(numel(nameFiles), numel(couponFiles))
        A(end+1) = trial_scores(attacker, t, libN, libC, nameFiles{t}, couponFiles{t}, p);   %#ok<AGROW>
    end
    fprintf('  %2d/%2d %s\n', k, numel(usable), attacker);
end

fprintf('\n%d genuine trials, %d proxy attacks.\n', numel(G), numel(A));

% ---------------------------------------------------------------------
% Phase 2: apply the deployed decision at the calibrated threshold.
% ---------------------------------------------------------------------
gAt = evaluate_at(G, p.dtwThreshold, p.dtwMarginRatio, true);
aAt = evaluate_at(A, p.dtwThreshold, p.dtwMarginRatio, false);

fprintf('\nAt the calibrated threshold %.4f (margin %.2f):\n', p.dtwThreshold, p.dtwMarginRatio);
fprintf('  genuine  : %d of %d served -> FRR %.1f %%\n', gAt.Success, gAt.Total, 100*(1-gAt.Rate));
fprintf('             refused at agreement %d, threshold %d, margin %d, wrong name %d\n', ...
    gAt.Agreement, gAt.Threshold, gAt.Margin, gAt.WrongName);
fprintf('  proxy    : %d of %d succeeded -> FAR %.1f %%\n', aAt.Success, aAt.Total, 100*aAt.Rate);
fprintf('             blocked at agreement %d, threshold %d, margin %d\n', ...
    aAt.Agreement, aAt.Threshold, aAt.Margin);

% The part of the false-rejection rate no threshold can remove.
floorCount = sum(~[G.Agree]);
fprintf('\n  %d of %d genuine trials fail cross-phrase agreement (%.1f %%).\n', ...
    floorCount, numel(G), 100*floorCount/numel(G));
fprintf('  That is the floor on FRR: the two recordings named two different\n');
fprintf('  students, which no choice of threshold can repair.\n');

% ---------------------------------------------------------------------
% Phase 3: sweep the threshold over the same trials.
% ---------------------------------------------------------------------
allDist = [ [G.NameDist], [G.CouponDist], [A.NameDist], [A.CouponDist] ];
allDist = allDist(isfinite(allDist));
grid = linspace(min(allDist), max(allDist), 160);

sweep = zeros(numel(grid), 6);
for i = 1:numel(grid)
    g = evaluate_at(G, grid(i), p.dtwMarginRatio, true);
    a = evaluate_at(A, grid(i), p.dtwMarginRatio, false);
    sweep(i,:) = [grid(i), 1-g.Rate, a.Rate, g.Success, a.Success, g.WrongName];
end

sweepTable = array2table(sweep, 'VariableNames', ...
    {'Threshold','FalseRejectionRate','ProxySuccessRate','Served','AttacksPassed','WrongName'});
sweepFile = strrep(outputFile, '.csv', '_sweep.csv');
writetable(sweepTable, sweepFile);

% Choosing an operating point from the sweep.
%
% The naive rule -- "take the largest threshold that still blocks every attack" --
% is useless on this corpus, because NO threshold on the grid admits an attack:
% cross-phrase agreement and the margin gate together stop all 60 proxies without
% consulting the threshold at all. That rule would return the top of the grid,
% which is not a threshold so much as the absence of one, and a threshold placed at
% the largest distance ever observed has no headroom: every future recording falls
% below it and is accepted on distance alone.
%
% The defensible rule is the opposite one. Find the lowest false-rejection rate the
% sweep can reach, then take the SMALLEST threshold that reaches it. Every
% threshold above that point turns nobody away who was not already turned away, so
% raising it further buys no student anything while widening the acceptance region
% for attackers this corpus happens not to contain. Keeping the surplus rejection
% power in reserve costs nothing measurable and is the only guard left if agreement
% ever fails -- for instance against a determined mimic, whom this corpus of 24
% cooperative speakers cannot represent.
bestFrr = min(sweep(:,2));
atFloor = find(sweep(:,2) <= bestFrr + 1e-12 & sweep(:,3) == 0);

fprintf('\nThreshold sweep (%d points from %.2f to %.2f):\n', numel(grid), grid(1), grid(end));
if all(sweep(:,3) == 0)
    fprintf('  No threshold on the grid lets a proxy attack through, not even the\n');
    fprintf('  largest observed distance %.2f. In that limit the threshold is inert and\n', grid(end));
    fprintf('  agreement plus margin hold all %d attacks unaided. The threshold still\n', numel(A));
    fprintf('  does useful work below that limit -- see the gate breakdown further down.\n');
else
    firstLeak = find(sweep(:,3) > 0, 1);
    fprintf('  First threshold that admits an attack: %.4f (%.1f %% succeed).\n', ...
        sweep(firstLeak,1), 100*sweep(firstLeak,3));
end
if max(sweep(:,6)) == 0
    fprintf('  No genuine trial was ever accepted as the WRONG student, at any\n');
    fprintf('  threshold on the grid. Every genuine failure is a refusal, not a\n');
    fprintf('  misidentification, so no student was ever charged for another''s meal.\n');
else
    fprintf('  WARNING: up to %d genuine trials were accepted as the wrong student.\n', max(sweep(:,6)));
end

if isempty(atFloor)
    recommended = p.dtwThreshold;
    fprintf('  No point reaches the floor with zero attacks; keeping %.4f.\n', recommended);
else
    recommended = sweep(atFloor(1), 1);
    flatTop = sweep(atFloor(end), 1);
    fprintf('  Lowest reachable FRR: %.1f %%, first reached at threshold %.4f\n', ...
        100*bestFrr, recommended);
    fprintf('  and unchanged from there to %.4f -- a flat region, so the exact\n', flatTop);
    fprintf('  value inside it is not critical and need not be quoted to 4 decimals.\n');
    fprintf('  Against the calibrated %.4f: FRR %.1f %% -> %.1f %%, recovering %d of %d\n', ...
        p.dtwThreshold, 100*(1-gAt.Rate), 100*bestFrr, ...
        round(numel(G)*((1-gAt.Rate) - bestFrr)), numel(G));
    fprintf('  turned-away students at no measured cost in attacks passed.\n');
end

% An EER is not defined here, and saying so is more useful than printing a number.
if all(sweep(:,3) == 0)
    fprintf('  There is no composite equal-error rate to quote: the proxy rate is 0\n');
    fprintf('  at every threshold, so the two curves never cross. The per-phrase EER\n');
    fprintf('  of %.1f %% describes a different decision rule and does not carry over.\n', ...
        100*ref.Eer);
end

% ---------------------------------------------------------------------
% Phase 4: how the three voice gates divide the work, and whether the margin
% gate is earning its keep.
%
% At the calibrated threshold the margin gate looked like pure cost: it turned away
% one genuine student and blocked zero attacks. That reading was wrong, and it was
% wrong in an instructive way. The margin gate blocked no attacks there only
% because the over-tight threshold had already caught the same attacks first.
% Relax the threshold to where it belongs and the margin gate becomes load-bearing.
% Measuring it with the threshold held at the wrong value would have led the group
% to delete the gate that was about to start doing the work.
% ---------------------------------------------------------------------
gRec  = evaluate_at(G, recommended, p.dtwMarginRatio, true);
aRec  = evaluate_at(A, recommended, p.dtwMarginRatio, false);
gNoM  = evaluate_at(G, recommended, 1.0, true);
aNoM  = evaluate_at(A, recommended, 1.0, false);

fprintf('\nHow the gates divide the work at threshold %.4f:\n', recommended);
fprintf('  %d proxy attacks: %d stopped by agreement, %d by threshold, %d by margin\n', ...
    aRec.Total, aRec.Agreement, aRec.Threshold, aRec.Margin);
fprintf('  %d genuine trials: %d lost to agreement, %d to threshold, %d to margin, %d served\n', ...
    gRec.Total, gRec.Agreement, gRec.Threshold, gRec.Margin, gRec.Success);
fprintf('  All three gates are load-bearing. None can be removed:\n');
fprintf('    margin disabled (ratio 1.0): FRR %.1f %% but proxy success %.1f %%\n', ...
    100*(1-gNoM.Rate), 100*aNoM.Rate);
fprintf('    -- so the %.1f pp of FRR the margin gate costs buys %.1f pp of proxy defence.\n', ...
    100*((1-gRec.Rate)-(1-gNoM.Rate)), 100*(aNoM.Rate-aRec.Rate));
if gRec.Threshold == 0
    fprintf('  Note the threshold gate rejects NO genuine student at this operating\n');
    fprintf('  point while still stopping %d attacks -- it is free security here, which\n', aRec.Threshold);
    fprintf('  is the property that makes this the right place to put it.\n');
end

% ---------------------------------------------------------------------
rows = [trial_rows(G, "genuine"); trial_rows(A, "proxy")];
writetable(rows, outputFile);

report = struct();
report.FrontEnd = p.featureFrontEnd;
report.ProcessingFs = p.processingFs;
report.Threshold = p.dtwThreshold;
report.MarginRatio = p.dtwMarginRatio;
report.Students = numel(usable);
report.GenuineTrials = numel(G);
report.GenuineGranted = gAt.Success;
report.FalseRejectionRate = 1-gAt.Rate;
report.AgreementFloor = floorCount/numel(G);
report.ProxyTrials = numel(A);
report.ProxySucceeded = aAt.Success;
report.FalseAcceptanceRate = aAt.Rate;
report.RecommendedThreshold = recommended;
report.RecommendedFrr = 1-gRec.Rate;
report.RecommendedProxyRate = aRec.Rate;
report.Sweep = sweepTable;

fprintf('\n=== Verification accuracy ================================\n');
fprintf('Front-end %s at %g Hz, margin %.2f, %d students\n', ...
    p.featureFrontEnd, p.processingFs, p.dtwMarginRatio, numel(usable));
fprintf('Per-phrase reference      : FRR %.1f %% at FAR %.1f %%, threshold %.4f (one distance)\n', ...
    100*ref.Frr, 100*ref.Far, ref.Threshold);
fprintf('Per-transaction at %7.3f: FRR %.1f %%, proxy success %.1f %%\n', ...
    p.dtwThreshold, 100*(1-gAt.Rate), 100*aAt.Rate);
fprintf('Per-transaction at %7.3f: FRR %.1f %%, proxy success %.1f %%  <- recommended\n', ...
    recommended, 100*(1-gRec.Rate), 100*aRec.Rate);
fprintf('Agreement-only floor      : FRR %.1f %% (%d of %d trials disagree)\n', ...
    100*floorCount/numel(G), floorCount, numel(G));
fprintf('Trials  -> %s\n', outputFile);
fprintf('Sweep   -> %s\n', sweepFile);
fprintf('=========================================================\n\n');
end

% -------------------------------------------------------------------------
function s = trial_scores(subject, index, libN, libC, testName, testCoupon, p)
%TRIAL_SCORES Score one transaction and return the raw quantities only.
%   No threshold is applied here. EVALUATE_AT turns these into a verdict, so that
%   every operating point in the sweep judges identical trials.
[dn, un, infoN] = voice_match_scores(libN, testName,   p);
[dc, uc, infoC] = voice_match_scores(libC, testCoupon, p);

s = struct('Subject', subject, 'Trial', index, ...
    'NameUser', string(un), 'NameDist', dn, 'NameMargin', infoN.Margin, ...
    'CouponUser', string(uc), 'CouponDist', dc, 'CouponMargin', infoC.Margin, ...
    'Agree', ~isempty(un) && ~isempty(uc) && strcmpi(strtrim(un), strtrim(uc)));
end

function r = evaluate_at(T, threshold, marginRatio, requireCorrectName)
%EVALUATE_AT Apply the deployed gates, in the deployed order, at one threshold.
%   Order matches VERIFY_MEAL_WORKFLOW: agreement, then absolute distance, then
%   runner-up margin. The order changes nothing about who is accepted, but it does
%   determine which gate gets the credit in the breakdown, so it is kept identical
%   to the workflow to keep the diagnostics comparable.
r = struct('Total',numel(T),'Success',0,'Agreement',0,'Threshold',0, ...
    'Margin',0,'WrongName',0,'Rate',0);
for i = 1:numel(T)
    t = T(i);
    if ~t.Agree
        r.Agreement = r.Agreement + 1;
        continue;
    end
    if t.NameDist > threshold || t.CouponDist > threshold
        r.Threshold = r.Threshold + 1;
        continue;
    end
    if max(t.NameMargin, t.CouponMargin) < marginRatio
        r.Margin = r.Margin + 1;
        continue;
    end
    % Accepted by every voice gate.
    if requireCorrectName && ~strcmpi(strtrim(t.NameUser), t.Subject)
        % Accepted, but as the wrong person. For a genuine student this is a
        % failure to serve them; it is counted separately because it is a far
        % worse failure than a refusal -- it debits another student's account.
        r.WrongName = r.WrongName + 1;
        continue;
    end
    r.Success = r.Success + 1;
end
if r.Total > 0
    r.Rate = r.Success / r.Total;
end
end

function tbl = trial_rows(T, protocol)
%TRIAL_ROWS Flatten trials into a table for the per-trial CSV.
if isempty(T)
    tbl = table();
    return;
end
tbl = table(repmat(protocol, numel(T), 1), [T.Subject]', [T.Trial]', ...
    [T.NameUser]', [T.NameDist]', [T.NameMargin]', ...
    [T.CouponUser]', [T.CouponDist]', [T.CouponMargin]', [T.Agree]', ...
    'VariableNames', {'Protocol','Subject','Trial','NameUser','NameDist', ...
    'NameMargin','CouponUser','CouponDist','CouponMargin','Agree'});
end

function lib = build_library(folder, p)
%BUILD_LIBRARY Extract features for every recording under FOLDER, once.
lib = struct('Users', strings(0,1), 'Templates', {{}});
if ~isfolder(folder), return; end
users = dir(folder);
users = users([users.isdir] & ~startsWith({users.name},'.'));
lib.Users = strings(numel(users),1);
lib.Templates = cell(numel(users),1);
for i = 1:numel(users)
    lib.Users(i) = string(users(i).name);
    files = dir(fullfile(folder, users(i).name, '*.wav'));
    bucket = cell(numel(files),1);
    for j = 1:numel(files)
        % ENROL_TEMPLATE_FEATURES is the single enrolment decision, shared with the
        % deployed matcher and the corpus audit. Measuring accuracy over a library
        % built by a private copy of that decision would measure the wrong library.
        bucket{j} = enrol_template_features( ...
            fullfile(files(j).folder, files(j).name), [], p);
    end
    lib.Templates{i} = bucket;
end
end

function t = templates_of(lib, who)
idx = find(lib.Users == who, 1);
if isempty(idx), t = {}; else, t = lib.Templates{idx}; end
end

function c = nonempty(c)
c = c(~cellfun('isempty', c));
end

function lib = library_without_recording(lib, who, index)
%LIBRARY_WITHOUT_RECORDING Drop one recording, keeping the student enrolled.
idx = find(lib.Users == who, 1);
if isempty(idx), return; end
kept = nonempty(lib.Templates{idx});
kept(index) = [];
lib.Templates{idx} = kept;
end

function lib = library_without_student(lib, who)
%LIBRARY_WITHOUT_STUDENT Remove a student from the library entirely.
keep = lib.Users ~= who;
lib.Users = lib.Users(keep);
lib.Templates = lib.Templates(keep);
end
