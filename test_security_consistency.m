function tests = test_security_consistency
% Security policy regressions use score evidence and temporary storage only.
tests = functiontests(localfunctions);
end

function testNameWinnerCannotReplaceDifferentIdWinner(t)
p = limits();
id = evidence({'2206135','2206137','2206139'}, [20 25 50]);
name = evidence({'2206135','2206137','2206139'}, [50 20 55]);
r = speaker_verification_decision('',id,name,p);
verifyFalse(t,r.Verified);
verifyEmpty(t,r.Student);
verifyEqual(t,r.Stage,'consistency');
end

function testStrongNameCannotCompensateForIdAboveThreshold(t)
p = limits();
id = evidence({'2206137','2206139'}, [44 60]);
name = evidence({'2206137','2206139'}, [20 40]);
r = speaker_verification_decision('',id,name,p);
verifyFalse(t,r.Verified);
verifyEqual(t,r.Stage,'threshold');
end

function testIdMarginCannotBeWaivedByStrongNameMargin(t)
p = limits();
id = evidence({'2206137','2206139'}, [20 21]);
name = evidence({'2206137','2206139'}, [20 40]);
r = speaker_verification_decision('',id,name,p);
verifyFalse(t,r.Verified);
verifyEqual(t,r.Stage,'margin');
end

function testNameMarginCannotBeWaivedByStrongIdMargin(t)
p = limits();
id = evidence({'2206137','2206139'}, [20 40]);
name = evidence({'2206137','2206139'}, [20 21]);
r = speaker_verification_decision('',id,name,p);
verifyFalse(t,r.Verified);
verifyEqual(t,r.Stage,'margin');
end

function testNoRunnerUpDoesNotBecomeInfiniteConfidence(t)
p = limits();
id = evidence({'2206137'},20);
name = evidence({'2206137'},20);
r = speaker_verification_decision('',id,name,p);
verifyFalse(t,r.Verified);
verifyEqual(t,r.Stage,'margin');
end

function testReportedScoresCannotPassByWeightedAverage(t)
p = limits(); p.idDtwThreshold = 31.348; p.nameDtwThreshold = 30.351;
id = evidence({'2206137','2206139','2206152','2206142'},[37.71 38.74 42.37 43.39]);
name = evidence({'2206137','2206139','2206152','2206142'},[33.60 37.59 37.88 38.01]);
r = speaker_verification_decision('',id,name,p);
verifyFalse(t,r.Verified);
verifyEqual(t,r.Stage,'threshold');
end

function testImpostorAttackRejectedUnderScoreFusion(t)
p = limits();
p.enableScoreFusion = true;
p.liveFusedThreshold = 1.15;
p.idDtwThreshold = 31.348;
p.nameDtwThreshold = 30.351;
% Exact scores where 2206135 spoke 2206137's phrases, with name having >= 1.12 margin
id = evidence({'2206137','2206139','2206152','2206142'}, [37.71 38.74 42.37 43.39]);
name = evidence({'2206137','2206139','2206152','2206142'}, [33.60 38.50 39.00 40.00]);
r = speaker_verification_decision('', id, name, p);
verifyFalse(t, r.Verified); % MUST BE REJECTED!
end

function testCloseGenuineMatchVerifiesUnderScoreFusion(t)
p = limits();
p.enableScoreFusion = true;
p.liveFusedThreshold = 1.15;
p.idDtwThreshold = 31.348;
p.nameDtwThreshold = 30.351;
users = {'2206157','2206141','2206158','2206159'};
id = evidence(users, [30.42, 30.90, 31.55, 31.91]);
name = evidence(users, [40.00, 32.04, 34.02, 36.50]);
r = speaker_verification_decision('', id, name, p);
verifyTrue(t, r.Verified);
verifyEqual(t, r.Student, '2206141');
verifyEqual(t, r.Decision, 'VERIFIED');
end

function testConsistentIndependentlyPassingPhrasesVerify(t)
p = limits();
id = evidence({'2206135','2206137'},[20 40]);
name = evidence({'2206135','2206137'},[22 45]);
r = speaker_verification_decision('',id,name,p);
verifyTrue(t,r.Verified);
verifyEqual(t,r.Student,'2206135');
verifyEqual(t,r.IdentifiedBy,'id+name');
verifyEqual(t,r.IDStage,'verified');
verifyEqual(t,r.NameStage,'verified');
end

function testClaimedIdDoesNotEnableContradictoryNameRescue(t)
p = limits();
id = evidence({'2206135','2206137'},[20 40]);
name = evidence({'2206135','2206137'},[45 20]);
r = speaker_verification_decision('2206137',id,name,p);
verifyFalse(t,r.Verified);
verifyEqual(t,r.Stage,'consistency');
end

function testTypedClaimCannotRescueAmbiguousDifferentId(t)
p = limits();
id = evidence({'2206135','2206137'},[20 21]);
name = evidence({'2206135','2206137'},[45 20]);
r = speaker_verification_decision('2206137',id,name,p);
verifyFalse(t,r.Verified);
verifyEmpty(t,r.Student);
verifyEqual(t,r.Stage,'consistency');
end

