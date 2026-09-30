function M = vsd_build_models(mode, c)
%VSD_BUILD_MODELS Enrol every student: templates, GMM-UBM voice models, digits.
%
%   M = VSD_BUILD_MODELS() loads VSD_Models.mat, rebuilding only what changed
%   (new, edited or deleted WAV files).  M = VSD_BUILD_MODELS('force')
%   re-extracts every file.  M = VSD_BUILD_MODELS('load') returns the saved
%   models without checking the folders (fast path for the counter).
%   KEYS = VSD_BUILD_MODELS('keys') lists the enrolment files (path|bytes|date)
%   so a caller can tell cheaply whether anything changed.
%
%   Folder layout read (DataRoot = VSD_CONFIG().DataRoot):
%     ID/<7-digit id>/*.wav            spoken roll number takes  (ALL takes)
%     ID/<id>/Adaptive/*.wav           high-confidence live takes (self-adaptation)
%     Name/<id>/*.wav                  spoken full-name takes
%     Name/<id>/Adaptive/*.wav
%     Digits/<id>/<id>_<digit>_01.wav  isolated digits zero..nine (challenge +
%                                      universal background model)
%
%   What is built
%   * Content templates: every usable ID and Name take (v4.1.4 used ONLY 1.wav).
%   * UBM: 64-component diagonal GMM trained on the pooled digit speech of all
%     students (text independent, never contains a test phrase).
%   * One MAP-adapted voice model per student from all of his ID+Name takes.
%   * Speech-trimmed digit waveforms per student for the random-digit challenge.

if nargin < 1 || isempty(mode), mode = 'update'; end
if nargin < 2 || isempty(c), c = vsd_config(); end
if exist('OCTAVE_VERSION','builtin'), try, pkg load signal; catch, end, end

if strcmpi(mode,'configkey'), M = config_key(c); return; end
if strcmpi(mode,'keys')                       % cheap folder signature
    files = list_files(c.DataRoot);
    M = arrayfun(@(f) sprintf('%s|%d|%.6f', f.path, f.bytes, f.datenum), files, 'UniformOutput', false);
    return;
end
if strcmpi(mode,'load') && exist(c.ModelFile,'file') == 2
    S = load(c.ModelFile, 'M');  M = S.M;  return;
end
old = [];
if ~strcmpi(mode,'force') && exist(c.ModelFile,'file') == 2
    try, S = load(c.ModelFile, 'M'); old = S.M; catch, old = []; end
end

files = list_files(c.DataRoot);
cfgKey = config_key(c);
cache = struct('key', {}, 'U', {});
if ~isempty(old) && isfield(old,'Cache') && isfield(old,'ConfigKey') && strcmp(old.ConfigKey, cfgKey)
    cache = old.Cache;
end
oldKeys = {cache.key};
keys = arrayfun(@(f) sprintf('%s|%d|%.6f', f.path, f.bytes, f.datenum), files, 'UniformOutput', false);
if ~isempty(old) && numel(keys) == numel(oldKeys) && all(strcmp(keys(:), oldKeys(:))) ...
        && strcmp(old.DataRoot, c.DataRoot) && isfield(old,'ConfigKey') && strcmp(old.ConfigKey, cfgKey)
    M = old;  M.NumNewFiles = 0;  return;             % nothing changed on disk
end
newCache = struct('key', {}, 'U', {});
nNew = 0;
for k = 1:numel(files)
    f = files(k);
    key = sprintf('%s|%d|%.6f', f.path, f.bytes, f.datenum);
    j = find(strcmp(oldKeys, key), 1);
    if ~isempty(j)
        U = cache(j).U;
    else
        try
            [x, fs] = audioread(f.path);
            U = vsd_frontend(x, fs, c);
            U = rmfield(U, {'Speech','LogE'});
            if strcmp(f.phrase,'Digits')
                U.Trim = single(trim_speech(U.Audio8k, c));
            end
            U = rmfield(U, 'Audio8k');
        catch err
            U = struct('Error', err.message);
        end
        nNew = nNew + 1;
    end
    newCache(end+1) = struct('key', key, 'U', U); %#ok<AGROW>
end

% ---- assemble ------------------------------------------------------------
ids = unique({files.id});
M = struct();
M.Version = c.Version;  M.DataRoot = c.DataRoot;  M.BuiltAt = datestr(now, 31);
M.Students = {};  M.Names = {};
M.Templates = struct('ID', {{}}, 'Name', {{}});
M.Speaker = {};  M.Digits = {};  M.Skipped = {};
for s = 1:numel(ids)
    sid = ids{s};
    T = struct('ID', {{}}, 'Name', {{}});  D = cell(1,10);
    for k = find(strcmp({files.id}, sid))
        U = newCache(k).U;  f = files(k);
        if isfield(U,'Error'), M.Skipped{end+1} = sprintf('%s (%s)', f.path, U.Error); continue; end %#ok<AGROW>
        if strcmp(f.phrase,'Digits')
            if f.digit >= 0 && isfield(U,'Trim'), D{f.digit+1} = double(U.Trim); end
            continue;
        end
        if U.RawRms < c.MinRms || U.SpeechSec < c.MinSpeechSec
            M.Skipped{end+1} = sprintf('%s (too quiet/short: rms %.4f, speech %.2fs)', f.path, U.RawRms, U.SpeechSec); %#ok<AGROW>
            continue;
        end
        t = struct('Content', U.Content, 'Speaker', U.Speaker, 'Path', f.path, ...
            'Adaptive', f.adaptive, 'SpeechSec', U.SpeechSec);
        T.(f.phrase){end+1} = t;
    end
    if isempty(T.ID) || isempty(T.Name), continue; end
    M.Students{end+1} = sid;                                  %#ok<AGROW>
    M.Names{end+1} = display_name(c.DataRoot, sid);           %#ok<AGROW>
    M.Templates.ID{end+1} = T.ID;  M.Templates.Name{end+1} = T.Name;
    M.Digits{end+1} = D;                                      %#ok<AGROW>
end

% ---- universal background model -----------------------------------------------
Xd = [];
for k = 1:numel(files)
    if strcmp(files(k).phrase,'Digits') && ~isfield(newCache(k).U,'Error')
        Xd = [Xd; newCache(k).U.Speaker]; %#ok<AGROW>
    end
end
if size(Xd,1) < 20 * c.UbmMixtures            % no digit corpus: fall back to phrases
    for s = 1:numel(M.Students)
        for p = {'ID','Name'}
            for t = 1:numel(M.Templates.(p{1}){s}), Xd = [Xd; M.Templates.(p{1}){s}{t}.Speaker]; end %#ok<AGROW>
        end
    end
    M.UbmSource = 'ID+Name phrases';
else
    M.UbmSource = 'Digits (all students)';
end
ubmKey = sprintf('%d|%d|%s|%s', size(Xd,1), c.UbmMixtures, M.UbmSource, cfgKey);
if ~isempty(old) && isfield(old,'UbmKey') && strcmp(old.UbmKey, ubmKey) && isfield(old,'UBM')
    M.UBM = old.UBM;
else
    M.UBM = vsd_gmm('train', Xd, c);
end
M.UbmKey = ubmKey;
for s = 1:numel(M.Students)
    M.Speaker{s} = speaker_model(M, s, c);
end
M.Cache = newCache;
M.ConfigKey = cfgKey;
M.NumNewFiles = nNew;
save(c.ModelFile, 'M', '-v7');
end

% =========================================================================
function mu = speaker_model(M, s, c)
X = [];
for p = {'ID','Name'}
    for t = 1:numel(M.Templates.(p{1}){s}), X = [X; M.Templates.(p{1}){s}{t}.Speaker]; end %#ok<AGROW>
end
mu = vsd_gmm('adapt', X, M.UBM, c.MapRelevance);
end

function files = list_files(root)
files = struct('path',{},'id',{},'phrase',{},'digit',{},'bytes',{},'datenum',{},'adaptive',{});
words = {'zero','one','two','three','four','five','six','seven','eight','nine'};
for p = {'ID','Name','Digits'}
    base = fullfile(root, p{1});
    if exist(base,'dir') ~= 7, continue; end
    d = dir(base);
    for k = 1:numel(d)
        if ~d(k).isdir || isempty(regexp(d(k).name, '^\d{7}$', 'once')), continue; end
        for sub = {'', 'Adaptive'}
            folder = fullfile(base, d(k).name, sub{1});
            if exist(folder,'dir') ~= 7, continue; end
            w = dir(fullfile(folder, '*.wav'));
            for j = 1:numel(w)
                dg = -1;
                if strcmp(p{1},'Digits')
                    tok = regexp(lower(w(j).name), '_([a-z]+)_\d+\.wav$', 'tokens', 'once');
                    if isempty(tok), continue; end
                    dg = find(strcmp(words, tok{1})) - 1;
                    if isempty(dg), continue; end
                end
                files(end+1) = struct('path', fullfile(folder, w(j).name), 'id', d(k).name, ...
                    'phrase', p{1}, 'digit', dg, 'bytes', w(j).bytes, 'datenum', w(j).datenum, ...
                    'adaptive', ~isempty(sub{1})); %#ok<AGROW>
            end
        end
    end
end
end

function y = trim_speech(x, c)
%TRIM_SPEECH Keep the spoken digit plus 40 ms either side (speech mask of the front-end).
U = vsd_frontend(x, c.Fs, c);
idx = find(U.Speech);
H = round(c.HopMs * 1e-3 * c.Fs);
if isempty(idx), y = x; return; end
a = max(1, (idx(1)-1)*H - 320 + 1);
b = min(numel(x), (idx(end)-1 + 3)*H + 320);
y = x(a:b);
end

function k = config_key(c)
%CONFIG_KEY Settings that change the features or the models (cache validity).
k = sprintf('%s|%g|%g|%g|%g|%g|%g|%g|%g|%g|%g|%g|%g|%g|%g|%g|%g', c.Version, c.Fs, c.FrameMs, c.HopMs, ...
    c.NFFT, c.NumMel, c.MelLowHz, c.MelHighHz, c.NumCep, c.Lifter, c.PreEmph, c.SSAlpha, c.SSBeta, ...
    c.SpeechFloorDb, c.UbmMixtures, c.MapRelevance, c.DeltaN);
end

function name = display_name(root, sid)
%DISPLAY_NAME Name saved by the Enrol tab (profile.mat), else profile.json, else the ID.
name = sid;
fm = fullfile(root, 'ID', sid, 'profile.mat');
try
    if exist(fm,'file') == 2
        S = load(fm);
        if isfield(S,'Name') && ~isempty(S.Name), name = char(S.Name); return; end
    end
catch
end
f = fullfile(root, 'ID', sid, 'profile.json');
try
    if exist(f,'file') == 2
        j = jsondecode(fileread(f));
        if isfield(j,'Name') && ~isempty(j.Name), name = char(j.Name); end
    end
catch
end
end
