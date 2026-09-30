function [features, info] = extract_features(x, fs, params)
%EXTRACT_FEATURES Front-end dispatcher for the meal-verification matcher.
%
%   [FEATURES, INFO] = EXTRACT_FEATURES(X, FS, PARAMS) returns a
%   D-by-NUMFRAMES feature matrix using the front-end named in
%   PARAMS.featureFrontEnd:
%
%     'dft'   Log magnitude-spectrum bands of 30 ms frames.  This is the
%             front-end specified in the Group 07 proposal.  See
%             EXTRACT_DFT_FEATURES.
%
%     'mfcc'  Mel-frequency cepstral coefficients with delta and
%             delta-delta.  This is the senior-baseline front-end, retained so
%             that the two can be measured against each other on the same
%             corpus, the same preprocessing and the same matcher.  See
%             EXTRACT_MFCC_DSP.
%
%   DSP_PARAMETERS sets 'mfcc' as the deployed default, on the measurement
%   reported there: 8.3 % equal error rate against the proposal front-end's
%   11.3 % on the same 97 genuine and 576 impostor pairs.  The proposal's
%   front-end is not discarded -- it is a measured condition with a calibrated
%   threshold of its own, selectable through SELECT_FEATURE_FRONTEND, which is
%   what CO2 asks for.
%
%   Having a single dispatcher matters for the validity of the comparison: the
%   only thing that changes between the two experimental conditions is the
%   contents of this switch statement, so any difference in accuracy is
%   attributable to the front-end and to nothing else.
%
%   INFO always contains a FrontEnd field naming the branch taken, plus
%   whatever the selected front-end reports.
%
%   See also EXTRACT_DFT_FEATURES, EXTRACT_MFCC_DSP, DSP_PARAMETERS,
%   SELECT_FEATURE_FRONTEND.

if nargin < 3, params = dsp_parameters(); end
featureTimer = tic;

% Fallback only, for a hand-built params struct with the field missing. It is
% deliberately NOT the deployed default: a caller reaching this line has told us
% nothing about which front-end it wants, and silently picking the deployed one
% would let a params struct that has lost the field keep working while its
% dtwThreshold, which IS front-end specific, no longer matches. 'dft' here means
% "the proposal's front-end, chosen by nobody", and it errors loudly downstream
% against an mfcc threshold instead of quietly mis-deciding.
frontEnd = 'dft';
if isfield(params,'featureFrontEnd') && ~isempty(params.featureFrontEnd)
    frontEnd = lower(char(params.featureFrontEnd));
end

switch frontEnd
    case 'dft'
        [features, info] = extract_dft_features(x, fs, params);
    case 'mfcc'
        [features, info] = extract_mfcc_dsp(x, fs, params);
    otherwise
        error('extract_features:unknownFrontEnd', ...
            'Unknown feature front-end "%s". Use ''dft'' or ''mfcc''.', frontEnd);
end

info.FrontEnd = frontEnd;
info.ExtractionSeconds = toc(featureTimer);
end
