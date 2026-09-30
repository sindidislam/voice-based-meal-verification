function [ok, message, info] = consume_monthly_coupon(studentName, couponCode, params, nowValue)
%CONSUME_MONTHLY_COUPON Retired compatibility wrapper; redemption always refuses.
if nargin < 3, params = []; end
if nargin < 4, nowValue = []; end
[ok, message, info] = monthly_coupon_registry(studentName, couponCode, params, nowValue, 'consume');
end
