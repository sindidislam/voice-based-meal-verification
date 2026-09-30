function calibration=deploy_vsd_calibration(experimentDir)
%DEPLOY_VSD_CALIBRATION Install an already frozen, completed VSD experiment.
% Selection is never recomputed here and final scores never change the gates.
root=fileparts(mfilename('fullpath'));
if nargin<1, experimentDir=fullfile(root,'Results','experiments_20260927'); end
summary=jsondecode(fileread(fullfile(experimentDir,'run_summary.json')));
loaded=load(fullfile(experimentDir,'frozen_selection.mat'),'freeze');
freeze=loaded.freeze;
assert(strcmp(summary.Mode,'full') && summary.Protocol.SelectionFrozenBeforeFinalExtraction, ...
    'deployment:incompleteExperiment','A completed full experiment is required.');
assert(strcmp(summary.SelectedVariant,char(freeze.Variant)), ...
    'deployment:selectionMismatch','Summary and frozen selection must agree.');
assert(strcmp(jsonencode(summary.SelectedParams),jsonencode(freeze.Params)), ...
    'deployment:parameterMismatch','Summary and frozen parameters must agree.');
manifest=readtable(fullfile(experimentDir,'recording_manifest.csv'),'TextType','string');
manifest.Student=string(manifest.Student);
enrollment=manifest(manifest.Role=="enrollment",:);
assert(height(enrollment)==2*summary.StudentCount);
for k=1:height(enrollment)
    expected=fullfile(root,'VSD_Enrollment','Train',enrollment.Phrase(k),enrollment.Student(k),'1.wav');
    assert(isfile(expected),'deployment:missingTemplate','Missing template %s',expected);
    assert(strcmp(sha256(expected),enrollment.SHA256(k)), ...
        'deployment:templateMismatch','Deployed enrollment differs from measured take 1.');
end
calibration=struct('Params',freeze.Params,'ProfileRoot','VSD_Enrollment/Train', ...
    'Variant',char(freeze.Variant),'Protocol',summary.Protocol, ...
    'ExperimentDirectory',experimentDir,'InstalledAt',char(datetime('now')), ...
    'StudentCount',summary.StudentCount,'FrozenSelectionSHA256',sha256(fullfile(experimentDir,'frozen_selection.mat')));
destination=fullfile(root,'VoiceCalibration.mat');
assert(~isfile(destination),'deployment:existingCalibration', ...
    'Preserve the previous calibration explicitly before replacing it.');
save(destination,'calibration');
p=dsp_parameters();
assert(p.recordDur==8 && strcmp(p.trainBaseFolder,fullfile(root,'VSD_Enrollment','Train')));
assert(p.idDtwThreshold==freeze.Params.idDtwThreshold && p.nameDtwThreshold==freeze.Params.nameDtwThreshold);
assert(p.idMarginRatio==freeze.Params.idMarginRatio && p.nameMarginRatio==freeze.Params.nameMarginRatio);
fprintf('DEPLOYED: %d profiles, %s, ID %.8f / margin %.6f, Name %.8f / margin %.6f, capture %g s.\n', ...
    summary.StudentCount,freeze.Variant,p.idDtwThreshold,p.idMarginRatio,p.nameDtwThreshold,p.nameMarginRatio,p.recordDur);
end

function hash=sha256(file)
fid=fopen(file,'rb'); assert(fid>=0); close=onCleanup(@()fclose(fid)); %#ok<NASGU>
raw=fread(fid,Inf,'*uint8'); digest=java.security.MessageDigest.getInstance('SHA-256'); digest.update(raw);
hash=lower(reshape(dec2hex(typecast(digest.digest(),'uint8'),2)',1,[]));
end
