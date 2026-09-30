function [y, fsOut, diag] = preprocess_audio(x, fsIn, params)
%PREPROCESS_AUDIO Shared signal-conditioning chain for live and stored audio.
%
%   [Y, FSOUT, DIAG] = PREPROCESS_AUDIO(X, FSIN, PARAMS) applies the complete
%   front-end of the Voice-Based Meal Verification System and returns the
%   conditioned speech region together with a diagnostic structure describing
%   every decision taken.
%
%   The chain, and the proposal modification each stage implements
%   -------------------------------------------------------------
%     1. Rate conversion 44100 -> 8000 Hz by L/M = 80/441   [mod 1a, Exp 1&2]
%     2. Capture-level RMS automatic gain control            [mod 1b, Exp 1]
%     3. Spectral subtraction from a 0.5 s ambient pre-roll   [mod 3,  Exp 4]
%     4. Endpointing by STE AND a two-sided ZCR band          [mod 4,  Exp 3]
%     5. Speech-level RMS automatic gain control              [mod 1b, Exp 1]
%     6. Sub-200 Hz liveness / replay detection               [mod 2,  Exp 4]
%
%   Why the order is what it is
%   ---------------------------
%   Resampling comes first so that every later stage runs on 5.5 times fewer
%   samples.  Spectral subtraction must precede endpointing, because the ambient
%   pre-roll it needs is exactly the part of the recording that endpointing
%   throws away.  Endpointing must precede the liveness test, because the
%   sub-200 Hz band-energy ratio is only meaningful when measured on speech --
%   measured on silence it reports the room's rumble and nothing about the
%   talker.
%
%   Why AGC is applied twice
%   ------------------------
%   Stage 2 normalises the whole capture, pre-roll included, so that the noise
%   profile and the speech stay in a fixed numeric relationship and the absolute
%   guards downstream operate in a known range.  Stage 5 then normalises the
%   extracted speech region on its own, because the RMS of the whole capture
%   depends on how much silence the student left around the phrase.  Only after
%   stage 5 is the level a property of the speech rather than of the timing.
%
%   DIAG fields
%   -----------
%     Resample, Agc, Noise, Endpoint, AgcSpeech, Liveness  -- per-stage info
%     LowFrequencyRatio   -- the sub-200 Hz band-energy ratio
%     Rejected            -- true if the capture must not be used
%     Reason              -- human-readable explanation shown in the GUI
%     Stage               -- which stage produced the rejection
%
%   See also AGC_NORMALIZE, SPECTRAL_SUBTRACT_NOISE, HYBRID_ENDPOINT_DETECT,
%   CHECK_LIVENESS_LOWFREQ, PREPROCESS_TEMPLATE_AUDIO.

if nargin < 3 || isempty(params), params = dsp_parameters(); end
totalTimer = tic;
timings = struct('Resample',0,'Agc',0,'Noise',0,'Endpoint',0, ...
    'AgcSpeech',0,'Liveness',0,'Total',0);
rawQuality = assess_raw_audio_quality(x,fsIn,params);

% ---- Stage 0: validate --------------------------------------------------
if ~rawQuality.Valid
    [y, fsOut, diag] = rejected_result(params, 'Invalid, empty, or non-finite audio input.', 'Input');
    diag.Quality = rawQuality;
    timings.Total = toc(totalTimer); diag.Timings = timings;
    return;
end

x = double(x(:));

% ---- Stage 1: rational resampling to the DSP rate -----------------------
stageTimer = tic;
[y, fsOut, resampleInfo] = rational_resample_audio(x, fsIn, params.processingFs, params.resample);
timings.Resample = toc(stageTimer);

% ---- Stage 2: capture-level automatic gain control ----------------------
stageTimer = tic;
[y, agcInfo] = agc_normalize(y, params.agc);
timings.Agc = toc(stageTimer);

% ---- Stage 3: spectral subtraction using the ambient pre-roll -----------
stageTimer = tic;
[y, noiseInfo] = spectral_subtract_noise(y, fsOut, params.noise);
timings.Noise = toc(stageTimer);

% ---- Stage 4: hybrid endpoint detection --------------------------------
stageTimer = tic;
[y, endpointInfo] = hybrid_endpoint_detect(y, fsOut, params.endpoint);
timings.Endpoint = toc(stageTimer);

diag = struct( ...
    'Resample', resampleInfo, ...
    'Agc', agcInfo, ...
    'Noise', noiseInfo, ...
    'Endpoint', endpointInfo, ...
    'AgcSpeech', struct(), ...
    'Liveness', struct(), ...
    'Quality', rawQuality, ...
    'LowFrequencyRatio', NaN, ...
    'Rejected', false, ...
    'Reason', '', ...
    'Stage', '');

if ~endpointInfo.HasSpeech
    diag.Rejected = true;
    diag.Stage = 'Endpoint';
    diag.Reason = ['No speech detected. No frame passed both the short-time ' ...
        'energy threshold and the zero-crossing-rate band for long enough ' ...
        'to be a spoken sound.'];
    diag.Liveness = struct('Ratio',NaN,'Rejected',true,'Reason','Not evaluated.');
    timings.Total = toc(totalTimer); diag.Timings = timings;
    return;
end

% ---- Stage 5: speech-level automatic gain control ----------------------
stageTimer = tic;
[y, agcSpeechInfo] = agc_normalize(y, params.agc);
timings.AgcSpeech = toc(stageTimer);
diag.AgcSpeech = agcSpeechInfo;

% ---- Stage 6: sub-200 Hz liveness / replay detection -------------------
stageTimer = tic;
if params.liveness.Enable
    [livenessReject, ratio, livenessInfo] = check_liveness_lowfreq(y, fsOut, params.liveness);
else
    livenessReject = false;
    ratio = NaN;
    livenessInfo = struct('Ratio',NaN,'Rejected',false,'Reason','Liveness check disabled.');
end

diag.Liveness = livenessInfo;
timings.Liveness = toc(stageTimer);
diag.LowFrequencyRatio = ratio;

if livenessReject
    diag.Rejected = true;
    diag.Stage = 'Liveness';
    diag.Reason = livenessInfo.Reason;
end
timings.Total = toc(totalTimer); diag.Timings = timings;
end

% -------------------------------------------------------------------------
function [y, fsOut, diag] = rejected_result(params, reason, stage)
y = zeros(0,1);
fsOut = params.processingFs;
endpoint = struct('HasSpeech',false,'StartSample',1,'EndSample',0);
liveness = struct('Ratio',NaN,'Rejected',true,'Reason',reason);
diag = struct('Resample',struct(),'Agc',struct(),'Noise',struct(), ...
    'Endpoint',endpoint,'AgcSpeech',struct(),'Liveness',liveness, ...
    'Quality',liveness,'LowFrequencyRatio',NaN,'Rejected',true, ...
    'Reason',reason,'Stage',stage);
end
