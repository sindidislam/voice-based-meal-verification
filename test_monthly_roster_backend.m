function ok = test_monthly_roster_backend()
%TEST_MONTHLY_ROSTER_BACKEND Exercise roster storage using temporary files only.
root = tempname;
mkdir(root);
cleanup = onCleanup(@() rmdir(root, 's')); %#ok<NASGU>
p = struct('trainIdFolder', fullfile(root,'ID'), ...
    'trainNameFolder', fullfile(root,'Name'), ...
    'monthlyEntitlementFile', fullfile(root,'entitlements.csv'), ...
    'monthlyCouponFile', fullfile(root,'coupons.csv'));
sept = datetime(2026,9,28,12,30,0);
oct = datetime(2026,10,1,12,30,0);
make_profile(p, '2206147', true, true);
make_profile(p, '2206148', true, true);
make_profile(p, '2206149', true, false);
make_profile(p, '2206150', false, false);
make_profile(p, '2206151', false, false);
fid = fopen(fullfile(p.trainIdFolder,'2206151','1.wav'),'w');
fprintf(fid,'not audio'); fclose(fid);
fid = fopen(fullfile(p.trainNameFolder,'2206151','1.wav'),'w');
fprintf(fid,'not audio'); fclose(fid);
failures = {};
ids = list_enrolled_student_ids(p);
check(isequal(ids, {'2206147','2206148'}), ...
    'Enrollment requires readable ID and name recordings; empty and corrupt profiles excluded');
calibrated = p;
calibrated.trainIdFolder = fullfile(root,'calibrated','ID');
calibrated.trainNameFolder = fullfile(root,'calibrated','Name');
calibrated.monthlyEntitlementFile = fullfile(root,'calibrated-roster.csv');
for id = {'2206154','2206155','2206156','2206157'}
    make_profile(calibrated,id{1},true,true);
end
for id = {'2206155','2206157'}
    movefile(fullfile(calibrated.trainIdFolder,id{1},'1.wav'), ...
        fullfile(calibrated.trainIdFolder,id{1},'2.wav'));
end
for id = {'2206155','2206156'}
    movefile(fullfile(calibrated.trainNameFolder,id{1},'1.wav'), ...
        fullfile(calibrated.trainNameFolder,id{1},'2.wav'));
end
check(isequal(list_enrolled_student_ids(calibrated),{'2206154','2206155','2206156','2206157'}), ...
    'Without an active template allowlist all readable ID and name takes are eligible');
calibrated.enrollmentTemplateFileNames = {'1.wav'};
check(isequal(list_enrolled_student_ids(calibrated),{'2206154'}), ...
    'Take-1 calibration excludes take-2-only enrollment in either ID or name');
[assigned,~] = monthly_fee_entitlement('2206155',calibrated,sept,'assign');
check(~assigned && ~isfile(calibrated.monthlyEntitlementFile), ...
    'A profile excluded by the active calibration cannot receive monthly assignment');
calibrated.enrollmentTemplateFileNames = {'2.wav'};
check(isequal(list_enrolled_student_ids(calibrated),{'2206155'}), ...
    'Enrollment uses the configured allowed takes rather than a hard-coded take number');
calibrated.enrollmentTemplateFileNames = {};
check(isempty(list_enrolled_student_ids(calibrated)), ...
    'An explicitly empty template allowlist excludes all profiles like the matcher');
invalidDestination = fullfile(root,'directory-instead-of-csv');
mkdir(invalidDestination);
invalidParams = p;
invalidParams.monthlyEntitlementFile = invalidDestination;
[assigned,~] = monthly_fee_entitlement('2206147',invalidParams,sept,'assign');
check(~assigned && isempty(dir(fullfile(invalidDestination,'*.csv'))), ...
    'A directory configured as the CSV destination cannot report a successful assignment');

for invalid = {'2206', '220614700', '22061a7', '9999999', '2206149'}
    erase_store(p.monthlyEntitlementFile);
    [assigned,~] = monthly_fee_entitlement(invalid{1},p,sept,'assign');
    check(~assigned && ~isfile(p.monthlyEntitlementFile), ...
        ['Assignment rejects invalid or incomplete identity ' invalid{1} ' without writing']);
end

erase_store(p.monthlyEntitlementFile);
legacy = table("2206147","654321","2026-09","2026-09-01","08:00:00",false,"","", ...
    'VariableNames',{'Student','Coupon','Month','AssignedDate','AssignedTime','Consumed','UsedDate','UsedTime'});
writetable(legacy,p.monthlyCouponFile);
couponBefore = fileread(p.monthlyCouponFile);
p.requireCoupon = true; p.requireMonthlyRoster = false;
[paid,~] = monthly_fee_entitlement('2206147',p,sept,'record', ...
    struct('CouponCode','654321','Method','Voice+Coupon'));
check(~paid && ~isfile(p.monthlyEntitlementFile), ...
    'Legacy coupon redemption cannot create a monthly entitlement');
check(strcmp(couponBefore,fileread(p.monthlyCouponFile)), ...
    'Rejected redemption leaves legacy coupon history unchanged');

