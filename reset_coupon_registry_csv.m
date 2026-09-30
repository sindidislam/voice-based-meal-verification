function [nModified, nRemaining, dataOut] = reset_coupon_registry_csv(registryFile, mode, targetValue) %#ok<INUSD>
%RESET_COUPON_REGISTRY_CSV Retired reset API; return existing history unchanged.
%   No mode can create, delete, reset, or rewrite a coupon registry. The
%   compatibility outputs report zero modifications and any readable history.
if nargin < 1 || isempty(registryFile)
    registryFile = fullfile(fileparts(mfilename('fullpath')),'MonthlyCouponRegistry.csv');
end
nModified = 0;
nRemaining = 0;
dataOut = table(strings(0,1),strings(0,1),strings(0,1),strings(0,1), ...
    strings(0,1),false(0,1),strings(0,1),strings(0,1), ...
    'VariableNames',{'Student','Coupon','Month','AssignedDate','AssignedTime','Consumed','UsedDate','UsedTime'});
if ~isfile(registryFile), return; end
try
    opts = detectImportOptions(registryFile,'TextType','string','VariableNamingRule','preserve');
    textNames = {'Student','Coupon','Month','AssignedDate','AssignedTime','UsedDate','UsedTime'};
    present = textNames(ismember(textNames,opts.VariableNames));
    if ~isempty(present), opts = setvartype(opts,present,'string'); end
    dataOut = readtable(registryFile,opts);
    nRemaining = height(dataOut);
catch
    % Unreadable legacy history stays untouched.
end
end
