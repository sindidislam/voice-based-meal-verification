function [pitch, spectral] = mfcc_auxiliary_features(frames, magnitude, fs, nfft, opts)
%MFCC_AUXILIARY_FEATURES Small, opt-in frame-aligned acoustic descriptors.
% Pitch: log2(F0/150 Hz), zero for unvoiced frames; correlation confidence.
% Spectral: centroid/Nyquist, 85%-power rolloff/Nyquist, flatness.
% No learned scaling: MFCC block weights are explicit experiment parameters.
nf = size(frames,2); n = size(frames,1);
pitch = zeros(2,nf); spectral = zeros(3,nf);
if opts.IncludePitch
    lo = max(1,ceil(fs/400)); hi = min(n-2,floor(fs/70));
    for k = 1:nf
        f = frames(:,k) - mean(frames(:,k));
        if sum(f.^2) <= eps || hi < lo, continue; end
        ac = real(ifft(abs(fft(f,2^nextpow2(2*n-1))).^2));
        lags = lo:hi; corr = zeros(size(lags));
        for j = 1:numel(lags)
            lag = lags(j);
            den = sqrt(sum(f(1:n-lag).^2)*sum(f(lag+1:n).^2));
            corr(j) = ac(lag+1)/max(den,eps);
        end
        peaks = find(corr >= [0 corr(1:end-1)] & corr >= [corr(2:end) 0]);
        if isempty(peaks), continue; end
        best = max(corr(peaks));
        % A negative correlation maximum cannot support a voiced period.
        % Multiplying it by .98 would put the selection threshold ABOVE
        % every peak and produce an empty index.
        if ~isfinite(best) || best <= 0, continue; end
        chosen = peaks(find(corr(peaks) >= .98*best,1));
        confidence = min(1,max(0,corr(chosen)));
        pitch(2,k) = confidence;
        if confidence >= .3
            pitch(1,k) = log2((fs/lags(chosen))/150);
        end
    end
end
if opts.IncludeSpectral
    power = magnitude.^2; frequency = (0:size(power,1)-1)'*fs/nfft;
    for k = 1:nf
        total = sum(power(:,k));
        if total <= eps, continue; end
        spectral(1,k) = sum(frequency.*power(:,k))/total/(fs/2);
        bin = find(cumsum(power(:,k)) >= .85*total,1);
        spectral(2,k) = frequency(bin)/(fs/2);
        spectral(3,k) = exp(mean(log(max(power(:,k),eps))))/max(mean(power(:,k)),eps);
    end
end
end
