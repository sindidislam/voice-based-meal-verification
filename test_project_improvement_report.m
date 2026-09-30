function test_project_improvement_report()
% Saved evidence must drive the display, with honest denominators and scope.
assert(exist('project_improvement_report','file')==2, ...
    'The source-backed project improvement report is missing.');
root=fileparts(mfilename('fullpath'));
p=dsp_parameters(false);
r=project_improvement_report(p,root);
assert(abs(r.SampleReductionRatio-5.5125)<1e-12);
assert(abs(r.SampleReductionPercent-81.859410430839)<1e-10);
m=r.Metrics;
t=m(m.Key=="two_phrase_compute",:);
assert(height(t)==1 && t.Count==93);
assert(abs(t.ReferenceValue-0.625346309677419)<1e-12);
assert(abs(t.UpdatedValue-0.472614952688172)<1e-12);
assert(t.RelativeChangePercent<0, 'Shorter compute time must have negative relative change.');
n=m(m.Key=="synthetic_noise_top1",:);
assert(n.Count==372 && abs(n.ReferenceValue-100*276/372)<1e-10);
assert(abs(n.UpdatedValue-100*315/372)<1e-10);
assert(abs(n.AbsoluteChange-100*39/372)<1e-10);
s=m(m.Key=="synthetic_noise_snr",:);
assert(abs(s.UpdatedValue-5.38398804833216)<1e-10);
assert(isnan(s.RelativeChangePercent), 'A zero reference cannot define percent improvement.');
a=m(m.Key=="synthetic_agc_top1",:);
assert(a.Count==186 && abs(a.AbsoluteChange-100/186)<1e-10);
assert(all(contains(r.Historical.Scope,"historical")));
assert(any(contains(r.Notes,"original senior",'IgnoreCase',true)));
assert(any(contains(r.Notes,"impersonation",'IgnoreCase',true)));
assert(any(contains(r.Proposal.Implementation,"power",'IgnoreCase',true)), ...
    'The implemented power subtraction must not be confused with the proposal magnitude equation.');

% Security costs must be recomputed from matching per-claim phrase trials.
deployed=dsp_parameters();
current=project_improvement_report(deployed,root);
assert(isfield(current,'Replay') && height(current.Replay)==2, ...
    'A separately labeled strict-both saved-decision replay is missing.');
old=current.Replay(current.Replay.Policy=="Historical fallback",:);
strict=current.Replay(current.Replay.Policy=="Strict ID AND Name",:);
assert(old.GenuineAccepted=="30/31" && strict.GenuineAccepted=="15/31");
assert(abs(strict.FRRPercent-100*16/31)<1e-10);
assert(strict.FARPercent==0 && old.FARPercent==0);
assert(all(contains(current.Replay.Scope,"archived")));
changed=deployed; changed.idDtwThreshold=changed.idDtwThreshold+1;
changedReport=project_improvement_report(changed,root);
assert(isempty(changedReport.Replay), 'Changed deployed gates must invalidate saved-decision replay.');
assert(any(contains(changedReport.Notes,"gates differ",'IgnoreCase',true)));

% Recompute from a small changed fixture; hard-coded headline values fail.
fixture=tempname; mkdir(fixture);
cleanup=onCleanup(@() remove_fixture(fixture)); %#ok<NASGU>
folder=fullfile(fixture,'Results','experiments_20260927'); mkdir(folder);
noise=table(["a";"a";"b";"b"],repmat("ID",4,1),ones(4,1), ...
    repmat("white",4,1),repmat(5,4,1),["none";"spectral";"none";"spectral"], ...
    [0;2;0;4],[1;1;0;1], ...
    'VariableNames',{'Student','Phrase','SourceTake','NoiseType','RequestedSNRDb', ...
    'Method','SNRChangeDb','CorrectTop1'});
writetable(noise,fullfile(folder,'synthetic_noise_results.csv'));
f=project_improvement_report(p,fixture);
n=f.Metrics(f.Metrics.Key=="synthetic_noise_top1",:);
assert(n.Count==2 && n.ReferenceValue==50 && n.UpdatedValue==100);
s=f.Metrics(f.Metrics.Key=="synthetic_noise_snr",:);
assert(s.UpdatedValue==3);
assert(~any(f.Metrics.Key=="two_phrase_compute"), ...
    'Missing results must not be replaced with remembered benchmark values.');

% Unequal fixture sets must never masquerade as a paired comparison.
writetable(noise(1:3,:),fullfile(folder,'synthetic_noise_results.csv'));
f=project_improvement_report(p,fixture);
assert(~any(f.Metrics.Key=="synthetic_noise_top1"));
assert(any(contains(f.Notes,"unmatched",'IgnoreCase',true)));
fprintf('Project improvement report arithmetic, provenance and missing-data checks passed.\n');
end

function remove_fixture(folder)
if isfolder(folder) && startsWith(folder,tempdir)
    rmdir(folder,'s');
end
end
