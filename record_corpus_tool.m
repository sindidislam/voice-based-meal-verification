function report = record_corpus_tool(varargin)
%RECORD_CORPUS_TOOL Record enrolment, test and replay-attack audio to disk.
%
%   RECORD_CORPUS_TOOL() runs an interactive console session that walks the
%   operator through recording one student.  This is the normal way to use it.
%
%   RECORD_CORPUS_TOOL('Student','Abir Siddique','Mode','enrol','Samples',3)
%   records non-interactively, for scripted collection sessions.
%
%   Proposal modification 3 (the 0.5 s noise pre-roll) and the "Spoofing" metric.
%   EEE 312 CO1, CO3, CO5, CO6.  PO(c) Design, PO(i) Individual and team work.
%
%   Why the group needs this tool at all
%   -----------------------------------
%   Three defects in the existing corpus can only be fixed at recording time, and
%   no amount of processing repairs them afterwards.
%
%   1. No silent pre-roll.  Modification 3 profiles the room noise from the first
%      0.5 s of the capture and subtracts it.  Recordings that begin with speech
%      have no noise to profile, so the profile is taken from speech and the
%      subtraction removes part of the talker.  PREPROCESS_TEMPLATE_AUDIO detects
%      this case and takes a different path, but detecting a problem is not the
%      same as not having it.  This tool enforces the pre-roll by starting the
%      recorder, waiting, and only then telling the student to speak.
%
%   2. One device per student.  Every student recorded both of their samples on
%      their own phone in a single sitting.  A matcher trained on that corpus
%      cannot distinguish "this is Abir" from "this is Abir's phone in Abir's
%      room", and EXPERIMENT_CHANNEL_ROBUSTNESS could not settle the question
%      because there is no data in which the two differ.  Recording through one
%      shared microphone is the only fix, and it is a recording-session decision.
%
%   3. Two samples per student.  Two recordings give one leave-one-out trial per
%      student, so EXPERIMENT_VERIFICATION_ACCURACY rests on 60 trials and cannot
%      resolve differences below about 2 percentage points.  It also means each
%      student is represented by a single remaining template at test time, so one
%      unlucky recording is the whole model.  PARAMS.samplesPerPhrase is 3 for
%      this reason.
%
%   The replay mode
%   ---------------
%   MODE 'replay' captures the attack the liveness test exists to detect: a
%   student's recording played back through a phone or laptop loudspeaker into the
%   counter microphone.  Without these recordings the liveness threshold in
%   PARAMS.liveness is calibrated on genuine speech alone, which fixes the false
%   reject rate but says nothing about whether it catches anything.  The
%   band-energy ratios of genuine captures already span 0.00053 to 0.46990 across
%   mixed microphones, so the current bounds are wide, and how much of that range
%   a replay occupies is unmeasured.  Quoting a spoofing figure without this data
%   would be a guess.
%
%   Recordings go to Replay/Name/<Student>/ and Replay/Coupon/<Student>/, never
%   into Train/, because a replay must never become an enrolment template.
%
%   NAME/VALUE OPTIONS
%     'Student'   student folder name.  Prompted for if omitted.
%     'Mode'      'enrol' (into Train/), 'test' (into Test/), 'replay' (Replay/).
%     'Samples'   recordings per phrase.  Default PARAMS.samplesPerPhrase.
%     'Phrases'   which phrases to record: {'name'}, {'coupon'} or both.
%     'Code'      6-digit coupon code to store in code.txt.
%     'Overwrite' true to replace existing files rather than adding numbered ones.
%     'Review'    true (default) to check each take and offer a retry.
%
%   See also RECORD_AUDIO_DSP, PREPROCESS_TEMPLATE_AUDIO, CALIBRATE_LIVENESS_BAND,
%   EXPERIMENT_REPLAY_SPOOF.

p = dsp_parameters();

o = parse_options(varargin, p);
if isempty(o.Student)
    o.Student = strtrim(input('Student name (folder name): ', 's'));
end
if isempty(o.Student)
    error('record_corpus_tool:noStudent', 'A student name is required.');
end

fprintf('\n=========================================================\n');
fprintf(' Recording: %s\n', o.Student);
fprintf(' Mode     : %s   ->  %s\n', o.Mode, describe_destination(o.Mode, p));
fprintf(' Phrases  : %s\n', strjoin(o.Phrases, ', '));
fprintf(' Samples  : %d per phrase\n', o.Samples);
fprintf(' Capture  : %g s at %g Hz, first %.2f s must be SILENT\n', ...
    p.recordDur, p.fs, p.noise.NoiseDuration);
