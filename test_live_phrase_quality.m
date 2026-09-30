function tests=test_live_phrase_quality
tests=functiontests(localfunctions);
end

function testBriefVoicedBurstCannotStandInForCompletePhrase(t)
p=dsp_parameters();
q=assess_recording_quality(fixture(.25,p.fs),p.fs,p,struct('Mode','live','Strict',true));
verifyFalse(t,q.Usable,'A 250 ms burst cannot supply a complete seven-digit ID/name.');
verifyEmpty(t,q.Audio);
verifyTrue(t,contains(q.Reason,'whole phrase'));
end

function testCompleteLivePhraseRemainsUsable(t)
p=dsp_parameters();
q=assess_recording_quality(fixture(1.2,p.fs),p.fs,p,struct('Mode','live','Strict',true));
verifyTrue(t,q.Usable,q.Reason);
verifyGreaterThan(t,q.SpeechDuration,.6);
end

function testMildPreRollNoiseDoesNotCauseFatalRejection(t)
p=dsp_parameters();
fs=p.fs;
% Fixture with mild pre-roll room noise / breath (amplitude 0.04 -> RMS ~0.028 > 0.020 limit)
leadNoise = 0.04 * sin(2*pi*150*(0:round(0.6*fs)-1)'/fs);
[voice,~] = synth_voiced_signal(fs, 1.2, [120 155], [550 1550 2600]);
speech = 0.35 * voice(:) / max(abs(voice));
audio = [leadNoise; speech; zeros(round(0.3*fs),1)];

q = assess_recording_quality(audio, fs, p, struct('Mode','live','Strict',true));
verifyTrue(t, q.Usable, 'Mild pre-roll noise should be an advisory, not a fatal rejection that wipes audio.');
verifyNotEmpty(t, q.Audio);
end


function x=fixture(duration,fs)
[voice,~]=synth_voiced_signal(fs,duration,[120 155],[550 1550 2600]);
x=[zeros(round(.65*fs),1);.25*voice(:)/max(abs(voice));zeros(round(.25*fs),1)];
end

