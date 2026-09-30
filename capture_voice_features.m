function [features, ok, diagnostics] = capture_voice_features(label, status, p)
%CAPTURE_VOICE_FEATURES Record one phrase, run the DSP chain, extract features.
%
%   [FEATURES, OK, DIAGNOSTICS] = CAPTURE_VOICE_FEATURES(LABEL, STATUS, P) records
%   until speech ends (at most P.recordDur seconds), preprocesses, and returns
%   the feature matrix produced by the configured front-end.  OK is false when any
%   stage rejected the capture; DIAGNOSTICS carries the per-stage report so the
%   caller can tell the student what went wrong.
%
%   LABEL is the phrase being asked for ('name' or 'coupon code') and is used only
%   in the prompts.  STATUS is the uitextarea handle passed to UPDATE_STATUS_TEXT,
%   or [] when running headless.
%
%   The instruction to stay quiet first is not politeness
%   ----------------------------------------------------
%   PREPROCESS_AUDIO learns the dining-hall noise spectrum from the first
%   P.noise.NoiseDuration seconds of the recording and subtracts it from the rest,
%   and the endpoint detector learns its energy and zero-crossing thresholds from
%   the same interval.  If the student starts speaking immediately, the system
%   learns their voice as the noise floor and then subtracts it, which removes the
%   speech and raises the thresholds above it.  The prompt therefore has to make
%   the pause explicit, and this function reports how much lead-in it actually got
%   so a student who spoke too early can be told exactly that instead of being
%   told, unhelpfully, that no speech was found.
%
%   Why features are extracted here rather than in the matcher
%   ---------------------------------------------------------
%   The same feature matrix is compared against every enrolled student, so it is
%   computed once at the point of capture.  Extraction is dispatched through
%   EXTRACT_FEATURES so that this function does not know or care which front-end
%   is configured -- switching P.featureFrontEnd changes what is compared without
%   touching the capture path.
%
%   See also PREPROCESS_AUDIO, EXTRACT_FEATURES, VERIFY_MEAL_WORKFLOW.

if nargin < 3 || isempty(p), p = dsp_parameters(); end
if nargin < 2, status = []; end

features = [];
ok = false;
diagnostics = struct('Rejected', true, 'Reason', '', 'Stage', 'init', ...
    'Agc', struct('InputRms', 0, 'Gain', 1), ...
    'Endpoint', struct('HasSpeech', false, 'StartSample', 1, 'EndSample', 1), ...
    'LowFrequencyRatio', 0, 'Features', []);

stopCheck = @() check_stop_requested(status);

infoDev = audiodevinfo;
if isempty(infoDev.input)
    diagnostics.Stage = 'no-mic';
    diagnostics.Reason = 'No audio input device found. Please connect a microphone or use Manual Entry.';
    update_status_text(status, diagnostics.Reason);
    return;
end

stopped = false;
captureState = struct();

% -------------------------------------------------------------------------
% 1. Ambient noise calibration (quiet pre-roll BEFORE speaking prompts)
% -------------------------------------------------------------------------
ambientDuration = 0.50; % Standard 0.50s pre-roll for spectral subtraction
update_status_text(status, '● Calibrating room noise floor...');
drawnow;
try
    bgRecorder = audiorecorder(p.fs, 16, 1);
    record(bgRecorder, ambientDuration);
    stoppedBg = interruptible_pause(ambientDuration, stopCheck);
    if isrecording(bgRecorder), stop(bgRecorder); end
    if stoppedBg || stopCheck()
        diagnostics.Stage = 'user-stop';
        diagnostics.Reason = 'Recording stopped by user.';
        update_status_text(status, '● Recording cancelled by user.');
        return;
    end
    ambientPreRoll = getaudiodata(bgRecorder);
    if isempty(ambientPreRoll)
        ambientPreRoll = zeros(round(ambientDuration * p.fs), 1);
    end
    ambientPreRoll = ambientPreRoll(:);
    if numel(ambientPreRoll) < round(ambientDuration * p.fs)
        ambientPreRoll = [ambientPreRoll; zeros(round(ambientDuration * p.fs) - numel(ambientPreRoll), 1)];
    end
catch
    ambientPreRoll = zeros(round(ambientDuration * p.fs), 1);
end

