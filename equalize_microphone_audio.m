function [equalizedAudio, profile] = equalize_microphone_audio(audio, fs, profilePath)
% EQUALIZE_MICROPHONE_AUDIO Equalize live audio using calibrated microphone profile
%
%   [EQUALIZEDAUDIO, PROFILE] = EQUALIZE_MICROPHONE_AUDIO(AUDIO, FS, PROFILEPATH)
%   Applies an acoustic channel equalization filter to AUDIO to compensate for
%   microphone frequency response variations relative to the training corpus.
%   If no calibration file exists or AUDIO is silent, returns AUDIO unchanged.

if nargin < 2 || isempty(fs), fs = 8000; end
if nargin < 3 || isempty(profilePath), profilePath = 'mic_calibration.mat'; end

profile = [];
equalizedAudio = audio;

if isempty(audio)
    return;
end

% Ensure mono column vector
if size(audio, 2) > 1
    audio = mean(audio, 2);
end
audio = double(audio(:));

% Check if calibration file exists
if ~isfile(profilePath)
    equalizedAudio = audio;
    return;
end

try
    calib = load(profilePath);
    if isfield(calib, 'profile')
        profile = calib.profile;
    elseif isfield(calib, 'eqFilter')
        profile = calib;
    else
        equalizedAudio = audio;
        return;
    end
    
    if isfield(profile, 'eqFilter') && ~isempty(profile.eqFilter) && isfield(profile, 'fs') && profile.fs == fs
        b = profile.eqFilter;
        % Apply FIR equalization filter with group delay compensation
        filterDelay = floor((length(b) - 1) / 2);
        paddedAudio = [audio; zeros(filterDelay, 1)];
        filtered = filter(b, 1, paddedAudio);
        if length(filtered) >= filterDelay + length(audio)
            equalizedAudio = filtered(filterDelay + 1 : filterDelay + length(audio));
        else
            equalizedAudio = filtered(1:min(length(filtered), length(audio)));
        end
    else
        equalizedAudio = audio;
    end
catch
    equalizedAudio = audio;
end
end
