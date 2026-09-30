function dg = assess_recording_quality(audio, fs, params, options)
%ASSESS_RECORDING_QUALITY Judge whether one recording is fit to be used.
%
%   DG = ASSESS_RECORDING_QUALITY(AUDIO, FS, PARAMS) runs the deployed
%   preprocessing over a capture and returns a struct describing everything wrong
%   with it, in terms an operator can act on.
%
%   DG = ASSESS_RECORDING_QUALITY(AUDIO, FS, PARAMS, OPTIONS) accepts:
%     Mode    'live' | 'enrol' | 'test' | 'replay'. 'live' uses PREPROCESS_AUDIO;
%             archived modes use PREPROCESS_TEMPLATE_AUDIO. In 'replay' mode a failed liveness test
%             is the expected outcome and is excluded from the verdict.
%     Strict  true (default) for audio being recorded now, where the operator can
%             simply record it again.  false when auditing files already on disk.
%
%   DG fields
%     Usable        no fatal defect: this recording is fit to be enrolled or matched.
%                   ENROL_TEMPLATE_FEATURES extracts features iff this is true, so
%                   the verdict here IS the deployed system's behaviour.
%     WellRecorded  no defect at all, fatal or advisory.
%     Problems      cell array of every problem found, most serious first.
%     Reason        the single line to show an operator; 'OK' when clean.
%     Audio, Fs     the preprocessed audio and its rate, already computed here, so a
%                   caller that needs the samples does not run the chain twice.
%                   Audio is empty when preprocessing rejected the capture.
%     PreRollRms, OverallRms, ClippedFraction, ClippedRun, SpeechDuration,
%     LowBandRatio, Clipped, Rejected.
%     AcRms is measured after DC removal. Preprocess carries the stage report
%     and timing measurements; Audio is empty whenever Usable is false.
%
%   EEE 312 CO1, CO3, CO4.  PO(c) Design, PO(d) Investigation.
%
%   Why fatal and advisory are separated
%   -----------------------------------
%   The first version of this function reported only the first problem it found and
%   treated a non-silent pre-roll as fatal.  Run over the existing corpus it
%   rejected 51 of 61 name recordings.  That verdict was both true and useless.
%
%   True, because the corpus really was recorded without the 0.5 s silent lead-in
%   that modification 3 needs in order to estimate the noise spectrum, and
%   PREPROCESS_TEMPLATE_AUDIO has a whole separate code path
%   ('LegacyCropped') that exists precisely to cope with those files.
%
%   Useless, because those 61 recordings are the only corpus that exists.  A
%   function that refuses all of them cannot be used by the enrolment tab or by the
%   corpus audit -- it would declare the system unenrollable.  The distinction that
%   matters is not "is this recording perfect" but "can this recording still be
%   used, and separately, was it recorded properly".  A fresh capture, with the
%   student still standing at the microphone, is held to the higher standard because
%   there the answer costs one retake.  A file on disk is held to the lower one
%   because the alternative is discarding data that cannot be recreated.
%
%   Reporting only the first problem was the second fault.  Amplifying a corpus file
%   thirty-fold and clipping it produced the message "the first 0.50 s is not
%   silent" -- accurate, and completely beside the point.  Every problem is now
%   collected, so a recording with three defects reports three.
%
%   What USABLE has to mean
%   -----------------------
%   The second version made clipping fatal.  The audit then reported that
%   Al Imran Limon had no usable name recording, while EXPERIMENT_VERIFICATION_ACCURACY
%   was enrolling both of his files and verifying him from them.  Both could not be
%   right.  A clipped file is degraded, not unusable; it is a severe advisory, which
%   keeps it high on the re-record list without pretending the system refuses it.
%
%   The third version claimed in this comment that the fatal list was "deliberately
%   the same condition" the experiments use to enrol a file, namely
%   ~Rejected && Endpoint.HasSpeech.  VERIFY_DSP_PIPELINE's corpus check then found
%   two files where the two disagreed, so the claim was false: the fatal list also
%   requires an overall RMS above 20*AGC.MinRms and a speech duration of at least
%   LIVENESS.MinDuration.  Both extra tests are right, and the two files they catch
%   are junk:
%
%     Train/Coupon/Anindya Guha/1.wav is 0.095 s long in total.  The coupon phrase is
%     six digits spoken one at a time; 95 ms cannot hold one of them, let alone six.
%     The endpoint detector still reports speech because it reports whatever exceeds
%     the local noise floor, and it has no notion of how long a phrase should be.
%
%     Train/Coupon/Imdadul Hasan Hamim/1.wav has an RMS of 0.000036, roughly 1500x
%     below a normal corpus file and 5x below the AGC's own silence floor.  The
%     endpoint detector finds speech in it only because it adapted to an even lower
%     noise floor -- it measures contrast, not level.
%
%   So the resolution ran the other way round.  Rather than weaken the audit to agree
%   with the experiments, the fatal list here became the single definition, and every
%   site that enrols a stored recording now goes through ENROL_TEMPLATE_FEATURES,
%   which asks this function.  That is structural rather than documentary: the two
%   cannot drift apart again, because there is only one of them.  It cost two coupon
%   templates out of 62; neither student was left unverifiable, and RECORD_CORPUS_TOOL
%   is how the two files get replaced.
%
%   The judgement deliberately checks things the matcher cannot fix
%   -------------------------------------------------------------
%   Silent pre-roll: modification 3 estimates the noise spectrum from the first
%   0.5 s and subtracts it.  If the student starts speaking immediately, the "noise"
%   profile contains their voice and the subtraction removes part of the talker from
%   every frame.  Nothing downstream undoes that, so it must be caught at the
%   microphone.
%
%   Clipping: a clipped sample has lost its amplitude information permanently.  AGC
%   rescales, which moves the flat tops but does not restore what was above them,
%   and the harmonic distortion clipping introduces lands inside the 300-3700 Hz
%   band the mel filterbank reads.
%
%   Both are measured on the RAW capture at the original rate, before resampling,
%   because that is where the evidence still exists.
%
%   See also RECORD_CORPUS_TOOL, PREPROCESS_TEMPLATE_AUDIO, DIAGNOSE_AUDIO_CORPUS,
%   ENROL_TEMPLATE_FEATURES.