% -------------------------------------------------------------------------
% 2. Synchronized Visual & Audio Prompts (3... 2... 1... Speak now!)
% -------------------------------------------------------------------------
try
    if contains(lower(label), 'id')
        update_status_text(status, 'Get ready to say your Student ID: 3...');
        drawnow;
        speak_text('Three', false);
        if stopCheck(), stopped = true; return; end

        update_status_text(status, 'Get ready to say your Student ID: 2...');
        drawnow;
        speak_text('Two', false);
        if stopCheck(), stopped = true; return; end

        update_status_text(status, 'Get ready to say your Student ID: 1...');
        drawnow;
        speak_text('One', false);
        if stopCheck(), stopped = true; return; end

        update_status_text(status, sprintf('>>> SPEAK NOW! Say your %s once.', label));
        drawnow;
        speak_text('Speak now!', false);
    else
        update_status_text(status, 'Get ready to say your full name in 3...');
        drawnow;
        speak_text('Three', false);
        if stopCheck(), stopped = true; return; end

        update_status_text(status, 'Get ready to say your full name in 2...');
        drawnow;
        speak_text('Two', false);
        if stopCheck(), stopped = true; return; end

        update_status_text(status, 'Get ready to say your full name in 1...');
        drawnow;
        speak_text('One', false);
        if stopCheck(), stopped = true; return; end

        update_status_text(status, sprintf('>>> SPEAK NOW! Say your %s once.', label));
        drawnow;
        speak_text('Say your full name. Speak now!', false);
    end
    if stopCheck(), stopped = true; return; end

    % ---------------------------------------------------------------------
    % 3. Live microphone recording (begins immediately upon cue)
    % ---------------------------------------------------------------------
    liveP = p;
    liveP.noise.NoiseDuration = ambientDuration;
    liveP.endpoint.NoiseDuration = ambientDuration;
    if ~isfield(liveP, 'speechStop') || isempty(liveP.speechStop)
        liveP.speechStop = struct();
    end
    liveP.speechStop.HangoverDuration = 0.8; % Stop when voice is low for 0.8s
    liveP.speechStop.MinStartRms = 0.0025;   % Voice threshold: ignore room noise below 2.5 mV
    liveP.speechStop.MinEndRms = 0.0012;     % Silence threshold: fall below 1.2 mV
    liveP.speechStop.StartNoiseRatio = 2.5;  % Sensitive 2.5x background noise
    liveP.speechStop.EndNoiseRatio = 1.8;
    liveP.speechStop.EndRelativeDb = 25.0;
    liveP.recordDur = 8.0;

    recorder = audiorecorder(p.fs, 16, 1);
    record(recorder, liveP.recordDur);
    update_status_text(status, sprintf('● RECORDING... Speak your %s now! (auto-stops on silence)', label));
    drawnow;

    announcedSpeech = false;
    stoppedSpeech = false;
    while isrecording(recorder)
        if stopCheck(), stoppedSpeech = true; break; end
        if recorder.TotalSamples == 0
            if interruptible_pause(0.04, stopCheck), stoppedSpeech = true; break; end
            continue;
        end
        try
            speechChunk = getaudiodata(recorder);
        catch
            speechChunk = [];
        end
        if isempty(speechChunk)
            if interruptible_pause(0.04, stopCheck), stoppedSpeech = true; break; end
            continue;
        end
        fullSignal = [ambientPreRoll; speechChunk(:)];
        captureState = speech_capture_state(fullSignal, p.fs, liveP);
        if captureState.ShouldStop, break; end
        if captureState.SpeechStarted && ~announcedSpeech
            update_status_text(status, 'Vocal detected! Keep speaking... (recording rolls on)');
            drawnow;
            announcedSpeech = true;
        end
        if interruptible_pause(0.04, stopCheck), stoppedSpeech = true; break; end
    end
    if isrecording(recorder), stop(recorder); end

    if stoppedSpeech || stopCheck()
        stopped = true;
    else
        speechChunk = getaudiodata(recorder);
        if isempty(speechChunk)
            speechChunk = zeros(0, 1);
        end
        raw = [ambientPreRoll; speechChunk(:)];
        if isempty(raw) || numel(raw) == 0
            diagnostics.Stage = 'recording-empty';
            diagnostics.Reason = 'Microphone produced no audio samples. Please check audio device or use Manual Entry.';
            update_status_text(status, diagnostics.Reason);
            return;
        end
        captureState = speech_capture_state(raw, p.fs, liveP);
        if captureState.ShouldStop && ~isnan(captureState.StopSample)
            if isfield(captureState, 'SpeechEndSample') && ~isnan(captureState.SpeechEndSample)
                speechEndWithPad = min(numel(raw), captureState.SpeechEndSample + round(0.3 * p.fs));
                raw = raw(1:speechEndWithPad);
            else
                raw = raw(1:min(numel(raw), captureState.StopSample));
            end
        end
        if ~captureState.SpeechStarted
            diagnostics.Stage = 'endpoint';
            diagnostics.Reason = sprintf('No vocal speech detected in the %.0f-second window. Please speak louder or use Manual Entry.', liveP.recordDur);
            diagnostics.Rejected = true;
            update_status_text(status, diagnostics.Reason);
            update_status_text(status, advice_for(diagnostics, p));
            return;
        elseif strcmp(captureState.Reason, 'speech-ended')
            speechSec = max(0, (numel(raw) - numel(ambientPreRoll)) / p.fs);
            update_status_text(status, sprintf('Speech finished. Recorded %.2f s. Verifying voice...', speechSec));
        else
            update_status_text(status, sprintf('Recording reached limit (%.2f s). Verifying voice...', numel(raw) / p.fs));
        end
    end
catch err
    try
        if exist('recorder','var') && isrecording(recorder), stop(recorder); end
    catch
    end
    diagnostics.Stage = 'recording-error';
    diagnostics.Reason = ['Microphone recording failed: ' err.message];
    update_status_text(status, diagnostics.Reason);
    return;