fprintf('=========================================================\n');

if strcmpi(o.Mode, 'replay')
    fprintf('\nREPLAY ATTACK CAPTURE. You are recording a loudspeaker, not a person.\n');
    fprintf('Play the student''s existing recording on a phone or laptop and hold it\n');
    fprintf('at the distance an attacker would use. Do not let anyone speak.\n');
    fprintf('These files go to Replay/ and are never used as enrolment templates.\n');
end

report = struct('Student', o.Student, 'Mode', o.Mode, 'Files', {{}}, ...
    'Accepted', 0, 'Retaken', 0, 'Skipped', 0, 'Diagnostics', {{}});

for iPhrase = 1:numel(o.Phrases)
    phrase = o.Phrases{iPhrase};
    folder = destination_folder(o.Mode, phrase, o.Student, p);
    if ~isfolder(folder)
        mkdir(folder);
    end

    fprintf('\n--- %s phrase -> %s ---\n', upper(phrase), folder);
    fprintf('%s\n', prompt_for_phrase(phrase, o));

    for k = 1:o.Samples
        [audio, dg, kept] = record_one_take(k, o.Samples, phrase, p, o);
        if ~kept
            report.Skipped = report.Skipped + 1;
            continue;
        end
        target = next_filename(folder, k, o.Overwrite);
        audiowrite(target, audio, p.fs);
        report.Files{end+1} = target;
        report.Diagnostics{end+1} = dg;
        report.Accepted = report.Accepted + 1;
        fprintf('    saved %s\n', target);
    end
end

% The coupon code belongs with the enrolment, not with a test or replay capture.
if strcmpi(o.Mode, 'enrol')
    write_code_file(o, p);
end

fprintf('\n%d recordings saved, %d retaken, %d skipped.\n', ...
    report.Accepted, report.Retaken, report.Skipped);
if strcmpi(o.Mode, 'enrol')
    fprintf('Run FIND_BEST_VOICE_MATCH(''reset'') before verifying, so the template\n');
    fprintf('cache picks up the new files.\n');
end
end

% =========================================================================
function [audio, dg, kept] = record_one_take(k, total, phrase, p, o)
%RECORD_ONE_TAKE Capture once, report the quality numbers, offer a retry.
%
%   The take is judged by the same PREPROCESS_TEMPLATE_AUDIO the system will use on
%   it later.  Checking at recording time is the whole point: a student is standing
%   there and can simply speak again, whereas a bad file discovered during
%   calibration weeks later is a file nobody can re-record.
attempt = 0;

while true
    attempt = attempt + 1;
    fprintf('\n  Take %d of %d (attempt %d)\n', k, total, attempt);
    fprintf('    Stay SILENT for the first %.2f s, then say the %s.\n', ...
        p.noise.NoiseDuration, phrase_words(phrase));
    input('    Press Enter when ready...', 's');

    fprintf('    [silence]');
    audio = record_audio_dsp(p.recordDur, p.fs);
    fprintf('  done.\n');

    % Strict: the student is standing at the microphone, so a defect costs one
    % retake. ASSESS_RECORDING_QUALITY relaxes the pre-roll rule only when auditing
    % files already on disk, where re-recording is not an option.
    dg = assess_recording_quality(audio, p.fs, p, ...
        struct('Mode', o.Mode, 'Strict', true));
    print_assessment(dg, p);

    if ~o.Review
        kept = true;
        return;
    end

    if dg.Usable
        answer = ask('    Keep this take? [Y/n/s(kip)] ', 'y');
    else
        answer = ask('    This take has problems. Keep anyway? [y/N/s(kip)] ', 'n');
    end

    switch lower(answer(1))
        case 'y'
            kept = true;
            return;
        case 's'
            fprintf('    Skipped.\n');
            kept = false;
            return;
        otherwise
            fprintf('    Retaking.\n');
    end
end
end

function print_assessment(dg, p)
fprintf('    pre-roll RMS %.5f | overall RMS %.5f', dg.PreRollRms, dg.OverallRms);
if ~isnan(dg.SpeechDuration)
    fprintf(' | speech %.2f s', dg.SpeechDuration);
else
    fprintf(' | speech NOT DETECTED');
end
if ~isnan(dg.LowBandRatio)
    fprintf(' | sub-200 Hz ratio %.5f (live band %.5f-%.5f)', ...
        dg.LowBandRatio, p.liveness.MinRatio, p.liveness.MaxRatio);
