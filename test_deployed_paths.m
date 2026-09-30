function test_deployed_paths()
% Starting MATLAB elsewhere must not silently select another enrollment store.
project=fileparts(mfilename('fullpath'));
original=pwd; cleanup=onCleanup(@()cd(original)); %#ok<NASGU>
cd(tempdir);
p=dsp_parameters();
base=fullfile(project,'Train');
if isfield(p,'voiceCalibration'), base=fullfile(project,'VSD_Enrollment','Train'); end
assert(strcmp(p.trainIdFolder,fullfile(base,'ID')), ...
    'Enrollment paths must be anchored to the installed project.');
assert(strcmp(p.trainNameFolder,fullfile(base,'Name')));
assert(strcmp(p.logFile,fullfile(project,'MealLog.csv')));
assert(strcmp(p.monthlyEntitlementFile,fullfile(project,'MonthlyFeeEntitlement.csv')));
assert(strcmp(p.mealScheduleFile,fullfile(project,'MealSchedule.csv')));
assert(p.recordDur==8 && p.noise.NoiseDuration==.5);
disp('DEPLOYED_PATHS_PASS');
end