end

if stopped || stopCheck()
    diagnostics.Stage = 'user-stop';
    diagnostics.Reason = 'Recording stopped by user.';
    update_status_text(status, '● Recording cancelled by user.');
    return;
end

raw = raw(:);

% Check for microphone clipping
if any(abs(raw) >= 0.999)
    update_status_text(status, '  [!] Microphone input clipped (peak >= 0 dBFS). Consider lowering gain or stepping slightly back.');
end

% Native-rate 44.1/48 kHz dual-path liveness check (Defect D5 fix)
[isLiveAcoustic, liveScore, liveMetrics, liveReport] = verifyLiveness(raw, p.fs);


quality = assess_recording_quality(raw,p.fs,liveP,struct('Mode','live','Strict',true));
audio = quality.Audio;
fs = quality.Fs;

% Apply calibrated acoustic channel equalization if a profile exists
audio = equalize_microphone_audio(audio, fs);

if ~isempty(fieldnames(quality.Preprocess))
    diagnostics = quality.Preprocess;
end
diagnostics.RecordingQuality = rmfield(quality,{'Audio','Preprocess'});
diagnostics.Capture=captureState;
diagnostics.LivenessWideband = liveMetrics;
diagnostics.LivenessScore = liveScore;
if ~isLiveAcoustic && isfield(p, 'enablePhysicalLiveness') && p.enablePhysicalLiveness
    diagnostics.Rejected = true;
    diagnostics.Stage = 'Liveness';
    diagnostics.Reason = liveReport;
end
if ~quality.Usable
    if ~diagnostics.Rejected || strcmp(diagnostics.Stage,'init')
        diagnostics.Stage = 'Quality';
    end
    diagnostics.Rejected = true;
    diagnostics.Reason = quality.Reason;
end

% Report the measurements before reporting the verdict, so that a rejection is
% always accompanied by the number that caused it.
update_status_text(status, sprintf( ...
    '  %s: capture RMS %.4g, AGC gain %.1f, speech %.2f s, sub-200 Hz ratio %.5f', ...
    label, diagnostics.Agc.InputRms, diagnostics.Agc.Gain, ...
    speech_duration(diagnostics, fs), diagnostics.LowFrequencyRatio));

if diagnostics.Rejected || ~diagnostics.Endpoint.HasSpeech
    reason = diagnostics.Reason;
    if isempty(reason)
        reason = 'no speech was detected in the recording';
    end
    update_status_text(status, sprintf('  %s rejected at the %s stage: %s', ...
        label, diagnostics.Stage, reason));
    update_status_text(status, advice_for(diagnostics, p));
    return;
end

[features, featureInfo] = extract_features(audio, fs, p);
diagnostics.Features = featureInfo;
% v4.1.4_claude: keep the raw capture so the GMM-UBM voice veto can score it
diagnostics.RawAudio = raw;
diagnostics.RawFs = p.fs;

if isempty(features)
    update_status_text(status, sprintf( ...
        '  %s rejected: only %.2f s of speech, too short to frame.', ...
        label, speech_duration(diagnostics, fs)));
    return;
end

ok = true;
update_status_text(status, sprintf('  %s accepted: %d frames of %d-dimensional %s features.', ...
    label, size(features,2), size(features,1), upper(p.featureFrontEnd)));
end

% -------------------------------------------------------------------------
function d = speech_duration(diagnostics, fs)
if diagnostics.Endpoint.HasSpeech
    d = (diagnostics.Endpoint.EndSample - diagnostics.Endpoint.StartSample + 1) / fs;
else
    d = 0;
end
end

function text = advice_for(diagnostics, p)
%ADVICE_FOR Turn a rejection into an instruction the student can act on.
switch lower(diagnostics.Stage)
    case 'agc'
        text = ['  Nothing reached the microphone. Check that the right input ' ...
                'device is selected and speak closer to it.'];
    case 'endpoint'
        text = ['  Speak louder and leave the first half second silent -- the ' ...
                'thresholds are learnt from it.'];
    case 'liveness'
        if diagnostics.Liveness.Ratio < p.liveness.MinRatio
            text = ['  The recording has very little energy below 200 Hz and ' ...
                    'failed the spectral quality heuristic. Move closer to the ' ...
                    'microphone and retry.'];
        else
            text = ['  The recording is mostly low-frequency rumble. Move the ' ...
                    'microphone away from the table or fan and try again.'];
        end
    case 'user-stop'
        text = '  Recording was stopped by the user.';
    otherwise
        text = '  Try the recording again.';
end
end

function tf = check_stop_requested(status)
tf = false;
if isempty(status), return; end
try
    if isvalid(status)
        fig = ancestor(status, 'figure');
        if ~isempty(fig) && isvalid(fig) && isfield(fig.UserData, 'stopRequested') && fig.UserData.stopRequested
            tf = true;
            return;
        end
    end
catch
end
try
    if isprop(status, 'UserData') && isstruct(status.UserData) && ...
            isfield(status.UserData, 'stopRequested') && status.UserData.stopRequested
        tf = true;
        return;
    end
catch
end
end

