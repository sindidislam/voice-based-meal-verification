function tests = test_speaker_verification
% Regression: a nearest neighbor must not substitute for a claimed identity.
tests = functiontests(localfunctions);
end

function setupOnce(t)
root = tempname; mkdir(root);
t.TestData.root = root;
p = dsp_parameters(false); p.requireCoupon = false;
p.trainIdFolder = fullfile(root,'ID');
p.trainNameFolder = fullfile(root,'Name');
p.logFile = fullfile(root,'MealLog.csv');
p.monthlyEntitlementFile = fullfile(root,'Fees.csv');
p.monthlyCouponFile = fullfile(root,'Coupons.csv');
p.verificationLogFile = fullfile(root,'Attempts.csv');
p.dtwThreshold = 1e6;
p.meals=struct('Name','Lunch','Start',[12 0],'End',[14 0]);
ids = {'2206149','2206150'};
for n=1:2
    % Both synthetic speakers need a fundamental inside the live-speech band.
    [speech,~] = synth_voiced_signal(p.fs,1.2,[100 140]+n*20,[500 1500 2500]+n*170);
    raw = [zeros(round(.6*p.fs),1); .3*speech(:)/max(abs(speech)); zeros(round(.2*p.fs),1)];
    for phrase={'ID','Name'}
        folder = fullfile(root,phrase{1},ids{n}); mkdir(folder);
        path = fullfile(folder,'1.wav'); audiowrite(path,raw,p.fs);
    end
end
find_best_voice_match('reset');
t.TestData.p = p;
[t.TestData.a,qa] = enrol_template_features(fullfile(p.trainIdFolder,ids{1},'1.wav'),[],p);
[t.TestData.b,qb] = enrol_template_features(fullfile(p.trainIdFolder,ids{2},'1.wav'),[],p);
assertTrue(t,qa.Usable,qa.Reason); assertTrue(t,qb.Usable,qb.Reason);
end

function teardownOnce(t)
find_best_voice_match('reset');
rmdir(t.TestData.root,'s');
end

function testIdAloneCannotVerifyWithoutNameEvidence(t)
o = struct('ClaimedID','2206149','IDFeatures',t.TestData.a,'SkipLogging',true);
r = verify_meal_workflow([], '', t.TestData.p, o);
verifyFalse(t,r.Verified); verifyFalse(t,r.Granted);
verifyEmpty(t,r.Student); verifyEqual(t,r.Stage,'evidence-name');
verifyTrue(t,r.NameCaptured); verifyTrue(t,isnan(r.NameDistance));
end

function testBothAgreeAndMatchClaim(t)
r = invoke(t,'2206149',t.TestData.a,t.TestData.a);
verifyTrue(t,r.Verified); verifyTrue(t,r.Granted);
verifyEqual(t,r.Student,'2206149');
verifyFalse(t,isfile(t.TestData.p.logFile));
verifyFalse(t,isfile(t.TestData.p.monthlyEntitlementFile));
end

function testFalseClaimDoesNotBecomeNearestStudent(t)
r = invoke(t,'2206150',t.TestData.a,t.TestData.a);
verifyFalse(t,r.Granted); verifyFalse(t,r.Verified); verifyEmpty(t,r.Student);
verifyEqual(t,r.Stage,'claim-match');
end

function testPassingIdCannotSkipContradictoryName(t)
r = invoke(t,'2206149',t.TestData.a,t.TestData.b);
verifyFalse(t,r.Granted); verifyEmpty(t,r.Student);
verifyTrue(t,r.NameCaptured); verifyEqual(t,r.Stage,'consistency');
end

function testConfidentDifferentIdCannotBeRescuedByName(t)
r = invoke(t,'2206149',t.TestData.b,t.TestData.a);
verifyFalse(t,r.Verified); verifyFalse(t,r.Granted);
verifyEmpty(t,r.Student); verifyEqual(t,r.Stage,'consistency');
verifyTrue(t,r.NameCaptured); verifyEqual(t,r.IDStage,'verified');
verifyFalse(t,isfile(t.TestData.p.monthlyEntitlementFile));
end

function testAutomaticModeCannotOverrideExplicitClaim(t)
o=struct('ClaimedID','2206150','AutomaticMode',true, ...
    'IDFeatures',t.TestData.a,'NameFeatures',t.TestData.a,'SkipLogging',true);
r=verify_meal_workflow([], '',t.TestData.p,o);
verifyFalse(t,r.Verified); verifyFalse(t,r.Granted);
verifyEqual(t,r.ClaimedID,'2206150'); verifyEmpty(t,r.Student);
end

