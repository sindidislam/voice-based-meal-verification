function state=speech_capture_state(audio,fs,p)
%SPEECH_CAPTURE_STATE Decide when a currently recorded phrase has finished.
% Re-evaluate the complete mono audio prefix on each recorder poll. The first
% noise.NoiseDuration seconds establish the noise floor; subsequent 20 ms
% frames must sustain an onset before speech starts. A lower end threshold
% preserves quieter words. Silence ends a sufficiently voiced phrase after
% the configured hangover, and capture always stops by min(recordDur,8) s.
% StopSample is the earliest completed endpoint, so a late poll may trim the
% returned audio there. StopSample/SpeechStartSample are NaN until available.
% This is an energy endpoint heuristic, not a speaker or liveness decision.
if nargin<3 || isempty(p), p=struct(); end
validateattributes(audio,{'numeric'},{'real','finite'},mfilename,'audio');
validateattributes(fs,{'numeric'},{'real','finite','scalar','positive'},mfilename,'fs');
if ~isvector(audio) && ~isempty(audio)
    error('speech_capture:invalidAudio','Audio must be a mono vector.');
end
if ~isstruct(p) || ~isscalar(p)
    error('speech_capture:invalidParameters','Parameters must be a scalar struct.');
end
audio=double(audio(:));
noise=get_option(p,'noise',struct());
noiseDuration=get_option(noise,'NoiseDuration',.5);
duration=get_option(p,'recordDur',8);
validateattributes(noiseDuration,{'numeric'},{'real','finite','scalar','positive'});
validateattributes(duration,{'numeric'},{'real','finite','scalar','positive'});
c=detector_options(get_option(p,'speechStop',struct()));
capSamples=max(1,round(min(duration,8)*fs));
sampleCount=min(numel(audio),capSamples);
noiseSamples=max(1,round(noiseDuration*fs));
state=struct('SpeechStarted',false,'ShouldStop',false,'Reason','profiling-noise', ...
    'StopSample',NaN,'SpeechStartSample',NaN,'SpeechEndSample',NaN,'NoiseRms',NaN, ...
    'StartThreshold',NaN,'EndThreshold',NaN,'SilenceSeconds',0);
if sampleCount<noiseSamples
    if sampleCount>=capSamples
        state.ShouldStop=true; state.Reason='capture-limit'; state.StopSample=capSamples;
    end
    return;
end

state.NoiseRms=sqrt(mean(audio(1:noiseSamples).^2));
state.StartThreshold=max(c.MinStartRms,c.StartNoiseRatio*state.NoiseRms);
state.EndThreshold=max(c.MinEndRms,c.EndNoiseRatio*state.NoiseRms);
state.Reason='waiting-for-speech';
frameSamples=max(1,round(c.FrameDuration*fs));
frameCount=floor((sampleCount-noiseSamples)/frameSamples);
onsetFrames=max(1,ceil(c.OnsetDuration*fs/frameSamples));
minimumVoicedSamples=ceil(c.MinVoicedDuration*fs);
hangoverSamples=ceil(c.HangoverDuration*fs);
onsetRun=0; voicedSamples=0; silenceSamples=0;
if frameCount>0
    frames=reshape(audio(noiseSamples+1:noiseSamples+frameCount*frameSamples), ...
        frameSamples,frameCount);
    frameRms=sqrt(mean(frames.^2,1));
    validFrame=true(1,frameCount);
    if c.UseZcr && frameSamples>1
        crossings=sum(frames(1:end-1,:).*frames(2:end,:)<0,1);
        validFrame=crossings*fs/(frameSamples-1)<=c.MaxZcrPerSecond;
    end
    for k=1:frameCount
        frameEnd=noiseSamples+k*frameSamples;
        if ~state.SpeechStarted
            if validFrame(k) && frameRms(k)>=state.StartThreshold
                onsetRun=onsetRun+1;
            else
                onsetRun=0;
            end
            if onsetRun>=onsetFrames
                state.SpeechStarted=true;
                state.SpeechStartSample=frameEnd-onsetRun*frameSamples+1;
                voicedSamples=onsetRun*frameSamples;
                state.Reason='speech-active';
            end
        elseif validFrame(k) && frameRms(k)>=state.EndThreshold
            peakSpeechRms = max(frameRms(1:k));
            relThreshRms = peakSpeechRms * 10^(-c.EndRelativeDb / 20);
            if voicedSamples >= max(minimumVoicedSamples, ceil(0.5 * fs)) && frameRms(k) < relThreshRms
                silenceSamples=silenceSamples+frameSamples;
                state.Reason='silence-hangover';
                if silenceSamples>=hangoverSamples
                    state.ShouldStop=true;
                    state.Reason='speech-ended';
                    state.StopSample=frameEnd;
                    state.SilenceSeconds=silenceSamples/fs;
                    return;
                end
            else
                voicedSamples=voicedSamples+frameSamples;
                silenceSamples=0;
                state.SpeechEndSample=frameEnd;
                state.Reason='speech-active';
            end
        else
            silenceSamples=silenceSamples+frameSamples;
            state.Reason='silence-hangover';
            if voicedSamples>=minimumVoicedSamples && silenceSamples>=hangoverSamples
                state.ShouldStop=true;
                state.Reason='speech-ended';
                state.StopSample=frameEnd;
                state.SilenceSeconds=silenceSamples/fs;
                return;
            end
        end
        state.SilenceSeconds=silenceSamples/fs;
    end
end
if sampleCount>=capSamples
    state.ShouldStop=true; state.Reason='capture-limit'; state.StopSample=capSamples;
end
end

function c=detector_options(options)
c=struct('FrameDuration',.02,'OnsetDuration',.12,'HangoverDuration',3.0, ...
    'MinVoicedDuration',.25,'StartNoiseRatio',3,'EndNoiseRatio',1.8, ...
    'MinStartRms',1e-5,'MinEndRms',5e-6,'UseZcr',false,'MaxZcrPerSecond',4000, ...
    'EndRelativeDb',25.0);

if ~isstruct(options) || ~isscalar(options)
    error('speech_capture:invalidParameters','speechStop must be a scalar struct.');
end
names=fieldnames(c);
for k=1:numel(names)
    name=names{k}; c.(name)=get_option(options,name,c.(name));
    if strcmp(name,'UseZcr')
        if ~(islogical(c.UseZcr) || isnumeric(c.UseZcr)) || ~isscalar(c.UseZcr) || ...
                ~isreal(c.UseZcr) || ~ismember(c.UseZcr,[0 1])
            error('speech_capture:invalidParameters','UseZcr must be a logical scalar.');
        end
    else
        validateattributes(c.(name),{'numeric'},{'real','finite','scalar','positive'});
    end
end
if c.EndNoiseRatio>=c.StartNoiseRatio || c.MinEndRms>=c.MinStartRms
    error('speech_capture:invalidParameters','End thresholds must be lower than start thresholds.');
end
end

function value=get_option(options,name,fallback)
value=fallback;
if isstruct(options) && isscalar(options) && isfield(options,name) && ~isempty(options.(name))
    value=options.(name);
end
end
