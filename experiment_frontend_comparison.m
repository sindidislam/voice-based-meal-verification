function results = experiment_frontend_comparison(outputFile)
%EXPERIMENT_FRONTEND_COMPARISON Measure every front-end and rate on one corpus.
%
%   RESULTS = EXPERIMENT_FRONTEND_COMPARISON() evaluates each combination of
%   feature front-end, processing sample rate and dynamic-feature setting on the
%   same enrolled corpus, using the same preprocessing and the same matcher, and
%   returns a table of equal error rates.
%
%   EEE 312 CO1 (implement DSP algorithms in software) and CO2 (compare
%   theoretical and experimental results).  Proposal Goal 2.
%
%   What is being controlled
%   ------------------------
%   Exactly one factor changes between rows.  Every row uses the same audio
%   files, the same resampling filter design, the same spectral subtraction, the
%   same endpoint detector and the same DTW recursion.  A difference in equal
%   error rate between two rows is therefore attributable to the factor named in
%   that row and to nothing else.  Without that control the comparison would be
%   an anecdote.
%
%   The factors
%   -----------
%   FrontEnd      'dft' is the proposal's log magnitude-spectrum front-end;
%                 'mfcc' is the senior baseline's mel-cepstral front-end.
%   ProcessingFs  8000 Hz is the proposal's rate; 16000 Hz is what the previous
%                 revision of the code actually used.  The pair answers the
%                 question the proposal raises but does not measure: what does
%                 decimating to 8 kHz cost in accuracy?
%   Delta         Whether the first difference of the feature trajectory is
%                 appended.  A static spectrum says what the vocal tract shape
%                 was; its derivative says how the shape was moving, which is
%                 speaker-specific in a way the static shape is not.
%   PreEmphasis   Included for the 'mfcc' rows so that the full senior-baseline
%                 condition can be reproduced, since the proposal's third
%                 modification is to discard that filter.
%
%   The reported metric
%   -------------------
%   Equal error rate is used for ranking because it is threshold-free: it
%   summarises how separable the genuine and impostor distributions are, without
%   depending on where the operating threshold happens to be set.  The
%   false-rejection rate at a 1 percent false-accept constraint is reported
%   alongside it, because that is the operating point a meal counter would
%   actually run at.
%
%   See also CALIBRATE_DTW_THRESHOLD, EXPERIMENT_MATCHER_COMPARISON.

if nargin < 1 || isempty(outputFile)
    outputFile = fullfile('Results','frontend_comparison.csv');
end

base = dsp_parameters();
if ~isfolder(fileparts(outputFile)) && ~isempty(fileparts(outputFile))
    mkdir(fileparts(outputFile));
end

