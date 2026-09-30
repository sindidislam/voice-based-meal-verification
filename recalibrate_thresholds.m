function report = recalibrate_thresholds(params, verbose)
%RECALIBRATE_THRESHOLDS Re-measure the DTW threshold for every front-end.
%
%   REPORT = RECALIBRATE_THRESHOLDS() runs CALIBRATE_DTW_THRESHOLD once per front-end
%   named in PARAMS.dtwThresholdByFrontEnd and prints, for each, the numbers that
%   have to be copied back into DSP_PARAMETERS.  REPORT is a struct with one field
%   per front-end holding that front-end's full calibration report.
%
%   EEE 312 CO2 (compare theoretical and experimental results), CO5 (ethics: a
%   reported figure has to be the figure the code produces).  PO(d) Investigation.
%
%   When to run this
%   ---------------
%   Any time the set of enrolled files changes or the front-end changes.  Both are
%   easy to do without realising the thresholds have gone stale:
%
%     * RECORD_CORPUS_TOOL adds or replaces a recording.
%     * A change to ASSESS_RECORDING_QUALITY moves the line between usable and not,
%       so ENROL_TEMPLATE_FEATURES enrols a different set of files.
%     * A change to the front-end, the pre-emphasis switch or PROCESSING_FS changes
%       what a distance means.
%
%   A stale threshold does not announce itself.  A DTW distance has no absolute
%   scale, so a threshold measured on a slightly different corpus is still a
%   plausible-looking number that silently sits at the wrong point on the trade-off
%   curve.  Running this and pasting the result back is the only way the figures in
%   DSP_PARAMETERS stay the figures the code actually produces.
%
%   What to copy where
%   -----------------
%   For each front-end the run prints ThresholdEER and ThresholdFar1.  DSP_PARAMETERS
%   wants:
%
%     params.dtwThresholdByFrontEnd.<fe>   <- ThresholdEER
%     params.perPhraseReference.<fe>       <- Threshold = ThresholdFar1, Far = 0.010,
%                                             Frr = FrrAtFar1, Eer = EER,
%                                             EerThreshold = ThresholdEER
%
%   The EER threshold is the deployed one because the per-transaction decision is not
%   one distance: cross-phrase agreement and the runner-up margin carry most of the
%   defence, so buying false-accept protection by tightening this threshold only
%   spends genuine students on attacks the other gates already stop.  See the
%   composite-threshold discussion in DSP_PARAMETERS and the gate breakdown in
%   EXPERIMENT_VERIFICATION_ACCURACY.
%
%   After pasting, re-run VERIFY_DSP_PIPELINE: its threshold check asserts the
%   configured value against PARAMS.dtwThresholdByFrontEnd, so an inconsistent paste
%   fails loudly instead of propagating into the report.
%
%   See also CALIBRATE_DTW_THRESHOLD, SELECT_FEATURE_FRONTEND, DSP_PARAMETERS,
%   EXPERIMENT_FRONTEND_COMPARISON, VERIFY_DSP_PIPELINE.

if nargin < 1 || isempty(params), params = dsp_parameters(); end
if nargin < 2 || isempty(verbose), verbose = true; end

frontEnds = fieldnames(params.dtwThresholdByFrontEnd);
report = struct();

for i = 1:numel(frontEnds)
    fe = frontEnds{i};
    % SELECT_FEATURE_FRONTEND rather than a bare field assignment: setting
    % featureFrontEnd alone leaves dtwThreshold calibrated for the previous
    % front-end, which is how an earlier sweep reported FAR 100 % without
    % complaining about anything.
    q = select_feature_frontend(params, fe);

    fprintf('\n########## calibrate_dtw_threshold %s ##########\n', fe);
    r = calibrate_dtw_threshold(q, verbose);
    report.(fe) = r;

    fprintf(['\nPASTE %s: dtwThresholdByFrontEnd.%s = %.4f;  ' ...
        'perPhraseReference.%s = struct(''Threshold'',%.4f,''Far'',0.010,' ...
        '''Frr'',%.4f,''Eer'',%.4f,''EerThreshold'',%.4f);\n'], ...
        fe, fe, r.ThresholdEER, fe, r.ThresholdFar1, r.FrrAtFar1, r.EER, ...
        r.ThresholdEER);
    fprintf(['      measured over %d genuine and %d impostor pairs; the threshold ' ...
        'currently configured (%.4f) gives FAR %.2f %% / FRR %.2f %%\n'], ...
        r.GenuineCount, r.ImpostorCount, r.ConfiguredThreshold, ...
        100*r.FarAtConfigured, 100*r.FrrAtConfigured);
end

fprintf(['\nOne genuine pair is %.2f percentage points at this corpus size, so a ' ...
    'difference of one pair is at the resolution limit and must not be leaned on.\n'], ...
    100 / max(1, report.(frontEnds{1}).GenuineCount));
end
