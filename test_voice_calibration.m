function tests = test_voice_calibration
% Real temporary MAT files exercise deployment and frontend threshold binding.
tests = functiontests(localfunctions);
end

function setup(t)
t.TestData.root = tempname;
mkdir(t.TestData.root);
t.TestData.p = base_params();
end

function teardown(t)
root = t.TestData.root;
% Delete only the exact test directory created under MATLAB's temp directory.
assert(startsWith(lower(root), lower(tempdir)), 'Unexpected test cleanup path.');
if isfolder(root), rmdir(root, 's'); end
end

function testAbsentFileReturnsIdenticalParameters(t)
p = t.TestData.p;
q = apply_voice_calibration(p, t.TestData.root);
verifyEqual(t, q, p);
end

function testFrozenDspAndPhraseGatesLoadWithoutBusinessChanges(t)
p = t.TestData.p;
calibration = valid_calibration(p);
calibration.Params.processingFs = 16000;
calibration.Params.agc.TargetRms = .08;
calibration.Params.mfcc.CmvNormalise = true;
calibration.Params.templateAggregation = 'median';
calibration.Params.recordDur = 99;
calibration.Params.requireCoupon = false;
calibration.Params.adminPassword = 'must-not-load';
calibration.Params.logFile = 'must-not-load.csv';
calibration.Params.meals = struct('Breakfast', [1 0 2 0]);
calibration.Params.unrecognizedField = 'must-not-load';
save_calibration(t, calibration, true);
q = apply_voice_calibration(p, t.TestData.root);
verifyEqual(t, q.processingFs, 16000);
verifyEqual(t, q.agc.TargetRms, .08);
verifyTrue(t, q.mfcc.CmvNormalise);
verifyEqual(t, q.templateAggregation, 'median');
verifyEqual(t, q.recordDur, 8);
verifyEqual(t, q.requireCoupon, p.requireCoupon);
verifyEqual(t, q.adminPassword, p.adminPassword);
verifyEqual(t, q.logFile, p.logFile);
verifyEqual(t, q.meals, p.meals);
verifyFalse(t, isfield(q, 'unrecognizedField'));
verifyEqual(t, q.trainBaseFolder, fullfile(t.TestData.root, 'VSD_Enrollment', 'Train'));
verifyEqual(t, q.trainIdFolder, fullfile(q.trainBaseFolder, 'ID'));
verifyEqual(t, q.trainNameFolder, fullfile(q.trainBaseFolder, 'Name'));
verifyEqual(t, q.trainCouponFolder, fullfile(q.trainBaseFolder, 'Coupon'));
verifyEqual(t, q.enrollmentTemplateFileNames, {'1.wav'});
verifyEqual(t, q.dtwThreshold, 18);
verifyEqual(t, q.dtwThresholdByFrontEnd.mfcc, 18);
verifyEqual(t, q.idDtwThreshold, 14);
verifyEqual(t, q.nameDtwThreshold, 18);
verifyEqual(t, q.idMarginRatio, 1.25);
verifyEqual(t, q.nameMarginRatio, 1.30);
verifyEqual(t, q.voiceCalibration.Variant, 'fixture_mfcc');
verifyEqual(t, q.voiceCalibration.Protocol, calibration.Protocol);
end

function testMalformedCalibrationFailsClosed(t)
calibration = struct('ProfileRoot', 'VSD_Enrollment/Train');
save_calibration(t, calibration, true);
verifyError(t, @() apply_voice_calibration(t.TestData.p, t.TestData.root), ...
    'voice_calibration:invalidCalibration');
end

function testNonpositiveNonfiniteOrMissingPhraseThresholdFailsClosed(t)
for bad = {0, -1, NaN, Inf, [1 2], 1+1i, '14', []}
    calibration = valid_calibration(t.TestData.p);
    calibration.Params.idDtwThreshold = bad{1};
    save_calibration(t, calibration, true);
    verifyError(t, @() apply_voice_calibration(t.TestData.p, t.TestData.root), ...
        'voice_calibration:invalidThreshold');
end
calibration = valid_calibration(t.TestData.p);
calibration.Params = rmfield(calibration.Params, 'nameDtwThreshold');
save_calibration(t, calibration, true);
verifyError(t, @() apply_voice_calibration(t.TestData.p, t.TestData.root), ...
    'voice_calibration:invalidThreshold');
end

function testUnseparatedOrInvalidMarginFailsClosed(t)
for bad = {0, 1, NaN, Inf, [1.2 1.3], '1.2'}
    calibration = valid_calibration(t.TestData.p);
    calibration.Params.nameMarginRatio = bad{1};
    save_calibration(t, calibration, true);
    verifyError(t, @() apply_voice_calibration(t.TestData.p, t.TestData.root), ...
        'voice_calibration:invalidThreshold');
end
end

function testMissingNameProfileDirectoryFailsClosed(t)
calibration = valid_calibration(t.TestData.p);
save_calibration(t, calibration, false);
verifyError(t, @() apply_voice_calibration(t.TestData.p, t.TestData.root), ...
    'voice_calibration:missingProfiles');
end

function testProfileRootCannotEscapeProject(t)
for relative = {'../outside/Train', '..\outside\Train', 'C:\outside\Train', '\\server\Train'}
    calibration = valid_calibration(t.TestData.p);
    calibration.ProfileRoot = relative{1};
    save_calibration(t, calibration, true);
    verifyError(t, @() apply_voice_calibration(t.TestData.p, t.TestData.root), ...
        'voice_calibration:invalidProfileRoot');
