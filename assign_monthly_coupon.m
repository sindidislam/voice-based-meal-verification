function [ok, message, info] = assign_monthly_coupon(studentName, couponCode, params, nowValue)
%ASSIGN_MONTHLY_COUPON Retired compatibility wrapper; assignment always refuses.
if nargin < 3, params = []; end
if nargin < 4, nowValue = []; end
[ok, message, info] = monthly_coupon_registry(studentName, couponCode, params, nowValue, 'assign');
end
