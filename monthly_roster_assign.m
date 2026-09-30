function [ok,message,info] = monthly_roster_assign(ids,params,nowValue)
%MONTHLY_ROSTER_ASSIGN Assign selected enrolled IDs in one calendar-month write.
%   IDS accepts a character ID, string vector, or cell array of IDs. Every
%   selection is validated before writing. Repeated IDs are deduplicated and
%   existing membership is preserved. INFO reports AddedIDs, AddedCount,
%   AlreadyAssignedIDs and AlreadyAssignedCount. The calling admin interface
%   must authorize the operator before invoking this mutation.
if nargin < 2, params = []; end
if nargin < 3, nowValue = []; end
[ok,message,info] = monthly_fee_entitlement(ids,params,nowValue,'assign_selected');
end