if nargin < 3 || isempty(params), params = dsp_parameters(); end
if nargin < 4, options = struct(); end

mode = 'enrol';
if isfield(options,'Mode') && ~isempty(options.Mode)
    mode = lower(char(options.Mode));
end
strict = true;
if isfield(options,'Strict') && ~isempty(options.Strict)
    strict = logical(options.Strict);
end

rawQuality = assess_raw_audio_quality(audio,fs,params);

dg = struct('Usable', false, 'WellRecorded', false, 'Problems', {{}}, 'Reason', '', ...
    'PreRollRms', NaN, 'OverallRms', NaN, 'AcRms',NaN, 'ClippedFraction', NaN, 'ClippedRun', NaN, ...
    'SpeechDuration', NaN, 'LowBandRatio', NaN, 'Clipped', false, ...
    'Rejected', false, 'Mode', mode, 'Strict', strict, ...
    'Audio', zeros(0,1), 'Fs', NaN, 'Preprocess',struct());

if ~rawQuality.Valid
    dg.Problems = {'the recording is empty, non-finite, or has an invalid sample rate'};
    dg.Reason = dg.Problems{1};
    dg.Rejected = true;
    return;
end
if size(audio, 2) > 1, audio = mean(audio, 2); end
audio = double(audio(:));

% --- Measurements on the raw capture -------------------------------------
dg.PreRollRms = rawQuality.PreRollRms;
dg.OverallRms = rawQuality.OverallRms;
dg.AcRms = rawQuality.AcRms;

% Clipping is measured two ways, because the fraction of samples at full scale
% alone is misleading. A loud syllable can put a handful of isolated peaks exactly
% at full scale without any waveform being flattened -- Al Imran Limon's name
% recording has 16 such samples in 1.275 s, which a fraction test flags and no ear
% would call distorted. What distortion actually requires is a RUN of consecutive
% pinned samples: a flattened crest, held long enough to replace the top of a pitch
% period with a constant. At 44.1 kHz a run of 10 samples is 0.23 ms, comfortably
% inside a single period of any voiced sound, so that is the shorter of the two
% tests. The fraction test still catches gross overload, where flat tops are
% everywhere and no single run is long.
dg.ClippedFraction = rawQuality.ClippedFraction;
dg.ClippedRun = rawQuality.ClippedRun;
dg.Clipped = rawQuality.Clipped;

% --- The deployed preprocessing chain ------------------------------------
chainReason = '';
try
    q = params;
    if strcmp(mode, 'replay')
        % A replay is SUPPOSED to fail the liveness test. Rejecting it here would
        % mean EXPERIMENT_REPLAY_SPOOF never receives a single attack sample.
        q.enforceLivenessOnTemplates = false;
    end
    if strcmp(mode,'live')
        [y, fsOut, d] = preprocess_audio(audio, fs, q);
    else
        [y, fsOut, d] = preprocess_template_audio(audio, fs, q);
    end
    dg.Preprocess = d;
    dg.Rejected = d.Rejected;
    dg.Audio = y;
    dg.Fs = fsOut;
    if isfield(d,'Endpoint') && isfield(d.Endpoint,'HasSpeech') && d.Endpoint.HasSpeech
        dg.SpeechDuration = (d.Endpoint.EndSample - d.Endpoint.StartSample + 1) / fsOut;
    end
    if isfield(d,'Liveness') && isfield(d.Liveness,'Ratio')
        dg.LowBandRatio = d.Liveness.Ratio;
    end
    if d.Rejected && isfield(d,'Reason') && ~isempty(d.Reason)
        chainReason = d.Reason;
    end
