function [y, info] = agc_normalize(x, opts)
%AGC_NORMALIZE Root-mean-square automatic gain control.
%
%   [Y, INFO] = AGC_NORMALIZE(X, OPTS) scales the discrete-time signal X so
%   that its root-mean-square amplitude equals OPTS.TargetRms.
%
%   Proposal modification 1b.  EEE 312 Experiment 1 (amplitude operations on
%   discrete-time signals).
%
%   Why RMS and not peak normalisation
%   ----------------------------------
%   The senior baseline normalised inside framing.m with
%
%       y = y / max(abs(y));
%
%   That divides by a single sample.  One dropped tray, one microphone bump or
%   one clipped sample sets the gain for the entire utterance, and every
%   subsequent energy threshold moves with it.  RMS normalisation uses
%
%       g = TargetRms / sqrt( (1/N) sum x[n]^2 )
%
%   which is driven by the mean square, i.e. by the whole signal, and is
%   therefore insensitive to isolated outliers.  Because a student may stand
%   anywhere from 5 cm to 50 cm from the counter microphone -- roughly a 20 dB
%   spread in received level -- this stage is what stops microphone distance
%   from appearing as a false rejection.
%
%   The gain is capped at OPTS.MaxGain so that a recording containing only
%   room noise is not amplified into apparent speech, and a peak limiter is
%   applied afterwards so that the scaled signal cannot exceed OPTS.Headroom.
%
%   INFO reports InputRms, Gain, OutputRms, Limited and Silent.
%
%   See also PREPROCESS_AUDIO, DSP_PARAMETERS.

if nargin < 2, opts = struct(); end
if ~isfield(opts,'TargetRms'), opts.TargetRms = 0.05; end
if ~isfield(opts,'MaxGain'),   opts.MaxGain   = 40;   end
if ~isfield(opts,'MinRms'),    opts.MinRms    = 1e-5; end
if ~isfield(opts,'Headroom'),  opts.Headroom  = 0.99; end
if ~isfield(opts,'Enable'),    opts.Enable    = true; end

x = double(x(:));
info = struct('InputRms',0,'Gain',1,'OutputRms',0,'Limited',false,'Silent',true);

if isempty(x)
    y = zeros(0,1);
    return;
end

% Remove any DC offset first: a constant term inflates the mean square
% without carrying speech information, which would bias the gain downwards.
x = x - mean(x);

inputRms = sqrt(mean(x.^2));
info.InputRms = inputRms;

% The ablation keeps DC removal identical and disables only level control.
if ~opts.Enable
    y = x;
    info.OutputRms = inputRms;
    info.Silent = inputRms < opts.MinRms;
    return;
end

if inputRms < opts.MinRms
    % Effectively silent. Return unscaled so the endpoint detector can report
    % "no speech" rather than being handed amplified noise.
    y = x;
    info.OutputRms = inputRms;
    return;
end

info.Silent = false;
gain = min(opts.TargetRms / inputRms, opts.MaxGain);
y = gain * x;

peak = max(abs(y));
if peak > opts.Headroom
    y = y * (opts.Headroom / peak);
    gain = gain * (opts.Headroom / peak);
    info.Limited = true;
end

info.Gain = gain;
info.OutputRms = sqrt(mean(y.^2));
end
