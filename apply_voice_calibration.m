function params = apply_voice_calibration(params, projectRoot)
%APPLY_VOICE_CALIBRATION Load frozen voice settings without business overrides.
% A missing file leaves PARAMS unchanged. An invalid deployment fails closed.
% v4.1.4_Final: all enrolment takes are used (the take-1-only rule was removed)
% and missing profile folders only raise a warning.
if nargin < 2 || isempty(projectRoot), projectRoot = fileparts(mfilename('fullpath')); end
file = fullfile(projectRoot, 'VoiceCalibration.mat');
if ~isfile(file), return; end
try
    variables = whos('-file', file);
    assert(any(strcmp({variables.name}, 'calibration')));
    loaded = load(file, 'calibration');
catch err
    error('voice_calibration:invalidCalibration', 'Cannot read voice calibration: %s', err.message);
end
c = loaded.calibration;
if ~isstruct(params) || ~isscalar(params) || ~isstruct(c) || ~isscalar(c) || ...
        ~isfield(c, 'Params') || ~isstruct(c.Params) || ~isscalar(c.Params)
    error('voice_calibration:invalidCalibration', 'Calibration must contain scalar struct Params.');
end
frozen = c.Params;
frontEnd = '';
if isfield(frozen, 'featureFrontEnd') && scalar_text(frozen.featureFrontEnd)
    frontEnd = lower(char(frozen.featureFrontEnd));
end
if ~ismember(frontEnd, {'mfcc','dft'})
    error('voice_calibration:invalidCalibration', 'Calibration has an unsupported feature frontend.');
end
gateNames = {'idDtwThreshold','nameDtwThreshold','idMarginRatio','nameMarginRatio'};
gates = struct();
for k = 1:numel(gateNames)
    name = gateNames{k};
    if ~isfield(frozen,name) || ~positive(frozen.(name)) || (k > 2 && frozen.(name) <= 1)
        error('voice_calibration:invalidThreshold', 'Invalid or missing calibrated gate: %s.', name);
    end
    gates.(name) = frozen.(name);
end
for name = {'dtwThreshold','dtwMarginRatio'}
    field = name{1};
    if isfield(frozen,field) && (~positive(frozen.(field)) || ...
            (strcmp(field,'dtwMarginRatio') && frozen.(field) <= 1))
        error('voice_calibration:invalidThreshold', 'Invalid calibrated gate: %s.', field);
    end
end
if ~isfield(c,'ProfileRoot') || ~scalar_text(c.ProfileRoot)
    error('voice_calibration:invalidProfileRoot', 'ProfileRoot must be a relative project folder.');
end
relative = char(c.ProfileRoot);
parts = regexp(relative, '[\\/]+', 'split');
if isempty(relative) || any(relative(1) == '/\') || contains(relative, ':') || any(strcmp(parts, '..'))
    error('voice_calibration:invalidProfileRoot', 'ProfileRoot must stay inside the project.');
end
profileRoot = fullfile(projectRoot, strrep(strrep(relative, '\', filesep), '/', filesep));
if ~isfolder(fullfile(profileRoot,'ID')) || ~isfolder(fullfile(profileRoot,'Name'))
    % v4.1.4_Final: warn and keep the defaults instead of refusing to start
    warning('voice_calibration:missingProfiles', ...
        'Calibrated profile folders not found under %s; legacy calibration not applied.', profileRoot);
    return;
end

% Do not copy the frozen experiment's acquisition duration, paths, payment,
% meal, admin, GUI or general evaluation settings into the live application.
allowed = {'processingFs','resample','agc','noise','endpoint','liveness', ...
    'usePreEmphasis','alpha','dft','Tw','Ts','R','M','C','L','mfcc','dtw', ...
    'dtwMarginRatio','templateAggregation','templateQuietLeadInRatio', ...
    'templateMinimumRms','enforceLivenessOnTemplates','quality'};
for k = 1:numel(allowed)
    name = allowed{k};
    if isfield(frozen,name), params.(name) = frozen.(name); end
end
for name = {'dtwThresholdByFrontEnd','speakerThresholdsByFrontEnd'}
    field = name{1};
    if ~isfield(params,field), params.(field) = struct(); end
    if ~isstruct(params.(field)) || ~isscalar(params.(field))
        error('voice_calibration:invalidCalibration', 'Invalid frontend calibration map: %s.', field);
    end
end
params.dtwThresholdByFrontEnd.(frontEnd) = max(gates.idDtwThreshold, gates.nameDtwThreshold);
params.speakerThresholdsByFrontEnd.(frontEnd) = gates;
params = select_feature_frontend(params, frontEnd);
params.trainBaseFolder = profileRoot;
params.trainIdFolder = fullfile(profileRoot,'ID');
params.trainNameFolder = fullfile(profileRoot,'Name');
params.trainCouponFolder = fullfile(profileRoot,'Coupon');
% v4.1.4 forced params.enrollmentTemplateFileNames = {'1.wav'} here, so every
% student was represented by ONE same-microphone take and any new microphone
% was rejected (root cause 1 of the false rejections).  v4.1.4_Final removes the
% allowlist: every usable take is a template (field absent = all files).
if isfield(params,'enrollmentTemplateFileNames')
    params = rmfield(params,'enrollmentTemplateFileNames');
end
params.voiceCalibration = struct('File',file,'ProfileRoot',profileRoot,'FrontEnd',frontEnd);
for name = {'Variant','Protocol'}
    field = name{1};
    if isfield(c,field), params.voiceCalibration.(field) = c.(field); end
end
end

function yes = positive(value)
yes = isnumeric(value) && isscalar(value) && isreal(value) && isfinite(value) && value > 0;
end

function yes = scalar_text(value)
yes = (ischar(value) && isrow(value) && ~isempty(value)) || ...
    (isstring(value) && isscalar(value) && ~ismissing(value) && strlength(value) > 0);
end