end
end

function testSwitchToUnmappedDftRemovesMfccPhraseGates(t)
p = t.TestData.p;
p.idDtwThreshold = 14; p.nameDtwThreshold = 18;
p.idMarginRatio = 1.25; p.nameMarginRatio = 1.30;
p.speakerThresholdsByFrontEnd.mfcc = phrase_gates();
q = select_feature_frontend(p, 'dft');
verifyFalse(t, any(isfield(q, {'idDtwThreshold','nameDtwThreshold','idMarginRatio','nameMarginRatio'})));
evidence = score(3, 10);
decision = speaker_verification_decision('2206149', evidence, evidence, q);
verifyFalse(t, decision.Verified);
verifyEqual(t, decision.Stage, 'threshold');
q = select_feature_frontend(q, 'mfcc');
decision = speaker_verification_decision('2206149', evidence, evidence, q);
verifyTrue(t, decision.Verified);
verifyEqual(t, q.idDtwThreshold, 14);
verifyEqual(t, q.nameMarginRatio, 1.30);
end

function testMappedDftUsesItsOwnPhraseGates(t)
p = t.TestData.p;
p.idDtwThreshold = 14; p.nameDtwThreshold = 18;
g = phrase_gates(); g.idDtwThreshold = .6; g.nameDtwThreshold = .9;
p.speakerThresholdsByFrontEnd.dft = g;
q = select_feature_frontend(p, 'dft');
decision = speaker_verification_decision('2206149', score(.8, 3), score(.8, 3), q);
verifyFalse(t, decision.Verified);
verifyEqual(t, decision.Stage, 'threshold');
verifyEqual(t, decision.IDStage, 'threshold');
verifyEqual(t, q.idDtwThreshold, .6);
verifyEqual(t, q.nameDtwThreshold, .9);
end

function testMappedDftRejectsBothPhrasesOverTheirOwnCeilings(t)
p = t.TestData.p;
g = phrase_gates(); g.idDtwThreshold = .6; g.nameDtwThreshold = .9;
p.speakerThresholdsByFrontEnd.dft = g;
q = select_feature_frontend(p, 'dft');
decision = speaker_verification_decision('2206149', score(.8, 3), score(1, 3), q);
verifyFalse(t, decision.Verified);
verifyEqual(t, decision.IDStage, 'threshold');
verifyEqual(t, decision.NameStage, 'threshold');
verifyEqual(t, decision.Stage, 'threshold');
end

function testInvalidFrontendThresholdMappingFailsClosed(t)
p = t.TestData.p;
p.dtwThresholdByFrontEnd.dft = Inf;
verifyError(t, @() select_feature_frontend(p, 'dft'), ...
    'select_feature_frontend:invalidThreshold');
p = t.TestData.p;
g = phrase_gates(); g.nameMarginRatio = 1;
p.speakerThresholdsByFrontEnd.dft = g;
verifyError(t, @() select_feature_frontend(p, 'dft'), ...
    'select_feature_frontend:invalidSpeakerThresholds');
end

function testActiveCalibrationRejectsUnmappedFrontend(t)
p = t.TestData.p;
p.voiceCalibration = struct('File','fixture.mat','FrontEnd','mfcc');
p.speakerThresholdsByFrontEnd.mfcc = phrase_gates();
verifyError(t, @() select_feature_frontend(p, 'dft'), ...
    'select_feature_frontend:uncalibratedFrontend');
end

function p = base_params()
p = struct('fs',44100,'processingFs',8000,'recordDur',8, ...
    'featureFrontEnd','mfcc','dtwThreshold',37,'dtwMarginRatio',1.2, ...
    'requireCoupon',true,'adminPassword','original','logFile','original.csv', ...
    'meals',struct('Breakfast',[7 0 9 30]), 'templateAggregation','mean');
p.dtwThresholdByFrontEnd = struct('mfcc',37,'dft',2.5);
p.agc = struct('TargetRms',.05,'MaxGain',40);
p.mfcc = struct('CmvNormalise',false);
p.trainBaseFolder = 'original/Train';
p.trainIdFolder = 'original/Train/ID';
p.trainNameFolder = 'original/Train/Name';
p.trainCouponFolder = 'original/Train/Coupon';
end

function calibration = valid_calibration(p)
g = phrase_gates();
for field = fieldnames(g)', p.(field{1}) = g.(field{1}); end
calibration = struct('Params',p,'ProfileRoot','VSD_Enrollment/Train', ...
    'Variant','fixture_mfcc','Protocol',struct('Selection','development only'));
end

function g = phrase_gates()
g = struct('idDtwThreshold',14,'nameDtwThreshold',18, ...
    'idMarginRatio',1.25,'nameMarginRatio',1.30);
end

function save_calibration(t, calibration, includeName)
base = fullfile(t.TestData.root, 'VSD_Enrollment', 'Train');
if ~isfolder(fullfile(base,'ID')), mkdir(fullfile(base,'ID')); end
if includeName && ~isfolder(fullfile(base,'Name')), mkdir(fullfile(base,'Name')); end
save(fullfile(t.TestData.root,'VoiceCalibration.mat'), 'calibration');
end

function info = score(distance, runner)
info = struct('BestUser','2206149','BestDistance',distance, ...
    'RunnerUpUser','2206150','RunnerUpDistance',runner);
end
