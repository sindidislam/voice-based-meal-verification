function [reject, ratio, info] = check_liveness_lowfreq(x, fs, opts)
%CHECK_LIVENESS_LOWFREQ Replay-attack detection from the sub-200 Hz band.
%
%   [REJECT, RATIO, INFO] = CHECK_LIVENESS_LOWFREQ(X, FS, OPTS) estimates the
%   fraction of the speech-band energy of X that lies below 200 Hz and decides
%   whether the capture is a live talker or a loudspeaker playback.
%
%   Proposal modification 2, Goal 5.  EEE 312 Experiment 4 (DFT and band
%   energy estimation).
%
%   The physical principle
%   ----------------------
%   A meal coupon is worth money, so the obvious attack is for one student to
%   record a friend saying their name and code and to play it back at the
%   counter from a phone.  A phone or laptop loudspeaker is a driver a few
%   millimetres across in a sealed plastic body.  Its low-frequency output
%   falls away steeply below roughly 300 Hz because it cannot displace enough
%   air, so the glottal fundamental of the original talker -- 85 to 180 Hz for
%   the students in this group -- simply is not reproduced.  A live talker
%   standing at the microphone radiates that fundamental directly.
%
%   The discriminating statistic is therefore the band-energy ratio
%
%       r = sum_{f in [20,200]} P(f)  /  sum_{f in [20,3800]} P(f)
%
%   and live speech has a LARGER r than a replay.  The decision is a lower
%   bound: reject when r < MinRatio.  An upper bound is also applied, because
%   r approaching one means the capture is dominated by rumble, a slammed door
%   or wind on the microphone rather than by speech.  Both bounds together form
%   the two-sided acceptance band
%
%       MinRatio <= r <= MaxRatio.
%
%   Two implementation points that matter
%   -------------------------------------
%   1. The ratio is measured over the WHOLE detected speech region, not over a
%      short prefix.  One glottal cycle at 120 Hz lasts about 8 ms, so a 50 ms
%      window spans only six cycles and the resulting estimate has enormous
%      variance -- large enough to swamp the live/replay difference it is
%      supposed to measure.  Averaging the periodogram over every frame of the
%      utterance (Welch's method) reduces that variance in proportion to the
%      number of frames.
%
%   2. The low band starts at 20 Hz rather than at DC.  Mains hum, HVAC rumble
%      and the DC offset of the sound card all sit below 20 Hz and are common
%      to live and replayed captures, so including them would add a bias that
%      carries no discriminative information.
%
%   INFO fields: Ratio, MinRatio, MaxRatio, LowEnergy, FullEnergy, NumFrames,
%   Duration, Rejected, Reason, Spectrum, Frequency.
%
%   See also PREPROCESS_AUDIO, CALIBRATE_LIVENESS_BAND, DSP_PARAMETERS.

if nargin < 3, opts = struct(); end
if ~isfield(opts,'LowBand'),      opts.LowBand      = [20 200];   end
if ~isfield(opts,'FullBand'),     opts.FullBand     = [20 3800];  end
if ~isfield(opts,'MinRatio'),     opts.MinRatio     = 0.0015;     end
if ~isfield(opts,'MaxRatio'),     opts.MaxRatio     = 0.60;       end
if ~isfield(opts,'MinDuration'),  opts.MinDuration  = 0.15;       end
if ~isfield(opts,'CentroidBand'), opts.CentroidBand = [150 3500]; end
if ~isfield(opts,'MaxCentroid'),  opts.MaxCentroid  = 1200;       end

x = double(x(:));
info = struct('Ratio',NaN,'MinRatio',opts.MinRatio,'MaxRatio',opts.MaxRatio, ...
    'LowEnergy',NaN,'FullEnergy',NaN,'NumFrames',0,'Duration',0, ...
    'SpectralCentroid',NaN,'MaxCentroid',opts.MaxCentroid, ...
    'Rejected',true,'Reason','','Spectrum',[],'Frequency',[]);

if isempty(x) || ~all(isfinite(x))
    reject = true;
    ratio = NaN;
    info.Reason = 'Empty or non-finite audio.';
    return;
end

info.Duration = numel(x) / fs;
if info.Duration < opts.MinDuration
    reject = true;
    ratio = NaN;
    info.Reason = sprintf('Only %.0f ms of speech; %.0f ms needed to judge liveness.', ...
        info.Duration*1000, opts.MinDuration*1000);
    return;
end

% ---- Averaged periodogram over the whole speech region -------------------
% A 64 ms window gives a bin spacing of about 15.6 Hz, so the 20-200 Hz band
% is resolved by roughly a dozen bins -- enough to separate the fundamental
% region from the first formant without smearing across the 200 Hz edge.
frameLen = min(numel(x), max(256, 2^nextpow2(round(0.064*fs))));
hopLen   = max(1, round(frameLen/2));
nfft     = 2^nextpow2(frameLen);
w        = 0.5 - 0.5*cos(2*pi*(0:frameLen-1)'/(frameLen-1));   % Hann
windowPower = sum(w.^2);

numFrames = max(1, 1 + floor((numel(x) - frameLen) / hopLen));
P = zeros(nfft/2 + 1, 1);
for k = 1:numFrames
    idx = (k-1)*hopLen + (1:frameLen);
    idx = idx(idx <= numel(x));
    f = zeros(frameLen,1);
    f(1:numel(idx)) = x(idx);
    f = f - mean(f);                     % Remove DC before the transform.
    F = fft(f .* w, nfft);
    Pk = abs(F(1:nfft/2+1)).^2 / windowPower;
    P = P + Pk;
end
P = P / numFrames;

freq = (0:nfft/2)' * fs / nfft;
info.NumFrames = numFrames;
info.Spectrum = P;
info.Frequency = freq;

lowMask  = freq >= opts.LowBand(1)  & freq <= min(opts.LowBand(2),  fs/2);
fullMask = freq >= opts.FullBand(1) & freq <= min(opts.FullBand(2), fs/2);

lowEnergy  = sum(P(lowMask));
fullEnergy = sum(P(fullMask));

centMask = freq >= opts.CentroidBand(1) & freq <= min(opts.CentroidBand(2), fs/2);
centPwr = sum(P(centMask));
if any(centMask) && centPwr > eps
    centroid = sum(freq(centMask) .* P(centMask)) / centPwr;
else
    centroid = 0;
end
info.SpectralCentroid = centroid;

info.LowEnergy = lowEnergy;
info.FullEnergy = fullEnergy;

if fullEnergy <= eps
    reject = true;
    ratio = NaN;
    info.Reason = 'No measurable energy in the speech band.';
    return;
end

ratio = lowEnergy / fullEnergy;
info.Ratio = ratio;

if ratio < opts.MinRatio
    reject = true;
    info.Reason = sprintf(['Sub-200 Hz energy ratio %.4f is below the configured ' ...
        'minimum %.4f. Replay attack detected.'], ratio, opts.MinRatio);
elseif ratio > opts.MaxRatio
    reject = true;
    info.Reason = sprintf(['Sub-200 Hz energy ratio %.4f exceeds %.4f: the capture ' ...
        'is dominated by low-frequency rumble rather than speech.'], ...
        ratio, opts.MaxRatio);
elseif centroid > opts.MaxCentroid
    reject = true;
    info.Reason = sprintf(['Spectral centroid %.0f Hz exceeds %.0f Hz: loudspeaker playback ' ...
        'replay attack detected.'], centroid, opts.MaxCentroid);
else
    reject = false;
end

info.Rejected = reject;
end
