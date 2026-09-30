function data = admin_refresh_meal_log(fig, view)
%ADMIN_REFRESH_MEAL_LOG Switch the shared admin table fully into log mode.
% Call only after authorization, including after a confirmed reset.
view.ColumnEditable=false;
view.CellEditCallback=[];
view.ColumnFormat={};
view.ColumnWidth='auto';
fig.UserData.adminCurrentView='meal_log';
p=fig.UserData.params;
if isfile(p.logFile)
    data=readtable(p.logFile,'TextType','string');
else
    data=table();
end
view.Data=data;
view.ColumnName=data.Properties.VariableNames;
view.Visible='on';
end
