function tests = test_admin_monthly_roster_gui
tests = functiontests(localfunctions);
end

function setup(t)
root = tempname; mkdir(root);
p = dsp_parameters(false);
p.monthlyEntitlementFile = fullfile(root,'Roster.csv');
p.logFile = fullfile(root,'Meals.csv');
p.verificationLogFile = fullfile(root,'Attempts.csv');
p.trainIdFolder = fullfile(root,'ID'); p.trainNameFolder = fullfile(root,'Name');
for id = {'2206133','2206137','2206147'}
    for base = {p.trainIdFolder,p.trainNameFolder}
        folder = fullfile(base{1},id{1}); mkdir(folder);
        audiowrite(fullfile(folder,'1.wav'),zeros(8000,1),8000);
    end
end
f = meal_verification_gui(p); f.Visible = 'off';
t.TestData.f = f; t.TestData.p = p; t.TestData.root = root;
t.addTeardown(@() cleanup(f,root));
end

function testCouponControlsAndManualBypassAreAbsent(t)
f=t.TestData.f;
verifyEmpty(t,findobj(f,'Text','Coupon registry'));
verifyEmpty(t,findobj(f,'Tag','verifyCode'));
verifyEmpty(t,findobj(f,'Tag','adminCouponCode'));
verifyEmpty(t,findobj(f,'Tag','manualEntryBtn'));
end

function testAssignmentRequiresAdmin(t)
f=t.TestData.f;
b=findobj(f,'Tag','adminAssignMonthBtn'); assertNotEmpty(t,b);
b.ButtonPushedFcn(b,[]);
verifyFalse(t,isfile(t.TestData.p.monthlyEntitlementFile));
verifyEqual(t,char(findobj(f,'Tag','adminTable').Visible),'off');
end

function testRosterDisplayMatchesBackendValidation(t)
f=t.TestData.f;
monthText=string(datetime('now'),'yyyy-MM');
data=table(" 2206133 "," "+monthText+" ","2026-09-01","12:00:00","Admin-Roster", ...
    'VariableNames',{'Student','Month','PaidDate','PaidTime','Method'});
writetable(data,t.TestData.p.monthlyEntitlementFile);
unlock(f);
view=findobj(f,'Tag','adminTable');
verifyTrue(t,view.Data{1,3});
% A malformed file must not advertise membership the meal gate would refuse.
writetable(data(:,{'Student','Month'}),t.TestData.p.monthlyEntitlementFile);
admin_roster_action(f,'show');
verifyFalse(t,any(cell2mat(view.Data(:,3))));
verifyTrue(t,contains(findobj(f,'Tag','adminMessage').Text,'Could not read roster'));
badHeader=data; badHeader.Properties.VariableNames{3}='Paid Date';
writetable(badHeader,t.TestData.p.monthlyEntitlementFile);
admin_roster_action(f,'show');
verifyFalse(t,any(cell2mat(view.Data(:,3))));
bad=data; bad.Month="2026-13";
writetable([data;bad],t.TestData.p.monthlyEntitlementFile);
admin_roster_action(f,'show');
verifyFalse(t,any(cell2mat(view.Data(:,3))));
end

function testLiveSearchSelectAndAssignSingle(t)
f=t.TestData.f; unlock(f);
search=findobj(f,'Tag','adminRosterSearch');
search.ValueChangingFcn(search,struct('Value','2206147'));
drop=findobj(f,'Tag','adminRosterDropdown');
verifyTrue(t,ismember('2206147',drop.Items));
verifyFalse(t,ismember('2206133',drop.Items));
search.Value='2206147'; search.ValueChangedFcn(search,[]);
b=findobj(f,'Tag','adminAssignMonthBtn'); b.ButtonPushedFcn(b,[]);
[assigned,~]=monthly_fee_entitlement('2206147',t.TestData.p,datetime('now'),'check');
verifyTrue(t,assigned);
verifyTrue(t,contains(findobj(f,'Tag','adminRosterMonth').Text,string(datetime('now'),'yyyy-MM')));
end

