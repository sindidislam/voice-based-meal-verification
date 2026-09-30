function test_experiment_protocol()
% Real invariants: a recording cannot occur in calibration and final test.
root = tempname; mkdir(root); cleanup = onCleanup(@() rmdir(root,'s'));
rng(9);
for phrase = ["ID","Name"]
    folder = fullfile(root,'Train',phrase,'2206141'); mkdir(folder);
    for take = 1:3
        audiowrite(fullfile(folder,sprintf('%d.wav',take)),0.01*randn(800,1),8000);
    end
end
assert(exist('experiment_recording_split','file') == 2, ...
    'Missing experiment_recording_split: safe role allocation is not implemented.');
manifest = experiment_recording_split(root);
assert(height(manifest)==6);
assert(all(manifest.Take(manifest.Role=="enrollment")==1));
assert(all(manifest.Take(manifest.Role=="development")==2));
assert(all(manifest.Take(manifest.Role=="final_test")==3));
assert(ismember('SHA256',manifest.Properties.VariableNames), ...
    'Each recording needs real SHA256 provenance for supplemental holdout checks.');
assert(all(strlength(manifest.SHA256)==64));
assert(numel(unique(manifest.SHA256))==height(manifest));
copyfile(fullfile(root,'Train','ID','2206141','1.wav'), ...
    fullfile(root,'Train','ID','2206141','3.wav'),'f');
failed = false;
try
    experiment_recording_split(root);
catch ex
    failed = strcmp(ex.identifier,'experiment:duplicateRecording');
end
assert(failed,'Byte-identical enrollment/test recordings must be rejected.');
fprintf('Experiment protocol invariants passed.\n');
end
