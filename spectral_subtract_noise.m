function [y, info] = spectral_subtract_noise(x, fs, opts)
%SPECTRAL_SUBTRACT_NOISE Magnitude spectral subtraction using a noise pre-roll.
%
%   [Y, INFO] = SPECTRAL_SUBTRACT_NOISE(X, FS, OPTS) removes stationary
%   background noise from X by estimating the noise power spectrum from the
%   first OPTS.NoiseDuration seconds and subtracting it in the STFT domain.
%
%   Proposal modification 3.  EEE 312 Experiment 4 (DFT, spectral analysis and
%   overlap-add reconstruction).
%
%   Why this replaces pre-emphasis
%   ------------------------------
%   The senior baseline began with a pre-emphasis filter, 1 - alpha*z^-1 with
%   alpha = 0.99, a first-order high-pass whose gain rises at 6 dB per octave.
%   Its textbook justification is to flatten the -6 dB/octave roll-off of the
%   glottal source.  In a dining hall the interference is broadband clatter,
%   cutlery and overlapping conversation, so that same rising response
%   amplifies the noise at least as much as the speech.  The proposal discards
%   it and instead measures what the noise actually is and takes it away.
%
%   The algorithm
%   -------------
%   For every analysis frame, with Y[k] the noisy spectrum and N[k] the
%   averaged noise power estimate,
%
%       |Xhat[k]|^2 = max( |Y[k]|^2 - alpha_os * |N[k]|^2 ,
%                          beta * |N[k]|^2 )
%
%   and the phase of Y[k] is retained unchanged.  Keeping the noisy phase is
%   standard and is not a compromise here: the ear is insensitive to absolute
%   phase, and the downstream feature front-end discards phase entirely.
%
%   The two constants
%   -----------------
%   alpha_os (OPTS.Oversubtraction) exceeds one because the noise estimate is
%   an average.  Roughly half the frames sit above that average, and in those
%   frames subtracting only the mean leaves residual noise behind.
%   Oversubtracting removes the residual at the price of some speech
%   distortion; 2.0 is the usual compromise.
%
%   beta (OPTS.SpectralFloor) is the spectral floor and it is what prevents
%   "musical noise".  Without it, the max() clips negative results to exactly
%   zero, so isolated bins survive as narrow spectral spikes that appear and
%   vanish frame to frame -- audible as random tones.  Leaving a small
%   proportion of the noise floor in place keeps the residual smooth and
%   noise-like instead.
%
%   Reconstruction
%   --------------
%   The half-spectrum is mirrored with conjugate symmetry so the inverse DFT is
%   exactly real, and the frames are recombined by weighted overlap-add: each
%   output sample is divided by the sum of the squared window values that
%   contributed to it, which makes the analysis-synthesis pair exact when no
%   modification is applied.
%
%   INFO reports NoiseFrames, NoiseDurationUsed, NFFT, FrameLength, HopLength
%   and Skipped, plus NoiseMagnitude and Frequency -- the estimated noise
%   magnitude spectrum that was actually subtracted, on its frequency axis, for
%   MEAL_VERIFICATION_GUI to display.  Both are empty when the stage was skipped.
%
%   See also PREPROCESS_AUDIO, DSP_PARAMETERS, MEAL_VERIFICATION_GUI.

if nargin < 3, opts = struct(); end
if ~isfield(opts,'NoiseDuration'),   opts.NoiseDuration   = 0.50;  end
if ~isfield(opts,'FrameDuration'),   opts.FrameDuration   = 0.032; end
if ~isfield(opts,'Oversubtraction'), opts.Oversubtraction = 2.0;   end
if ~isfield(opts,'SpectralFloor'),   opts.SpectralFloor   = 0.02;  end
if ~isfield(opts,'Enable'),          opts.Enable          = true;  end
if ~isfield(opts,'Method'),          opts.Method          = 'spectral'; end
method = validatestring(opts.Method, {'none','spectral','wiener'});

x = double(x(:));
N = max(16, round(opts.FrameDuration * fs));

% Hop may be given directly or as a fraction of the window length. A quarter
% window is used by default: with a Hann window that satisfies the
% overlap-add condition comfortably and gives four independent noise estimates
% per window length.
if isfield(opts,'HopDuration') && ~isempty(opts.HopDuration)
    H = max(1, round(opts.HopDuration * fs));