function testAutomaticTwoPhraseAgreementVerifies(t)
o=struct('IDFeatures',t.TestData.a,'NameFeatures',t.TestData.a,'SkipLogging',true);
r=verify_meal_workflow([], '',t.TestData.p,o);
verifyTrue(t,r.Verified); verifyEqual(t,r.Student,'2206149');
verifyTrue(t,r.NameCaptured); verifyEqual(t,r.IdentifiedBy,'id+name');
end

function testAutomaticMixedIdAndNameCannotGrant(t)
o=struct('IDFeatures',t.TestData.a,'NameFeatures',t.TestData.b,'SkipLogging',true);
r=verify_meal_workflow([], '',t.TestData.p,o);
verifyFalse(t,r.Verified); verifyFalse(t,r.Granted);
verifyTrue(t,r.NameCaptured); verifyEqual(t,r.Stage,'consistency');
verifyEmpty(t,r.Student);
end

function testMissingClaimNeverCapturesOrGrants(t)
r = invoke(t,'',t.TestData.a,t.TestData.a);
verifyFalse(t,r.Granted); verifyEqual(t,r.Stage,'claim');
end

function testAbsentOfflineFeaturesNeverOpenMicrophone(t)
r = invoke(t,'2206149',[],[]);
verifyFalse(t,r.Granted); verifyEqual(t,r.Stage,'evidence-id');
verifyEqual(t,r.AttemptCount,1);
end

function testInvalidFeaturesRetry(t)
r = invoke(t,'2206149',NaN(39,4),NaN(39,4));
verifyFalse(t,r.Granted); verifyEmpty(t,r.Student);
end

function testNameCannotRescueUnusableIdFeatures(t)
r = invoke(t,'2206149',NaN(39,4),t.TestData.a);
verifyFalse(t,r.Granted); verifyEmpty(t,r.IdentifiedBy);
verifyEqual(t,r.IDStage,'evidence');
end

function testBothPhrasesMustPassTheirOwnMargins(t)
p=t.TestData.p; p.dtwThreshold=40;
a=info('2206149',20,21); b=info('2206149',20,30);
r=speaker_verification_decision('2206149',a,b,p);
verifyFalse(t,r.Verified); verifyEqual(t,r.Stage,'margin');
verifyEqual(t,r.IDStage,'margin');
r=speaker_verification_decision('2206149',a,a,p);
verifyFalse(t,r.Verified); verifyEqual(t,r.Stage,'margin');
end

function testRunnerOutsideThresholdDoesNotWaiveMargin(t)
p=t.TestData.p; p.dtwThreshold=40;
a=info('2206149',39,41);
r=speaker_verification_decision('2206149',a,a,p);
verifyFalse(t,r.Verified); verifyEqual(t,r.Stage,'margin');
end

function testPassingIdDistanceStillRequiresNameDistance(t)
p=t.TestData.p; p.dtwThreshold=40;
r=speaker_verification_decision('2206149',info('2206149',1,90),info('2206149',41,90),p);
verifyFalse(t,r.Verified); verifyEqual(t,r.Stage,'threshold');
verifyEqual(t,r.NameStage,'threshold');
end

function testBothPhrasesUseTheirOwnDistanceCeilings(t)
p=t.TestData.p; p.idDtwThreshold=40; p.nameDtwThreshold=2;
r=speaker_verification_decision('2206149',info('2206149',41,90),info('2206149',3,90),p);
verifyFalse(t,r.Verified); verifyEqual(t,r.Stage,'threshold');
r=speaker_verification_decision('2206149',info('2206149',41,90),info('2206149',1,90),p);
verifyFalse(t,r.Verified); verifyEqual(t,r.Stage,'threshold');
verifyEqual(t,r.NormalizedScore,41/40);
r=speaker_verification_decision('2206149',info('2206149',20,90),info('2206149',1,90),p);
verifyTrue(t,r.Verified); verifyEqual(t,r.IdentifiedBy,'id+name');
verifyEqual(t,r.NormalizedScore,0.5);
end

function testTieAndMissingCompetitionRetry(t)
p=t.TestData.p;
for d=[0,Inf]
    r=speaker_verification_decision('2206149',info('2206149',0,d),info('2206149',0,d),p);
    verifyFalse(t,r.Verified);
end
end

function testServedLogCarriesEvidenceColumnsAndDuplicateIsDenied(t)
p=t.TestData.p;
p.logFile=fullfile(t.TestData.root,'servedMeal.csv');
p.verificationLogFile=fullfile(t.TestData.root,'servedAttempts.csv');
p.monthlyEntitlementFile=fullfile(t.TestData.root,'servedFees.csv');
o=struct('ClaimedID','2206149','IDFeatures',t.TestData.a, ...
    'NameFeatures',t.TestData.a,'NowValue',datetime(2026,9,22,12,30,0));
