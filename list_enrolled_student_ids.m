function ids = list_enrolled_student_ids(params)
%LIST_ENROLLED_STUDENT_IDS Sorted complete ID+name voice profile identities.
%   Empty folders and unreadable WAV files do not establish enrollment. Each
%   seven-digit identity must have a readable, nonempty recording for both
%   its spoken ID and name before administration may assign dining access.
%   An active enrollmentTemplateFileNames allowlist matches the voice matcher:
%   only those takes establish enrollment for either phrase.
if nargin < 1 || isempty(params), params = dsp_parameters(); end
ids = {};
if ~isfield(params,'trainIdFolder') || ~isfield(params,'trainNameFolder') || ...
        ~isfolder(params.trainIdFolder) || ~isfolder(params.trainNameFolder)
    return;
end
entries = dir(params.trainIdFolder);
entries = entries([entries.isdir]);
for k = 1:numel(entries)
    id = entries(k).name;
    if numel(id)~=7 || any(id<'0' | id>'9'), continue; end
    if has_audio(fullfile(params.trainIdFolder,id),params) && has_audio(fullfile(params.trainNameFolder,id),params)
        ids{end+1} = id; %#ok<AGROW>
    end
end
ids = sort(unique(ids));
end

function found = has_audio(folder,params)
found = false;
files = dir(fullfile(folder,'*.wav'));
files = files(~[files.isdir]);
if isfield(params,'enrollmentTemplateFileNames')
    files = files(ismember(string({files.name}),string(params.enrollmentTemplateFileNames)));
end
for k = 1:numel(files)
    try
        details = audioinfo(fullfile(folder,files(k).name));
        if details.TotalSamples>0 && details.SampleRate>0 && details.NumChannels>0
            found = true;
            return;
        end
    catch
        % A stale or corrupt take is not an enrolled voice recording.
    end
end
end
