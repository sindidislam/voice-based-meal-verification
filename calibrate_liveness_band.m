function report = calibrate_liveness_band(spoofFolder, params)
%CALIBRATE_LIVENESS_BAND Set the sub-200 Hz liveness bounds from measured audio.
%
%   REPORT = CALIBRATE_LIVENESS_BAND() measures the sub-200 Hz band-energy ratio
%   of every enrolled template and reports the distribution, together with the
%   liveness bounds those measurements support.
%
%   REPORT = CALIBRATE_LIVENESS_BAND(SPOOFFOLDER) additionally measures every
%   WAV under SPOOFFOLDER, which is expected to contain loudspeaker replays of
%   enrolled phrases as produced by RECORD_CORPUS_TOOL in replay mode.  When
%   both populations are available the bound is placed between them and the
%   achievable error rates are reported.
%
%   Proposal modification 2, Goal 5, evaluation metric "Spoofing".  EEE 312
%   CO2 (compare theoretical and experimental results).
%
%   Why this function has to exist
%   ------------------------------
%   The previous revision of this system hard-coded a threshold of 0.35 and
%   applied it as an UPPER bound.  Two things were wrong with that.  The bound
%   was on the wrong side -- a loudspeaker cannot reproduce the glottal
%   fundamental, so a replay has LESS sub-200 Hz energy than live speech, not
%   more -- and the number had never been compared against a measurement.  The
%   result was that 21 of 123 genuine enrolment files were discarded while a
%   replay would have passed unchallenged.  A threshold that has not been
%   measured against both populations is not a decision rule, it is a guess.
%
%   Interpreting the report
%   -----------------------
%   Live speech occupies a band of ratios rather than a single value, because
%   the amount of energy at the fundamental depends on the talker's pitch, the
%   microphone's own low-frequency response and the distance to it.  The
%   recommended MinRatio is placed below the lowest genuine measurement with a
%   safety factor, so that no enrolled student is ever rejected as a replay;
%   MaxRatio is placed above the highest, so that only genuine rumble trips it.
%   When spoof recordings are supplied the recommendation instead becomes the
%   equal-error point between the two distributions, which is the defensible
%   operating point to quote in the report.
%
%   See also CHECK_LIVENESS_LOWFREQ, RECORD_CORPUS_TOOL, DSP_PARAMETERS.

if nargin < 1, spoofFolder = ''; end
if nargin < 2 || isempty(params), params = dsp_parameters(); end

% Measure, never reject, while calibrating.
measureParams = params;
measureParams.liveness.Enable = false;
measureParams.enforceLivenessOnTemplates = false;

fprintf('Measuring sub-200 Hz band-energy ratio over the enrolled corpus...\n');
[genuine, genuineFiles] = measure_folder_set( ...
    {params.trainNameFolder, params.trainCouponFolder}, measureParams, params);

if isempty(genuine)
    error('calibrate_liveness_band:noData', ...
        'No usable enrolment audio was found under %s or %s.', ...
        params.trainNameFolder, params.trainCouponFolder);
end

report = struct();
report.GenuineCount = numel(genuine);
report.GenuineMin   = min(genuine);
report.GenuineP01   = prctile(genuine, 1);
report.GenuineP05   = prctile(genuine, 5);
report.GenuineMedian= median(genuine);
report.GenuineP95   = prctile(genuine, 95);
report.GenuineMax   = max(genuine);
report.GenuineRatios = genuine;
report.GenuineFiles  = genuineFiles;

% Default recommendation with genuine data only: keep every enrolled student.
% A factor of three below the 1st percentile is roughly 10 dB of margin in the
% band-energy ratio, which comfortably covers talker and microphone variation.
report.RecommendedMinRatio = report.GenuineP01 / 3;
report.RecommendedMaxRatio = min(0.95, max(0.60, report.GenuineMax * 1.5));
report.SpoofCount = 0;
report.Basis = 'genuine-only';

if ~isempty(spoofFolder) && isfolder(spoofFolder)
    fprintf('Measuring replay recordings under %s...\n', spoofFolder);
    [spoof, spoofFiles] = measure_folder_set({spoofFolder}, measureParams, params);
    report.SpoofCount = numel(spoof);
    report.SpoofRatios = spoof;
    report.SpoofFiles = spoofFiles;
    if ~isempty(spoof)
        report.SpoofMin    = min(spoof);
        report.SpoofMedian = median(spoof);
        report.SpoofP95    = prctile(spoof, 95);
        report.SpoofMax    = max(spoof);
        [thr, frr, far] = equal_error_threshold(genuine, spoof);
        report.RecommendedMinRatio = thr;
        report.FalseRejectRate = frr;
        report.FalseAcceptRate = far;
        report.Separation = report.GenuineP05 / max(report.SpoofP95, eps);
        report.Basis = 'genuine-vs-replay';
    end
end

print_report(report, params);
end

