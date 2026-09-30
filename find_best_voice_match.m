function [bestDist, bestUser, info] = find_best_voice_match(folder, testFeatures, p)
%FIND_BEST_VOICE_MATCH Identify the enrolled student closest to a live capture.
%
%   [BESTDIST, BESTUSER, INFO] = FIND_BEST_VOICE_MATCH(FOLDER, TESTFEATURES, P)
%   compares TESTFEATURES against every enrolled template under FOLDER and returns
%   the closest student's score and name.  Each immediate subfolder of FOLDER is
%   one student; the WAV files inside are that student's recordings of the phrase.
%
%   FIND_BEST_VOICE_MATCH('reset') clears the template cache.
%
%   This function is responsible for turning a folder of WAV files into a feature
%   library.  The scoring and ranking rule itself lives in VOICE_MATCH_SCORES, so
%   that the offline experiments can measure the deployed decision rather than a
%   reimplementation of it.
%
%   Caching
%   -------
%   Template features are cached in a persistent map keyed on the file path, its
%   modification time and every parameter that affects the result.  Recomputing
%   the whole corpus on each attempt would add seconds to every meal transaction;
%   including the parameters in the key means a configuration change invalidates
%   the cache automatically rather than silently serving features extracted under
%   the old settings.  That second property matters more than the speed: a stale
%   cache would make an experiment report the wrong front-end's error rate.
%
%   See also VOICE_MATCH_SCORES, EXTRACT_FEATURES, VERIFY_MEAL_WORKFLOW.

persistent featureCache

if nargin == 1 && (ischar(folder) || isstring(folder)) && strcmpi(folder,'reset')
    featureCache = containers.Map('KeyType','char','ValueType','any');
    bestDist = Inf; bestUser = ''; info = struct();
    return;
end

if nargin < 3 || isempty(p), p = dsp_parameters(); end
if isempty(featureCache)
    featureCache = containers.Map('KeyType','char','ValueType','any');
end

if isempty(testFeatures) || ~isfolder(folder)
    bestDist = Inf; bestUser = '';
    info = struct('Scores',[],'Users',strings(0,1),'BestUser','','BestDistance',Inf, ...
        'RunnerUpUser','','RunnerUpDistance',Inf,'Margin',Inf, ...
        'TemplatesUsed',0,'TemplatesRejected',0,'FrontEnd',p.featureFrontEnd);
    return;
end

users = dir(folder);
users = users([users.isdir] & ~startsWith({users.name}, '.'));

% Identity folders are keyed by the seven-digit Student ID. Any other folder is
% legacy (the old name-keyed senior corpus) and must never become a match
% candidate, or a spoken phrase could resolve to a name that has no ID. The
% offline experiments can opt out by setting p.idKeyedProfilesOnly = false.
if ~isfield(p, 'idKeyedProfilesOnly') || p.idKeyedProfilesOnly
    keep = false(numel(users), 1);
    for i = 1:numel(users)
        [~, keep(i)] = student_id_contract(users(i).name);
    end
    users = users(keep);
end

library = struct('Users', strings(numel(users),1), 'Templates', {cell(numel(users),1)});

for i = 1:numel(users)
    library.Users(i) = string(users(i).name);
    files = dir(fullfile(folder, users(i).name, '*.wav'));
    % The calibrated protocol reserves takes 2/3 for evaluation. Never let a
    % later copy into this folder silently expand the enrollment population.
    if isfield(p,'enrollmentTemplateFileNames')
        files = files(ismember(string({files.name}),string(p.enrollmentTemplateFileNames)));
    end
    bucket = cell(numel(files),1);
    for j = 1:numel(files)
        filePath = fullfile(files(j).folder, files(j).name);
        key = template_cache_key(filePath, files(j).datenum, files(j).bytes, p);
        if isKey(featureCache, key)
            bucket{j} = featureCache(key);
        else
            bucket{j} = template_features(filePath, p);
            featureCache(key) = bucket{j};
        end
    end
    library.Templates{i} = bucket;
end

[bestDist, bestUser, info] = voice_match_scores(library, testFeatures, p);
end

% -------------------------------------------------------------------------
function key = template_cache_key(filePath, fileDatenum, fileBytes, p)
%TEMPLATE_CACHE_KEY Every input that can change the extracted features.
% Include the complete configuration: the previous hand-picked list omitted
% the lifter, mel limits and preprocessing settings. Extra invalidations from
% unrelated settings are harmless; stale features are not.
[ok, attr] = fileattrib(filePath);
if ok, filePath = attr.Name; end
key = sprintf('%s|%.17g|%d|%s',filePath,fileDatenum,fileBytes,jsonencode(p));
end

function f = template_features(filePath, p)
%TEMPLATE_FEATURES Read one enrolment WAV and extract its features, or [].
%   Delegated to ENROL_TEMPLATE_FEATURES so the deployed matcher, the offline
%   experiments and the corpus audit all enrol exactly the same set of files. This
%   used to be an inline copy of the decision, and it drifted: two junk coupon files
%   were loaded here as real templates while DIAGNOSE_AUDIO_CORPUS reported them
%   unusable.
f = enrol_template_features(filePath, [], p);
end
