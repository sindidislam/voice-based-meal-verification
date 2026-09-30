function report = calibrate_dtw_threshold(params, verbose)
%CALIBRATE_DTW_THRESHOLD Choose the DTW decision threshold from the corpus.
%
%   REPORT = CALIBRATE_DTW_THRESHOLD() builds every genuine and every impostor
%   template pair available in the enrolled corpus, measures the DTW distance of
%   each, and reports the operating points those two distributions support.
%
%   REPORT = CALIBRATE_DTW_THRESHOLD(PARAMS) calibrates for a specific
%   configuration, which is how EXPERIMENT_FRONTEND_COMPARISON obtains a fair
%   threshold for each front-end.
%
%   EEE 312 CO2 (compare theoretical and experimental results) and Experiment 5.
%
%   How the two populations are formed
%   ----------------------------------
%   Genuine pairs  : both recordings belong to the same student and the same
%                    phrase.  Their distances describe how much a person varies
%                    from one attempt to the next.
%   Impostor pairs : the two recordings belong to different students speaking
%                    the same phrase type.  Their distances describe how far
%                    apart two different people are.
%
%   Comparing only within a phrase type matters.  A student's NAME template and
%   another student's COUPON template differ both in who said it and in what was
%   said, so a distance between them would mix speaker difference with content
%   difference and would flatter the system.
%
%   What the report means
%   ---------------------
%   If the two distributions were separated, any threshold in the gap would work.
%   They are not, so the report quotes three defensible operating points:
%
%     ThresholdEER   -- equal error rate: false rejections equal false accepts.
%                       The conventional single number for quoting performance.
%     ThresholdFar1  -- the strictest threshold whose false-accept rate stays at
%                       or below 1 percent.  This is the right choice for a meal
%                       counter, because a false accept is a meal served on
%                       somebody else's account, while a false reject only costs
%                       the student a second attempt.
%     ThresholdMid   -- midpoint of genuine p95 and impostor p05, reported only
%                       so that the previous revision's rule can be compared.
%
%   The previous revision used ThresholdMid and set 55 while genuine p95 was
%   50.5 and impostor p05 was 38.2.  Because those two numbers are in the wrong
%   order the distributions overlap, and a midpoint inside an overlap admits
%   every impostor in the overlapping region.  Reporting the false-accept rate
%   alongside the threshold makes that failure visible instead of hiding it.
%
%   See also DTW_DISTANCE_DSP, FIND_BEST_VOICE_MATCH, EXPERIMENT_FRONTEND_COMPARISON.

if nargin < 1 || isempty(params), params = dsp_parameters(); end
if nargin < 2, verbose = true; end

folders = {params.trainNameFolder, params.trainCouponFolder};
phraseNames = {'Name','Coupon'};

genuine = [];
impostor = [];

for q = 1:numel(folders)
    if ~isfolder(folders{q}), continue; end
    users = dir(folders{q});
    users = users([users.isdir] & ~startsWith({users.name},'.'));

    features = cell(numel(users),1);
    for u = 1:numel(users)
        files = dir(fullfile(folders{q}, users(u).name, '*.wav'));
        bucket = cell(numel(files),1);
        for k = 1:numel(files)
            % One shared enrolment decision -- see ENROL_TEMPLATE_FEATURES. A
            % threshold calibrated over files the deployed matcher would not load is
            % a threshold for a system that does not exist.
            bucket{k} = enrol_template_features( ...
                fullfile(files(k).folder, files(k).name), [], params);
        end
        features{u} = bucket(~cellfun('isempty', bucket));
    end

    % Genuine: every within-student pair.
    for u = 1:numel(users)
        current = features{u};
        for a = 1:numel(current)
            for b = a+1:numel(current)
                genuine(end+1,1) = dtw_distance_dsp(current{a}, current{b}, params.dtw); %#ok<AGROW>
            end
        end
    end

    % Impostor: first template of each student against the first of every other.
    % Using one template per student keeps the impostor count comparable to the
    % genuine count instead of letting it grow as the square of the sample count.
    for u = 1:numel(users)
        for v = u+1:numel(users)
            if ~isempty(features{u}) && ~isempty(features{v})
                impostor(end+1,1) = dtw_distance_dsp(features{u}{1}, features{v}{1}, params.dtw); %#ok<AGROW>
            end
        end
    end

    if verbose
        fprintf('  %s phrase: cumulative %d genuine, %d impostor pairs\n', ...
            phraseNames{q}, numel(genuine), numel(impostor));
    end
end

if isempty(genuine) || isempty(impostor)
    error('calibrate_dtw_threshold:insufficientData', ...
        ['Calibration needs at least two templates for one student and at ' ...
         'least two students. Found %d genuine and %d impostor pairs.'], ...
        numel(genuine), numel(impostor));
end

report = struct();
report.FrontEnd = params.featureFrontEnd;
report.ProcessingFs = params.processingFs;
report.GenuineCount = numel(genuine);
report.ImpostorCount = numel(impostor);
report.GenuineMedian = median(genuine);
report.GenuineP95 = prctile(genuine, 95);
report.GenuineMax = max(genuine);
report.ImpostorMin = min(impostor);
report.ImpostorP05 = prctile(impostor, 5);
report.ImpostorMedian = median(impostor);
report.GenuineDistances = genuine;
report.ImpostorDistances = impostor;

