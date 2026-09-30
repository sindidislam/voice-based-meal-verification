function ok = test_monthly_roster_system()
%TEST_MONTHLY_ROSTER_SYSTEM Current direct-roster backend and GUI regressions.
ok = test_monthly_roster_backend();
r = runtests('test_admin_monthly_roster_gui');
assertSuccess(r);
ok = ok && all([r.Passed]);
end
