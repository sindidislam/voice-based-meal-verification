function tests=test_speech_capture_state
% Streaming endpoint decisions from deterministic native-rate audio prefixes.
tests=functiontests(localfunctions);
end

function testNoiseProfilingDoesNotStartSpeech(t)
[p,fs]=settings();
s=speech_capture_state(zeros(round(.3*fs),1),fs,p);
verifyFalse(t,s.SpeechStarted); verifyFalse(t,s.ShouldStop);
verifyEqual(t,s.Reason,'profiling-noise');
end

function testSilenceWaitsForEightSecondCap(t)
[p,fs]=settings();
s=speech_capture_state(zeros(round(7.98*fs),1),fs,p);
verifyFalse(t,s.SpeechStarted); verifyFalse(t,s.ShouldStop);
s=speech_capture_state(zeros(round(8.2*fs),1),fs,p);
verifyFalse(t,s.SpeechStarted); verifyTrue(t,s.ShouldStop);
verifyEqual(t,s.Reason,'capture-limit');
verifyEqual(t,s.StopSample,8*fs);
end

function testSustainedBackgroundDoesNotBecomeSpeech(t)
[p,fs]=settings();
x=tone(fs,3,.02,100);
s=speech_capture_state(x,fs,p);
verifyFalse(t,s.SpeechStarted); verifyFalse(t,s.ShouldStop);
verifyGreaterThan(t,s.NoiseRms,.01);
verifyGreaterThan(t,s.StartThreshold,s.EndThreshold);
end

function testIsolatedSpikeDoesNotStartSpeech(t)
[p,fs]=settings();
x=[zeros(round(.5*fs),1);ones(round(.04*fs),1);zeros(round(1.2*fs),1)];
s=speech_capture_state(x,fs,p);
verifyFalse(t,s.SpeechStarted); verifyFalse(t,s.ShouldStop);
end

function testOnsetMustPersistForTwelveHundredths(t)
[p,fs]=settings();
profile=zeros(round(.5*fs),1);
s=speech_capture_state([profile;tone(fs,.10,.3,200)],fs,p);
verifyFalse(t,s.SpeechStarted);
s=speech_capture_state([profile;tone(fs,.12,.3,200)],fs,p);
verifyTrue(t,s.SpeechStarted); verifyFalse(t,s.ShouldStop);
verifyEqual(t,s.SpeechStartSample,round(.5*fs)+1);
end

function testNormalSpeechStopsAfterSilenceHangover(t)
[p,fs]=settings();
prefix=[zeros(round(.5*fs),1);tone(fs,.5,.3,200)];
s=speech_capture_state([prefix;zeros(round(.78*fs),1)],fs,p);
verifyTrue(t,s.SpeechStarted); verifyFalse(t,s.ShouldStop);
s=speech_capture_state([prefix;zeros(round(.80*fs),1)],fs,p);
verifyTrue(t,s.ShouldStop); verifyEqual(t,s.Reason,'speech-ended');
verifyEqual(t,s.StopSample,round(1.8*fs));
verifyEqual(t,s.SilenceSeconds,.8,'AbsTol',1e-12);
end

function testShortInternalPauseDoesNotCutOffLaterWords(t)
[p,fs]=settings();
prefix=[zeros(round(.5*fs),1);tone(fs,.5,.3,200); ...
    zeros(round(.4*fs),1);tone(fs,.5,.25,200)];
s=speech_capture_state([prefix;zeros(round(.78*fs),1)],fs,p);
verifyTrue(t,s.SpeechStarted); verifyFalse(t,s.ShouldStop);
s=speech_capture_state([prefix;zeros(round(.8*fs),1)],fs,p);
verifyTrue(t,s.ShouldStop); verifyEqual(t,s.StopSample,round(2.7*fs));
end

function testVeryBriefVoicedBurstCannotEndCaptureEarly(t)
[p,fs]=settings();
x=[zeros(round(.5*fs),1);tone(fs,.14,.3,200);zeros(round(1*fs),1)];
s=speech_capture_state(x,fs,p);
verifyTrue(t,s.SpeechStarted); verifyFalse(t,s.ShouldStop);
end

function testLowAndHighAmplitudeSpeechBothEndAfterSilence(t)
[p,fs]=settings();
for amplitude=[4e-5 .9]
    x=[tone(fs,.5,2e-7,100);tone(fs,.5,amplitude,200);zeros(round(.8*fs),1)];
    s=speech_capture_state(x,fs,p);
    verifyTrue(t,s.SpeechStarted); verifyTrue(t,s.ShouldStop);
    verifyEqual(t,s.Reason,'speech-ended');
    verifyEqual(t,s.StopSample,round(1.8*fs));
end
end

