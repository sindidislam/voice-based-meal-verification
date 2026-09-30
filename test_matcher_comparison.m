function tests=test_matcher_comparison
% Known alignment invariances, measured through the real comparison runner.
tests=functiontests(localfunctions);
end

function setupOnce(t)
root=tempname; mkdir(root); t.TestData.root=root;
t.addTeardown(@() remove_test_output(root));
t.TestData.report=experiment_matcher_comparison(struct('OutputDir',root,'Repeats',2));
end

function testIdenticalFeaturesHaveZeroDistanceForBothMatchers(t)
a=t.TestData.report.Trials;
a=a(a.Condition=="identity" & a.Genuine,:);
verifyEqual(t,sort(a.Matcher),["dtw";"xcorr"]);
verifyLessThanOrEqual(t,abs(a.Distance),[1e-12;1e-12]);
end

function testGlobalShiftIsHandledByBothMatchers(t)
a=t.TestData.report.Trials;
a=a(a.Condition=="global_shift" & a.Genuine,:);
verifyEqual(t,height(a),2);
verifyLessThanOrEqual(t,abs(a.Distance),[1e-12;1e-12]);
correlation=a(a.Matcher=="xcorr",:);
verifyEqual(t,abs(correlation.BestLagFrames),7);
end

function testDtwAlignsLocalTimingChangesThatOneLagCannotRemove(t)
a=t.TestData.report.Trials;
a=a(a.Condition=="nonlinear_timing" & a.Genuine,:);
verifyEqual(t,height(a),2);
verifyEqual(t,a.Distance(a.Matcher=="dtw"),0,'AbsTol',1e-12);
verifyGreaterThan(t,a.Distance(a.Matcher=="xcorr"),.01);
end

function testDtwStillSeparatesDifferentContentAfterTimeWarp(t)
a=t.TestData.report.Trials;
for condition=["uniform_slow","nonlinear_timing"]
    b=a(a.Condition==condition & a.Matcher=="dtw",:);
    verifyEqual(t,height(b),2);
    verifyLessThan(t,b.Distance(b.Genuine),b.Distance(~b.Genuine));
end
end

function testBothMethodsSeeTheSameQueryAndCandidateFrames(t)
a=t.TestData.report.Trials;
for condition=unique(a.Condition,'stable')'
    for candidate=unique(a.Candidate,'stable')'
        b=a(a.Condition==condition & a.Candidate==candidate,:);
        verifyEqual(t,height(b),2);
        verifyEqual(t,b.QueryFrames(1),b.QueryFrames(2));
        verifyEqual(t,b.TemplateFrames(1),b.TemplateFrames(2));
    end
end
end

function testArtifactsContainMeasuredScoresAndExplicitSyntheticScope(t)
r=t.TestData.report;
saved=readtable(fullfile(t.TestData.root,'matcher_trials.csv'),'TextType','string');
verifyEqual(t,height(saved),height(r.Trials));
verifyEqual(t,saved.Distance,r.Trials.Distance,'AbsTol',1e-12);
verifyTrue(t,all(r.Trials.EvidenceType=="synthetic scalar feature trajectories"));
verifyTrue(t,all(isfinite(r.Trials.Distance)));
verifyTrue(t,all(r.Trials.MeanSeconds>=0));
verifyTrue(t,isfile(fullfile(t.TestData.root,'matcher_summary.csv')));
metadata=jsondecode(fileread(fullfile(t.TestData.root,'run_summary.json')));
verifyFalse(t,metadata.IsSpeakerAccuracyEstimate);
verifyFalse(t,metadata.UsesFinalTestRecordings);
verifyFalse(t,metadata.ChangesCalibration);
end

function remove_test_output(root)
assert(startsWith(lower(root),lower(tempdir)));
if isfolder(root), rmdir(root,'s'); end
end
