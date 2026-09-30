function results = experiment_channel_robustness(outputFile)
%EXPERIMENT_CHANNEL_ROBUSTNESS Does the matcher survive a microphone change?
%
%   RESULTS = EXPERIMENT_CHANNEL_ROBUSTNESS() enrols each student from one clean
%   recording, then tests them with a second recording passed through a simulated
%   microphone channel, and reports how each front-end configuration degrades.
%
%   EEE 312 CO2 (compare theoretical and experimental results), CO1 (implement
%   DSP algorithms), Experiment 4 (DFT), Experiment 6/7 (LTI filtering and
%   convolution).  PO(d) Investigation, PO(e) understanding the limits of a tool.
%
%   Why this experiment is necessary
%   --------------------------------
%   EXPERIMENT_FRONTEND_COMPARISON reports that cepstral mean and variance
%   normalisation makes the equal error rate WORSE on the stored corpus (8.2 to
%   11.3 percent).  Taken at face value that says channel normalisation is
%   harmful.  Taken together with how the corpus was recorded it says something
%   quite different, and the difference decides how the deployed system should be
%   configured.
%
%   Every student in the corpus recorded both of their samples on one device in
%   one sitting.  A microphone and room impose a fixed transfer function H(w),
%   which is multiplicative on the magnitude spectrum and therefore a constant
%   additive vector in the log-spectral and cepstral domains.  Because each
%   student has their own device, that constant is effectively a per-student
%   label.  A matcher can score well by recognising the label instead of the
%   voice, and a corpus-internal test cannot tell the two apart -- it rewards
%   exactly the shortcut it should be penalising.
%
%   A dining hall does not work that way.  Every student speaks into the SAME
%   counter microphone, so at test time the channel is identical for everybody
%   and carries zero information about who is speaking.  Meanwhile the enrolled
%   templates were captured on 26 different phones.  The deployed system
%   therefore faces a channel MISMATCH between template and test that the corpus
%   never exhibits, and channel normalisation is the thing that removes it.
%
%   The protocol below creates that mismatch on purpose.  Template features come
%   from a clean recording; test features come from a different recording of the
%   same phrase convolved with a simulated microphone response.  If the channel
%   argument is right, the un-normalised front-end will degrade sharply and the
%   normalised one will barely move.  If it is wrong, both will degrade together
%   and the corpus result should be believed as it stands.
%
%   The simulated channels
%   ----------------------
%   Each is a minimal linear time-invariant filter whose log magnitude response
%   is a smooth slope or bump ACROSS the analysed band, because that is what a
%   cepstral mean can and cannot remove.  All of them sit inside 300-3700 Hz on
%   purpose:
%
%   'none'          Identity, printed as the reference row so the degradation of
%                   every other row can be read off directly.
%   'lowpass_tilt'  One pole at z = 0.7: H(z) = 1/(1 - 0.7 z^-1).  Falls at about
%                   6 dB per octave above roughly 1.1 kHz, so the top of the
%                   speech band is attenuated by of order 10 dB relative to the
%                   bottom.  This is the shape of a damped or dust-covered
%                   capsule, and of a talker standing off-axis.
%   'highpass_tilt' One zero at z = 0.7: H(z) = 1 - 0.7 z^-1.  The mirror image,
%                   rising across the band.  This is the shape of a bright
%                   close-talking headset.
%   'resonance'     Second-order peak near 1200 Hz, in the middle of the first
%                   and second formant region.  Unlike the two tilts this is not
%                   monotonic, so it tests a channel whose effect varies from
%                   band to band rather than sloping uniformly.
%
%   Because each filter is LTI, its contribution to the log magnitude spectrum is
%   a fixed vector added to every frame, which is exactly the quantity cepstral
%   mean subtraction removes.  The prediction is therefore sharp: the
%   un-normalised front-end should degrade and the normalised one should not.
%
%   A note on band limits
%   ---------------------
%   An earlier version of this experiment used a high-pass at 250 Hz and a
%   low-pass at 3 kHz, chosen to imitate a cheap electret.  Neither changed the
%   error rate at all, because PARAMS.R limits the mel filterbank to
%   300-3700 Hz and both corners fall outside it.  That null result is worth
%   recording: restricting the analysis band is itself a channel-robustness
%   measure, since any part of the microphone response outside the band cannot
%   reach the features.  The channels above were then moved inside the band so
%   that the question actually being asked is the one described here.
%
%   What the experiment found
%   -------------------------
%   The prediction was not borne out, and the reason matters more than the
%   prediction did.  Measured on 49 genuine and 1225 impostor pairs:
%
%     Configuration                none   lp_tilt  hp_tilt  resonance
%     MFCC, no normalisation       12.2      12.2     12.2       14.3
%     MFCC + CMVN, statics only    16.3      16.3     16.3       16.3
%     MFCC + CMVN, with deltas     16.3      16.3     16.3       16.3
%     Proposal DFT                 16.3      16.3     16.3       18.4
%
%   Three things follow.
%
%   First, neither smooth tilt changed any error rate.  A one-pole tilt perturbs
%   only the lowest one or two cepstral coefficients, and DTW is accumulating a
%   Euclidean distance over twelve of them, so the perturbation is small relative
%   to the distance already there.  The mel filterbank's 300-3700 Hz limit
%   removes the rest.  Cepstral mean subtraction is therefore solving a problem
%   this front-end did not have.
%
%   Second, the only channel that moved anything was the non-monotonic
%   resonance, and there the normalised configurations did hold steady while the
%   un-normalised MFCC and the DFT front-end each lost 2.1 points.  That is the
%   predicted direction, but it is a single point of movement.
%
%   Third, and decisively, the un-normalised MFCC is about 4 points better than
%   every normalised configuration in EVERY channel condition, including the ones
%   normalisation was supposed to win.  Since 49 genuine pairs quantise the equal
%   error rate to steps of about 2 points, a 4-point gap is real and a 2-point
%   gap is one quantum and should not be leaned on.
%
%   The conclusion drawn for the deployed system is therefore the opposite of the
%   hypothesis: cepstral mean subtraction is switched OFF by default, because on
%   every measurement available it costs accuracy and buys robustness this
%   front-end does not need.  The honest caveat is that this corpus still cannot
%   separate the talker from the talker's phone, since each student recorded both
%   samples on one device; a simulated channel is not a substitute for a real
%   one.  RECORD_CORPUS_TOOL exists so that the group can re-record through one
%   shared microphone and settle the question with measurement rather than
%   argument.  Until then the setting rests on the evidence above, and the
%   evidence says leave it off.
%
%   See also EXPERIMENT_FRONTEND_COMPARISON, EXTRACT_MFCC_DSP, DSP_PARAMETERS.

