function authenticate_workflow(status, codeValue, userType, guestCount) %#ok<INUSD>
%AUTHENTICATE_WORKFLOW Refuse the retired name-and-coupon-only interface.
% Its arguments contain no independently entered Student ID. It cannot safely
% dispatch a verification or grant access. Use the canonical counter workflow.
% Original source: ../preservation/continuation_2026-09-27_before/authenticate_workflow.m.
error('authenticate_workflow:legacyDisabled', ...
    ['This legacy authentication path is disabled. Run run_meal_system, ' ...
     'enter the Student ID to verify, then speak the whole ID and full name.']);
end
