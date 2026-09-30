function tests = test_dsp_options
% Regression and behavioral tests for optional DSP experiments.
tests = functiontests(localfunctions);
end

function testAgcCanDisableGain(t)
x = [0.01; 0.03; -0.01; -0.03];
[y, info] = agc_normalize(x, struct('Enable',false));
verifyEqual(t, y, x);
verifyEqual(t, info.Gain, 1);
end

function testNoiseNoneIsIdentity(t)
x = sin((1:4000)'/13) * .1;
[y, d] = spectral_subtract_noise(x, 8000, struct('Method','none'));
verifyEqual(t,y,x); verifyTrue(t,d.Skipped);
end

function testWienerReducesStationaryNoise(t)
rng(312); fs = 8000; x = .02 * randn(2*fs,1);
x(fs+1:end) = x(fs+1:end) + .15*sin(2*pi*220*(0:fs-1)'/fs);
[y, d] = spectral_subtract_noise(x,fs,struct('Method','wiener'));
z = spectral_subtract_noise(x,fs,struct('Method','spectral'));
verifySize(t,y,size(x)); verifyTrue(t,all(isfinite(y)));
verifyLessThan(t,mean(y(3000:6000).^2),mean(x(3000:6000).^2));
verifyGreaterThan(t,norm(y-z),1e-5);
verifyEqual(t,d.Method,'wiener');
end

function testEnergyModeRetainsLowCrossingActivity(t)
fs = 8000; x = [zeros(fs,1); .1*ones(fs,1); zeros(fs,1)];
[~, h] = hybrid_endpoint_detect(x,fs,struct('Mode','hybrid'));
[~, e] = hybrid_endpoint_detect(x,fs,struct('Mode','energy'));
verifyFalse(t,h.HasSpeech); verifyTrue(t,e.HasSpeech);
verifyEqual(t,e.RejectedLowZcr,0);
end

function testOptionalMfccDimensionsAndWeights(t)
p = dsp_parameters(); x = speech_fixture(p.processingFs);
f = extract_features(x,p.processingFs,p);
verifyEqual(t,size(f,1),39);
p.mfcc.IncludeDelta = false; p.mfcc.IncludeDeltaDelta = false;
f0 = extract_features(x,p.processingFs,p); verifyEqual(t,size(f0,1),13);
p.mfcc.IncludePitch = true; p.mfcc.IncludeSpectral = true;
f1 = extract_features(x,p.processingFs,p); verifyEqual(t,size(f1,1),18);
p.mfcc.PitchWeight = 0; p.mfcc.SpectralWeight = 0;
f2 = extract_features(x,p.processingFs,p);
verifyEqual(t,f2(1:13,:),f0); verifyEqual(t,f2(14:end,:),zeros(5,size(f0,2)));
p.mfcc.StaticWeight = 2;
f3 = extract_features(x,p.processingFs,p); verifyEqual(t,f3(1:13,:),2*f0);
end

function testRastaSuppressesConstantCepstralOffset(t)
p = dsp_parameters(); p.mfcc.IncludeDelta = false; p.mfcc.IncludeDeltaDelta = false;
p.mfcc.Rasta = true;
ts = (0:p.processingFs-1)'/p.processingFs;
x = .1*sin(2*pi*220*ts) + .04*sin(2*pi*730*ts);
f = extract_features(x,p.processingFs,p);
g = extract_features(2*x,p.processingFs,p);
verifyLessThan(t,max(abs(f(:)-g(:))),1e-8);
p.mfcc.Rasta = false; h = extract_features(x,p.processingFs,p);
verifyGreaterThan(t,norm(f-h,'fro'),1);
end

function testPitchAndSpectralDescriptorsTrackKnownTones(t)
p = dsp_parameters(); p.mfcc.IncludePitch = true; p.mfcc.IncludeSpectral = true;
fs = 8000; ts = (0:fs-1)'/fs;
for hz = [200 300]
    f = extract_features(.1*sin(2*pi*hz*ts),fs,p);
    verifyEqual(t,median(f(40,:)),log2(hz/150),'AbsTol',.06);
    verifyGreaterThan(t,median(f(41,:)),.95);
    verifyEqual(t,median(f(42,:)),hz/4000,'AbsTol',.004);
    verifyEqual(t,median(f(43,:)),hz/4000,'AbsTol',.02);
    verifyLessThan(t,median(f(44,:)),.01);
end
end

function testCmvnAndDerivativeDimensions(t)
p = dsp_parameters(); p.mfcc.CmvNormalise = true;
p.mfcc.IncludeDeltaDelta = false;
f = extract_features(speech_fixture(p.processingFs),p.processingFs,p);
verifyEqual(t,size(f,1),26);
verifyLessThan(t,max(abs(mean(f(1:13,:),2))),1e-10);
verifyLessThan(t,max(abs(std(f(1:13,:),0,2)-1)),1e-10);
end

function testTemplateAggregation(t)
p = dsp_parameters(); lib.Users = "2206141"; lib.Templates = {{0,2,10}};
p.templateAggregation = 'mean'; [a,~] = voice_match_scores(lib,0,p);
p.templateAggregation = 'median'; [b,~] = voice_match_scores(lib,0,p);
p.templateAggregation = 'min'; [c,~] = voice_match_scores(lib,0,p);
verifyEqual(t,[a b c],[2 1 0]);
end

function testRateOptionsAndStageTiming(t)
p = dsp_parameters(); p.liveness.Enable = false; x = speech_fixture(44100);
for fs = [8000 16000 44100]
    p.processingFs = fs;
    [y, actualFs, d] = preprocess_audio(x,44100,p);
    verifyEqual(t,actualFs,fs); verifyNotEmpty(t,y);
    verifyTrue(t,isfield(d,'Timings'));
    if isfield(d,'Timings')
        verifyGreaterThanOrEqual(t,d.Timings.Total,0);
        verifyGreaterThanOrEqual(t,d.Timings.Noise,0);
    end
end
end

function testDtwBandPreservesIdentityAndLimitsWork(t)
a = [1:50; sin(1:50)];
[near,n] = dtw_distance_dsp(a,a,struct('SakoeChibaBand',.05));
[wide,w] = dtw_distance_dsp(a,a,struct('SakoeChibaBand',1));
verifyEqual(t,[near wide],[0 0]); verifyLessThan(t,n.CellsEvaluated,w.CellsEvaluated);
end

function testZcrReferenceMaintainsPhysicalLowerBoundary(t)
fs = 44100; time = (0:fs-1)'/fs;
x = [zeros(fs,1); .1*sin(2*pi*80*time); zeros(fs,1)];
[~, old] = hybrid_endpoint_detect(x,fs,struct());
[~, scaled] = hybrid_endpoint_detect(x,fs,struct('ZcrReferenceFs',8000));
verifyFalse(t,old.HasSpeech); verifyTrue(t,scaled.HasSpeech);
verifyEqual(t,scaled.ZcrLow,.008*8000/fs,'AbsTol',1e-14);
end

function testLiveQualityRejectsWeakAndClippedInput(t)
p = dsp_parameters(); p.liveness.Enable = false;
x = speech_fixture(8000);
d = assess_recording_quality(x*1e-5,8000,p,struct('Mode','live','Strict',true));
verifyFalse(t,d.Usable); verifyEmpty(t,d.Audio);
d = assess_recording_quality(.1+x*1e-5,8000,p,struct('Mode','live','Strict',true));
verifyFalse(t,d.Usable);
d = assess_recording_quality(min(1,max(-1,100*x)),8000,p,struct('Mode','live','Strict',true));
verifyFalse(t,d.Usable); verifyTrue(t,d.Clipped); verifyEmpty(t,d.Audio);
end

function testQualityDiagnosticsAreNotLivenessAlias(t)
p = dsp_parameters(); p.liveness.Enable = false;
[~,~,d] = preprocess_audio(speech_fixture(8000),8000,p);
verifyTrue(t,isfield(d.Quality,'AcRms'));
verifyFalse(t,isequaln(d.Quality,d.Liveness));
end

function testInvalidRateAndNonfiniteQualityAreRejected(t)
p = dsp_parameters();
for fs = [0 NaN Inf]
    d = assess_recording_quality(ones(100,1),fs,p);
    verifyFalse(t,d.Usable); verifyTrue(t,d.Rejected);
end
d = assess_recording_quality([NaN;1],8000,p);
verifyFalse(t,d.Usable); verifyTrue(t,d.Rejected);
end

function testCacheRecomputesAfterFeatureAffectingChange(t)
p = dsp_parameters(); p.liveness.Enable = false;
root = tempname; mkdir(root); mkdir(fullfile(root,'2206141'));
cleanup = onCleanup(@()cleanup_cache(root)); %#ok<NASGU>
audiowrite(fullfile(root,'2206141','1.wav'),speech_fixture(8000),8000);
file = fullfile(root,'2206141','1.wav');
[f,d] = enrol_template_features(file,[],p); verifyTrue(t,d.Usable);
find_best_voice_match('reset'); [a,~] = find_best_voice_match(root,f,p);
verifyEqual(t,a,0);
p.L = 10; [g,d] = enrol_template_features(file,[],p); verifyTrue(t,d.Usable);
[b,~] = find_best_voice_match(root,g,p); verifyEqual(t,b,0);
p.mfcc.IncludePitch = true; g = enrol_template_features(file,[],p);
[c,~] = find_best_voice_match(root,g,p); verifyEqual(t,c,0);
end

function testReplayCentroidRejection(t)
p = dsp_parameters();
fs = 8000;
timeAx = (0:1/fs:0.5)';
% Synthetic loudspeaker replay: bandpass filtered with high centroid (1500 Hz peak)
replaySig = 0.2 * sin(2*pi*1500*timeAx) + 0.1 * sin(2*pi*2000*timeAx);
[reject, ~, info] = check_liveness_lowfreq(replaySig, fs, p.liveness);
verifyTrue(t, reject);
verifyTrue(t, isfield(info, 'SpectralCentroid'));
verifyGreaterThan(t, info.SpectralCentroid, 1100);
end

function testCMVNZeroMeanUnitVariance(t)
p = dsp_parameters();
p.mfcc.useCMVN = true;
fs = 8000;
sig = speech_fixture(fs);
feat = extract_mfcc_dsp(sig, fs, p);
% Check mean across time frames (dimension 2) is close to 0 and std close to 1
mu = mean(feat, 2);
sig_std = std(feat, 0, 2);
verifyLessThan(t, max(abs(mu)), 1e-4);
verifyLessThan(t, max(abs(sig_std - 1)), 1e-2);
end

function testDefaultReferenceIsUnchanged(t)
% A frozen reference generated from the unmodified archived functions.
file = fullfile(fileparts(mfilename('fullpath')),'tests','fixtures','dsp_default_reference.mat');
assertTrue(t,isfile(file),'Generate the archive reference before modifying DSP functions.');
s = load(file); p = s.reference.Params; x = s.reference.Input;
[y,fs,d] = preprocess_audio(x,44100,p);
verifyEqual(t,y,s.reference.LiveAudio); verifyEqual(t,fs,s.reference.LiveFs);
verifyEqual(t,d.Rejected,s.reference.LiveRejected);
verifyEqual(t,extract_features(y,fs,p),s.reference.LiveFeatures,'AbsTol',1e-9);
[y,fs,d] = preprocess_template_audio(s.reference.LegacyInput,s.reference.LegacyInputFs,p);
verifyEqual(t,y,s.reference.LegacyAudio); verifyEqual(t,fs,s.reference.LegacyFs);
verifyEqual(t,d.Rejected,s.reference.LegacyRejected);
verifyEqual(t,extract_features(y,fs,p),s.reference.LegacyFeatures,'AbsTol',1e-9);
end

function x = speech_fixture(fs)
t = (0:fs-1)'/fs;
x = [zeros(round(.65*fs),1); .1*(.3+.7*sin(pi*t).^2).*(sin(2*pi*180*t)+.35*sin(2*pi*730*t)); zeros(round(.25*fs),1)];
end

function cleanup_cache(root)
find_best_voice_match('reset');
if isfolder(root), rmdir(root,'s'); end
end