% Separation: greater than 1 means the distributions are cleanly ordered.
report.Separation = report.ImpostorP05 / max(report.GenuineP95, eps);
report.Overlapping = report.ImpostorP05 <= report.GenuineP95;

[report.ThresholdEER, report.EER] = equal_error_point(genuine, impostor);
[report.ThresholdFar1, report.FrrAtFar1] = threshold_for_far(genuine, impostor, 0.01);
report.ThresholdMid = (report.GenuineP95 + report.ImpostorP05) / 2;
report.FarAtMid = mean(impostor < report.ThresholdMid);
report.FrrAtMid = mean(genuine >= report.ThresholdMid);

% The system default: protect the meal account, accept a few retries.
report.SuggestedThreshold = report.ThresholdFar1;

% Also report how the currently configured value behaves.
report.ConfiguredThreshold = params.dtwThreshold;
report.FarAtConfigured = mean(impostor < params.dtwThreshold);
report.FrrAtConfigured = mean(genuine >= params.dtwThreshold);

if verbose
    print_report(report);
end
end

% -------------------------------------------------------------------------
function [thr, eer] = equal_error_point(genuine, impostor)
candidates = sort(unique([genuine(:); impostor(:)]));
best = struct('thr',candidates(1),'gap',Inf,'eer',1);
for k = 1:numel(candidates)
    t = candidates(k);
    frr = mean(genuine >= t);     % Genuine attempt wrongly rejected.
    far = mean(impostor < t);     % Impostor wrongly accepted.
    gap = abs(frr - far);
    if gap < best.gap
        best = struct('thr',t,'gap',gap,'eer',(frr+far)/2);
    end
end
thr = best.thr;
eer = best.eer;
end

function [thr, frr] = threshold_for_far(genuine, impostor, targetFar)
%THRESHOLD_FOR_FAR Largest threshold whose false-accept rate stays <= targetFar.
candidates = sort(unique([genuine(:); impostor(:)]), 'descend');
thr = min(candidates);
for k = 1:numel(candidates)
    t = candidates(k);
    if mean(impostor < t) <= targetFar
        thr = t;
        break;
    end
end
frr = mean(genuine >= thr);
end

function print_report(r)
fprintf('\n=== DTW threshold calibration ===========================\n');
fprintf('Front-end: %s    Processing rate: %g Hz\n', r.FrontEnd, r.ProcessingFs);
fprintf('Genuine pairs  : n = %4d | median %.4f | p95 %.4f | max %.4f\n', ...
    r.GenuineCount, r.GenuineMedian, r.GenuineP95, r.GenuineMax);
fprintf('Impostor pairs : n = %4d | min    %.4f | p05 %.4f | median %.4f\n', ...
    r.ImpostorCount, r.ImpostorMin, r.ImpostorP05, r.ImpostorMedian);
fprintf('Separation (impostor p05 / genuine p95) = %.3f  -> %s\n', ...
    r.Separation, ternary(r.Overlapping, 'DISTRIBUTIONS OVERLAP', 'cleanly separated'));
fprintf('\nOperating points\n');
fprintf('  Equal error rate : threshold %.4f  EER %.1f %%\n', r.ThresholdEER, 100*r.EER);
fprintf('  FAR <= 1 %%       : threshold %.4f  FRR %.1f %%\n', ...
    r.ThresholdFar1, 100*r.FrrAtFar1);
fprintf('  Legacy midpoint  : threshold %.4f  FAR %.1f %%  FRR %.1f %%\n', ...
    r.ThresholdMid, 100*r.FarAtMid, 100*r.FrrAtMid);
fprintf('\nCurrently configured threshold %.4f -> FAR %.1f %%, FRR %.1f %%\n', ...
    r.ConfiguredThreshold, 100*r.FarAtConfigured, 100*r.FrrAtConfigured);

% Deliberately NOT printed as "set this in dsp_parameters.m".
%
% Every number above describes one distance judged against one threshold. The
% deployed decision is not that: VERIFY_MEAL_WORKFLOW records two phrases and
% requires them to agree, and agreement stops most impostors without consulting
% the threshold at all. Pasting the FAR<=1 % figure into dsp_parameters.m is
% exactly how this system came to reject 35 % of genuine students while its proxy
% attack rate was already zero -- a threshold tightened to catch attackers another
% gate had already caught. EXPERIMENT_VERIFICATION_ACCURACY sweeps the composite
% decision and reports the operating point that belongs in the parameter file.
fprintf('\nThese are PER-PHRASE figures for one distance against one threshold.\n');
fprintf('Do NOT copy %.4f into dsp_parameters.m. The deployed decision uses two\n', ...
    r.ThresholdFar1);
fprintf('phrases and requires them to agree, which changes the trade-off entirely.\n');
fprintf('Run EXPERIMENT_VERIFICATION_ACCURACY for the threshold to actually deploy.\n');
fprintf('=========================================================\n\n');
end

function out = ternary(c, a, b)
if c, out = a; else, out = b; end
end
