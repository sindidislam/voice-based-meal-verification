function tests=test_verification_sequence
tests=functiontests(localfunctions);
end
function setupOnce(t)
root=tempname; mkdir(root); t.TestData.root=root;
p=dsp_parameters(false); p.requireCoupon=false; p.dtwThreshold=1e6;
p.trainIdFolder=fullfile(root,'ID'); p.trainNameFolder=fullfile(root,'Name');
p.logFile=fullfile(root,'Meals.csv'); p.verificationLogFile=fullfile(root,'Attempts.csv');
p.monthlyEntitlementFile=fullfile(root,'Fees.csv'); p.monthlyCouponFile=fullfile(root,'Coupons.csv');
ids={'2206149','2206150'}; features=cell(1,2);
for i=1:2
    [x,~]=synth_voiced_signal(p.fs,1.2,[100 140]+i*20,[500 1500 2500]+i*170);
    raw=[zeros(round(.6*p.fs),1);.3*x(:)/max(abs(x));zeros(round(.2*p.fs),1)];
    for phrase={'ID','Name'}
        folder=fullfile(root,phrase{1},ids{i}); mkdir(folder); audiowrite(fullfile(folder,'1.wav'),raw,p.fs);
    end
    features{i}=enrol_template_features(fullfile(p.trainIdFolder,ids{i},'1.wav'),[],p);
end
t.TestData.p=p; t.TestData.a=features{1}; t.TestData.b=features{2};
end
function teardownOnce(t)
find_best_voice_match('reset'); assert(startsWith(lower(t.TestData.root),lower(tempdir))); rmdir(t.TestData.root,'s');
end
function testStrongIdDoesNotVerifyWithoutName(t)
p=t.TestData.p; s=score('2206149',1,5);
r=speaker_verification_decision('2206149',s,struct(),p);
verifyFalse(t,r.Verified); verifyEqual(t,r.Stage,'evidence-name');
end
function testConfidentDifferentIdRejectsContradictoryName(t)
p=t.TestData.p; p.idDtwThreshold=2; p.nameDtwThreshold=3;
r=speaker_verification_decision('2206149',score('2206150',1,5),score('2206149',1,5),p);
verifyFalse(t,r.Verified); verifyEqual(t,r.Stage,'consistency');
verifyEqual(t,r.NameStage,'verified');
r=speaker_verification_decision('2206149',score('2206150',1,5),score('2206149',4,9),p);
verifyFalse(t,r.Verified);
end
function testSuccessfulTransactionCapturesBothPhrasesOnce(t)
[r,calls]=sequence(t,{t.TestData.a,t.TestData.a});
verifyTrue(t,r.Verified); verifyEqual(t,calls,{'ID','Name'});
verifyEqual(t,r.AttemptCount,1); verifyTrue(t,r.NameCaptured);
end
function testConfidentDifferentIdAndNameCannotVerify(t)
[r,calls]=sequence(t,{t.TestData.b,t.TestData.a});
verifyFalse(t,r.Verified); verifyEqual(t,calls,{'ID','Name'});
verifyTrue(t,r.NameCaptured); verifyEqual(t,r.AttemptCount,1);
end
function testFailedPairDisplaysFailedAndNeverThirdCapture(t)
[r,calls]=sequence(t,{[],t.TestData.b});
verifyFalse(t,r.Verified); verifyFalse(t,r.Granted);
verifyEqual(t,calls,{'ID','Name'});
verifyEqual(t,r.AttemptCount,1); verifyEqual(t,r.Decision,'FAILED'); verifyEqual(t,r.Stage,'failed');
verifyTrue(t,isfield(r,'FailureStage'),'The GUI needs the original refusal gate.');
if isfield(r,'FailureStage'), verifyEqual(t,r.FailureStage,'evidence-id'); end
verifyFalse(t,isfile(t.TestData.p.logFile));
end
function testFailedPairDoesNotUseAnAdditionalGoodId(t)
[r,calls]=sequence(t,{[],t.TestData.b,t.TestData.a});
verifyFalse(t,r.Verified); verifyEqual(t,calls,{'ID','Name'}); verifyEqual(t,r.AttemptCount,1);
end
function testNameCannotRescueIdCaptureQualityFailure(t)
[r,calls]=sequence(t,{[],t.TestData.a});
verifyFalse(t,r.Verified); verifyEqual(t,calls,{'ID','Name'});
end
function testStopPreventsNameCapture(t)
[r,calls]=sequence(t,{'STOP'});
verifyFalse(t,r.Verified); verifyEqual(t,calls,{'ID'}); verifyEqual(t,r.Stage,'user-stop');
end
function [r,calls]=sequence(t,outputs)
calls={}; index=0;
o=struct('ClaimedID','2206149','IDFeatures',[],'NameFeatures',[], ...
    'CaptureFcn',@capture,'SkipLogging',true);
r=verify_meal_workflow([], '',t.TestData.p,o);
    function [f,ok,d]=capture(phrase,~,~,~)
        index=index+1; assert(index<=numel(outputs),'Unexpected extra recording');
        calls{end+1}=phrase; f=outputs{index}; d=struct('Stage','fixture');
        if ischar(f), f=[]; d.Stage='user-stop'; end
        ok=~isempty(f);
    end
end
function s=score(id,d,runner)
other='2206150'; if strcmp(id,other), other='2206149'; end
s=struct('BestUser',id,'BestDistance',d,'RunnerUpUser',other,'RunnerUpDistance',runner);
end
