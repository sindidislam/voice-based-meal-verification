function q = assess_raw_audio_quality(audio, fs, params)
%ASSESS_RAW_AUDIO_QUALITY Observe the raw capture before gain or filtering.
% This function measures only. Acceptance remains in ASSESS_RECORDING_QUALITY.
q = struct('Valid',false,'OverallRms',NaN,'AcRms',NaN,'PreRollRms',NaN, ...
    'ClippedFraction',NaN,'ClippedRun',0,'Clipped',false);
if isempty(audio) || ~isnumeric(audio) || ~isreal(audio) || ...
        any(~isfinite(audio(:))) || ~isnumeric(fs) || ~isscalar(fs) || ~isreal(fs) || ...
        ~isfinite(fs) || fs <= 0
    return;
end
if size(audio, 2) > 1, audio = mean(audio, 2); end
audio = double(audio(:));
n = min(numel(audio),max(1,round(params.noise.NoiseDuration*fs)));
q.OverallRms = sqrt(mean(audio.^2));
q.AcRms = sqrt(mean((audio-mean(audio)).^2));
q.PreRollRms = sqrt(mean(audio(1:n).^2));
pinned = abs(audio) > .99;
q.ClippedFraction = mean(pinned);
if any(pinned)
    edges = diff([false;pinned;false]);
    q.ClippedRun = max(find(edges == -1)-find(edges == 1));
end
q.Clipped = q.ClippedRun >= 10 || q.ClippedFraction > 1e-3;
q.Valid = true;
end