function testEndThresholdPreservesSofterSpeechAfterOnset(t)
[p,fs]=settings();
noise=tone(fs,.5,sqrt(2)*.01,100);
x=[noise;tone(fs,.3,sqrt(2)*.08,200);tone(fs,.9,sqrt(2)*.02,200)];
s=speech_capture_state(x,fs,p);
verifyTrue(t,s.SpeechStarted); verifyFalse(t,s.ShouldStop);
verifyEqual(t,s.SilenceSeconds,0,'AbsTol',1e-12);
end

function testNativeSampleRatesHaveTheSamePhysicalStopTime(t)
[p,~]=settings();
for fs=[8000 44100 48000]
    x=[zeros(round(.5*fs),1);tone(fs,.5,.3,200);zeros(round(.8*fs),1)];
    s=speech_capture_state(x,fs,p);
    verifyTrue(t,s.ShouldStop);
    verifyEqual(t,s.StopSample,round(1.8*fs));
    verifyEqual(t,s.SpeechStartSample,round(.5*fs)+1);
end
end

function testEarliestStopIsRetainedWhenPollingArrivesLate(t)
[p,fs]=settings();
x=[zeros(round(.5*fs),1);tone(fs,.5,.3,200); ...
    zeros(round(.8*fs),1);tone(fs,.2,.3,200)];
s=speech_capture_state(x,fs,p);
verifyTrue(t,s.ShouldStop); verifyEqual(t,s.Reason,'speech-ended');
verifyEqual(t,s.StopSample,round(1.8*fs));
end

function testContinuingSpeechStillObeysEightSecondCap(t)
[p,fs]=settings();
x=[zeros(round(.5*fs),1);tone(fs,7.8,.3,200)];
s=speech_capture_state(x,fs,p);
verifyTrue(t,s.SpeechStarted); verifyTrue(t,s.ShouldStop);
verifyEqual(t,s.Reason,'capture-limit'); verifyEqual(t,s.StopSample,8*fs);
end

function [p,fs]=settings()
fs=8000; p=struct('recordDur',8,'noise',struct('NoiseDuration',.5),'speechStop',struct('HangoverDuration',.8));
end

function testLiveTimingOneSecondNoiseAndThreeSecondHangover(t)
fs=8000;
p=struct('recordDur',8,'noise',struct('NoiseDuration',1.0),'speechStop',struct('HangoverDuration',3.0));
% Test 1: During 1.0s noise profiling, speech does not start
s=speech_capture_state(zeros(round(.8*fs),1),fs,p);
verifyFalse(t,s.SpeechStarted);
verifyEqual(t,s.Reason,'profiling-noise');

% Test 2: Voice starts after 1.0s noise, rolls on and does not stop during internal pauses or 2.9s silence
prefix=[zeros(round(1.0*fs),1); tone(fs,1.0,.3,200); zeros(round(.5*fs),1); tone(fs,1.0,.25,200)];
s=speech_capture_state([prefix; zeros(round(2.9*fs),1)],fs,p);
verifyTrue(t,s.SpeechStarted);
verifyFalse(t,s.ShouldStop);

% Test 3: Stops when silence reaches 3.0 seconds
s=speech_capture_state([prefix; zeros(round(3.0*fs),1)],fs,p);
verifyTrue(t,s.ShouldStop);
verifyEqual(t,s.Reason,'speech-ended');
verifyEqual(t,s.SilenceSeconds,3.0,'AbsTol',1e-12);
end

function testNoSpeechStopsAtEightSeconds(t)
fs=8000;
p=struct('recordDur',8,'noise',struct('NoiseDuration',1.0),'speechStop',struct('HangoverDuration',3.0));
s=speech_capture_state(zeros(round(8.0*fs),1),fs,p);
verifyFalse(t,s.SpeechStarted);
verifyTrue(t,s.ShouldStop);
verifyEqual(t,s.Reason,'capture-limit');
end

function testLowBackgroundNoiseDoesNotPreventSilenceStop(t)
fs=8000;
% Initial noise: amplitude 1e-4. Speech: amplitude 0.3 (peak ~ -10 dBFS).
% Background chatter after speech: amplitude 0.008 (RMS ~0.0056, ~ -45 dBFS, 31 dB down).
p=struct('recordDur',8,'noise',struct('NoiseDuration',0.5), ...
    'speechStop',struct('HangoverDuration',0.8, 'EndRelativeDb',25.0));
prefix=[tone(fs,0.5,1e-4,100); tone(fs,0.6,0.3,200)];
% Add 0.8s of background chatter (31 dB below speech)
hum=tone(fs,0.8,0.008,120);
s=speech_capture_state([prefix; hum],fs,p);
verifyTrue(t,s.SpeechStarted);
verifyTrue(t,s.ShouldStop, 'Should stop after 0.8s because background noise is >25 dB below speech peak');
verifyEqual(t,s.Reason,'speech-ended');
end

function x=tone(fs,seconds,amplitude,hz)
x=amplitude*sin(2*pi*hz*(0:round(seconds*fs)-1)'/fs);
end

