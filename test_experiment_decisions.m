function test_experiment_decisions()
% Fallback can accept different claims; count claims and source trials honestly.
assert(exist('experiment_decision_metrics','file')==2, ...
    'Missing experiment_decision_metrics: experiment metrics absent.');
users = ["2206141";"2206147"];
id = {score(users,[1;4]);score(users,[4;1])};
name = {score(users,[4;1]);score(users,[4;1])};
p = dsp_parameters(false);
p.idDtwThreshold = 2; p.nameDtwThreshold = 2;
p.idMarginRatio = 1.2; p.nameMarginRatio = 1.2;
[metrics,trials] = experiment_decision_metrics(id,name,users,p,"ID+Name");
assert(metrics.GenuineAttempts==2 && metrics.ImpostorAttempts==2);
assert(metrics.GenuineAccepted==2 && metrics.FalseAccepted==1, ...
    'ID-first fallback must evaluate each supplied claim through the production decision.');
assert(metrics.FRR==0 && metrics.FAR==0.5 && metrics.WSAR==0.5);
assert(sum(trials.Accepted(trials.ActualStudent==users(1)))==2, ...
    'The same conflicting pair can verify its ID candidate and its Name candidate under different claims.');
assert(metrics.Top1Accuracy==1, ...
    'Combined-mode Top1Accuracy is the usable raw ID ranking, independent of Name disagreement.');
name{2} = score(users,[Inf;Inf]);
metrics = experiment_decision_metrics(id,name,users,p,"ID+Name");
assert(metrics.GenuineAccepted==2,'A passing ID does not need Name evidence.');
empty=score(users,[Inf;Inf]);
fallbackNames={score(users,[1;4]);score(users,[4;1])};
metrics=experiment_decision_metrics({empty;empty},fallbackNames,users,p,"ID+Name");
assert(metrics.GenuineAccepted==2 && metrics.FalseAccepted==0, ...
    'Usable Name evidence must independently rescue missing ID evidence for the requested claim.');
assert(metrics.Top1Accuracy==0,'Missing ID evidence cannot invent a correct ID-primary ranking.');
% Both speakers confidently match user 1: user 2's false claim is accepted.
% A correct claim is never reassigned, but enumerating claims still reveals
% one wrong identity acceptance out of the two actual-speaker attempts.
agreedWrong={score(users,[1;4]);score(users,[1;4])};
for mode=["ID","Name","ID+Name"]
    [metrics,trials]=experiment_decision_metrics(agreedWrong,agreedWrong,users,p,mode);
    assert(metrics.GenuineAccepted==1 && metrics.FalseAccepted==1);
    assert(metrics.FAR==0.5 && metrics.WSAR==0.5);
    assert(metrics.ClosedSetWrongAccepted==1 && metrics.ClosedSetWSAR==0.5, ...
        'Agreed wrong-candidate acceptance must count in closed-set WSAR with denominator N.');
    assert(metrics.CorrectClaimIdentityErrors==0);
    assert(~any(trials.Accepted(trials.ActualStudent==users(2) & trials.Genuine)), ...
        'A correct claimed ID must reject rather than be reassigned to the wrong candidate.');
end
% One actual speaker produces two wrong accepted claims. FAR counts both
% claims, whereas closed-set WSAR counts this source speaker only once.
users3=[users;"2206149"];
id3={score(users3,[4;1;4]);score(users3,[4;1;4]);score(users3,[4;4;1])};
name3={score(users3,[4;4;1]);score(users3,[4;1;4]);score(users3,[4;4;1])};
[metrics,trials]=experiment_decision_metrics(id3,name3,users3,p,"ID+Name");
assert(metrics.FalseAccepted==2 && metrics.ImpostorAttempts==6);
assert(abs(metrics.FAR-1/3)<1e-12 && metrics.WSAR==metrics.FAR);
assert(metrics.ClosedSetWrongAccepted==1 && abs(metrics.ClosedSetWSAR-1/3)<1e-12, ...
    'Two false claims from one actual student count once in closed-set WSAR.');
assert(abs(metrics.Top1Accuracy-2/3)<1e-12);
reported=report_fixture(metrics,trials,users3);
confusion=reported.confusion_matrix;
assert(sum(confusion.Count(confusion.ActualStudent==users3(1) & ...
    confusion.Outcome=="MULTIPLE CLAIMS"))==1, ...
    'Conflicting accepted claims must appear explicitly rather than abort or choose the first identity.');
for student=users3'
    assert(sum(confusion.Count(confusion.ActualStudent==student))==1, ...
        'Confusion bins must preserve one source-trial count per actual student.');
end
assert(any(contains(reported.limitations.Limitation,"ID-first fallback")), ...
    'The retained ID+Name mode identifier must be explained as ID-first fallback.');
assert(any(contains(reported.limitations.Limitation,"at least one false claim")), ...
    'Closed-set denominator documentation must distinguish actual students from accepted claims.');
fprintf('Experiment decision invariants passed.\n');
end

function result=report_fixture(metrics,trials,users)
variant="current_dsp"; split="development"; mode="ID+Name";
tables=struct();
tables.timing_raw=table(variant,split,"ID","Features","archive",0.1, ...
    'VariableNames',{'Variant','Split','Phrase','Stage','Scope','Seconds'});
tables.pair_distances=table(variant,split,"ID",1,true, ...
    'VariableNames',{'Variant','Split','Phrase','Distance','Genuine'});
tables.decision_trials=addvars(trials,repmat(variant,height(trials),1), ...
    repmat(split,height(trials),1),repmat(mode,height(trials),1), ...
    'Before',1,'NewVariableNames',{'Variant','Split','Mode'});
tables.accuracy_results=addvars(struct2table(metrics),variant,split,mode,"measured", ...
    'Before',1,'NewVariableNames',{'Variant','Split','Mode','Status'});
catalog=table(variant,"MFCC derivatives","fixture","measured_development", ...
    'VariableNames',{'Variant','Group','Change','Status'});
result=experiment_report_tables(tables,catalog,struct('Variant',variant),users);
end

function info = score(users,distances)
[d,ix] = sort(distances);
info = struct('Users',users,'Scores',distances,'BestUser',char(users(ix(1))), ...
    'BestDistance',d(1),'RunnerUpUser',char(users(ix(2))), ...
    'RunnerUpDistance',d(2),'Margin',d(2)/max(d(1),eps));
end
