function params = select_feature_frontend(params, frontEnd)
%SELECT_FEATURE_FRONTEND Switch front-end and its calibrated threshold together.
%
%   PARAMS = SELECT_FEATURE_FRONTEND(PARAMS, FRONTEND) sets PARAMS.featureFrontEnd to
%   FRONTEND and PARAMS.dtwThreshold to the value calibrated for it, erroring if no
%   such value exists.
%
%   EEE 312 CO1, CO3.  PO(c) Design, PO(e) Modern tool usage.
%
%   Why a two-line function is worth having
%   --------------------------------------
%   A DTW distance has no absolute scale.  The 39-dimensional MFCC produces distances
%   around 20 to 50 and the 24-band log spectrum around 1 to 4, so a threshold
%   belonging to one front-end applied to the other is not a slightly wrong setting,
%   it is "accept everybody" or "accept nobody".  An earlier revision of this system
%   accepted 89.9 % of impostors for exactly that reason.
%
%   DSP_PARAMETERS binds params.dtwThreshold from params.featureFrontEnd at
%   construction and its header calls that mistake "unrepresentable".  It is not:
%
%       q = dsp_parameters();
%       q.featureFrontEnd = 'dft';      % threshold still 37.1585, calibrated for mfcc
%
%   which is the natural way to write a two-front-end sweep, and the resulting run
%   reports FAR 100.0 % without complaining about anything.  The binding is only safe
%   at construction, and nothing enforced that it be re-established afterwards.
%   Routing every switch through here does enforce it, and the error branch means a
%   new front-end cannot be measured until it has been calibrated -- which is the
%   right order to do those two things in.
%
%   See also DSP_PARAMETERS, CALIBRATE_DTW_THRESHOLD, EXTRACT_FEATURES.

if ~(ischar(frontEnd) && isrow(frontEnd)) && ...
        ~(isstring(frontEnd) && isscalar(frontEnd) && ~ismissing(frontEnd))
    error('select_feature_frontend:noThreshold', 'A single calibrated frontend name is required.');
end
frontEnd = lower(char(frontEnd));

if ~isfield(params, 'dtwThresholdByFrontEnd') || ...
        ~isstruct(params.dtwThresholdByFrontEnd) || ~isscalar(params.dtwThresholdByFrontEnd) || ...
        ~isfield(params.dtwThresholdByFrontEnd, frontEnd)
    error('select_feature_frontend:noThreshold', ...
        ['Front-end "%s" has no calibrated DTW threshold. Run ' ...
         'CALIBRATE_DTW_THRESHOLD and add the result to ' ...
         'params.dtwThresholdByFrontEnd.'], frontEnd);
end

threshold = params.dtwThresholdByFrontEnd.(frontEnd);
if ~positive(threshold)
    error('select_feature_frontend:invalidThreshold', 'The frontend DTW threshold must be positive and finite.');
end
names = {'idDtwThreshold','nameDtwThreshold','idMarginRatio','nameMarginRatio'};
gates = struct();
if isfield(params, 'voiceCalibration') && ~isempty(params.voiceCalibration) && ...
        (~isfield(params, 'speakerThresholdsByFrontEnd') || ...
         ~isstruct(params.speakerThresholdsByFrontEnd) || ...
         ~isfield(params.speakerThresholdsByFrontEnd, frontEnd))
    error('select_feature_frontend:uncalibratedFrontend', ...
        'Frontend "%s" has no phrase calibration for the deployed enrollment.', frontEnd);
end
if isfield(params, 'speakerThresholdsByFrontEnd')
    map = params.speakerThresholdsByFrontEnd;
    if ~isstruct(map) || ~isscalar(map)
        error('select_feature_frontend:invalidSpeakerThresholds', 'The phrase threshold map is invalid.');
    end
    if isfield(map, frontEnd)
        gates = map.(frontEnd);
        if ~isstruct(gates) || ~isscalar(gates)
            error('select_feature_frontend:invalidSpeakerThresholds', 'Phrase thresholds must be a scalar struct.');
        end
        for k = 1:numel(names)
            name = names{k};
            if ~isfield(gates,name) || ~positive(gates.(name)) || (k > 2 && gates.(name) <= 1)
                error('select_feature_frontend:invalidSpeakerThresholds', 'Invalid or missing phrase gate: %s.', name);
            end
        end
    end
end
% Never keep phrase gates from the previously selected feature scale.
present = names(isfield(params,names));
if ~isempty(present), params = rmfield(params,present); end
params.featureFrontEnd = frontEnd;
params.dtwThreshold = threshold;
if ~isempty(fieldnames(gates))
    for k = 1:numel(names), params.(names{k}) = gates.(names{k}); end
end
end

function yes = positive(value)
yes = isnumeric(value) && isscalar(value) && isreal(value) && isfinite(value) && value > 0;
end