end
fprintf('\n');

% Every problem, not just the first. A take can be both clipped and missing its
% pre-roll, and the operator needs to fix both before the retake rather than
% discovering the second one on attempt three.
if isempty(dg.Problems)
    fprintf('    OK.\n');
    return;
end
for k = 1:numel(dg.Problems)
    fprintf('    PROBLEM %d of %d: %s\n', k, numel(dg.Problems), dg.Problems{k});
end
end

% =========================================================================
function o = parse_options(args, p)
o = struct('Student','', 'Mode','enrol', 'Samples',p.samplesPerPhrase, ...
    'Phrases',{{'name','coupon'}}, 'Code','', 'Overwrite',false, 'Review',true);
for k = 1:2:numel(args)
    name = validatestring(args{k}, fieldnames(o), 'record_corpus_tool');
    o.(name) = args{k+1};
end
o.Mode = validatestring(o.Mode, {'enrol','test','replay'}, 'record_corpus_tool', 'Mode');
if ischar(o.Phrases) || isstring(o.Phrases)
    o.Phrases = cellstr(o.Phrases);
end
o.Student = char(string(o.Student));
o.Code = char(string(o.Code));
validateattributes(o.Samples, {'numeric'}, {'scalar','integer','positive'});
end

function folder = destination_folder(mode, phrase, student, p)
switch lower(mode)
    case 'enrol'
        base = p.trainBaseFolder;
    case 'test'
        base = p.testFolder;
    case 'replay'
        base = 'Replay';
end
if strcmpi(phrase, 'name')
    folder = fullfile(base, 'Name', student);
else
    folder = fullfile(base, 'Coupon', student);
end
end

function text = describe_destination(mode, p)
switch lower(mode)
    case 'enrol',  text = sprintf('%s/{Name,Coupon}/<student>/  (enrolment templates)', p.trainBaseFolder);
    case 'test',   text = sprintf('%s/{Name,Coupon}/<student>/  (held-out test audio)', p.testFolder);
    case 'replay', text = 'Replay/{Name,Coupon}/<student>/  (attack samples, never enrolled)';
end
end

function words = phrase_words(phrase)
if strcmpi(phrase, 'name')
    words = 'student''s full name';
else
    words = 'six digits of the coupon code, one at a time';
end
end

function text = prompt_for_phrase(phrase, o)
if strcmpi(phrase, 'name')
    text = sprintf('Say: "%s"', o.Student);
elseif ~isempty(o.Code)
    text = sprintf('Say the digits: %s', strjoin(cellstr(o.Code(:)), ' '));
else
    text = 'Say the six digits of the coupon code, one at a time.';
end
end

function target = next_filename(folder, k, overwrite)
%NEXT_FILENAME Pick a filename, without silently destroying existing audio.
%   The corpus already suffers from having too few recordings per student, so the
%   default is to add rather than replace. Overwriting is available but must be
%   asked for.
if overwrite
    target = fullfile(folder, sprintf('%d.wav', k));
    return;
end
n = k;
while isfile(fullfile(folder, sprintf('%d.wav', n)))
    n = n + 1;
end
target = fullfile(folder, sprintf('%d.wav', n));
end

function write_code_file(o, p)
code = o.Code;
folder = fullfile(p.trainNameFolder, o.Student);
codePath = fullfile(folder, p.codeFileName);

if isempty(code) && isfile(codePath)
    fid = fopen(codePath, 'r');
    if fid > 0
        existing = strtrim(fscanf(fid, '%s'));
        fclose(fid);
        fprintf('\nCoupon code on file for %s: %s (left unchanged).\n', o.Student, existing);
        return;
    end
end

while numel(code) ~= 6 || ~all(isstrprop(code, 'digit'))
    code = strtrim(input(sprintf('\n6-digit coupon code for %s: ', o.Student), 's'));
    if numel(code) ~= 6 || ~all(isstrprop(code, 'digit'))
        fprintf('  Must be exactly 6 digits.\n');
    end
end

if ~isfolder(folder), mkdir(folder); end
fid = fopen(codePath, 'w');
if fid < 0
    warning('record_corpus_tool:codeWrite', 'Could not write %s', codePath);
    return;
end
fprintf(fid, '%s\n', code);
fclose(fid);
fprintf('Coupon code %s written to %s\n', code, codePath);
end

function answer = ask(prompt, default)
answer = strtrim(input(prompt, 's'));
if isempty(answer), answer = default; end
end
