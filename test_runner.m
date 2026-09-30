function test_runner(testName)
try
    res = runtests(testName);
    nPassed = sum([res.Passed]);
    nFailed = sum([res.Failed]);
    fid = fopen('runner_result.txt', 'w');
    fprintf(fid, '=== TEST SUMMARY: %s ===\nPassed: %d, Failed: %d\n', testName, nPassed, nFailed);
    if nFailed > 0
        for k = 1:numel(res)
            if res(k).Failed
                fprintf(fid, 'FAILED: %s\n', res(k).Name);
            end
        end
    end
    fclose(fid);
catch ME
    % Fallback: try executing directly as script/function
    try
        fh = str2func(testName);
        [ok, fails] = fh();
        fid = fopen('runner_result.txt', 'w');
        if ok
            fprintf(fid, '=== TEST SUMMARY: %s ===\nPassed: 1, Failed: 0\n', testName);
        else
            fprintf(fid, '=== TEST SUMMARY: %s ===\nPassed: 0, Failed: %d\n', testName, numel(fails));
            for f = 1:numel(fails)
                fprintf(fid, 'FAILED: %s\n', fails{f});
            end
        end
        fclose(fid);
    catch ME2
        fid = fopen('runner_result.txt', 'w');
        fprintf(fid, '=== TEST ERROR ===\n%s\n%s\n', ME.message, ME2.message);
        fclose(fid);
    end
end
exit;
end
