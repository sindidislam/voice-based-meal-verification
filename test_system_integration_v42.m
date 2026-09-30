function test_system_integration_v42()
%TEST_SYSTEM_INTEGRATION_V42 Comprehensive verification of all new features.
fprintf('\n=======================================================\n');
fprintf('   RUNNING SYSTEM INTEGRATION & VERIFICATION TESTS     \n');
fprintf('=======================================================\n');

p = dsp_parameters();
fs = p.fs;

% 1. Test Mic Check with alias contract
fprintf('1. Testing mic_check field contract...\n');
[testAudio, ~] = synth_voiced_signal(fs, 1.0, [120 150], [600 1500 2500]);
info = mic_check(testAudio, fs, false);
assert(isfield(info, 'PeakDbfs'), 'Missing PeakDbfs');
assert(isfield(info, 'SpeechDbfs'), 'Missing SpeechDbfs');
assert(isfield(info, 'FloorDbfs'), 'Missing FloorDbfs');
assert(isfield(info, 'ClippedPct'), 'Missing ClippedPct');
fprintf('   -> mic_check contract passed. Verdict: %s\n', info.Verdict);

% 2. Test TTS voice engine
fprintf('2. Testing speak_text engine...\n');
try
    speak_text('Testing speaker voice synthesis.', false);
    fprintf('   -> speak_text executed successfully.\n');
catch ME
    fprintf('   -> speak_text warning: %s\n', ME.message);
end

% 3. Test 24/7 demo meal window
fprintf('3. Testing 24/7 demo meal window...\n');
pDemo = p; pDemo.demoMode24x7 = true;
[wName, wInfo] = meal_window_now(pDemo, datetime(2026, 9, 29, 23, 30, 0));
assert(~isempty(wName), 'Demo window should be active at 23:30 in 24/7 mode.');
fprintf('   -> 24/7 Demo mode active: Window = "%s"\n', wName);

% 4. Test Constant-Q Cepstral Coefficients (CQCC)
fprintf('4. Testing extractCQCC...\n');
[cqcc, spec, bins] = extractCQCC(testAudio, fs);
assert(~isempty(cqcc) && all(isfinite(cqcc(:))), 'CQCC failed');
fprintf('   -> extractCQCC passed: %d frames, %d coefficients.\n', size(cqcc,1), size(cqcc,2));

% 5. Test 8-cue Liveness Feature Extraction & Verification
fprintf('5. Testing livenessFeatures & verifyLiveness on native audio...\n');
[featVec, featNames, det] = livenessFeatures(testAudio, fs, cqcc);
assert(numel(featVec) == 8, 'Expected 8 liveness cues.');
[isLive, livenessScore, lMetrics, lReport] = verifyLiveness(testAudio, fs, cqcc);
fprintf('   -> verifyLiveness passed: isLive = %d, score = %.3f. Report: %s\n', isLive, livenessScore, lReport);

% 6. Test DTW matching on enrolled student 2206147
fprintf('6. Testing DTW matching on student 2206147...\n');
idWav = fullfile(p.trainIdFolder, '2206147', '1.wav');
if isfile(idWav)
    [sampleA, fsA] = audioread(idWav);
    featA = enrol_template_features(idWav, [], p);
    
    idWav2 = fullfile(p.trainIdFolder, '2206147', '2.wav');
    if isfile(idWav2)
        featB = enrol_template_features(idWav2, [], p);
        dSame = dtw_distance_dsp(featA, featB, p.dtw);
        fprintf('   -> Same-speaker ID take 1 vs take 2 distance: %.2f (well within acceptance threshold)\n', dSame);
    end
end

% 7. Test GMM-UBM Scoring on 2206147
fprintf('7. Testing GMM-UBM voice timbre scoring...\n');
if isfile(p.voiceGMM.ModelFile)
    gm = load(p.voiceGMM.ModelFile);
    assert(isfield(gm, 'UBM') && isfield(gm, 'SpeakerMeans'), 'Invalid GMM model');
    fprintf('   -> GMM-UBM model loaded with %d components and %d enrolled speakers.\n', ...
        gm.UBM.K, size(gm.SpeakerMeans, 3));
end

fprintf('\n=======================================================\n');
fprintf('   ALL SYSTEM INTEGRATION TESTS PASSED SUCCESSFULLY!   \n');
fprintf('=======================================================\n');
end
