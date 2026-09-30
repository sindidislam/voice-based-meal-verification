function test_experiment_legacy_policy()
% The old workflow bypasses Name on significant ID and waives fallback margin.
assert(exist('experiment_legacy_policy','file')==2, ...
    'Missing source-traced existing-policy evaluator.');
p = dsp_parameters(); p.dtwThreshold=10; p.dtwMarginRatio=1.2;
id=score('2206149',9,'2206148',11);
name=score('2206148',2,'2206149',9);
r=experiment_legacy_policy(id,name,p);
assert(r.Accepted && r.Student=="2206149" && r.UsedPhrase=="ID", ...
    'Preserved policy accepts significant ID without consulting contradictory Name.');
id=score('2206149',5,'2206148',5.1);
name=score('2206148',6,'2206149',6.01);
r=experiment_legacy_policy(id,name,p);
assert(r.Accepted && r.Student=="2206148" && r.UsedPhrase=="Name", ...
    'Preserved policy waives Name margin for an ambiguous ID top-two candidate.');
fprintf('Preserved workflow policy characterization passed.\n');
end

function info=score(best,d,runner,r)
info=struct('BestUser',best,'BestDistance',d,'RunnerUpUser',runner, ...
    'RunnerUpDistance',r,'Margin',r/max(d,eps));
end
