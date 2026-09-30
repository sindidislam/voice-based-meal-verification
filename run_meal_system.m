function run_meal_system(varargin)
%RUN_MEAL_SYSTEM Start the voice-based meal verification system.
%
%   RUN_MEAL_SYSTEM opens MEAL_VERIFICATION_GUI with the deployed configuration.
%   This is the single entry point: a student, a demonstrator or an examiner needs
%   to know one command.
%
%   RUN_MEAL_SYSTEM('dft') or RUN_MEAL_SYSTEM('mfcc') requests a named frontend.
%   An active deployment accepts only frontends with phrase-specific calibration
%   for its enrollment. SELECT_FEATURE_FRONTEND binds their distance/margin gates.
%
%   RUN_MEAL_SYSTEM('check') runs VERIFY_DSP_PIPELINE instead of opening a window.
%   Use this first on a machine that has never run the project: it exercises every
%   DSP stage against signals with known answers, needs no microphone, and takes a
%   few seconds. It checks software/DSP behavior, not live microphone accuracy.
%
%   Voice-Based Meal Verification System for Hall Dining
%   EEE 312 Digital Signal Processing I Laboratory -- Group 07, Section C1
%
%   See also MEAL_VERIFICATION_GUI, VERIFY_DSP_PIPELINE, DSP_PARAMETERS,
%   SELECT_FEATURE_FRONTEND.

if nargin >= 1 && (ischar(varargin{1}) || isstring(varargin{1})) && ...
        strcmpi(varargin{1}, 'check')
    verify_dsp_pipeline();
    return;
end

params = dsp_parameters();
if nargin >= 1 && ~isempty(varargin{1})
    params = select_feature_frontend(params, varargin{1});
end

fprintf('Voice-Based Meal Verification System for Hall Dining\n');
fprintf('  front-end %s at %g Hz, up to %.1f s per phrase; stops after detected pause\n', ...
    upper(params.featureFrontEnd), params.processingFs, params.recordDur);
fprintf('  ID distance <= %.4f, runner-up margin >= %.3f\n', ...
    field_or(params,'idDtwThreshold',params.dtwThreshold), ...
    field_or(params,'idMarginRatio',params.dtwMarginRatio));
fprintf('  Name distance <= %.4f, runner-up margin >= %.3f\n', ...
    field_or(params,'nameDtwThreshold',params.dtwThreshold), ...
    field_or(params,'nameMarginRatio',params.dtwMarginRatio));
if isfield(params,'voiceCalibration')
    fprintf('  voice calibration: %s\n', params.voiceCalibration.File);
end
fprintf('  meal log: %s\n', params.logFile);
fprintf(['  Speak ID once and name once; both must independently verify the same student.\n' ...
    '  An optional typed ID binds both checks. Admin assigns current-month access by ID.\n']);

meal_verification_gui(params);
end

function value = field_or(params,name,fallback)
value = fallback;
if isfield(params,name) && ~isempty(params.(name)), value = params.(name); end
end
