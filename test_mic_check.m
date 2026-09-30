function tests = test_mic_check
tests = functiontests(localfunctions);
end

function testNormalCleanSpeechGivesGoodVerdict(t)
fs = 44100;
% Clean voiced speech signal at ~ -12 dBFS peak, low noise floor
[voice, ~] = synth_voiced_signal(fs, 1.5, [120 155], [550 1550 2600]);
speech = 0.25 * voice(:) / max(abs(voice));
noise = 0.001 * randn(round(0.5 * fs), 1);
audio = [noise; speech; noise];

info = mic_check(audio, fs, false);
verifyEqual(t, info.Verdict, 'GOOD');
verifyGreaterThan(t, info.SnrDb, 20);
verifyLessThan(t, info.ClippedPercent, 0.01);
verifyTrue(t, isfield(info, 'PeakDbfs'));
verifyTrue(t, isfield(info, 'SpeechDbfs'));
verifyTrue(t, isfield(info, 'FloorDbfs'));
verifyTrue(t, isfield(info, 'ClippedPct'));
end

function testClippedAudioGivesTooLoudVerdict(t)
fs = 44100;
% Highly amplified signal with pinned flat tops
[voice, ~] = synth_voiced_signal(fs, 1.5, [120 155], [550 1550 2600]);
speech = 2.5 * voice(:) / max(abs(voice));
audio = min(max(speech, -1.0), 1.0); % Pinned clipping

info = mic_check(audio, fs, false);
verifyEqual(t, info.Verdict, 'TOO LOUD');
verifyGreaterThan(t, info.ClippedPercent, 0.1);
verifyTrue(t, contains(lower(info.Advice), 'lower'));
end

function testAttenuatedSignalGivesTooQuietVerdict(t)
fs = 44100;
% Very quiet speech with peak < -20 dBFS (amplitude 0.04 is -28 dBFS)
[voice, ~] = synth_voiced_signal(fs, 1.5, [120 155], [550 1550 2600]);
audio = 0.04 * voice(:) / max(abs(voice));

info = mic_check(audio, fs, false);
verifyEqual(t, info.Verdict, 'TOO QUIET');
verifyLessThan(t, info.PeakDb, -20);
verifyTrue(t, contains(lower(info.Advice), 'raise') || contains(lower(info.Advice), 'closer'));
end

function testNoisySignalGivesNoisyVerdict(t)
fs = 44100;
% Speech level close to background noise level (SNR < 18 dB)
[voice, ~] = synth_voiced_signal(fs, 1.5, [120 155], [550 1550 2600]);
speech = 0.10 * voice(:) / max(abs(voice));
heavyNoise = 0.05 * randn(size(speech));
audio = speech + heavyNoise;

info = mic_check(audio, fs, false);
verifyEqual(t, info.Verdict, 'NOISY');
verifyLessThan(t, info.SnrDb, 18);
verifyTrue(t, contains(lower(info.Advice), 'noise') || contains(lower(info.Advice), 'quiet'));
end
