function test_experiment_runner()
% Catch empty reporting, stale selections, and final-data leakage in the runner.
assert(exist('run_all_experiments','file')==2,'Integrated experiment runner is missing.');
output=tempname; mkdir(output); cleanup=onCleanup(@() rmdir(output,'s'));
r=run_all_experiments(struct('Mode','smoke','OutputDir',output,'Repeats',1,'MakePlots',false,'SyntheticStress',false));
assert(isfile(fullfile(output,'frozen_selection.mat')));
assert(isfile(fullfile(output,'accuracy_results.csv')));
assert(all(r.FreezeRoles~="final_test"),'Final records cannot enter selection.');
assert(r.FinalTestRecordingCount==8);
t=readtable(fullfile(output,'accuracy_results.csv'),'TextType','string');
assert(any(t.Split=="final_test" & t.Mode=="ID+Name"));
assert(all(t.GenuineAttempts(t.Status=="measured")==4));
assert(isfile(fullfile(output,'limitations.csv')));
files=["timing_results","ablation_results","confusion_matrix","threshold_results", ...
    "agc_results","noise_results","vad_results","liveness_results", ...
    "quality_results","feature_results","dtw_results","candidate_catalog"];
for file=files, assert(isfile(fullfile(output,file+".csv"))); end
frozen=load(fullfile(output,'frozen_selection.mat'));
assert(all(frozen.freeze.Manifest.Role~="final_test"));
assert(frozen.freeze.Params.idMarginRatio>1 && frozen.freeze.Params.nameMarginRatio>1);
assert(frozen.freeze.FinalExtractionStarted==false);
timing=readtable(fullfile(output,'timing_results.csv'),'TextType','string');
assert(any(timing.Stage=="ID+Name") && all(timing.MeanSeconds>=0));
pair=readtable(fullfile(output,'pair_distances.csv'),'TextType','string');
assert(any(pair.Genuine) && any(~pair.Genuine));
assert(isfile(fullfile(output,'run_summary.json')));
assert(isfile(fullfile(output,'multitemplate_results.csv')), ...
    'Supplemental multi-template measurements must be exported after frozen final evaluation.');
multi=readtable(fullfile(output,'multitemplate_results.csv'),'TextType','string');
assert(height(multi)==72);
summary=jsondecode(fileread(fullfile(output,'run_summary.json')));
assert(summary.RuntimeSeconds>0 && ~isempty(summary.MatlabVersion));
assert(strcmp(summary.Protocol.Enrollment,'take1') && strcmp(summary.Protocol.FinalTest,'take3'));
assert(strcmp(summary.SelectedVariant,r.SelectedVariant));
assert(summary.SelectedParams.idMarginRatio>1);
limits=readtable(fullfile(output,'limitations.csv'),'TextType','string');
assert(any(limits.Topic=="Archive preprocessing"));
assert(any(limits.Topic=="Replay security"));
pairCurve=readtable(fullfile(output,'pair_threshold_results.csv'),'TextType','string');
assert(all(pairCurve.GenuinePairs==4) && all(pairCurve.ImpostorPairs==12));
fprintf('Integrated experiment smoke passed.\n');
end