erase_store(p.monthlyEntitlementFile);
[assigned,~,assignInfo] = monthly_fee_entitlement('2206147',p,sept,'assign');
check(assigned && assignInfo.Recorded, 'An enrolled ID can be assigned directly');
before = fileread(p.monthlyEntitlementFile);
[assigned,~,assignInfo] = monthly_fee_entitlement('2206147',p,sept,'assign');
check(assigned && ~assignInfo.Recorded && strcmp(before,fileread(p.monthlyEntitlementFile)), ...
    'Repeated current-month assignment makes no duplicate and no rewrite');
[paid,~] = monthly_fee_entitlement('2206147',p,sept,'record');
check(~paid, 'Deprecated record action is rejected even for an assigned ID');
[paid,~] = monthly_fee_entitlement('2206147',p,sept,'unknown_action');
check(~paid, 'Unknown operations cannot return success from an existing entitlement');
[paid,~] = monthly_fee_entitlement('2206147',p,oct,'check');
check(~paid, 'A September assignment does not grant October dining');
[assigned,~] = monthly_fee_entitlement('2206147',p,oct,'assign');
data = read_text_table(p.monthlyEntitlementFile);
check(assigned && height(data)==2 && all(ismember(["2026-09";"2026-10"],data.Month)), ...
    'New-month assignment preserves the previous month');
[removed,~] = monthly_fee_entitlement('2206147',p,oct,'remove');
[septPaid,~] = monthly_fee_entitlement('2206147',p,sept,'check');
[octPaid,~] = monthly_fee_entitlement('2206147',p,oct,'check');
check(removed && septPaid && ~octPaid, 'Removal changes only the selected month');

hasBatch = exist('monthly_roster_assign','file') == 2;
check(hasBatch, 'Selected-ID batch assignment API is available');
if hasBatch
    before = fileread(p.monthlyEntitlementFile);
    [assigned,~] = monthly_roster_assign({'2206148','9999999'},p,sept);
    check(~assigned && strcmp(before,fileread(p.monthlyEntitlementFile)), ...
        'Mixed valid-invalid batch is rejected atomically');
    [assigned,~,batchInfo] = monthly_roster_assign({'2206148','2206147','2206148'},p,sept);
    data = read_text_table(p.monthlyEntitlementFile);
    check(assigned && height(data)==2 && batchInfo.AddedCount==1 && batchInfo.AlreadyAssignedCount==1, ...
        'Batch deduplicates selections and reports added versus already assigned IDs');
    before = fileread(p.monthlyEntitlementFile);
    [assigned,~] = monthly_roster_assign({},p,sept);
    check(~assigned && strcmp(before,fileread(p.monthlyEntitlementFile)), ...
        'Empty selection does not change the roster');

    data.OperatorNote = ["retain original note";"second note"];
    writetable(data,p.monthlyEntitlementFile);
    [assigned,~] = monthly_roster_assign('2206148',p,oct);
    after = read_text_table(p.monthlyEntitlementFile);
    check(assigned && height(after)==3 && isequaln(after(1:2,:),data), ...
        'Assignment preserves existing rows and additional history columns');
end

fid = fopen(p.monthlyEntitlementFile,'w');
fprintf(fid,'Student,Month\n2206147,2026-09\n'); fclose(fid);
corrupt = fileread(p.monthlyEntitlementFile);
for action = {'check','assign','assign_all','remove'}
    [success,~] = monthly_fee_entitlement('2206147',p,sept,action{1});
    check(~success && strcmp(corrupt,fileread(p.monthlyEntitlementFile)), ...
        ['Invalid schema fails closed without rewriting during ' action{1}]);
end
if hasBatch
    [assigned,~] = monthly_roster_assign({'2206147','2206148'},p,sept);
    check(~assigned && strcmp(corrupt,fileread(p.monthlyEntitlementFile)), ...
        'Invalid schema blocks batch assignment without partial writes');
end

erase_store(p.monthlyEntitlementFile);
[assigned,~,allInfo] = monthly_fee_entitlement('all',p,sept,'assign_all');
data = read_text_table(p.monthlyEntitlementFile);
check(assigned && height(data)==2 && isequal(sort(data.Student),["2206147";"2206148"]), ...
    'Assign all includes complete enrolled identities only');
check(isfield(allInfo,'AddedCount') && allInfo.AddedCount==2, ...
    'Assign all reports its current-month additions');
ok = isempty(failures);
fprintf('Monthly roster backend: %d failure(s).\n',numel(failures));

    function check(condition, message)
        if condition
            fprintf('  PASS: %s\n',message);
        else
            fprintf(2,'  FAIL: %s\n',message);
            failures{end+1} = message;
        end
    end
end

function make_profile(p,id,hasID,hasName)
mkdir(fullfile(p.trainIdFolder,id));
mkdir(fullfile(p.trainNameFolder,id));
t = (0:799)'/8000;
audio = 0.1*sin(2*pi*220*t);
if hasID, audiowrite(fullfile(p.trainIdFolder,id,'1.wav'),audio,8000); end
if hasName, audiowrite(fullfile(p.trainNameFolder,id,'1.wav'),audio,8000); end
end

function erase_store(path)
if isfile(path), delete(path); end
end

function data = read_text_table(path)
opts = detectImportOptions(path,'TextType','string');
opts = setvartype(opts,opts.VariableNames,'string');
data = readtable(path,opts);
end
