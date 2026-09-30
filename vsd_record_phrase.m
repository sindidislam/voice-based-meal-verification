function [raw, fs, diag] = vsd_record_phrase(label, status, p, spokenPrompt)
%VSD_RECORD_PHRASE Record one phrase from the microphone and return the raw audio.
%
%   [RAW, FS, DIAG] = VSD_RECORD_PHRASE(LABEL, STATUS, P) records the phrase
%   named LABEL ('Student ID', 'full name', or a challenge text) with the same
%   acquisition policy as v4.1.4 (0.5 s ambient pre-roll, 3-2-1 cue, automatic
%   stop 0.8 s after speech ends, 8 s cap) but returns the WAVEFORM so that the
%   v4.1.4_claude engine can run its own front-end, the replay guard and the
%   self-adaptation store.  DIAG.Stage is 'ok', 'user-stop', 'no-mic',
%   'endpoint' (no speech) or 'recording-error'.
%
%   SPOKENPROMPT (optional) is spoken by the text-to-speech cue instead of
%   the default ("Say your full name. Speak now!").

if nargin < 4, spokenPrompt = ''; end
fs = p.fs;  raw = zeros(0,1);
diag = struct('Stage','init','Reason','','SpeechStarted',false,'Clipped',false);
stopCheck = @() stop_requested(status);
try
    infoDev = audiodevinfo;
    if isempty(infoDev.input)
        diag.Stage = 'no-mic'; diag.Reason = 'No audio input device found.';
        update_status_text(status, diag.Reason); return;
    end
catch
end
ambientDuration = 0.50;
update_status_text(status, '● Calibrating room noise floor (stay silent)...'); drawnow;
try
    bg = audiorecorder(fs, 16, 1);
    record(bg, ambientDuration);
    if interruptible_pause(ambientDuration, stopCheck) || stopCheck()
        if isrecording(bg), stop(bg); end
        diag.Stage = 'user-stop'; diag.Reason = 'Recording stopped by user.'; return;
    end
    if isrecording(bg), stop(bg); end
    pre = getaudiodata(bg);  pre = pre(:);
catch
    pre = zeros(round(ambientDuration*fs), 1);
end
if numel(pre) < round(ambientDuration*fs), pre = [pre; zeros(round(ambientDuration*fs) - numel(pre), 1)]; end

for k = 3:-1:1
    update_status_text(status, sprintf('Get ready to say %s in %d...', label, k)); drawnow;
    speak_text(sprintf('%d', k), false);
    if stopCheck(), diag.Stage = 'user-stop'; diag.Reason = 'Recording stopped by user.'; return; end
end
update_status_text(status, sprintf('>>> SPEAK NOW! Say %s once.', label)); drawnow;
if isempty(spokenPrompt), spokenPrompt = 'Speak now!'; end
speak_text(spokenPrompt, false);

liveP = p;
liveP.speechStop.HangoverDuration = 0.8;
liveP.speechStop.MinStartRms = 0.0025;
liveP.speechStop.MinEndRms = 0.0012;
liveP.speechStop.StartNoiseRatio = 2.5;
liveP.speechStop.EndNoiseRatio = 1.8;
liveP.speechStop.EndRelativeDb = 25.0;
liveP.recordDur = 8.0;
try
    rec = audiorecorder(fs, 16, 1);
    record(rec, liveP.recordDur);
    update_status_text(status, sprintf('● RECORDING %s ... (auto-stops on silence)', label)); drawnow;
    announced = false;  stopped = false;  state = struct('ShouldStop',false,'SpeechStarted',false);
    while isrecording(rec)
        if stopCheck(), stopped = true; break; end
        if rec.TotalSamples == 0
            if interruptible_pause(0.04, stopCheck), stopped = true; break; end
            continue;
        end
        chunk = getaudiodata(rec);
        state = speech_capture_state([pre; chunk(:)], fs, liveP);
        if state.ShouldStop, break; end
        if state.SpeechStarted && ~announced
            update_status_text(status, 'Voice detected - keep speaking...'); drawnow; announced = true;
        end
        if interruptible_pause(0.04, stopCheck), stopped = true; break; end
    end
    if isrecording(rec), stop(rec); end
    if stopped || stopCheck()
        diag.Stage = 'user-stop'; diag.Reason = 'Recording stopped by user.'; return;
    end
    chunk = getaudiodata(rec);
    raw = [pre; chunk(:)];
    state = speech_capture_state(raw, fs, liveP);
    if state.ShouldStop && isfield(state,'SpeechEndSample') && ~isnan(state.SpeechEndSample)
        raw = raw(1:min(numel(raw), state.SpeechEndSample + round(0.3*fs)));
    end
    diag.SpeechStarted = state.SpeechStarted;
    if ~state.SpeechStarted
        diag.Stage = 'endpoint';
        diag.Reason = 'No speech detected. Speak louder, after the SPEAK NOW cue.';
        update_status_text(status, diag.Reason); return;
    end
    diag.Clipped = any(abs(raw) >= 0.999);
    if diag.Clipped
        update_status_text(status, '  [!] Input clipped - step back slightly or lower the mic gain.');
    end
    diag.Stage = 'ok';
    update_status_text(status, sprintf('  %s captured: %.2f s.', label, numel(raw)/fs));
catch err
    diag.Stage = 'recording-error'; diag.Reason = ['Microphone recording failed: ' err.message];
    update_status_text(status, diag.Reason);
end
end

function tf = stop_requested(status)
tf = false;
if isempty(status), return; end
try
    fig = ancestor(status, 'figure');
    if ~isempty(fig) && isvalid(fig) && isfield(fig.UserData,'stopRequested') && fig.UserData.stopRequested
        tf = true; return;
    end
catch
end
try
    if isprop(status,'UserData') && isstruct(status.UserData) && isfield(status.UserData,'stopRequested') ...
            && status.UserData.stopRequested
        tf = true;
    end
catch
end
end
