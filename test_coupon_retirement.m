function ok = test_coupon_retirement()
%TEST_COUPON_RETIREMENT Legacy coupon entry points cannot mutate private files.
root = tempname;
mkdir(root);
cleanup = onCleanup(@() rmdir(root,'s')); %#ok<NASGU>
p = struct('monthlyCouponFile',fullfile(root,'coupons.csv'), ...
    'monthlyEntitlementFile',fullfile(root,'entitlements.csv'), ...
    'requireCoupon',true,'requireMonthlyRoster',false);
nowValue = datetime(2026,9,28,12,30,0);
legacy = table(["2206147";"2206149"],["654321";"111222"], ...
    ["2026-09";"2026-08"],["2026-09-01";"2026-08-01"],["08:00:00";"08:00:00"], ...
    [false;true],["";"2026-08-01"],["";"12:30:00"], ...
    'VariableNames',{'Student','Coupon','Month','AssignedDate','AssignedTime','Consumed','UsedDate','UsedTime'});
roster = table("2206147","2026-09","2026-09-01","08:00:00","Admin-Roster", ...
    'VariableNames',{'Student','Month','PaidDate','PaidTime','Method'});
writetable(roster,p.monthlyEntitlementFile);
rosterBefore = fileread(p.monthlyEntitlementFile);
failures = {};
operations = { ...
    @() assign_monthly_coupon('2206148','777888',p,nowValue), ...
    @() consume_monthly_coupon('2206147','654321',p,nowValue), ...
    @() monthly_coupon_registry('2206148','777888',p,nowValue,'assign'), ...
    @() monthly_coupon_registry('2206147','654321',p,nowValue,'consume'), ...
    @() monthly_fee_entitlement('2206147',p,nowValue,'record',struct('CouponCode','654321'))};
labels = {'coupon assignment wrapper','coupon consumption wrapper', ...
    'direct coupon assignment','direct coupon consumption','entitlement coupon redemption'};
for k = 1:numel(operations)
    writetable(legacy,p.monthlyCouponFile);
    before = fileread(p.monthlyCouponFile);
    accepted = operations{k}();
    check(~accepted, [labels{k} ' is retired even with legacy flags and matching records']);
    check(strcmp(before,fileread(p.monthlyCouponFile)) && strcmp(rosterBefore,fileread(p.monthlyEntitlementFile)), ...
        [labels{k} ' preserves both private files']);
end
for mode = {'all','student','month','unconsume'}
    writetable(legacy,p.monthlyCouponFile);
    before = fileread(p.monthlyCouponFile);
    target = '2206149';
    if strcmp(mode{1},'month'), target = '2026-08'; end
    [modified,remaining,data] = reset_coupon_registry_csv(p.monthlyCouponFile,mode{1},target);
    check(modified==0 && remaining==2 && height(data)==2 && strcmp(before,fileread(p.monthlyCouponFile)), ...
        ['Retired reset mode ' mode{1} ' leaves readable legacy history unchanged']);
end
missing = fullfile(root,'missing.csv');
[modified,remaining] = reset_coupon_registry_csv(missing,'all');
check(modified==0 && remaining==0 && ~isfile(missing), ...
    'Retired reset does not create an empty registry file');
p.monthlyCouponFile = fullfile(root,'another-missing.csv');
[accepted,~] = assign_monthly_coupon('2206148','777888',p,nowValue);
check(~accepted && ~isfile(p.monthlyCouponFile), 'Retired assignment cannot create a registry');
check(strcmp(rosterBefore,fileread(p.monthlyEntitlementFile)), 'All coupon APIs preserve monthly dining assignments');
ok = isempty(failures);
fprintf('Coupon retirement: %d failure(s).\n',numel(failures));

    function check(condition,message)
        if condition
            fprintf('  PASS: %s\n',message);
        else
            fprintf(2,'  FAIL: %s\n',message);
            failures{end+1} = message;
        end
    end
end