monthly_fee_entitlement('2206149',p,o.NowValue,'assign');
r=verify_meal_workflow([], '', p, o);
verifyTrue(t,r.Logged);
tab=readtable(p.logFile);
verifyTrue(t,all(ismember({'IDDistance','NameDistance','IDMargin','NameMargin'},tab.Properties.VariableNames)));
verifyTrue(t,isfinite(r.NameDistance),'Both phrases must contribute measured evidence.');
r2=verify_meal_workflow([], '', p, o);
verifyTrue(t,r2.Verified); verifyFalse(t,r2.Granted);
tab2=readtable(p.logFile); verifyEqual(t,height(tab2),1);
end

function testRejectedAttemptDoesNotWriteMealOrPayment(t)
p=t.TestData.p;
p.logFile=fullfile(t.TestData.root,'rejectedMeal.csv');
p.verificationLogFile=fullfile(t.TestData.root,'rejectedAttempts.csv');
p.monthlyEntitlementFile=fullfile(t.TestData.root,'rejectedFees.csv');
o=struct('ClaimedID','2206150','IDFeatures',t.TestData.a,'NameFeatures',t.TestData.a);
r=verify_meal_workflow([], '', p, o);
verifyFalse(t,r.Verified); verifyFalse(t,isfile(p.logFile));
verifyFalse(t,isfile(p.monthlyEntitlementFile));
tab=readtable(p.verificationLogFile,'TextType','string');
verifyEqual(t,height(tab),1); verifyEqual(t,tab.Verified(1),0);
verifyTrue(t,contains(tab.IDTop5(1),'2206149:'));
end

function testGMMUBMSpeakerRanking(t)
rng(42);
dim = 13;
% Generate speech frames for 3 synthetic students with distinct means
X1 = randn(200, dim) + 2.0;
X2 = randn(200, dim) - 2.0;
X3 = randn(200, dim) + repmat(linspace(-1, 1, dim), 200, 1);
allX = [X1; X2; X3];

ubm = voice_gmm_ubm('trainubm', allX, 8, 10);
m1 = voice_gmm_ubm('adapt', X1, ubm, 16);
m2 = voice_gmm_ubm('adapt', X2, ubm, 16);
m3 = voice_gmm_ubm('adapt', X3, ubm, 16);

MU = cat(3, m1, m2, m3);
% Test utterance from student 1
testUtt = randn(50, dim) + 2.0;
[llr, ranks] = voice_gmm_ubm('score', testUtt, MU, ubm);

verifyEqual(t, ranks(1), 1); % Student 1 must rank #1
verifyGreaterThan(t, llr(1), llr(2));
verifyGreaterThan(t, llr(1), llr(3));
end

function testCohortScoreRejectsImpostor(t)
% Student 1 is a genuine match (dist = 22); Students 2-5 are competitors (~38)
dists = [22.0; 37.5; 38.2; 39.0; 38.8];
cohortScore = voice_match_scores('cohort_ratio', dists, 1, 4);
verifyGreaterThan(t, cohortScore, 0.30); % Genuine > 0.30

% Impostor case: distance is 37.71, competitors are ~38.7
impostorDists = [37.71; 38.74; 42.37; 43.39; 44.0];
impostorCohort = voice_match_scores('cohort_ratio', impostorDists, 1, 4);
verifyLessThan(t, impostorCohort, 0.15); % Impostor fails cohort gate (< 0.15)
end

function testCohortNormalizationRescuesAttenuatedLiveCapture(t)
% Parameter threshold = 31.35. A live capture with distance = 35.0 would fail raw threshold.
% But with competitors at 45.0, CohortRatio is log(45/35) = 0.25 > 0.12.
p = dsp_parameters(false);
p.idDtwThreshold = 31.35;
p.nameDtwThreshold = 31.35;
p.dtwMarginRatio = 1.20;
p.cohortGate = 0.12;

idInfo = struct('BestUser','2206149','BestDistance',35.0,'RunnerUpUser','2206150', ...
    'RunnerUpDistance',45.0,'Margin',45.0/35.0,'CohortRatio',0.25);
nameInfo = struct('BestUser','2206149','BestDistance',34.5,'RunnerUpUser','2206150', ...
    'RunnerUpDistance',44.5,'Margin',44.5/34.5,'CohortRatio',0.25);

res = speaker_verification_decision('2206149', idInfo, nameInfo, p);
verifyTrue(t, res.Verified, 'Cohort normalization should verify genuine speaker when raw distance drifts due to mic level');
verifyEqual(t, res.Student, '2206149');
end


function r=invoke(t,claim,a,b)
o=struct('ClaimedID',claim,'IDFeatures',a,'NameFeatures',b,'SkipLogging',true);
r=verify_meal_workflow([], '', t.TestData.p, o);
end

function s=info(id,d,r)
s=struct('BestUser',id,'BestDistance',d,'RunnerUpUser','2206150', ...
    'RunnerUpDistance',r,'Margin',r/max(d,eps));
end
