function test_baseline_output_guard()
% An audit output cannot overwrite its preserved source, including equality.
root=tempname; mkdir(root); cleanup=onCleanup(@()rmdir(root,'s'));
for destination={root,fullfile(root,'results')}
    caught='';
    try
        baseline_audit(root,{},destination{1});
    catch err
        caught=err.identifier;
    end
    assert(strcmp(caught,'baseline_audit:preservation'), ...
        'Expected preservation guard, got %s',caught);
end
fprintf('Baseline source/output separation guard passed.\n');
end
