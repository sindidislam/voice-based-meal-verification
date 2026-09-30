function generate_dsp_default_reference(archiveRoot)
% Run once BEFORE implementation; use only the immutable archived functions.
here = fileparts(mfilename('fullpath')); old = pwd; oldPath = path;
c = onCleanup(@()restore_context(old,oldPath)); %#ok<NASGU>
cd(archiveRoot); addpath(archiveRoot,'-begin');
p = dsp_parameters(); fs = 44100; t = (0:fs-1)'/fs;
x = [zeros(round(.65*fs),1); .1*(.3+.7*sin(pi*t).^2).*(sin(2*pi*180*t)+.35*sin(2*pi*730*t)); zeros(round(.25*fs),1)];
reference.Params = p; reference.Input = x;
[y,f,d] = preprocess_audio(x,fs,p);
reference.LiveAudio = y; reference.LiveFs = f; reference.LiveRejected = d.Rejected;
reference.LiveFeatures = extract_features(y,f,p);
[x,fs] = audioread(fullfile(archiveRoot,'Train','Name','2206141','1.wav'));
reference.LegacyInput = x; reference.LegacyInputFs = fs;
[y,f,d] = preprocess_template_audio(x,fs,p);
reference.LegacyAudio = y; reference.LegacyFs = f; reference.LegacyRejected = d.Rejected;
reference.LegacyFeatures = extract_features(y,f,p);
target = fullfile(here,'fixtures'); if ~isfolder(target), mkdir(target); end
save(fullfile(target,'dsp_default_reference.mat'),'reference');
fprintf('Frozen archive reference: live %d frames, stored %d frames\n',size(reference.LiveFeatures,2),size(reference.LegacyFeatures,2));
end

function restore_context(old,oldPath)
cd(old); path(oldPath);
end
