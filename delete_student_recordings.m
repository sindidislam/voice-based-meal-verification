function nDeleted = delete_student_recordings(folders)
%DELETE_STUDENT_RECORDINGS Remove all .wav files from specified profile folders.
%
%   nDeleted = delete_student_recordings(folders)
%   folders can be a char vector, string, or cell array of folder paths.

if ischar(folders) || isstring(folders)
    folders = {char(folders)};
end

nDeleted = 0;
for k = 1:numel(folders)
    f = char(folders{k});
    if isfolder(f)
        wavs = dir(fullfile(f, '*.wav'));
        for w = 1:numel(wavs)
            filePath = fullfile(wavs(w).folder, wavs(w).name);
            if isfile(filePath)
                try
                    delete(filePath);
                    nDeleted = nDeleted + 1;
                catch
                end
            end
        end
    end
end
end
