function root = find_project_root()
%FIND_PROJECT_ROOT Dynamically locates the root directory of the project.
%   Searches up the directory tree until it finds RUN_ME.m, Train, or data.

p = fileparts(mfilename('fullpath'));
root = p;
for i = 1:5
    if isfile(fullfile(p, 'RUN_ME.m')) || isfolder(fullfile(p, 'Train')) || isfolder(fullfile(p, 'data'))
        root = p;
        return;
    end
    parent = fileparts(p);
    if strcmp(parent, p), break; end
    p = parent;
end
end