else
    frac = 0.25;
    if isfield(opts,'HopFraction') && ~isempty(opts.HopFraction)
        frac = opts.HopFraction;
    end
    H = max(1, round(frac * N));
end

nfft = 2^nextpow2(N);
% NoiseMagnitude and Frequency are initialised empty rather than omitted: the
% enable-off and empty-input branches below return early, and a caller that plots
% info.NoiseMagnitude must get an empty vector to plot, not an undefined field.
info = struct('NoiseFrames',0,'NoiseDurationUsed',0,'NFFT',nfft, ...
    'FrameLength',N,'HopLength',H,'Skipped',false, ...
    'NoiseMagnitude',zeros(0,1),'Frequency',zeros(0,1),'Method',method);

if isempty(x)
    y = zeros(0,1);
    info.Skipped = true;
    return;
end

if ~opts.Enable || strcmp(method,'none')
    y = x;
    info.Skipped = true;
    return;
end

if numel(x) < N
    x = [x; zeros(N - numel(x), 1)];
end

nFrames = 1 + ceil((numel(x) - N) / H);
pad = (nFrames - 1) * H + N - numel(x);
xp = [x; zeros(pad, 1)];

win = 0.5 - 0.5 * cos(2 * pi * (0:N-1)' / (N-1));   % Hann
frames = zeros(N, nFrames);
for k = 1:nFrames
    idx = (1:N) + (k - 1) * H;
    frames(:,k) = xp(idx) .* win;
end

X = fft(frames, nfft, 1);
K = floor(nfft / 2) + 1;

% ---- Noise profile from the pre-roll ------------------------------------
% Averaging over this many frames is what makes the estimate usable: the
% periodogram of a single frame has a standard deviation as large as its mean,
% so a 0.5 s pre-roll at this hop gives enough frames to average that variance
% down to a few per cent.
noiseFrames = max(1, min(nFrames, floor(opts.NoiseDuration * fs / H) + 1));
noisePow = mean(abs(X(1:K, 1:noiseFrames)).^2, 2);
info.NoiseFrames = noiseFrames;
info.NoiseDurationUsed = min(numel(x), noiseFrames * H) / fs;

% The profile itself, on a frequency axis, so that MEAL_VERIFICATION_GUI can draw
% the spectrum this function actually subtracted rather than re-estimating it from
% the pre-roll with a second, slightly different periodogram. A display that
% recomputes what it claims to be showing can agree with the algorithm by accident
% and disagree with it by accident, and neither is visible to the reader.
info.NoiseMagnitude = sqrt(noisePow);
info.Frequency = (0:K-1)' * fs / nfft;

mag = abs(X(1:K,:));
phase = angle(X(1:K,:));

if strcmp(method,'wiener')
    % A stationary Wiener estimate shares the measured pre-roll, frames and
    % overlap-add with subtraction. No learned model or test-set fitting.
    signalPow = max(mag.^2 - noisePow, 0);
    gain = signalPow ./ max(signalPow + noisePow, eps);
    gain = max(gain, sqrt(opts.SpectralFloor));
    cleanPow = (gain .* mag).^2;
else
    cleanPow = max(mag.^2 - opts.Oversubtraction * noisePow, ...
                   opts.SpectralFloor * noisePow);
end

% ---- Hermitian-symmetric reconstruction ---------------------------------
Ypos = sqrt(cleanPow) .* exp(1i * phase);
Y = zeros(nfft, nFrames);
Y(1:K,:) = Ypos;
if rem(nfft,2) == 0
    Y(K+1:end,:) = conj(Ypos(end-1:-1:2,:));
else
    Y(K+1:end,:) = conj(Ypos(end:-1:2,:));
end

% ---- Weighted overlap-add ------------------------------------------------
out = zeros(size(xp));
normW = zeros(size(xp));
for k = 1:nFrames
    frame = real(ifft(Y(:,k), nfft));
    idx = (1:N) + (k - 1) * H;
    out(idx) = out(idx) + frame(1:N) .* win;
    normW(idx) = normW(idx) + win.^2;
end

out = out ./ max(normW, eps);
y = out(1:numel(x));
end
