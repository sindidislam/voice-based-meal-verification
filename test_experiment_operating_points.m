function test_experiment_operating_points()
% Catch calibration selecting invalid gates and single/joint policy divergence.
users=["2206141";"2206147"]; p=dsp_parameters();
a=score(users,[1;1]); b=score(users,[4;1]);
id={a;b}; name=id;
[q,curve]=experiment_operating_points(id,name,users,p);
assert(all(curve.Margin>1),'Calibration must never propose invalid margin=1.');
m=experiment_decision_metrics(id,name,users,q,"ID");
j=experiment_decision_metrics(id,name,users,q,"ID+Name");
assert(m.GenuineAccepted==1 && j.GenuineAccepted==1, ...
    'Tied candidates reject while separated genuine evidence remains usable.');
% Cached Margin cannot override actual runner-up evidence.
id{1}.Margin=100; p.idDtwThreshold=2; p.nameDtwThreshold=2;
p.idMarginRatio=1.2; p.nameMarginRatio=1.2;
m=experiment_decision_metrics(id,id,users,p,"ID");
assert(m.GenuineAccepted==1,'Single-phrase scoring must reject a spoofed cached margin.');
% A tiny development set must not relax the deployed separation safeguard.
near={score(users,[1;1.05]);score(users,[1.05;1])};
[q,curve]=experiment_operating_points(near,near,users,p);
assert(all(curve.Margin>=1.2) && q.idMarginRatio>=1.2 && q.nameMarginRatio>=1.2, ...
    'Calibration must retain the configured 1.2 runner-up margin floor.');
% The scalable sweep must reproduce the real decision on both genuine and
% confidently wrong winners, including every proposed threshold/margin pair.
roster=["2206141";"2206147";"2206150"];
mixed={score(roster,[1;4;6]);score(roster,[.8;1.6;5]);score(roster,[4;5;1.5])};
[~,sweep]=experiment_operating_points(mixed,mixed,roster,p);
for row=1:height(sweep)
    check=p; check.idDtwThreshold=sweep.Threshold(row); check.nameDtwThreshold=sweep.Threshold(row);
    check.idMarginRatio=sweep.Margin(row); check.nameMarginRatio=sweep.Margin(row);
    reference=experiment_decision_metrics(mixed,mixed,roster,check,sweep.Mode(row));
    assert(reference.FalseAccepted==sweep.FalseAccepted(row));
    assert(abs(reference.FRR-sweep.FRR(row))<1e-12);
end
fprintf('Experiment operating-point invariants passed.\n');
end

function i=score(users,d)
[sorted,ix]=sort(d);
i=struct('Users',users,'Scores',d,'BestUser',char(users(ix(1))), ...
    'BestDistance',sorted(1),'RunnerUpUser',char(users(ix(2))), ...
    'RunnerUpDistance',sorted(2),'Margin',sorted(2)/max(sorted(1),eps));
end