catch err
    dg.Rejected = true;
    dg.Problems = {sprintf('preprocessing failed: %s', err.message)};
    dg.Reason = dg.Problems{1};
    return;
end

% --- Fatal defects: the recording cannot be used, so the system must not use it ---
% This list is the ONE definition of a usable recording. ENROL_TEMPLATE_FEATURES
% asks it, and every offline experiment and the deployed matcher ask
% ENROL_TEMPLATE_FEATURES, so there is no second opinion to drift from. Note that it
% is strictly stronger than the preprocessing chain's own verdict: the chain answers
% "did this produce features", which a 95 ms fragment and a near-silent file both do.
% The two tests below are what "and is it plausibly the phrase" adds.
fatal = {};
minRms = params.agc.MinRms * 20;
minSpeechDuration = params.liveness.MinDuration;
if strict && isfield(params,'quality') && isfield(params.quality,'MinLiveSpeechDuration')
    minSpeechDuration = max(minSpeechDuration,params.quality.MinLiveSpeechDuration);
end

if dg.AcRms <= minRms
    % 20x the AGC's silence floor. Below this the AGC refuses to amplify at all, so
    % whatever features come out describe the noise floor, not a talker.
    fatal{end+1} = sprintf(['too quiet overall (RMS %.5f, minimum %.5f). Move ' ...
        'closer to the microphone or speak up.'], dg.AcRms, minRms);
end
if isnan(dg.SpeechDuration)
    fatal{end+1} = 'no speech was detected. Check the correct microphone is selected.';
elseif dg.SpeechDuration < minSpeechDuration
    % The endpoint detector reports contrast against the local noise floor and has no
    % notion of how long a phrase should be, so a click passes it. This is the test
    % that knows a name or a six-digit code takes time to say.
    fatal{end+1} = sprintf(['only %.2f s of speech was found (minimum %.2f s). Say ' ...
        'the whole phrase at a normal pace.'], dg.SpeechDuration, minSpeechDuration);
end
if dg.Rejected && ~strcmp(mode,'replay') && ~isempty(chainReason)
    fatal{end+1} = chainReason;
end

% --- Advisory defects: features come out, but degraded --------------------------
% Fatal when the audio is being captured now, because a retake costs seconds.
% Advisory when auditing a stored file, because the alternative is discarding the
% only corpus that exists. Ordered by how permanent the damage is: clipping cannot
% be undone by anything, whereas a missing pre-roll has PREPROCESS_TEMPLATE_AUDIO's
% LegacyCropped path -- worse than a proper pre-roll, but it works.
advisory = {};
if dg.Clipped
    advisory{end+1} = sprintf(['clipped: %.3f %% of samples are at full scale, ' ...
        'longest flat run %d samples (%.2f ms). Unrecoverable -- move back from the ' ...
        'microphone or lower the input gain.'], 100*dg.ClippedFraction, ...
        dg.ClippedRun, 1000*dg.ClippedRun/fs);
end
if dg.PreRollRms >= 0.02
    preRollMsg = sprintf(['the first %.2f s is not silent (RMS %.4f, limit ' ...
        '0.0200), so the noise profile is measured over speech. Wait for the prompt ' ...
        'before speaking.'], params.noise.NoiseDuration, dg.PreRollRms);
    if dg.PreRollRms >= 0.5 * dg.AcRms
        fatal{end+1} = preRollMsg;
    else
        advisory{end+1} = preRollMsg;
    end
end

if strict
    % Severe flat-topping clipping (>3% or very long run) is fatal in strict mode
    if dg.Clipped && (dg.ClippedFraction > 0.03 || dg.ClippedRun > round(0.005 * fs))
        fatal = [fatal, advisory];
        advisory = {};
    end
end

dg.Problems = [fatal, advisory];
dg.Usable = isempty(fatal);
dg.WellRecorded = isempty(dg.Problems);
if ~dg.Usable
    dg.Rejected = true;
    dg.Audio = zeros(0,1);
end

if dg.WellRecorded
    if strcmp(mode,'replay')
        dg.Reason = 'OK for replay capture (the liveness verdict is the measurement)';
    else
        dg.Reason = 'OK';
    end
elseif ~isempty(fatal)
    dg.Reason = fatal{1};
else
    dg.Reason = sprintf('usable, but %s', advisory{1});
end
end