if nargin < 1 || isempty(outputFile)
    outputFile = fullfile('Results','channel_robustness.csv');
end
if ~isempty(fileparts(outputFile)) && ~isfolder(fileparts(outputFile))
    mkdir(fileparts(outputFile));
end

base = dsp_parameters();
base.liveness.Enable = false;   % Measuring the matcher, not the gate.

channels = {'none','lowpass_tilt','highpass_tilt','resonance'};

configs = {
  'MFCC, no normalisation', ...
      {'featureFrontEnd','mfcc'; 'mfcc.CmsNormalise',false; ...
       'mfcc.CmvNormalise',false; 'mfcc.DropC0',false}
  'MFCC + CMVN, statics only', ...
      {'featureFrontEnd','mfcc'; 'mfcc.CmsNormalise',true; ...
       'mfcc.CmvNormalise',true; 'mfcc.DropC0',true; ...
       'mfcc.IncludeDelta',false; 'mfcc.IncludeDeltaDelta',false}
  'MFCC + CMVN, with deltas', ...
      {'featureFrontEnd','mfcc'; 'mfcc.CmsNormalise',true; ...
       'mfcc.CmvNormalise',true; 'mfcc.DropC0',true}
  'Proposal DFT (CMVN inherent)', ...
      {'featureFrontEnd','dft'; 'dft.IncludeDelta',false}
};
configs = reshape(configs', 2, [])';

rows = {};
fprintf('\nEnrol clean, test through a simulated microphone channel.\n');
fprintf('%-30s %-10s %7s %7s %8s %9s\n', ...
    'Configuration','Channel','EER %','Sep','FRR@1%','dEER pp');
fprintf('%s\n', repmat('-',1,78));

for c = 1:size(configs,1)
    p = apply_overrides(base, configs{c,2});
    baselineEer = NaN;

    for h = 1:numel(channels)
        try
            r = channel_mismatch_rates(p, channels{h});
            if strcmp(channels{h},'none')
                baselineEer = r.EER;
            end
            delta = 100*(r.EER - baselineEer);
            rows(end+1,:) = {string(configs{c,1}), string(channels{h}), ...
                100*r.EER, r.Separation, 100*r.FrrAtFar1, delta, ...
                r.GenuineCount, r.ImpostorCount};             %#ok<AGROW>
            fprintf('%-30s %-10s %7.1f %7.3f %8.1f %+9.1f\n', ...
                configs{c,1}, channels{h}, 100*r.EER, r.Separation, ...
                100*r.FrrAtFar1, delta);
        catch exception
            fprintf('%-30s %-10s  failed: %s\n', ...
                configs{c,1}, channels{h}, exception.message);
        end
    end
    fprintf('\n');
end

results = cell2table(rows, 'VariableNames', ...
    {'Configuration','Channel','EERPercent','Separation','FRRatFAR1Percent', ...
     'EERDegradationPoints','GenuinePairs','ImpostorPairs'});
writetable(results, outputFile);
fprintf('Written to %s\n', outputFile);
end

% -------------------------------------------------------------------------
function r = channel_mismatch_rates(p, channelName)
%CHANNEL_MISMATCH_RATES Genuine and impostor rates under template/test mismatch.
%
%   Template features are extracted from the FIRST recording of each student,
%   unfiltered.  Test features are extracted from the SECOND recording, filtered.
%   Genuine pairs compare a student's template with their own filtered test;
%   impostor pairs compare a student's template with every other student's
%   filtered test of the same phrase.  Using different recordings on the two
%   sides is what makes the comparison honest: filtering one copy of the SAME
%   recording would measure only the filter, not the person.

folders = {p.trainNameFolder, p.trainCouponFolder};
genuine = [];
impostor = [];

for q = 1:numel(folders)
    if ~isfolder(folders{q}), continue; end
    users = dir(folders{q});
    users = users([users.isdir] & ~startsWith({users.name},'.'));

    templates = cell(numel(users),1);
    tests     = cell(numel(users),1);

    for u = 1:numel(users)
        files = dir(fullfile(folders{q}, users(u).name, '*.wav'));
        if numel(files) < 2, continue; end
        templates{u} = features_from_file(fullfile(files(1).folder, files(1).name), p, 'none');
        tests{u}     = features_from_file(fullfile(files(2).folder, files(2).name), p, channelName);
    end

    for u = 1:numel(users)
        if isempty(templates{u}), continue; end
        for v = 1:numel(users)
            if isempty(tests{v}), continue; end
            if size(templates{u},1) ~= size(tests{v},1), continue; end
            d = dtw_distance_dsp(templates{u}, tests{v}, p.dtw);
            if u == v
                genuine(end+1,1) = d;    %#ok<AGROW>
            else
                impostor(end+1,1) = d;   %#ok<AGROW>
            end
        end
    end
end

if isempty(genuine) || isempty(impostor)
    error('experiment_channel_robustness:noPairs', ...
        'Found %d genuine and %d impostor pairs.', numel(genuine), numel(impostor));
end

r = struct();
r.GenuineCount = numel(genuine);
r.ImpostorCount = numel(impostor);
r.Separation = prctile(impostor,5) / max(prctile(genuine,95), eps);

candidates = sort(unique([genuine; impostor]));
bestGap = Inf; r.EER = 1; r.ThresholdEER = candidates(1);
for k = 1:numel(candidates)
    t = candidates(k);
    frr = mean(genuine >= t);
    far = mean(impostor < t);
    if abs(frr-far) < bestGap
        bestGap = abs(frr-far);
        r.EER = (frr+far)/2;
        r.ThresholdEER = t;
    end
end

descending = sort(candidates, 'descend');
r.ThresholdFar1 = min(descending);
for k = 1:numel(descending)
    if mean(impostor < descending(k)) <= 0.01
        r.ThresholdFar1 = descending(k);
        break;
    end
end
r.FrrAtFar1 = mean(genuine >= r.ThresholdFar1);
end

function f = features_from_file(path, p, channelName)
%FEATURES_FROM_FILE Read, optionally filter, preprocess and extract features.
f = [];
try
    [x, fs] = audioread(path);
    x = double(x(:,1));
    x = apply_channel(x, fs, channelName);
    % The channel goes on the raw capture, so this passes audio rather than a path --
    % but the enrolment decision is still the shared one. A channel severe enough to
    % push a file below the level floor now drops it here exactly as it would in the
    % deployed matcher, which is part of what this experiment is measuring.
    f = enrol_template_features(x, fs, p);
catch
    f = [];
end
end

function y = apply_channel(x, fs, name)
%APPLY_CHANNEL Convolve with a simulated microphone transfer function.
%
%   The filter is applied to the RAW capture, before resampling and before AGC,
%   which is where a real microphone sits in the signal path.  Applying it later
%   would let the pipeline's own gain control undo part of it and would
%   understate the mismatch.
switch name
    case 'none'
        y = x;
    case 'lowpass_tilt'
        % One pole at z = 0.7. Log magnitude falls roughly 6 dB per octave above
        % about 1.1 kHz at 44.1 kHz, i.e. a smooth downward slope across the
        % analysed band.
        y = filter(1, [1 -0.7], x);
    case 'highpass_tilt'
        % One zero at z = 0.7, the mirror image: a smooth upward slope.
        y = filter([1 -0.7], 1, x);
    case 'resonance'
        % Second-order peak near 1200 Hz, in the F1/F2 region. Built as a narrow
        % band-pass added back to the original, which raises that region by
        % roughly 8 dB while leaving the rest of the spectrum in place.
        [b,a] = butter(2, [max(1e-3, 900/(fs/2)) min(0.99, 1600/(fs/2))], 'bandpass');
        y = x + 1.5 * filter(b, a, x);
    otherwise
        error('experiment_channel_robustness:unknownChannel', ...
            'Unknown channel "%s".', name);
end
% Guard against the filter pushing the signal outside the representable range;
% the pipeline's AGC will set the working level anyway.
peak = max(abs(y));
if peak > 1
    y = y / peak;
end
end

function p = apply_overrides(p, overrides)
for i = 1:size(overrides,1)
    parts = strsplit(overrides{i,1}, '.');
    if numel(parts) == 1
        p.(parts{1}) = overrides{i,2};
    else
        p.(parts{1}).(parts{2}) = overrides{i,2};
    end
end
end
