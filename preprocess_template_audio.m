function [y, fsOut, diagnostics] = preprocess_template_audio(x, fsIn, params)
%PREPROCESS_TEMPLATE_AUDIO Condition a stored enrolment template.
%
%   [Y, FSOUT, DIAGNOSTICS] = PREPROCESS_TEMPLATE_AUDIO(X, FSIN, PARAMS)
%   applies the same conditioning chain as PREPROCESS_AUDIO, but adapted to the
%   fact that a stored WAV may or may not contain the ambient pre-roll that
%   spectral subtraction and the endpoint detector want to learn from.
%
%   The two template modes
%   ----------------------
%   'RawWithQuietLeadIn'
%       The file begins with ambient noise, because it was recorded by
%       RECORD_CORPUS_TOOL or by the enrolment tab, both of which enforce a
%       0.5 s silent lead-in.  Such a file is passed through the full
%       PREPROCESS_AUDIO chain unchanged, so enrolment and verification see
%       bit-identical processing.
%
%   'LegacyCropped'
%       The file was already trimmed to the spoken word by the earlier version
%       of the system, so its first samples ARE speech.  Two adaptations follow:
%
%         - Spectral subtraction is disabled.  Estimating the noise spectrum
%           from the first frames of such a file would take the speech onset as
%           the noise profile and then subtract the talker from the talker.
%
%         - The endpoint detector falls back to its percentile noise estimator
%           automatically, because its pre-roll test fails.
%
%   Why the liveness gate is advisory for legacy templates
%   ------------------------------------------------------
%   The sub-200 Hz ratio is a property of the recording chain as much as of the
%   talker, and the legacy corpus was captured on a mixture of laptop and phone
%   microphones months before the gate existed.  Enforcing it retrospectively
%   discards good enrolment data: the previous revision of this system rejected
%   21 of the 123 stored files that way, including five of the six files
%   belonging to one student, which left that student unable to be recognised at
%   all.  Liveness is a defence against a LIVE replay attack at the counter, so
%   it is enforced where the attack happens -- on live capture -- and merely
%   recorded as a diagnostic on archived files.  Set
%   PARAMS.enforceLivenessOnTemplates to true to override this.
%
%   See also PREPROCESS_AUDIO, DIAGNOSE_AUDIO_CORPUS, RECORD_CORPUS_TOOL.

if nargin < 3 || isempty(params), params = dsp_parameters(); end
totalTimer = tic;
timings = struct('Resample',0,'Agc',0,'Noise',0,'Endpoint',0, ...
    'AgcSpeech',0,'Liveness',0,'Total',0);
if size(x, 2) > 1, x = mean(x, 2); end
rawQuality = assess_raw_audio_quality(x,fsIn,params);

enforceLiveness = false;
if isfield(params,'enforceLivenessOnTemplates')
    enforceLiveness = params.enforceLivenessOnTemplates;
end

if ~rawQuality.Valid
    [y, fsOut, diagnostics] = invalid_result(params.processingFs, ...
        'Template audio is empty or non-finite.');
    diagnostics.Quality = rawQuality;
    timings.Total = toc(totalTimer); diagnostics.Timings = timings;
    return;
end

% ---- Rate conversion and capture-level gain ----------------------------
stageTimer = tic;
[y, fsOut, resampleInfo] = rational_resample_audio(x, fsIn, params.processingFs, params.resample);
timings.Resample = toc(stageTimer);
stageTimer = tic;
[y, agcInfo] = agc_normalize(y, params.agc);
timings.Agc = toc(stageTimer);

if isempty(y)
    [y, fsOut, diagnostics] = invalid_result(params.processingFs, ...
        'Template audio is empty after resampling.');
    diagnostics.Quality = rawQuality;
    timings.Total = toc(totalTimer); diagnostics.Timings = timings;
    return;
end

