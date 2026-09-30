function tests = test_legacy_entry_points
% Legacy public entry points must not retain a weaker authentication policy.
tests = functiontests(localfunctions);
end

function testLegacyGuiLaunchersUseCanonicalWorkflow(t)
% Source routing is checked without opening a window or microphone. These
% compatibility functions may only forward to the one deployed entry point.
for name = {'voice_recognition_gui','voice_recognition_gui1', ...
        'guest_entry_gui','registration_entry_gui'}
    source = executable_source(name{1});
    route = ['^function\s+' name{1} '\s*\(\s*\)\s*' ...
        'run_meal_system\s*\(\s*\)\s*;?\s*end\s*$'];
    verifyNotEmpty(t,regexp(source,route,'once'), ...
        [name{1} ' must use the canonical Student-ID plus name workflow.']);
end
end

function testLegacyScriptsUseCanonicalWorkflow(t)
% Executing the old scripts would clear the workspace and open recording UI.
for name = {'untitled','untitled2'}
    verifyNotEmpty(t,regexp(executable_source(name{1}), ...
        '^run_meal_system\s*\(\s*\)\s*;?\s*$','once'), ...
        [name{1} ' must not run a separate nearest-candidate access policy.']);
end
end

function testLegacyAuthenticationRefusesMissingClaim(t)
verifyError(t,@()authenticate_workflow(), ...
    'authenticate_workflow:legacyDisabled');
% A malformed code made the old workflow return normally. This direct call
% checks intentional refusal without ever starting that old microphone path.
verifyError(t,@()authenticate_workflow([],'bad','User',0), ...
    'authenticate_workflow:legacyDisabled');
end

function testLegacyAuthenticationCannotCaptureWithValidCode(t)
source=executable_source('authenticate_workflow');
assertEmpty(t,regexp(source, ...
    '\<(capture_voice_features|record_audio_dsp|find_best_voice_match|log_entry_csv)\s*\(', ...
    'once'),'Legacy authentication must refuse before capture, scoring, or logging.');
verifyError(t,@()authenticate_workflow([],'123456','User',0), ...
    'authenticate_workflow:legacyDisabled');
end

function testPaidManualClaimCannotServeWithoutBiometrics(t)
root=tempname; mkdir(root);
cleanup=onCleanup(@()rmdir(root,'s')); %#ok<NASGU>
p=dsp_parameters(); p.requireCoupon=true;
p.trainIdFolder=fullfile(root,'ID');
p.trainNameFolder=fullfile(root,'Name');
p.trainCouponFolder=fullfile(root,'Coupon');
p.logFile=fullfile(root,'MealLog.csv');
p.monthlyEntitlementFile=fullfile(root,'Fees.csv');
p.monthlyCouponFile=fullfile(root,'Coupons.csv');
p.verificationLogFile=fullfile(root,'Attempts.csv');
p.meals=struct('Name','Lunch','Start',[12 0],'End',[14 0]);
mkdir(fullfile(p.trainIdFolder,'2206149'));
paid=table("2206149","2026-09","2026-09-01","12:00:00","Fixture", ...
    'VariableNames',{'Student','Month','PaidDate','PaidTime','Method'});
writetable(paid,p.monthlyEntitlementFile);
before=fileread(p.monthlyEntitlementFile);
r=manual_entry_workflow('2206149','',p,datetime(2026,9,27,12,30,0),false);
verifyFalse(t,r.Granted,'Payment alone cannot establish the person at the counter.');
verifyFalse(t,r.Logged);
verifyFalse(t,isfile(p.logFile));
verifyEqual(t,fileread(p.monthlyEntitlementFile),before);
verifyFalse(t,isfile(p.monthlyCouponFile));
end

function testManualDryRunCannotReportBiometricSuccess(t)
p=dsp_parameters(); p.requireCoupon=false;
root=tempname; mkdir(root);
cleanup=onCleanup(@()rmdir(root,'s')); %#ok<NASGU>
p.trainIdFolder=fullfile(root,'ID'); p.trainNameFolder=fullfile(root,'Name');
p.trainCouponFolder=fullfile(root,'Coupon');
mkdir(fullfile(p.trainIdFolder,'2206149'));
r=manual_entry_workflow('2206149','',p,datetime(2026,9,27,12,30,0),true);
verifyFalse(t,r.Granted,'SkipLogging must not turn a typed ID into verified identity.');
verifyFalse(t,r.Logged);
end

function source=executable_source(name)
file=fullfile(fileparts(mfilename('fullpath')),[name '.m']);
source=fileread(file);
source=regexprep(source,'(?m)^\s*%[^\r\n]*','');
source=strtrim(source);
end
