function admin_reset_coupon_registry(fig, adminId, pass, view, message) %#ok<INUSD>
%ADMIN_RESET_COUPON_REGISTRY Retired callback; never changes any private files.
%   Old GUI handles may still invoke this entry point. In particular, it must
%   never clear monthly dining assignments while retiring the coupon system.
if nargin < 5 || isempty(message), return; end
try
    message.Text = 'Coupon controls are retired. Use the monthly Student-ID roster; historical records are unchanged.';
    message.FontColor = [0.35 0.35 0.35];
catch
    % A stale or absent GUI handle requires no action.
end
end