% -------------------------------------------------------------------------
function [ratios, files] = measure_folder_set(folders, measureParams, params)
ratios = [];
files = strings(0,1);
for f = 1:numel(folders)
    if ~isfolder(folders{f}), continue; end
    found = dir(fullfile(folders{f}, '**', '*.wav'));
    for k = 1:numel(found)
        fullPath = fullfile(found(k).folder, found(k).name);
        try
            [x, fs] = audioread(fullPath);
            % The same enrolment decision the rest of the system uses, via
            % ASSESS_RECORDING_QUALITY -- which also hands back the processed audio,
            % so the chain runs once. MEASUREPARAMS has the liveness gate disabled,
            % otherwise the band would be fitted only to files the current band
            % already accepts and could never widen.
            %
            % Using the shared decision matters here beyond tidiness: this function
            % sets MinRatio from the low tail of the genuine distribution, so one
            % near-silent file measuring an implausible ratio would drag the accepted
            % band open for every real attack. Files with no phrase in them are not
            % evidence about what a phrase looks like.
            %
            % On this corpus the guard did not have to fire: excluding the two
            % unenrollable coupon files took n from 123 to 121 and left the
            % recommendation at MinRatio 0.00024 / MaxRatio 0.70485 unchanged, with
            % the genuine minimum still 0.00053. So this is a guard against a hazard
            % that has not yet bitten, not the repair of a measured error -- worth
            % saying plainly, because the two are easy to conflate in a report.
            dg = assess_recording_quality(x, fs, measureParams, struct('Strict', false));
            if ~dg.Usable || isempty(dg.Audio)
                continue;
            end
            [~, r] = check_liveness_lowfreq(dg.Audio, dg.Fs, params.liveness);
            if isfinite(r)
                ratios(end+1,1) = r;                     %#ok<AGROW>
                files(end+1,1) = string(fullPath);       %#ok<AGROW>
            end
        catch exception
            fprintf(2, '  skipped %s (%s)\n', found(k).name, exception.message);
        end
    end
end
end

function [thr, frr, far] = equal_error_threshold(genuine, spoof)
%EQUAL_ERROR_THRESHOLD Lower bound where false-reject equals false-accept.
candidates = unique([genuine(:); spoof(:)]);
candidates = sort(candidates);
best = struct('thr',candidates(1),'gap',Inf,'frr',1,'far',1);
for k = 1:numel(candidates)
    t = candidates(k);
    frr = mean(genuine < t);      % Live speech wrongly called a replay.
    far = mean(spoof  >= t);      % Replay wrongly accepted as live.
    gap = abs(frr - far);
    if gap < best.gap
        best = struct('thr',t,'gap',gap,'frr',frr,'far',far);
    end
end
thr = best.thr;
frr = best.frr;
far = best.far;
end

function print_report(report, params)
fprintf('\n=== Sub-200 Hz liveness calibration =====================\n');
fprintf('Low band      : %g - %g Hz\n', params.liveness.LowBand(1), params.liveness.LowBand(2));
fprintf('Reference band: %g - %g Hz\n', params.liveness.FullBand(1), params.liveness.FullBand(2));
fprintf('\nGenuine (live) templates, n = %d\n', report.GenuineCount);
fprintf('  min %.5f | p01 %.5f | p05 %.5f | median %.5f | p95 %.5f | max %.5f\n', ...
    report.GenuineMin, report.GenuineP01, report.GenuineP05, ...
    report.GenuineMedian, report.GenuineP95, report.GenuineMax);
if report.SpoofCount > 0
    fprintf('\nReplay recordings, n = %d\n', report.SpoofCount);
    fprintf('  min %.5f | median %.5f | p95 %.5f | max %.5f\n', ...
        report.SpoofMin, report.SpoofMedian, report.SpoofP95, report.SpoofMax);
    fprintf('  separation (genuine p05 / spoof p95) = %.2f\n', report.Separation);
    fprintf('\nEqual-error operating point\n');
    fprintf('  false rejection of live speech : %.1f %%\n', 100*report.FalseRejectRate);
    fprintf('  false acceptance of replay     : %.1f %%\n', 100*report.FalseAcceptRate);
else
    fprintf('\nNo replay recordings supplied. The MinRatio below is a safe lower\n');
    fprintf('bound that rejects nobody; run RECORD_CORPUS_TOOL in replay mode and\n');
    fprintf('re-run this function to obtain a measured operating point.\n');
end
fprintf('\nRecommended settings for dsp_parameters.m (basis: %s)\n', report.Basis);
fprintf('  params.liveness.MinRatio = %.5f;\n', report.RecommendedMinRatio);
fprintf('  params.liveness.MaxRatio = %.5f;\n', report.RecommendedMaxRatio);
fprintf('Currently configured: MinRatio = %.5f, MaxRatio = %.5f\n', ...
    params.liveness.MinRatio, params.liveness.MaxRatio);
nBelow = sum(report.GenuineRatios < params.liveness.MinRatio);
nAbove = sum(report.GenuineRatios > params.liveness.MaxRatio);
fprintf('With the current settings, %d of %d genuine templates would be rejected.\n', ...
    nBelow + nAbove, report.GenuineCount);
fprintf('=========================================================\n\n');
end
