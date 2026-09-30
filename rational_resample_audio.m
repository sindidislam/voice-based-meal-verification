function [y, fsOut, info] = rational_resample_audio(x, fsIn, fsTarget, opts)
%RATIONAL_RESAMPLE_AUDIO Polyphase rational rate conversion by L/M.
%
%   [Y, FSOUT, INFO] = RATIONAL_RESAMPLE_AUDIO(X, FSIN, FSTARGET, OPTS)
%   converts X from FSIN to FSTARGET using interpolation by L, lowpass
%   filtering, and decimation by M, where L/M is the reduced rational
%   approximation of FSTARGET/FSIN.
%
%   Proposal modification 1a.  EEE 312 Experiment 1 (sampling and the
%   Nyquist-Shannon theorem) and Experiment 2 (sampling-rate conversion).
%
%   For this system
%   ---------------
%       FSIN     = 44100 Hz  (native sound-card rate)
%       FSTARGET = 8000  Hz  (DSP rate chosen in the proposal)
%       8000/44100 = 80/441  after dividing both by gcd(8000,44100) = 100
%
%   so L = 80 and M = 441 exactly, with no rounding error.  Upsampling first
%   and downsampling second is required because L/M < 1 here: if we decimated
%   before interpolating we would discard samples that the interpolation stage
%   still needs.
%
%   Why the project evaluates an 8 kHz target
%   -----------------------------------------
%   The 4 kHz Nyquist boundary deliberately removes higher-frequency content;
%   it does not preserve every vowel formant or every speaker cue. Rate
%   experiments support the selected setting for this corpus and protocol.
%   A 3 s waveform has 132300 samples at 44.1 kHz and 24000 at 8 kHz.
%   This reduces waveform work, not necessarily the number of 10 ms feature
%   frames or the DTW grid. It is not a 5.5x end-to-end speed measurement.
%

%   Anti-aliasing
%   -------------
%   Decimation by M without prefiltering folds everything above fsOut/2 back
%   into the baseband.  RESAMPLE designs a linear-phase Kaiser-windowed FIR
%   lowpass with cutoff 1/max(L,M) in normalised terms and applies it between
%   the interpolation and decimation stages, so the same filter serves as both
%   the anti-imaging and the anti-aliasing filter.  Its length is
%   2*OPTS.FilterOrder*max(L,M)+1 taps.  RESAMPLE also compensates for the
%   filter's group delay, so Y remains time-aligned with X.
%
%   INFO reports L, M, FilterOrder, FilterLength, ActualRate and Nyquist.
%
%   See also RESAMPLE, RAT, PREPROCESS_AUDIO.

if nargin < 4, opts = struct(); end
if ~isfield(opts,'FilterOrder'), opts.FilterOrder = 20; end
if ~isfield(opts,'Beta'),        opts.Beta        = 5;  end

if size(x, 2) > 1, x = mean(x, 2); end
x = double(x(:));

[L, M] = rat(fsTarget / fsIn, 1e-12);
g = gcd(L, M);
L = L / g;
M = M / g;

info = struct( ...
    'L', L, ...
    'M', M, ...
    'P', L, ...                       % Backwards-compatible aliases.
    'Q', M, ...
    'FilterOrder', opts.FilterOrder, ...
    'FilterLength', 2*opts.FilterOrder*max(L,M) + 1, ...
    'InputRate', fsIn, ...
    'ActualRate', fsIn * L / M, ...
    'Nyquist', fsIn * L / M / 2, ...
    'Bypassed', false);

if isempty(x)
    y = zeros(0,1);
    fsOut = info.ActualRate;
    return;
end

if L == 1 && M == 1
    y = x;
    fsOut = fsIn;
    info.Bypassed = true;
    return;
end

y = resample(x, L, M, opts.FilterOrder, opts.Beta);
fsOut = info.ActualRate;
end
