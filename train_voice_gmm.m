function model = train_voice_gmm(params, outputPath)
%TRAIN_VOICE_GMM Train GMM-UBM voice timbre verification model from enrolled templates.
%
%   MODEL = TRAIN_VOICE_GMM(PARAMS, OUTPUTPATH)
%
%   Builds a Universal Background Model (UBM) and MAP-adapted speaker models
%   for all valid enrolled student profiles using ALL available speech samples
%   (ID, Name, Digits, and AllSamples).

if nargin < 1 || isempty(params), params = dsp_parameters(); end
if nargin < 2 || isempty(outputPath)
    outputPath = fullfile(fileparts(mfilename('fullpath')), 'VoiceGMM_Model.mat');
end

projectRoot = fileparts(mfilename('fullpath'));

% Enrolled folders
idFolder = params.trainIdFolder;
nameFolder = params.trainNameFolder;
baseFolder = params.trainBaseFolder;

users = dir(idFolder);
users = users([users.isdir] & ~startsWith({users.name}, '.'));
keep = false(numel(users), 1);
for i = 1:numel(users)
    [~, keep(i)] = student_id_contract(users(i).name);
end
users = {users(keep).name};
users = sort(users);

numUsers = numel(users);
if numUsers == 0
    error('train_voice_gmm:noUsers', 'No valid enrolled student IDs found.');
end

K = 8;
if isfield(params, 'voiceGMM') && isfield(params.voiceGMM, 'NumMixtures')
    K = params.voiceGMM.NumMixtures;
end
r = 16;
if isfield(params, 'voiceGMM') && isfield(params.voiceGMM, 'RelevanceFactor')
    r = params.voiceGMM.RelevanceFactor;
end

allFrames = [];
userFrames = cell(numUsers, 1);
totalRecordingsProcessed = 0;

for u = 1:numUsers
    userId = users{u};
    uFeats = [];
    
    % Search across all template and sample directories for this student
    candidateFolders = {
        fullfile(baseFolder, 'AllSamples', userId), ...
        fullfile(projectRoot, 'Train', 'AllSamples', userId), ...
        fullfile(idFolder, userId), ...
        fullfile(nameFolder, userId), ...
        fullfile(baseFolder, 'Digits', userId), ...
        fullfile(projectRoot, 'Train', 'Digits', userId)
    };
    
    processedHashes = containers.Map('KeyType', 'char', 'ValueType', 'logical');
    
    for cIdx = 1:numel(candidateFolders)
        fld = candidateFolders{cIdx};
        if isfolder(fld)
            wavs = dir(fullfile(fld, '*.wav'));
            for w = 1:numel(wavs)
                fName = wavs(w).name;
                fBytes = wavs(w).bytes;
                fKey = sprintf('%d_%s', fBytes, fName);
                if isKey(processedHashes, fKey), continue; end
                processedHashes(fKey) = true;
                
                wavPath = fullfile(fld, fName);
                try
                    feat = enrol_template_features(wavPath, [], params);
                    if isempty(feat)
                        % Fallback direct extraction for short speech tokens (isolated digits 0-9)
                        [a, fsRaw] = audioread(wavPath);
                        if numel(a) > round(0.10 * fsRaw)
                            [y, fo, d] = preprocess_template_audio(a, fsRaw, params);
                            if d.Endpoint.HasSpeech
                                feat = extract_features(y, fo, params);
                            end
                        end
                    end
                    if ~isempty(feat) && isnumeric(feat)
                        if size(feat, 1) < size(feat, 2)
                            feat = feat.';
                        end
                        uFeats = [uFeats; feat]; %#ok<AGROW>
                        totalRecordingsProcessed = totalRecordingsProcessed + 1;
                    end
                catch
                end
            end
        end
    end
    userFrames{u} = uFeats;
    if ~isempty(uFeats)
        allFrames = [allFrames; uFeats]; %#ok<AGROW>
    end
end

if isempty(allFrames)
    error('train_voice_gmm:noFeatures', 'No usable features extracted from training templates.');
end

fprintf('Extracted %d feature frames from %d audio files across %d students.\n', ...
    size(allFrames, 1), totalRecordingsProcessed, numUsers);

% Train Universal Background Model (UBM)
fprintf('Training Universal Background Model with %d Gaussian components...\n', K);
UBM = voice_gmm_ubm('trainubm', allFrames, K, 10);

% MAP adapt speaker means
dim = size(UBM.mu, 2);
SpeakerMeans = zeros(K, dim, numUsers);
for u = 1:numUsers
    uFeats = userFrames{u};
    if ~isempty(uFeats)
        SpeakerMeans(:, :, u) = voice_gmm_ubm('adapt', uFeats, UBM, r);
    else
        SpeakerMeans(:, :, u) = UBM.mu;
    end
end

Users = users;
model = struct('UBM', UBM, 'SpeakerMeans', SpeakerMeans, 'Users', Users);
save(outputPath, 'UBM', 'SpeakerMeans', 'Users');
fprintf('Trained Voice GMM-UBM for %d students, saved to %s\n', numUsers, outputPath);
end
