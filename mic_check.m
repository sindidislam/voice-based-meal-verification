function info = mic_check(audio, fs, verbose)
%MIC_CHECK Real-time microphone level check, clipping analysis, and SNR diagnostic.
%
%   INFO = MIC_CHECK() records 3.0 seconds live from the default input device
%   and prints an interactive diagnostic verdict.
%
%   INFO = MIC_CHECK(AUDIO, FS, VERBOSE) analyzes supplied audio.
%
%   Verdict categories:
%     'TOO LOUD'  Peak > -0.5 dBFS or Clipped > 0.10% samples.
%     'TOO QUIET' Peak < -20.0 dBFS.
%     'NOISY'     SNR < 18.0 dB (background noise too close to speech).
%     'GOOD'      Optimal level and healthy SNR.

if nargin < 3, verbose = true; end
if nargin < 2 || isempty(fs), fs = 44100; end
if nargin < 1 || isempty(audio)
    try
        recorder = audiorecorder(fs, 16, 1);
        if verbose
            fprintf('\n>>> Recording 3.0 seconds for mic check... Speak your roll number or name at normal volume.\n');
        end
        recordblocking(recorder, 3.0);
        audio = getaudiodata(recorder);
    catch ME
        error('mic_check:deviceError', 'Cannot record from microphone: %s', ME.message);
    end
end

audio = double(audio(:));
if isempty(audio)
    audio = zeros(round(fs * 0.5), 1);
end

win = round(0.020 * fs);
n = floor(numel(audio) / win);
if n < 1
    e = -80;
else
    e = 10 * log10(mean(reshape(audio(1:n*win), win, n).^2, 1) + 1e-12);
end

pk = 20 * log10(max(abs(audio)) + 1e-12);
fl = prctile(e, 10);
sp = prctile(e, 95);
snr = sp - fl;
clipped = mean(abs(audio) >= 0.999) * 100;

if clipped > 0.10 || pk > -0.5
    v = 'TOO LOUD';
    adv = 'Lower the Windows input volume in Sound Settings (by 15-20%) or step slightly back.';
elseif pk < -20.0
    v = 'TOO QUIET';
    adv = 'Raise the input volume in Windows Sound Settings or speak closer to the microphone.';
elseif snr < 18.0
    v = 'NOISY';
    adv = 'High background noise close to speech level. Move away from fans or ambient noise.';
else
    v = 'GOOD';
    adv = 'Microphone level, headroom, and background noise are optimal.';
end

info = struct( ...
    'PeakDbfs', pk, 'PeakDb', pk, ...
    'SpeechDbfs', sp, 'SpeechDb', sp, ...
    'FloorDbfs', fl, 'BackgroundDb', fl, ...
    'SnrDb', snr, ...
    'ClippedPct', clipped, 'ClippedPercent', clipped, ...
    'Verdict', v, 'Advice', adv);

if verbose
    fprintf('\n---------------- MICROPHONE LEVEL CHECK ----------------\n');
    fprintf('  Peak Level       : %6.1f dBFS\n', pk);
    fprintf('  Speech Level     : %6.1f dBFS\n', sp);
    fprintf('  Background Noise : %6.1f dBFS\n', fl);
    fprintf('  Signal-to-Noise  : %6.1f dB\n', snr);
    fprintf('  Clipped Samples  : %6.2f %%\n', clipped);
    fprintf('  VERDICT          : %s\n', v);
    fprintf('  RECOMMENDATION   : %s\n', adv);
    fprintf('--------------------------------------------------------\n\n');
end
end
