function report = diagnose_audio_corpus(outputFile)
%DIAGNOSE_AUDIO_CORPUS Audit every enrolled recording and rank what to re-record.
%
%   REPORT = DIAGNOSE_AUDIO_CORPUS() judges every WAV under the enrolment folders
%   with ASSESS_RECORDING_QUALITY, writes one row per file to
%   Results/corpus_diagnostics.csv, and prints a re-record list ordered by how
%   badly each student needs it.
%
%   REPORT = DIAGNOSE_AUDIO_CORPUS(OUTPUTFILE) writes elsewhere.
%
%   EEE 312 CO2 (theoretical against experimental), CO5 (ethics: report the corpus
%   as it is, not as it should be).  PO(d) Investigation, PO(k) Project management.
%
%   Why the audit is graded rather than pass/fail
%   --------------------------------------------
%   The audit runs with Strict = false.  These files exist; they cannot be
%   re-recorded by deciding to be stricter about them.  The question worth asking
%   is not "is this recording perfect" but "is it still usable, and if it is
%   imperfect, how urgently should it be replaced".  A recording missing its silent
%   pre-roll is imperfect and usable, because PREPROCESS_TEMPLATE_AUDIO has a
%   fallback path for exactly that case.  A clipped recording is imperfect and
%   irreparable, because the samples that were above full scale are gone.
%
%   The distinction is not academic.  Judged strictly, 51 of the 61 name recordings
%   fail, which sounds like a corpus that cannot be used and is not what the
%   measurements show: EXPERIMENT_VERIFICATION_ACCURACY serves 50 of 56 genuine
%   trials on it, an 89.3 % grant rate.
%   Judged as stored audio, all 61 are usable, 3 are clipped, and 51 lack the silent
%   pre-roll -- one short actionable list and one long advisory one.
%
%   USABLE means what the deployed system means by it
%   ------------------------------------------------
%   A file is usable here iff ENROL_TEMPLATE_FEATURES would enrol it, which is the
%   single decision FIND_BEST_VOICE_MATCH, EXPERIMENT_VERIFICATION_ACCURACY and
%   CALIBRATE_DTW_THRESHOLD all go through.  There is no second definition to drift
%   from, and that is a deliberate repair rather than an original design.
%
%   Two revisions got it wrong in opposite directions.  The first made clipping fatal;
%   this audit then announced that Al Imran Limon had no usable name recording while
%   the accuracy experiment was busy verifying him from both of them.  The second
%   fixed that by defining usable as "the preprocessing chain produced features",
%   which was too weak: VERIFY_DSP_PIPELINE found two coupon files the chain accepted
%   and this audit refused, and the audit was right about both -- one is 0.095 s long
%   where six spoken digits should be, the other sits 5x below the AGC's silence
%   floor.  So the audit's rule became the system's rule, and the six inline copies of
%   the weaker one were deleted.  An audit that contradicts the system it audits is
%   worse than no audit; an audit that IS the system's own decision cannot.
%
%   The re-record priority
%   ---------------------
%   1  No usable recording of a phrase.  The student cannot be verified at all,
%      because VERIFY_MEAL_WORKFLOW needs both phrases to name the same person.
%   2  Clipped.  Usable but permanently distorted, and the distortion lands inside
%      the 300-3700 Hz band the mel filterbank reads.
%   3  Below PARAMS.samplesPerPhrase.  The student has too few templates for the
%      mean-of-distances score in VOICE_MATCH_SCORES to average anything.
%   4  No silent pre-roll.  Usable through the fallback path, worth replacing when
%      the student is being recorded anyway.
%
%   Students are listed worst-first so a recording session with limited time spends
%   it where it changes the measured outcome.
%
%   See also ASSESS_RECORDING_QUALITY, RECORD_CORPUS_TOOL,
%   EXPERIMENT_VERIFICATION_ACCURACY.

p = dsp_parameters();

if nargin < 1 || isempty(outputFile)
    if ~isfolder('Results'), mkdir('Results'); end
    outputFile = fullfile('Results', 'corpus_diagnostics.csv');
end

roots = {p.trainNameFolder, p.trainCouponFolder};
phraseTypes = {'Name', 'Coupon'};

rows = struct('PhraseType',{},'Student',{},'FileName',{},'InputFs',{}, ...
    'InputDuration',{},'PreRollRms',{},'OverallRms',{},'ClippedPercent',{}, ...
    'ClippedRun',{},'Clipped',{},'SpeechDuration',{},'LowBandRatio',{}, ...
    'Usable',{},'WellRecorded',{},'ProblemCount',{},'Verdict',{});

fprintf('\n=== Corpus audit ========================================\n');

