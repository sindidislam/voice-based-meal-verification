function ok = test_id_margin_disambiguation()
%TEST_ID_MARGIN_DISAMBIGUATION Compatibility entry for the revised decision tests.
% ID-only acceptance and name fallback were deliberately removed. Regression
% coverage lives in the shared workflow/decision suite to avoid divergent rules.
r=runtests('test_speaker_verification');
ok=all([r.Passed]);
if ~ok, error('meal:DecisionRegression','Conservative verification regression failed.'); end
end
