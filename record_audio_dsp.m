function audio = record_audio_dsp(duration, fs)
%RECORD_AUDIO_DSP Record mono 16-bit audio for the requested duration.
%
%   AUDIO = RECORD_AUDIO_DSP(DURATION, FS) blocks for DURATION seconds and returns
%   the captured samples as a column vector in [-1, 1].
%
%   Why the error is translated
%   --------------------------
%   On a machine with no working capture device, AUDIORECORDER fails with a message
%   about a device or a driver.  That message is accurate and useless to a student
%   standing at a counter: it does not say that the rest of the system is fine, and
%   it does not say what to do.  Every recording path in this project goes through
%   this function -- CAPTURE_VOICE_FEATURES, RECORD_CORPUS_TOOL and the enrol tab of
%   MEAL_VERIFICATION_GUI -- so translating it once here is what lets all three
%   report something actionable, and what lets the GUI suggest its file-driven demo
%   path instead of simply failing.
%
%   See also CAPTURE_VOICE_FEATURES, RECORD_CORPUS_TOOL, MEAL_VERIFICATION_GUI.

validateattributes(duration,{'numeric'},{'scalar','positive','finite'});
validateattributes(fs,{'numeric'},{'scalar','positive','finite'});

try
    recorder = audiorecorder(fs,16,1);
    recordblocking(recorder,duration);
    audio = getaudiodata(recorder);
catch cause
    err = MException('record_audio_dsp:noInputDevice', ...
        ['Could not record %g s at %g Hz. No working audio input device was ' ...
         'available.\n' ...
         'Check that a microphone is connected and selected as the default ' ...
         'recording device, and that MATLAB is allowed to use it (on Windows: ' ...
         'Settings > Privacy > Microphone).\n' ...
         'Every offline part of this system runs without a microphone: use the ' ...
         'file-driven demo in MEAL_VERIFICATION_GUI, or run VERIFY_DSP_PIPELINE ' ...
         'and the EXPERIMENT_* functions, which read the stored corpus.'], ...
        duration, fs);
    throw(addCause(err, cause));
end

audio = audio(:);
end