% ---- Decide which mode this template is in -----------------------------
leadSamples = min(numel(y), max(1, round(params.noise.NoiseDuration * fsOut)));
fullRms = sqrt(mean(y.^2));
leadRms = sqrt(mean(y(1:leadSamples).^2));
leadRatio = leadRms / (fullRms + eps);
hasQuietLeadIn = numel(y) > leadSamples * 1.5 && leadRatio < params.templateQuietLeadInRatio;

if hasQuietLeadIn
    % Identical treatment to a live capture.
    [y, fsOut, diagnostics] = preprocess_audio(y, fsOut, params);
    diagnostics.Quality = rawQuality;
    diagnostics.Timings.Resample = diagnostics.Timings.Resample + timings.Resample;
    diagnostics.Timings.Agc = diagnostics.Timings.Agc + timings.Agc;
    diagnostics.Timings.Total = toc(totalTimer);
    diagnostics.TemplateMode = 'RawWithQuietLeadIn';
    diagnostics.QuietLeadInRatio = leadRatio;
    return;
end

% ---- Legacy cropped path ------------------------------------------------
legacyNoise = params.noise;
legacyNoise.Enable = false;                  % See the header comment.
stageTimer = tic;
[y, noiseInfo] = spectral_subtract_noise(y, fsOut, legacyNoise);
timings.Noise = toc(stageTimer);

stageTimer = tic;
[y, endpointInfo] = hybrid_endpoint_detect(y, fsOut, params.endpoint);
timings.Endpoint = toc(stageTimer);

diagnostics = struct( ...
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
    'Stage', '', ...
    'TemplateMode', 'LegacyCropped', ...
    'QuietLeadInRatio', leadRatio);

durationOk = numel(y) >= round(params.dft.FrameDuration * fsOut);
if ~endpointInfo.HasSpeech || ~durationOk || fullRms < params.templateMinimumRms
    diagnostics.Rejected = true;
    diagnostics.Stage = 'Endpoint';
    diagnostics.Reason = sprintf( ...
        'Template unusable: RMS %.3g (minimum %.3g), %d samples of speech found.', ...
        fullRms, params.templateMinimumRms, numel(y));
    diagnostics.Liveness = struct('Ratio',NaN,'Rejected',true,'Reason','Not evaluated.');
    timings.Total = toc(totalTimer); diagnostics.Timings = timings;
    return;
end

stageTimer = tic;
[y, agcSpeechInfo] = agc_normalize(y, params.agc);
timings.AgcSpeech = toc(stageTimer);
diagnostics.AgcSpeech = agcSpeechInfo;

stageTimer = tic;
[livenessReject, ratio, livenessInfo] = check_liveness_lowfreq(y, fsOut, params.liveness);
timings.Liveness = toc(stageTimer);
diagnostics.Liveness = livenessInfo;
diagnostics.LowFrequencyRatio = ratio;

if livenessReject
    if enforceLiveness
        diagnostics.Rejected = true;
        diagnostics.Stage = 'Liveness';
        diagnostics.Reason = livenessInfo.Reason;
    else
        diagnostics.Reason = ['Advisory only (archived template): ' livenessInfo.Reason];
    end
end
timings.Total = toc(totalTimer); diagnostics.Timings = timings;
end

% -------------------------------------------------------------------------
function [y, fsOut, diagnostics] = invalid_result(fsOut, reason)
y = zeros(0,1);
endpoint = struct('HasSpeech',false,'StartSample',1,'EndSample',0);
liveness = struct('Ratio',NaN,'Rejected',true,'Reason',reason);
diagnostics = struct('Resample',struct(),'Agc',struct(),'Noise',struct(), ...
    'Endpoint',endpoint,'AgcSpeech',struct(),'Liveness',liveness, ...
    'Quality',liveness,'LowFrequencyRatio',NaN,'Rejected',true, ...
    'Reason',reason,'Stage','Input','TemplateMode','Invalid', ...
    'QuietLeadInRatio',NaN);
end
