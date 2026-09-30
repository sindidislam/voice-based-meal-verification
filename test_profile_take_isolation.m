function test_profile_take_isolation()
% A development/final recording placed beside enrollment must not enter scoring.
root=tempname; mkdir(root); clean=onCleanup(@()cleanup(root)); %#ok<NASGU>
p=dsp_parameters(false); p.enrollmentTemplateFileNames={'1.wav'};
source=fullfile(fileparts(mfilename('fullpath')),'Train','ID','2206147');
target=fullfile(root,'2206147'); mkdir(target);
copyfile(fullfile(source,'1.wav'),fullfile(target,'1.wav'));
copyfile(fullfile(source,'2.wav'),fullfile(target,'2.wav'));
f=enrol_template_features(fullfile(target,'1.wav'),[],p);
assert(~isempty(f));
find_best_voice_match('reset');
[distance,~,info]=find_best_voice_match(root,f,p);
assert(info.TemplatesUsed==1 && distance==0, ...
    'Only designated enrollment take 1 may enter the calibrated matcher.');
disp('PROFILE_TAKE_ISOLATION_PASS');
end

function cleanup(root)
find_best_voice_match('reset');
assert(startsWith(lower(root),lower(tempdir)));
rmdir(root,'s');
end
