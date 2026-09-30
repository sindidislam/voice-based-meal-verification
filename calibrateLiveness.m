function model = calibrateLiveness(liveDir, replayDir, outFile)
%CALIBRATELIVENESS Train shrinkage LDA liveness model for replay attack rejection.
%   MODEL = CALIBRATELIVENESS(LIVEDIR, REPLAYDIR, OUTFILE)
%   Uses Fisher Linear Discriminant Analysis with covariance shrinkage
%   to separate genuine live speech from loudspeaker replay captures.

if nargin < 3 || isempty(outFile)
    currDir = fileparts(mfilename('fullpath'));
    outFile = fullfile(currDir, 'LivenessModel.mat');
end

featNames = {'LowBandRatio_dB', 'HighBandRatio_dB', 'SpectralRipple', ...
             'ModulationDepth', 'SilenceTilt_dB', 'CQCCQuefRatio', ...
             'UltraBandRatio_dB', 'HighSlope_dBkHz'};
numFeats = numel(featNames);

hasLive = (nargin >= 1 && ~isempty(liveDir) && isfolder(liveDir));
hasReplay = (nargin >= 2 && ~isempty(replayDir) && isfolder(replayDir));

if hasLive && hasReplay
    fprintf('Calibrating Liveness Model from measured audio folders...\n');
    % Extract features from files
    lFiles = dir(fullfile(liveDir, '*.wav'));
    rFiles = dir(fullfile(replayDir, '*.wav'));
    
    Xl = []; Xr = [];
    for k = 1:numel(lFiles)
        try
            [a, fs] = audioread(fullfile(liveDir, lFiles(k).name));
            [fv, ~] = livenessFeatures(a, fs);
            if ~any(isnan(fv(1:4))), Xl = [Xl; fv]; end %#ok<AGROW>
        catch
        end
    end
    for k = 1:numel(rFiles)
        try
            [a, fs] = audioread(fullfile(replayDir, rFiles(k).name));
            [fv, ~] = livenessFeatures(a, fs);
            if ~any(isnan(fv(1:4))), Xr = [Xr; fv]; end %#ok<AGROW>
        catch
        end
    end
else
    Xl = []; Xr = [];
end

if size(Xl, 1) >= 5 && size(Xr, 1) >= 5
    % Fit Shrinkage LDA
    lambda = 0.25;
    A = Xl; B = Xr;
    mu = mean([A; B], 1);
    sigma = std([A; B], 0, 1); sigma(sigma < 1e-6) = 1e-6;
    Az = (A - mu) ./ sigma; Bz = (B - mu) ./ sigma;
    mA = mean(Az, 1); mB = mean(Bz, 1);
    Sw = (cov(Az)*(size(Az,1)-1) + cov(Bz)*(size(Bz,1)-1)) / (size(Az,1) + size(Bz,1) - 2);
    Sw = (1 - lambda) * Sw + lambda * eye(size(Sw));
    w = (Sw \ (mA - mB).').';
    w = w / (norm(w) + eps);
    if mean(Az * w.') < mean(Bz * w.'), w = -w; end
    pA = Az * w.'; pB = Bz * w.';
    offset = (mean(pA) + mean(pB)) / 2;
    scale  = max((mean(pA) - mean(pB)) / 4, 1e-3);
    threshold = 0.50;
    active = true(1, numFeats);
else
    % Principled physical prior weights (LowBandRatio, HighBandRatio, UltraBandRatio positive for live;
    % SpectralRipple negative for live because replay adds comb ripple).
    active = true(1, numFeats);
    w = [2.2, 1.8, -1.5, 1.2, 0.8, 1.0, 2.5, 1.4];
    w = w / norm(w);
    mu = [-5.0, -18.0, 2.2, 0.45, -2.5, 0.35, -22.0, -1.8];
    sigma = [4.0, 5.0, 0.8, 0.15, 1.5, 0.15, 6.0, 0.8];
    offset = 0.0;
    scale = 1.0;
    threshold = 0.45;
end

model = struct('FeatureNames', {featNames}, 'Active', active, 'W', w, 'Mu', mu, ...
               'Sigma', sigma, 'Offset', offset, 'Scale', scale, 'Threshold', threshold, ...
               'BuildDate', datestr(now)); %#ok<TNOW1,DATST>

LivenessModel = model; %#ok<NASGU>
save(outFile, 'LivenessModel');
fprintf('Liveness Shrinkage LDA Model saved to: %s\n', outFile);
end
