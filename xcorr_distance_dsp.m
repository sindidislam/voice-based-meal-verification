function [distance, info] = xcorr_distance_dsp(x, y, opts)
%XCORR_DISTANCE_DSP Time-domain cross-correlation distance (baseline method).
%
%   [DISTANCE, INFO] = XCORR_DISTANCE_DSP(X, Y, OPTS) compares two time-domain
%   utterances by normalised cross-correlation and returns
%
%       DISTANCE = 1 - max_l rho[l]
%
%   where rho[l] is the cross-correlation sequence normalised so that
%   rho[l] = 1 for identical signals.  DISTANCE is therefore 0 for a perfect
%   match and approaches 1 for uncorrelated signals.
%
%   Proposal Goal 2.  EEE 312 Experiment 5 (correlation of discrete-time
%   sequences).
%
%   Purpose of this function
%   ------------------------
%   This is deliberately the WEAK method.  It exists so that the claim "DTW on
%   spectral features outperforms time-domain correlation" is measured on the
%   group's own corpus rather than asserted, which is what CO2 asks for --
%   compare theoretical and experimental results of DSP algorithms.
%
%   Why it is expected to fail
%   --------------------------
%   The cross-correlation of two real sequences,
%
%       r_xy[l] = sum_n x[n] y[n-l]
%
%   scanned over lag l, tests one hypothesis: that y is x delayed by a constant
%   l.  That is exactly the wrong model for speech.  Two utterances of the same
%   phrase by the same person differ by a time-VARYING rate -- the speaker
%   lingers on one digit and rushes the next -- so no single lag aligns them.
%   The correlation peak is smeared and reduced, and the genuine speaker looks
%   like an impostor.
%
%   There is a second, independent problem.  Correlation operates on the raw
%   waveform, and the waveform depends on absolute phase.  Two recordings that
%   begin at different points of the glottal cycle have waveforms that differ
%   sample by sample even when their short-time spectra are nearly identical.
%   The DFT front-end used by the DTW path discards phase for exactly this
%   reason; correlation cannot.
%
%   Normalisation
%   -------------
%   Each signal is mean-removed and scaled to unit energy before correlating,
%   so the score measures waveform shape agreement and is not inflated by one
%   recording simply being louder than the other.  Without this the comparison
%   with DTW would be unfair in the opposite direction.
%
%   INFO reports MaxCorrelation, BestLag, BestLagSeconds, LengthX and LengthY.
%
%   See also DTW_DISTANCE_DSP, EXPERIMENT_MATCHER_COMPARISON.

if nargin < 3, opts = struct(); end
if ~isfield(opts,'MaxLagSeconds'), opts.MaxLagSeconds = []; end
if ~isfield(opts,'Fs'),            opts.Fs            = NaN; end

x = double(x(:));
y = double(y(:));
info = struct('MaxCorrelation',NaN,'BestLag',NaN,'BestLagSeconds',NaN, ...
    'LengthX',numel(x),'LengthY',numel(y));

if isempty(x) || isempty(y)
    distance = Inf;
    return;
end

x = x - mean(x);
y = y - mean(y);

ex = sqrt(sum(x.^2));
ey = sqrt(sum(y.^2));
if ex < eps || ey < eps
    distance = Inf;
    return;
end
x = x / ex;
y = y / ey;

% Full cross-correlation via the FFT: linear convolution of x with the
% time-reversed y, zero-padded to avoid circular wrap-around.
nfft = 2^nextpow2(numel(x) + numel(y) - 1);
r = real(ifft(fft(x, nfft) .* conj(fft(y, nfft))));
% Reorder so that index 1 corresponds to the most negative lag.
r = [r(nfft - numel(y) + 2 : nfft); r(1 : numel(x))];
lags = (-(numel(y)-1) : (numel(x)-1))';

if ~isempty(opts.MaxLagSeconds) && isfinite(opts.Fs)
    maxLag = round(opts.MaxLagSeconds * opts.Fs);
    keep = abs(lags) <= maxLag;
    r = r(keep);
    lags = lags(keep);
end

[peak, at] = max(r);
info.MaxCorrelation = peak;
info.BestLag = lags(at);
if isfinite(opts.Fs)
    info.BestLagSeconds = lags(at) / opts.Fs;
end

distance = 1 - peak;
end
