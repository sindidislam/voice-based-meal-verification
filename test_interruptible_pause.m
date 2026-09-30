function ok = test_interruptible_pause()
%TEST_INTERRUPTIBLE_PAUSE Regression test ensuring interruptible_pause exists
%and functions as an accessible standalone utility across the application.

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

fprintf('\n--- 1. Testing interruptible_pause existence on MATLAB path ---\n');
p = which('interruptible_pause');
check(~isempty(p), sprintf('interruptible_pause is on MATLAB path (%s)', p));

fprintf('\n--- 2. Testing non-interrupted pause duration ---\n');
try
    t0 = tic;
    stopped = interruptible_pause(0.1, @() false);
    elapsed = toc(t0);
    check(~stopped, 'Returns false when stop check is false');
    check(elapsed >= 0.08, sprintf('Elapsed time (%.3f s) is close to requested duration (0.1 s)', elapsed));
catch err
    check(false, sprintf('interruptible_pause failed during non-interrupted run: %s', err.message));
end

fprintf('\n--- 3. Testing early interruption ---\n');
try
    t0 = tic;
    stopped = interruptible_pause(2.0, @() true);
    elapsed = toc(t0);
    check(stopped, 'Returns true when stop check is true');
    check(elapsed < 0.2, sprintf('Exits immediately upon stop request (elapsed: %.3f s)', elapsed));
catch err
    check(false, sprintf('interruptible_pause failed during interrupted run: %s', err.message));
end

fprintf('\n--- 4. Testing default arguments ---\n');
try
    stopped = interruptible_pause(0.05);
    check(~stopped, 'Default checkStopFcn handles missing 2nd argument gracefully');
catch err
    check(false, sprintf('interruptible_pause failed with 1 argument: %s', err.message));
end

if isempty(failures)
    fprintf('\n>>> ALL INTERRUPTIBLE_PAUSE TESTS PASSED! <<<\n\n');
    ok = true;
else
    fprintf(2, '\n>>> %d CHECK(S) FAILED <<<\n\n', numel(failures));
    ok = false;
end
end