function testTypedClaimRequiresBothPhrases(t)
p=limits(); s=evidence({'2206135','2206137'},[20 40]);
r=speaker_verification_decision('2206135',s,struct(),p);
verifyFalse(t,r.Verified); verifyEqual(t,r.Stage,'evidence-name');
r=speaker_verification_decision('2206135',struct(),s,p);
verifyFalse(t,r.Verified); verifyEqual(t,r.Stage,'evidence-id');
end

function testTypedClaimCannotUseIdOnlyThresholdPass(t)
p=limits();
id=evidence({'2206135','2206137'},[20 50]);
name=evidence({'2206135','2206137'},[44 60]);
r=speaker_verification_decision('2206135',id,name,p);
verifyFalse(t,r.Verified); verifyEqual(t,r.Stage,'threshold');
end

function testTypedClaimCannotUseNameOnlyThresholdPass(t)
p=limits();
id=evidence({'2206135','2206137'},[44 60]);
name=evidence({'2206135','2206137'},[20 50]);
r=speaker_verification_decision('2206135',id,name,p);
verifyFalse(t,r.Verified); verifyEqual(t,r.Stage,'threshold');
end

function testLegacyFlagsCannotBypassMonthlyRoster(t)
folder=tempname; mkdir(folder);
cleanup=onCleanup(@()remove_temp(folder));
p=dsp_parameters(false);
p.trainIdFolder=fullfile(folder,'ID'); p.trainNameFolder=fullfile(folder,'Name');
p.logFile=fullfile(folder,'Meals.csv'); p.verificationLogFile=fullfile(folder,'Attempts.csv');
p.monthlyEntitlementFile=fullfile(folder,'Roster.csv'); p.monthlyCouponFile=fullfile(folder,'Coupons.csv');
p.requireMonthlyRoster=false; p.requireCoupon=false;
p.dtwThreshold=1e6; p.meals=struct('Name','Lunch','Start',[12 0],'End',[14 0]);
ids={'2206135','2206137'}; feat=[];
for n=1:2
    [speech,~]=synth_voiced_signal(p.fs,1.2,[100 140]+n*20,[500 1500 2500]+n*170);
    raw=[zeros(round(.6*p.fs),1);.3*speech(:)/max(abs(speech));zeros(round(.2*p.fs),1)];
    for phrase={'ID','Name'}
        path=fullfile(folder,phrase{1},ids{n}); mkdir(path);
        audiowrite(fullfile(path,'1.wav'),raw,p.fs);
    end
    if n==1, feat=enrol_template_features(fullfile(p.trainIdFolder,ids{n},'1.wav'),[],p); end
end
find_best_voice_match('reset');
opts=struct('ClaimedID','2206135','IDFeatures',feat,'NameFeatures',feat,'NowValue',datetime(2026,9,28,12,30,0));
r=verify_meal_workflow([],'123456',p,opts);
verifyTrue(t,r.Verified);
verifyFalse(t,r.Granted);
verifyEqual(t,r.Stage,'roster');
verifyFalse(t,isfile(p.logFile));
verifyFalse(t,isfile(p.monthlyEntitlementFile));
verifyFalse(t,isfile(p.monthlyCouponFile));
end

function testImpersonatorRejectedAtVoiceTimbreStage(t)
p = limits();
id = evidence({'2206137','2206139'}, [20 40]);
name = evidence({'2206137','2206139'}, [20 40]);
voiceReport = struct('VoiceRank', 2, 'TopUser', '2206139', 'LLRs', [0.5, 1.2]);
r = speaker_verification_decision('2206137', id, name, p, voiceReport);
verifyFalse(t, r.Verified);
verifyEqual(t, r.Stage, 'timbre');
verifySubstring(t, r.Reason, 'Voice timbre model ranked applicant #2');
end

function testGenuineApplicantPassesVoiceTimbreStage(t)
p = limits();
id = evidence({'2206137','2206139'}, [20 40]);
name = evidence({'2206137','2206139'}, [20 40]);
voiceReport = struct('VoiceRank', 1, 'TopUser', '2206137', 'LLRs', [1.2, 0.5]);
r = speaker_verification_decision('2206137', id, name, p, voiceReport);
verifyTrue(t, r.Verified);
verifyEqual(t, r.Stage, 'verified');
end

function p=limits()
p=struct('dtwThreshold',40,'idDtwThreshold',40,'nameDtwThreshold',40, ...
    'dtwMarginRatio',1.20,'idMarginRatio',1.20,'nameMarginRatio',1.20);
end

function s=evidence(users,scores)
users=string(users(:)); scores=scores(:);
[sorted,order]=sort(scores,'ascend');
s=struct('Users',users,'Scores',scores,'BestUser',char(users(order(1))), ...
    'BestDistance',sorted(1),'RunnerUpUser','','RunnerUpDistance',Inf);
if numel(sorted)>1
    s.RunnerUpUser=char(users(order(2))); s.RunnerUpDistance=sorted(2);
end
end

function remove_temp(folder)
find_best_voice_match('reset');
assert(startsWith(lower(folder),lower(tempdir)),'Unexpected cleanup path.');
if isfolder(folder), rmdir(folder,'s'); end
end