for r = 1:numel(roots)
    if ~isfolder(roots{r})
        fprintf('%s folder not found: %s\n', phraseTypes{r}, roots{r});
        continue;
    end
    files = dir(fullfile(roots{r}, '**', '*.wav'));
    for k = 1:numel(files)
        filePath = fullfile(files(k).folder, files(k).name);
        [~, student] = fileparts(files(k).folder);

        row = struct('PhraseType', string(phraseTypes{r}), 'Student', string(student), ...
            'FileName', string(files(k).name), 'InputFs', NaN, 'InputDuration', NaN, ...
            'PreRollRms', NaN, 'OverallRms', NaN, 'ClippedPercent', NaN, ...
            'ClippedRun', NaN, 'Clipped', false, 'SpeechDuration', NaN, ...
            'LowBandRatio', NaN, 'Usable', false, 'WellRecorded', false, ...
            'ProblemCount', 1, 'Verdict', "");

        try
            [x, fs] = audioread(filePath);
            row.InputFs = fs;
            row.InputDuration = size(x,1) / fs;

            % Strict = false: see the header. These files are what they are.
            dg = assess_recording_quality(x, fs, p, struct('Strict', false));

            row.PreRollRms     = dg.PreRollRms;
            row.OverallRms     = dg.OverallRms;
            row.ClippedPercent = 100 * dg.ClippedFraction;
            row.ClippedRun     = dg.ClippedRun;
            row.Clipped        = dg.Clipped;
            row.SpeechDuration = dg.SpeechDuration;
            row.LowBandRatio   = dg.LowBandRatio;
            row.Usable         = dg.Usable;
            row.WellRecorded   = dg.WellRecorded;
            row.ProblemCount   = numel(dg.Problems);
            row.Verdict        = string(dg.Reason);
        catch err
            row.Verdict = "unreadable: " + string(err.message);
        end
        rows(end+1) = row;   %#ok<AGROW> one row per WAV; the corpus is ~123 files.
    end
end

if isempty(rows)
    error('diagnose_audio_corpus:noAudio', ...
        'No WAV files found under %s or %s.', roots{1}, roots{2});
end

report = struct2table(rows);
writetable(report, outputFile);

print_summary(report, p);
print_unverifiable(report, p);
print_rerecord_list(report, p);

fprintf('Per-file detail written to %s (%d rows).\n', outputFile, height(report));
fprintf('=========================================================\n\n');
end

% =========================================================================
function print_summary(T, p)
fprintf('\nFiles by phrase\n');
for phrase = ["Name","Coupon"]
    S = T(T.PhraseType == phrase, :);
    if isempty(S), continue; end
    fprintf('  %-6s n = %3d | usable %3d | recorded cleanly %3d | clipped %2d | no pre-roll %2d\n', ...
        phrase, height(S), sum(S.Usable), sum(S.WellRecorded), ...
        sum(S.Clipped), sum(S.PreRollRms >= 0.02));
end

fprintf('\nWhat the numbers mean\n');
fprintf('  usable      : ENROL_TEMPLATE_FEATURES enrols this file, so the deployed\n');
fprintf('                matcher and every experiment load it. One shared decision.\n');
fprintf('  clipped     : a flat run of >= 10 samples, or > 0.1 %% of samples pinned at\n');
fprintf('                full scale. Usable but unrecoverable -- AGC moves the flat\n');
fprintf('                tops and restores nothing, and the harmonic distortion lands\n');
fprintf('                in the %g-%g Hz mel band.\n', p.R(1), p.R(2));
fprintf('  no pre-roll : the first %.2f s is not silent, so modification 3 profiles\n', ...
    p.noise.NoiseDuration);
fprintf('                the noise over speech. Usable through the fallback path.\n');

% Sample rates: the corpus is uniform now, and a mixed-rate corpus would silently
% change the resampling ratio per file, so it is worth saying out loud.
uniqueFs = unique(T.InputFs(~isnan(T.InputFs)));
if isscalar(uniqueFs)
    fprintf('\nAll files sampled at %g Hz -> %g Hz for processing.\n', uniqueFs, p.processingFs);