% Condition list. Each entry is a label plus a cell array of {field, value}
% overrides applied to the baseline parameter struct. Writing the conditions this
% way means every row is explicit about the single factor it changes, and the
% table can be extended without touching the loop below.
conditions = {
  'Proposal DFT, 8 kHz', ...
      {'featureFrontEnd','dft'; 'processingFs',8000; 'dft.IncludeDelta',false}
  'Proposal DFT, 16 kHz', ...
      {'featureFrontEnd','dft'; 'processingFs',16000; 'dft.IncludeDelta',false}
  'Proposal DFT + delta, 8 kHz', ...
      {'featureFrontEnd','dft'; 'processingFs',8000; 'dft.IncludeDelta',true}
  'Senior baseline MFCC, 16 kHz', ...
      {'featureFrontEnd','mfcc'; 'processingFs',16000; 'usePreEmphasis',true; ...
       'mfcc.CmsNormalise',false; 'mfcc.CmvNormalise',false; 'mfcc.DropC0',false}
  % The deployed configuration. It was missing from this list, which meant the
  % experiment that exists to justify running at 8 kHz never measured the settings
  % actually running at 8 kHz -- and DSP_PARAMETERS quoted a "Senior baseline MFCC,
  % 8 kHz" row that no condition here produced. Its 8.3 % came from
  % CALIBRATE_DTW_THRESHOLD, a different protocol, presented in the same table.
  'Deployed MFCC, 8 kHz', ...
      {'featureFrontEnd','mfcc'; 'processingFs',8000; 'usePreEmphasis',false; ...
       'mfcc.CmsNormalise',false; 'mfcc.CmvNormalise',false; 'mfcc.DropC0',false}
  % Same settings at twice the rate: this pair, and only this pair, answers the
  % sample-rate question. Comparing the 8 kHz row against a 16 kHz row that also
  % differs in pre-emphasis would attribute the pre-emphasis effect to the rate.
  'Deployed MFCC, 16 kHz', ...
      {'featureFrontEnd','mfcc'; 'processingFs',16000; 'usePreEmphasis',false; ...
       'mfcc.CmsNormalise',false; 'mfcc.CmvNormalise',false; 'mfcc.DropC0',false}
  % Proposal modification 3 instructs that pre-emphasis be discarded, on the grounds
  % that spectral subtraction already handles the spectral tilt. That instruction is
  % only testable against its matched pair at the rate actually deployed -- the
  % 16 kHz rows above answer the same question at a rate the system does not use.
  'Deployed MFCC + pre-emphasis, 8 kHz', ...
      {'featureFrontEnd','mfcc'; 'processingFs',8000; 'usePreEmphasis',true; ...
       'mfcc.CmsNormalise',false; 'mfcc.CmvNormalise',false; 'mfcc.DropC0',false}
  'MFCC + drop c0', ...
      {'featureFrontEnd','mfcc'; 'processingFs',16000; 'usePreEmphasis',false; ...
       'mfcc.CmsNormalise',false; 'mfcc.CmvNormalise',false; 'mfcc.DropC0',true}
  'MFCC + drop c0 + CMS', ...
      {'featureFrontEnd','mfcc'; 'processingFs',16000; 'usePreEmphasis',false; ...
       'mfcc.CmsNormalise',true; 'mfcc.CmvNormalise',false; 'mfcc.DropC0',true}
  'MFCC + drop c0 + CMVN', ...
      {'featureFrontEnd','mfcc'; 'processingFs',16000; 'usePreEmphasis',false; ...
       'mfcc.CmsNormalise',true; 'mfcc.CmvNormalise',true; 'mfcc.DropC0',true}
  'MFCC + CMVN, statics only', ...
      {'featureFrontEnd','mfcc'; 'processingFs',16000; 'usePreEmphasis',false; ...
       'mfcc.CmsNormalise',true; 'mfcc.CmvNormalise',true; 'mfcc.DropC0',true; ...
       'mfcc.IncludeDelta',false; 'mfcc.IncludeDeltaDelta',false}
  'MFCC + CMVN, no delta-delta', ...
      {'featureFrontEnd','mfcc'; 'processingFs',16000; 'usePreEmphasis',false; ...
       'mfcc.CmsNormalise',true; 'mfcc.CmvNormalise',true; 'mfcc.DropC0',true; ...
       'mfcc.IncludeDelta',true; 'mfcc.IncludeDeltaDelta',false}
  'MFCC + drop c0 + CMVN, 8 kHz', ...
      {'featureFrontEnd','mfcc'; 'processingFs',8000; 'usePreEmphasis',false; ...
       'mfcc.CmsNormalise',true; 'mfcc.CmvNormalise',true; 'mfcc.DropC0',true}
};
conditions = reshape(conditions', 2, [])';

n = size(conditions,1);
rows = cell(n, 8);

fprintf('\nRunning %d conditions over the enrolled corpus.\n', n);
fprintf('%-32s %7s %7s %9s %9s %7s %5s\n', ...
    'Condition','EER %','Sep','Thr(EER)','Thr(F1%)','FRR@1%','Dims');
fprintf('%s\n', repmat('-',1,86));

for k = 1:n
    p = apply_overrides(base, conditions{k,2});

    % Liveness must not gate the experiment: the matcher is what is being
    % measured, and a rejected file would change the pair count between rows and
    % break the one-factor-at-a-time control.
    p.liveness.Enable = false;

    % A fresh cache per condition, otherwise features computed under one
    % configuration would be reused under the next.
    find_best_voice_match('reset');

    t0 = tic;
    try
        r = calibrate_dtw_threshold(p, false);
        elapsed = toc(t0);
        dims = feature_dimension(p);
        rows(k,:) = {string(conditions{k,1}), 100*r.EER, r.Separation, ...
            r.ThresholdEER, r.ThresholdFar1, 100*r.FrrAtFar1, dims, r.GenuineCount};
        fprintf('%-32s %7.1f %7.3f %9.4f %9.4f %7.1f %5d   (%.1f s)\n', ...
            conditions{k,1}, 100*r.EER, r.Separation, r.ThresholdEER, ...
            r.ThresholdFar1, 100*r.FrrAtFar1, dims, elapsed);
    catch exception
        rows(k,:) = {string(conditions{k,1}), NaN, NaN, NaN, NaN, NaN, NaN, NaN};
        fprintf('%-32s  failed: %s\n', conditions{k,1}, exception.message);
    end
end

results = cell2table(rows, 'VariableNames', ...
    {'Condition','EERPercent','Separation','ThresholdEER','ThresholdFAR1', ...
     'FRRatFAR1Percent','FeatureDimension','GenuinePairs'});

writetable(results, outputFile);
fprintf('\nWritten to %s\n', outputFile);

valid = results(~isnan(results.EERPercent), :);
if ~isempty(valid)
    [~, best] = min(valid.EERPercent);
    fprintf('\nLowest equal error rate: %s (EER %.1f %%, threshold %.4f at FAR 1 %%).\n', ...
        valid.Condition(best), valid.EERPercent(best), valid.ThresholdFAR1(best));
end
find_best_voice_match('reset');
end

% -------------------------------------------------------------------------
function p = apply_overrides(p, overrides)
%APPLY_OVERRIDES Set dotted field paths such as 'mfcc.DropC0' on a struct.
for i = 1:size(overrides,1)
    parts = strsplit(overrides{i,1}, '.');
    if numel(parts) == 1
        p.(parts{1}) = overrides{i,2};
    else
        p.(parts{1}).(parts{2}) = overrides{i,2};
    end
end
end

function d = feature_dimension(p)
%FEATURE_DIMENSION Rows the configured front-end will emit, for the report.
switch lower(p.featureFrontEnd)
    case 'dft'
        d = p.dft.NumBands * (1 + double(p.dft.IncludeDelta));
    case 'mfcc'
        static = p.C - double(p.mfcc.DropC0);
        blocks = 1 + double(p.mfcc.IncludeDelta) ...
                   + double(p.mfcc.IncludeDelta && p.mfcc.IncludeDeltaDelta);
        d = static * blocks;
    otherwise
        d = NaN;
end
end
