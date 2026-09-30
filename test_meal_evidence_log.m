function tests=test_meal_evidence_log
% Catch lost two-utterance evidence and destructive legacy-log migration.
tests=functiontests(localfunctions);
end

function testBothUtteranceScoresSurviveCsvRoundTrip(t)
[p,clean]=fixture(); %#ok<ASGLU>
e=struct('StudentName','Test student','IDDistance',12,'NameDistance',17, ...
    'IDMargin',1.8,'NameMargin',1.6,'Margin',1.6,'Method','Voice-ID+Name');
[ok,~,~]=log_meal_csv('2206149',e,p,datetime(2026,9,25,12,30,0));
verifyTrue(t,ok);
data=readtable(p.logFile);
required={'IDDistance','NameDistance','IDMargin','NameMargin'};
assertTrue(t,all(ismember(required,data.Properties.VariableNames)));
verifyEqual(t,data{1,required},[12 17 1.8 1.6]);
end

function testLegacyRowsRetainHistoryWhenEvidenceColumnsAreAdded(t)
[p,clean]=fixture(); %#ok<ASGLU>
old=table("2206148","Historical student","2026-09-24","12:30:00", ...
    "Lunch","Voice",10,NaN,1.4,'VariableNames', ...
    {'StudentID','StudentName','Date','Time','Meal','Method','NameDistance','CouponDistance','Margin'});
writetable(old,p.logFile);
e=struct('StudentName','Test student','IDDistance',12,'NameDistance',17, ...
    'IDMargin',1.8,'NameMargin',1.6,'Margin',1.6);
[ok,~,~]=log_meal_csv('2206149',e,p,datetime(2026,9,25,12,30,0));
verifyTrue(t,ok);
data=readtable(p.logFile,'TextType','string');
assertTrue(t,ismember('IDDistance',data.Properties.VariableNames));
verifyEqual(t,height(data),2); verifyEqual(t,string(data.StudentID(1)),"2206148");
verifyEqual(t,data.NameDistance(1),10); verifyTrue(t,isnan(data.IDDistance(1)));
verifyEqual(t,data.IDDistance(2),12);
end

function [p,clean]=fixture()
root=tempname; mkdir(root); clean=onCleanup(@()rmdir(root,'s'));
p=dsp_parameters(); p.logFile=fullfile(root,'MealLog.csv');
end
