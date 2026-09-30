function tests = test_gui_stop_controls
%TEST_GUI_STOP_CONTROLS Stop/reentry UI regression without opening a microphone.
tests = functiontests(localfunctions);
end

function setup(t)
p = dsp_parameters(false);
f = meal_verification_gui(p);
f.Visible = 'off';
t.TestData.figure = f;
t.addTeardown(@() delete_if_valid(f));
t.TestData.live = findobj(f,'Tag','verifyLiveBtn');
t.TestData.stop = findobj(f,'Tag','verifyStopBtn');
t.TestData.status = findobj(f,'Tag','verifyStatus');
end

function testStopRetainsCancellationUntilTransactionUnwinds(t)
f = t.TestData.figure;
live = t.TestData.live; stop = t.TestData.stop; status = t.TestData.status;
f.UserData.verificationActive = true;
f.UserData.stopRequested = false;
status.UserData = struct('stopRequested',false);
live.Enable = 'off'; stop.Enable = 'on';
stop.ButtonPushedFcn(stop,[]);
verifyTrue(t,f.UserData.stopRequested);
verifyTrue(t,status.UserData.stopRequested);
verifyEqual(t,char(live.Enable),'off');
verifyTrue(t,f.UserData.verificationActive);
end

function testSecondTransactionCannotEnterWhileFirstIsActive(t)
f = t.TestData.figure; live = t.TestData.live; status = t.TestData.status;
f.UserData.verificationActive = true;
status.Value = {'First transaction still active'};
before = status.Value;
% The blank claim also prevents microphone capture if this guard regresses.
claim = findobj(f,'Tag','manualIdentity'); claim.Value = '';
live.ButtonPushedFcn(live,[]);
verifyEqual(t,status.Value,before);
verifyTrue(t,f.UserData.verificationActive);
end

function delete_if_valid(f)
if isvalid(f), delete(f); end
end
