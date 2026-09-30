function ok = test_reset_coupon_registry()
%TEST_RESET_COUPON_REGISTRY Test reset_coupon_registry_csv operations

failures = {};
check = @(cond, msg) record_check(cond, msg);

    function record_check(cond, msg)
        if cond
            fprintf('  PASS: %s\n', msg);
        else
            fprintf(2, '  FAIL: %s\n', msg);
            failures{end+1} = msg;
        end
    end

fprintf('\n--- 1. Testing reset_coupon_registry_csv setup ---\n');
testDir = tempname;
mkdir(testDir);
cleanupDir = onCleanup(@() rm_if_present(testDir));
testRegistry = fullfile(testDir, 'MonthlyCouponRegistry.csv');

sampleData = table( ...
    ["2206147"; "2206148"; "2206149"], ...
    ["123456"; "654321"; "777777"], ...
    ["2026-09"; "2026-09"; "2026-08"], ...
    ["2026-09-01"; "2026-09-01"; "2026-08-01"], ...
    ["08:00:00"; "08:00:00"; "08:00:00"], ...
    [true; true; false], ...
    ["2026-09-01"; "2026-09-01"; ""], ...
    ["08:00:00"; "08:00:00"; ""], ...
    'VariableNames', {'Student','Coupon','Month','AssignedDate','AssignedTime','Consumed','UsedDate','UsedTime'});

writetable(sampleData, testRegistry);
check(isfile(testRegistry), 'Sample MonthlyCouponRegistry.csv written');

fprintf('\n--- 2. Testing unconsume mode ---\n');
[nMod, nRem, tbl] = reset_coupon_registry_csv(testRegistry, 'unconsume', '2206147');
check(nMod == 1, sprintf('Unconsumed 1 record for 2206147 (got %d)', nMod));
idx = find(tbl.Student == "2206147", 1);
check(~tbl.Consumed(idx), '2206147 is now Consumed=false');
check(tbl.UsedDate(idx) == "", '2206147 UsedDate cleared');

fprintf('\n--- 3. Testing student delete mode ---\n');
[nMod, nRem, tbl] = reset_coupon_registry_csv(testRegistry, 'student', '2206148');
check(nMod == 1, 'Removed 2206148');
check(nRem == 2, '2 records remain');
check(~any(tbl.Student == "2206148"), '2206148 no longer in table');

fprintf('\n--- 4. Testing month delete mode ---\n');
[nMod, nRem, tbl] = reset_coupon_registry_csv(testRegistry, 'month', '2026-08');
check(nMod == 1, 'Removed 1 August record');
check(nRem == 1, '1 record remains');

fprintf('\n--- 5. Testing all clear mode ---\n');
[nMod, nRem, tbl] = reset_coupon_registry_csv(testRegistry, 'all');
check(nMod == 1, 'Removed final record');
check(nRem == 0, '0 records remain');
check(height(tbl) == 0, 'Empty table returned');

readBack = readtable(testRegistry, 'TextType', 'string');
check(height(readBack) == 0, 'On-disk file has 0 rows');
check(all(ismember({'Student','Coupon','Month','Consumed'}, readBack.Properties.VariableNames)), ...
    'All schema headers intact');

if isempty(failures)
    fprintf('\n>>> ALL RESET COUPON REGISTRY TESTS PASSED! <<<\n\n');
    ok = true;
else
    fprintf(2, '\n>>> %d CHECK(S) FAILED <<<\n\n', numel(failures));
    ok = false;
end
end

function rm_if_present(folder)
if isfolder(folder), rmdir(folder, 's'); end
end
