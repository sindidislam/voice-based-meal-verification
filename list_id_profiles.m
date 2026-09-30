function profiles = list_id_profiles(params)
%LIST_ID_PROFILES Enumerate complete Student-ID voice profiles.
%
%   PROFILES = LIST_ID_PROFILES(PARAMS) scans Train/ID and returns a struct
%   array with fields Id and Name for every folder whose name is a valid
%   seven-digit Student ID and that holds at least one spoken-ID recording. The
%   display Name is read from the ID folder's metadata when present.
%
%   Only Train/ID is treated as the source of truth for identity. Legacy
%   name-keyed folders under Train/Name are never returned as identities: they
%   have no seven-digit key, so STUDENT_ID_CONTRACT rejects them and they are
%   silently skipped. This is what keeps the old senior corpus out of the new
%   ID-based matcher and analysis.
%
%   See also STUDENT_ID_CONTRACT, STUDENT_PROFILE, FIND_BEST_VOICE_MATCH.

if nargin < 1 || isempty(params)
    params = dsp_parameters();
end

profiles = struct('Id', {}, 'Name', {});

if ~isfolder(params.trainIdFolder)
    return;
end

entries = dir(params.trainIdFolder);
entries = entries([entries.isdir] & ~startsWith({entries.name}, '.'));

for k = 1:numel(entries)
    [id, ok] = student_id_contract(entries(k).name);
    if ~ok
        continue;   % legacy or malformed folder: not an identity
    end
    idFolder = fullfile(params.trainIdFolder, id);
    if isempty(dir(fullfile(idFolder, '*.wav')))
        continue;   % no spoken-ID takes yet: incomplete profile
    end
    meta = student_profile(params, id);
    profiles(end+1) = struct('Id', id, 'Name', meta.Name); %#ok<AGROW>
end

if ~isempty(profiles)
    [~, order] = sort({profiles.Id});
    profiles = profiles(order);
end
end
