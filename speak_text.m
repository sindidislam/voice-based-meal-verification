function speak_text(txt, isAsync)
%SPEAK_TEXT Windows .NET Speech Synthesis for interactive voice prompts.
%   SPEAK_TEXT(TXT) speaks TXT asynchronously via System.Speech.Synthesis.
%   SPEAK_TEXT(TXT, FALSE) speaks synchronously (blocking).

if nargin < 2, isAsync = true; end
if isempty(txt), return; end
txt = char(txt);

persistent synth;
persistent hasDotNet;

if isempty(hasDotNet)
    hasDotNet = ispc;
end

if hasDotNet
    try
        if isempty(synth)
            NET.addAssembly('System.Speech');
            synth = System.Speech.Synthesis.SpeechSynthesizer;
            synth.Rate = 1;     % Natural crisp pacing
            synth.Volume = 100; % Full volume
        end
        if isAsync
            synth.SpeakAsync(txt);
        else
            synth.Speak(txt);
        end
        return;
    catch
        synth = [];
    end
end

% Fallback if .NET Speech is unavailable or fails
fprintf('[VOICE SYNTHESIZER]: %s\n', txt);
end
