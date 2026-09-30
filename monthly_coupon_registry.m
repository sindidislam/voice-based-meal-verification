function [ok, message, info] = monthly_coupon_registry(studentId, couponCode, params, nowValue, action) %#ok<INUSD>
%MONTHLY_COUPON_REGISTRY Retired compatibility entry point; never reads or writes.
%   Dining access is administered through the monthly Student-ID roster.
%   Existing coupon files are retained only as history. Legacy parameters,
%   assigned codes, and matching records cannot enable this retired route.
if nargin < 1, studentId = ''; end
if nargin < 2, couponCode = ''; end
if nargin < 3, params = struct(); end
if nargin < 4 || isempty(nowValue), nowValue = datetime('now'); end
fileName = fullfile(fileparts(mfilename('fullpath')),'MonthlyCouponRegistry.csv');
if isstruct(params) && isfield(params,'monthlyCouponFile') && ~isempty(params.monthlyCouponFile)
    fileName = params.monthlyCouponFile;
end
monthText = '';
if isdatetime(nowValue) && isscalar(nowValue) && ~isnat(nowValue)
    monthText = char(string(nowValue,'yyyy-MM'));
end
ok = false;
message = 'Coupons are retired. An administrator must assign the enrolled Student ID for the current month.';
info = struct('Student',single_text(studentId),'Coupon',single_text(couponCode), ...
    'Month',monthText,'Consumed',false,'Retired',true,'File',fileName);
end

function text = single_text(value)
text = '';
if ischar(value) && (isrow(value) || isempty(value))
    text = value;
elseif isstring(value) && isscalar(value) && ~ismissing(value)
    text = char(value);
end
end