else
    fprintf('\nMIXED SAMPLE RATES in the corpus: %s Hz.\n', ...
        strjoin(compose('%g', uniqueFs(:)'), ', '));
end

dur = T.InputDuration(~isnan(T.InputDuration));
fprintf('Durations %.3f-%.3f s (capture length is %g s).\n', min(dur), max(dur), p.recordDur);
short = sum(dur < p.noise.NoiseDuration + p.liveness.MinDuration);
if short > 0
    fprintf('  %d file(s) are shorter than pre-roll + minimum speech (%.2f s), so they\n', ...
        short, p.noise.NoiseDuration + p.liveness.MinDuration);
    fprintf('  cannot contain both a noise profile and a full phrase.\n');
end
end

% -------------------------------------------------------------------------
function print_unverifiable(T, p)
%PRINT_UNVERIFIABLE Students the system can never admit, whatever the threshold.
%   A student is enrolled on paper the moment code.txt exists. They are verifiable
%   only if BOTH phrases have a usable template, because VERIFY_MEAL_WORKFLOW
%   requires the two spoken phrases to identify the same person. A coupon code with
%   no name recording behind it is an account that cannot be used -- and it fails
%   silently, as a student turned away at the counter rather than as an error.
%
%   Siam Ahmed is that case in the current corpus: Train/Name/Siam Ahmed holds a
%   code.txt and no audio at all.
students = unique(T.Student);
broken = strings(0,1);
detail = strings(0,1);

for i = 1:numel(students)
    S = T(T.Student == students(i), :);
    haveName   = sum(S.Usable & S.PhraseType == "Name");
    haveCoupon = sum(S.Usable & S.PhraseType == "Coupon");
    if haveName >= 1 && haveCoupon >= 1, continue; end

    codePath = fullfile(p.trainNameFolder, char(students(i)), p.codeFileName);
    if haveName == 0 && haveCoupon == 0
        why = "no usable recording of either phrase";
    elseif haveName == 0
        why = "no usable NAME recording";
    else
        why = "no usable COUPON recording";
    end
    if isfile(codePath)
        why = why + ", but a coupon code is on file";
    end
    broken(end+1) = students(i);   %#ok<AGROW> at most one entry per student.
    detail(end+1) = why;           %#ok<AGROW>
end

if isempty(broken)
    return;
end

fprintf('\nEnrolled but UNVERIFIABLE -- these students cannot be admitted at all\n');
for i = 1:numel(broken)
    fprintf('  %-24s %s\n', broken(i), detail(i));
end
fprintf('  VERIFY_MEAL_WORKFLOW needs both phrases to name the same person, so one\n');
fprintf('  missing phrase is a refusal at every threshold. No calibration fixes it.\n');
end

% -------------------------------------------------------------------------
function print_rerecord_list(T, p)
%PRINT_RERECORD_LIST Rank students by how much a retake would change the result.
students = unique(T.Student);
n = numel(students);
score = zeros(n,1);
notes = strings(n,1);

for i = 1:n
    S = T(T.Student == students(i), :);
    reasons = strings(0,1);
    s = 0;

    for phrase = ["Name","Coupon"]
        P = S(S.PhraseType == phrase, :);
        usable = sum(P.Usable);
        if isempty(P)
            s = s + 100;
            reasons(end+1) = phrase + ": no recordings";   %#ok<AGROW> few per student.
        elseif usable == 0
            s = s + 100;
            reasons(end+1) = phrase + ": no usable recording";   %#ok<AGROW>
        elseif usable < 2
            % One usable template means no leave-one-out trial is possible for this
            % student, so they contribute nothing to the accuracy measurement.
            s = s + 50;
            reasons(end+1) = phrase + sprintf(": only %d usable", usable);   %#ok<AGROW>
        elseif usable < p.samplesPerPhrase
            s = s + 10;
            reasons(end+1) = phrase + sprintf(": %d of %d templates", usable, p.samplesPerPhrase);   %#ok<AGROW>
        end
        nClipped = sum(P.Clipped);
        if nClipped > 0
            s = s + 25 * nClipped;
            reasons(end+1) = phrase + sprintf(": %d clipped", nClipped);   %#ok<AGROW>
        end
    end

    nNoPreRoll = sum(S.PreRollRms >= 0.02);
    if nNoPreRoll > 0
        s = s + nNoPreRoll;
        reasons(end+1) = sprintf("%d file(s) without a silent pre-roll", nNoPreRoll);   %#ok<AGROW>
    end

    score(i) = s;
    notes(i) = strjoin(reasons, '; ');
end

[score, order] = sort(score, 'descend');
students = students(order);
notes = notes(order);

fprintf('\nRe-record priority (worst first)\n');
if all(score == 0)
    fprintf('  Nothing to re-record: every student has %d clean templates per phrase.\n', ...
        p.samplesPerPhrase);
    return;
end
shown = 0;
for i = 1:numel(students)
    if score(i) == 0, continue; end
    fprintf('  %3d  %-24s %s\n', score(i), students(i), notes(i));
    shown = shown + 1;
end
fprintf('\n  %d of %d students would benefit from a retake. Run:\n', shown, numel(students));
fprintf('    record_corpus_tool(''Student'', ''<name>'', ''Mode'', ''enrol'')\n');
fprintf('  then FIND_BEST_VOICE_MATCH(''reset'') so the template cache reloads.\n');
end
