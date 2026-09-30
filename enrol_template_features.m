function [features, dg] = enrol_template_features(source, fs, params)
%ENROL_TEMPLATE_FEATURES The one decision on whether a stored recording is enrolled.
%
%   FEATURES = ENROL_TEMPLATE_FEATURES(FILEPATH) reads the file, judges it with
%   ASSESS_RECORDING_QUALITY, and returns its feature matrix if the recording is
%   usable or [] if it is not.  Any read or processing error also returns [].
%
%   FEATURES = ENROL_TEMPLATE_FEATURES(AUDIO, FS) judges audio already in memory,
%   which is what EXPERIMENT_CHANNEL_ROBUSTNESS needs after it has convolved a
%   simulated microphone response onto the raw capture.
%
%   FEATURES = ENROL_TEMPLATE_FEATURES(..., PARAMS) uses PARAMS instead of
%   DSP_PARAMETERS(), so a sweep can vary one setting and see what it enrols.
%
%   [FEATURES, DG] = ... also returns the full quality verdict, whose Reason field
%   says why a rejected recording was rejected.
%
%   EEE 312 CO1 (implement DSP algorithms), CO5 (report the corpus as it is).
%   PO(c) Design, PO(d) Investigation.
%
%   Why this function exists
%   ----------------------
%   Six places decided independently whether a stored WAV was fit to enrol, and all
%   six spelled the decision out inline as
%
%       [y, fo, d] = preprocess_template_audio(x, fs, p);
%       if ~d.Rejected && d.Endpoint.HasSpeech
%           f = extract_features(y, fo, p);
%       end
%
%   in FIND_BEST_VOICE_MATCH (the deployed matcher), EXPERIMENT_VERIFICATION_ACCURACY,
%   CALIBRATE_DTW_THRESHOLD, EXPERIMENT_CHANNEL_ROBUSTNESS, CALIBRATE_LIVENESS_BAND
%   and VERIFY_DSP_PIPELINE.  ASSESS_RECORDING_QUALITY, which the corpus audit and the
%   enrolment tab use, applied a seventh and slightly stronger rule while its own
%   header claimed to apply the same one.
%
%   Six copies of a decision are six chances for it to differ, and it did differ:
%   VERIFY_DSP_PIPELINE's corpus check found two files the audit called unusable and
%   the experiments enrolled anyway.  Both were junk -- a 0.095 s fragment where six
%   spoken digits should be, and a file 5x below the AGC's silence floor -- so the
%   experiments were the ones measuring accuracy against templates with no phrase in
%   them, and the reported figures were computed over a library the audit said was
%   partly empty.
%
%   Collapsing all seven into this function is what makes the audit's verdict true by
%   construction instead of true by inspection.  It is deliberately thin: the
%   judgement lives in ASSESS_RECORDING_QUALITY, and nothing here re-decides it.
%
%   Why the chain's own verdict is not enough
%   ----------------------------------------
%   PREPROCESS_TEMPLATE_AUDIO answers "did this produce features".  A click and a
%   whisper of room noise both do.  HYBRID_ENDPOINT_DETECT reports whatever exceeds
%   the local noise floor, so it finds speech in a near-silent file by adapting down
%   to it, and it has no notion of how long a phrase ought to be.  The two extra tests
%   in ASSESS_RECORDING_QUALITY -- an absolute level floor and a minimum speech
%   duration -- are what turn "something happened" into "a phrase was said".
%
%   Stored files are judged with Strict = false
%   ------------------------------------------
%   A recording on disk is judged leniently: clipping and a missing silent pre-roll
%   are advisory, because the alternative is discarding data that cannot be recreated,
%   and PREPROCESS_TEMPLATE_AUDIO has a documented fallback path for a missing
%   pre-roll.  A capture being made now is judged strictly, because there a retake
%   costs seconds -- that is what the enrolment tab and RECORD_CORPUS_TOOL do, by
%   calling ASSESS_RECORDING_QUALITY themselves with Strict left at its default.
%
%   See also ASSESS_RECORDING_QUALITY, PREPROCESS_TEMPLATE_AUDIO, EXTRACT_FEATURES,
%   FIND_BEST_VOICE_MATCH, DIAGNOSE_AUDIO_CORPUS.

if nargin < 2, fs = []; end
if nargin < 3 || isempty(params), params = dsp_parameters(); end

features = [];
dg = struct('Usable', false, 'Reason', 'not assessed', 'Problems', {{}});

try
    if ischar(source) || isstring(source)
        [audio, fs] = audioread(char(source));
    else
        audio = source;
        if isempty(fs)
            error('enrol_template_features:noRate', ...
                'FS is required when the first argument is audio rather than a file path.');
        end
    end

    if size(audio, 2) > 1, audio = mean(audio, 2); end

    % Strict = false: see the header. These files are what they are.
    dg = assess_recording_quality(audio, fs, params, struct('Strict', false));

    if dg.Usable
        features = extract_features(dg.Audio, dg.Fs, params);
    end
catch err
    % A caller enrolling a whole folder must not stop because one file is corrupt or
    % has an unreadable header. The reason is carried out in DG for whoever wants it.
    features = [];
    dg.Usable = false;
    dg.Reason = sprintf('could not be enrolled: %s', err.message);
    dg.Problems = {dg.Reason};
end
end
