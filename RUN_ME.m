% =========================================================================
% VOICE-BASED MEAL VERIFICATION SYSTEM FOR HALL DINING (EEE 312, Group 07)
% v4.1.4_claude - single entry point launcher
% =========================================================================
%   RUN_ME            open the counter GUI (builds the voice models first)
%   RUN_ME('evaluate') measure the engine on every stored voice
%                      (leave-one-take-out, cross-microphone, unknown speaker,
%                      perfect-mimic imposter) -> Results/claude_eval
%   RUN_ME('demo')     genuine / imposter / replay demonstration from files
%   RUN_ME('rebuild')  re-extract every enrolment file and retrain the models
%   RUN_ME('mic_check'), RUN_ME('calibrate_mic'), RUN_ME('enroll'), RUN_ME('test')
%                      unchanged v4.1.4 tools

function RUN_ME(mode)
if nargin < 1, mode = 'gui'; end

prjRoot = fileparts(mfilename('fullpath'));
% A sibling copy (e.g. "Final project v4.1.4") on the MATLAB path would shadow
% the functions of this version, so every other folder of the parent directory
% is removed from the path before this one is added.
parent = fileparts(prjRoot);
entries = strsplit(path, pathsep);
for k = 1:numel(entries)
    e = entries{k};
    if startsWith(e, parent) && ~startsWith(e, prjRoot)
        rmpath(e);
    end
end
addpath(genpath(prjRoot));

fprintf('\n=================================================================\n');
fprintf('  VOICE-BASED MEAL VERIFICATION SYSTEM FOR HALL DINING (EEE 312)\n');
fprintf('  v4.1.4_claude: phrase + voice biometrics, imposter ID, anti-replay\n');
fprintf('=================================================================\n');

switch lower(char(mode))
    case 'gui'
        p = dsp_parameters();
        if isfield(p,'vsd') && p.vsd.Enable
            fprintf('Voice profiles: %s\n', p.vsd.DataRoot);
            fprintf('Preparing voice models (first run on this PC takes about a minute)...\n');
            t = tic;  M = vsd_models(p.vsd);
            fprintf('  %d students enrolled, UBM from %s (%.1f s).\n', numel(M.Students), M.UbmSource, toc(t));
        end
        fprintf('Starting Graphical User Interface...\n');
        meal_verification_gui(p);

    case 'evaluate'
        E = vsd_evaluate_corpus();
        fprintf('%s\n', E.summary{:});

    case 'demo'
        test_vsd_engine();

    case 'rebuild'
        p = dsp_parameters();
        vsd_models(p.vsd, 'force');

    case 'mic_check'
        fprintf('Running Microphone Diagnostic Check...\n');
        mic_check([], 44100, true);

    case 'calibrate_mic'
        fprintf('Running Microphone Acoustic Calibration Wizard...\n');
        calibrate_microphone();

    case 'enroll'
        fprintf('Running Database Import and Model Enrollment...\n');
        import_and_enroll_database();

    case 'test'
        fprintf('Running Test Suites...\n');
        test_vsd_engine();
        runtests('test_mic_check');
        test_dtw_equivalence;

    otherwise
        fprintf(['Unknown mode: %s. Valid modes: "gui", "evaluate", "demo", "rebuild", ' ...
            '"mic_check", "calibrate_mic", "enroll", "test".\n'], mode);
end
end
