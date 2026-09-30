function [isLive, livenessScore, metrics, report] = verifyLiveness(rawAudio, fsRaw, cqccFeatures, modelFile)
%VERIFYLIVENESS Multi-cue replay attack verification on NATIVE-rate audio.
%   [ISLIVE, SCORE, METRICS, REPORT] = VERIFYLIVENESS(RAWAUDIO, FSRAW, CQCC, MODELFILE)
%   computes the 8-cue physical liveness descriptor and evaluates the calibrated
%   shrinkage LDA model.

if nargin < 4 || isempty(modelFile)
    currDir = fileparts(mfilename('fullpath'));
    modelFile = fullfile(currDir, 'LivenessModel.mat');
end

if ~isfile(modelFile)
    % Auto-calibrate baseline if model not present
    calibrateLiveness('', '', modelFile);
end

if nargin < 3, cqccFeatures = []; end

isLive = false;
livenessScore = 0.5;
metrics = struct();

if size(rawAudio, 2) > 1
    x = mean(double(rawAudio), 2);
else
    x = double(rawAudio(:));
end
x = x - mean(x);

metrics.RMS  = sqrt(mean(x.^2));
metrics.Peak = max(abs(x));

if metrics.Peak < 0.01 || metrics.RMS < 0.002 || numel(x) < round(0.20 * fsRaw)
    isLive = false;
    livenessScore = 0;
    report = 'Silence or insufficient audio to assess liveness.';
    return;
end

[featVec, featNames, det] = livenessFeatures(rawAudio, fsRaw, cqccFeatures);
metrics.Features = featVec;
metrics.FeatureNames = featNames;
metrics.Detail = det;

M = load(modelFile);
model = M.LivenessModel;

usable = ~isnan(featVec) & model.Active;
if ~any(usable)
    isLive = false;
    livenessScore = 0;
    report = 'No usable acoustic liveness cues.';
    return;
end

z = (featVec - model.Mu) ./ model.Sigma;
z(~usable) = 0;
proj = sum(model.W(usable) .* z(usable));

livenessScore = 1 / (1 + exp(-(proj - model.Offset) / max(model.Scale, eps)));
isLive = livenessScore >= model.Threshold;

metrics.LivenessScore = livenessScore;
metrics.DecisionThreshold = model.Threshold;

if isLive
    report = sprintf('Acoustics match LIVE speaker (Score = %.3f, Threshold = %.3f)', livenessScore, model.Threshold);
else
    report = sprintf('REPLAY ATTACK DETECTED: Loudspeaker acoustic profile (Score = %.3f < %.3f)', livenessScore, model.Threshold);
end
end
