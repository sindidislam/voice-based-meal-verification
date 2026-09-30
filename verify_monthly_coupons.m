function ok = verify_monthly_coupons(verbose)
%VERIFY_MONTHLY_COUPONS Test admin-assigned, month-bound, single-use coupons.
if nargin < 1, verbose = true; end
p = dsp_parameters();
p.monthlyCouponFile = [tempname '.csv'];
cleanup = onCleanup(@() delete_if_present(p.monthlyCouponFile)); %#ok<NASGU>
firstMonth = datetime(2026, 4, 5, 12, 0, 0);
nextMonth = datetime(2026, 5, 5, 12, 0, 0);

[assigned, msg] = assign_monthly_coupon('Student A', 'APR-001', p, firstMonth);
assert(assigned, 'admin assignment failed: %s', msg);

[valid, msg] = consume_monthly_coupon('Student A', 'APR-001', p, firstMonth);
assert(valid, 'assigned coupon was not accepted: %s', msg);

[reused, ~] = consume_monthly_coupon('Student A', 'APR-001', p, firstMonth);
assert(~reused, 'a consumed coupon was accepted twice');

[wrongStudent, ~] = consume_monthly_coupon('Student B', 'APR-001', p, firstMonth);
assert(~wrongStudent, 'a coupon was accepted for the wrong student');

[wrongMonth, ~] = consume_monthly_coupon('Student A', 'APR-001', p, nextMonth);
assert(~wrongMonth, 'a coupon was accepted outside its assigned month');

if verbose, fprintf('VERIFY_MONTHLY_COUPONS: all checks passed.\n'); end
ok = true;
end

function delete_if_present(path)
if isfile(path), delete(path); end
end