function testPartialSearchCannotAssignStaleDropdown(t)
f=t.TestData.f; unlock(f);
search=findobj(f,'Tag','adminRosterSearch');
search.Value='220613'; search.ValueChangedFcn(search,[]);
b=findobj(f,'Tag','adminAssignMonthBtn'); b.ButtonPushedFcn(b,[]);
verifyFalse(t,isfile(t.TestData.p.monthlyEntitlementFile));
end

function testCheckboxSelectionSurvivesFilterAndAssignsOnlyMarked(t)
f=t.TestData.f; unlock(f);
view=findobj(f,'Tag','adminTable');
view.CellEditCallback(view,struct('Indices',[1 1],'NewData',true));
search=findobj(f,'Tag','adminRosterSearch');
search.Value='2206147'; search.ValueChangedFcn(search,[]);
view.CellEditCallback(view,struct('Indices',[1 1],'NewData',true));
b=findobj(f,'Tag','adminAssignSelectedBtn'); b.ButtonPushedFcn(b,[]);
tab=readtable(t.TestData.p.monthlyEntitlementFile,'TextType','string');
verifyEqual(t,sort(string(tab.Student)),["2206133";"2206147"]);
verifyTrue(t,all(string(tab.Month)==string(datetime('now'),'yyyy-MM')));
b.ButtonPushedFcn(b,[]);
verifyEqual(t,height(readtable(t.TestData.p.monthlyEntitlementFile)),2);
end

function testLockClearsPrivateSelection(t)
f=t.TestData.f; unlock(f);
b=findobj(f,'Tag','adminLockBtn'); b.ButtonPushedFcn(b,[]);
verifyEmpty(t,findobj(f,'Tag','adminTable').Data);
verifyEqual(t,char(findobj(f,'Tag','adminTable').Visible),'off');
verifyEqual(t,findobj(f,'Tag','adminRosterDropdown').Items,{'-- Select Student ID --'});
end

function testScheduleLeavesNoEditableRosterCells(t)
f=t.TestData.f; unlock(f);
b=findobj(f,'Tag','adminViewScheduleBtn'); b.ButtonPushedFcn(b,[]);
v=findobj(f,'Tag','adminTable');
verifyFalse(t,any(v.ColumnEditable));
verifyEmpty(t,v.CellEditCallback);
verifyEqual(t,f.UserData.adminCurrentView,'schedule');
end

function testResetRefreshClearsRosterEditing(t)
f=t.TestData.f; unlock(f);
data=table("2206133","2026-09-28","12:30:00","Lunch", ...
    'VariableNames',{'StudentID','Date','Time','Meal'});
writetable(data,t.TestData.p.logFile);
reset_meal_log_csv(t.TestData.p.logFile,'all');
view=findobj(f,'Tag','adminTable');
admin_refresh_meal_log(f,view);
verifyFalse(t,any(view.ColumnEditable));
verifyEmpty(t,view.CellEditCallback);
verifyEqual(t,f.UserData.adminCurrentView,'meal_log');
verifyTrue(t,istable(view.Data)); verifyEqual(t,height(view.Data),0);
end

function testImprovementsArePrivateAndLockRemovesTab(t)
f=t.TestData.f;
b=findobj(f,'Tag','adminWorkspaceBtn'); b.ButtonPushedFcn(b,[]);
verifyEmpty(t,findobj(f,'Tag','adminImprovementsTab'));
unlock(f); b.ButtonPushedFcn(b,[]);
tab=findobj(f,'Tag','adminImprovementsTab'); assertNotEmpty(t,tab);
verifyNotEmpty(t,findobj(f,'Tag','improvementsTable').Data);
lock=findobj(f,'Tag','adminLockBtn'); lock.ButtonPushedFcn(lock,[]);
verifyEmpty(t,findobj(f,'Tag','adminImprovementsTab'));
end

function unlock(f)
id=findobj(f,'Tag','adminId'); id.Value='admin';
pass=findobj(f,'Tag','adminPass'); pass.Value='admin';
b=findobj(f,'Tag','adminUnlockBtn'); b.ButtonPushedFcn(b,[]);
end

function cleanup(f,root)
if isvalid(f), delete(f); end
if isfolder(root), rmdir(root,'s'); end
end
