function test_experiment_helpers()
% Catch unavailable synthetic modules and fabricated/ill-labeled stress data.
assert(exist('experiment_synthetic_stress','file')==2, ...
    'Synthetic stress measurement helper is missing.');
assert(exist('experiment_export_figures','file')==2, ...
    'Measured figure export helper is missing.');
root=fileparts(mfilename('fullpath'));
m=experiment_recording_split(root); users=unique(m.Student,'stable');
users=users(1:2); m=m(ismember(m.Student,users),:);
output=tempname; mkdir(output); cleanup=onCleanup(@() rmdir(output,'s'));
before=rng;
t=experiment_synthetic_stress(m(m.Role=="enrollment",:), ...
    m(m.Role=="development",:),users,dsp_parameters(),output,false);
after=rng;
assert(isequal(before,after),'Synthetic stress must preserve the caller random stream.');
assert(all(t.synthetic_agc_results.EvidenceType=="synthetic gain"));
assert(any(t.synthetic_agc_results.AGCEnabled) && any(~t.synthetic_agc_results.AGCEnabled));
assert(all(t.synthetic_noise_results.EvidenceType=="synthetic additive noise"));
assert(all(abs(t.synthetic_noise_results.InputSNRDb-t.synthetic_noise_results.RequestedSNRDb)<1e-8));
assert(all(isfinite(t.synthetic_noise_results.OutputSNRDb)));
v=t.synthetic_vad_results;
assert(any(v.ExpectedSpeech) && any(~v.ExpectedSpeech));
assert(all(~v.HasSpeech(v.Signal=="silence")));
assert(all(v.EvidenceType=="synthetic endpoint fixture"));
fprintf('Experiment helper invariants passed.\n');
end
