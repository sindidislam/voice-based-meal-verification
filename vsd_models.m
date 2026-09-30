function M = vsd_models(c, action)
%VSD_MODELS Cached access to the enrolled voice models (VSD_Models.mat).
%
%   M = VSD_MODELS(C) returns the models kept in memory between transactions.
%   Before every use the enrolment folders are listed (a few milliseconds);
%   if any WAV was added, replaced or removed - by the Enrol tab, an import,
%   the digit recorder or self-adaptation - only the changed files are
%   processed and the voice models are re-adapted (VSD_BUILD_MODELS 'update').
%   M = VSD_MODELS(C, 'rebuild') forces that update now (admin button);
%   M = VSD_MODELS(C, 'force') re-extracts every file from scratch.

persistent cached
if nargin < 1 || isempty(c), c = vsd_config(); end
if nargin < 2, action = ''; end
if strcmpi(action, 'force')
    cached = vsd_build_models('force', c);  M = cached;  return;
end
if isempty(cached) && exist(c.ModelFile,'file') == 2 && ~strcmpi(action,'rebuild')
    try, cached = vsd_build_models('load', c); catch, cached = []; end
end
keys = vsd_build_models('keys', c);
stale = isempty(cached) || ~isfield(cached,'Cache') || ~strcmp(cached.DataRoot, c.DataRoot) || ...
    numel(keys) ~= numel(cached.Cache) || ~all(strcmp(keys(:), {cached.Cache.key}')) || ...
    ~isfield(cached,'Version') || ~strcmp(cached.Version, c.Version) || ...
    ~isfield(cached,'ConfigKey') || ~strcmp(cached.ConfigKey, vsd_build_models('configkey', c));
if stale || strcmpi(action, 'rebuild')
    cached = vsd_build_models('update', c);
end
if exist([c.ModelFile '.dirty'], 'file') == 2, try, delete([c.ModelFile '.dirty']); catch, end, end
M = cached;
end
