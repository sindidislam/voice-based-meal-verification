function admin_log_gui()
%ADMIN_LOG_GUI Display the authoritative CSV event log.
p = dsp_parameters();
answer = inputdlg('Admin password:','Admin Login',[1 35]);
if isempty(answer) || ~strcmp(answer{1},'BuetHall')
    return;
end
fig = uifigure('Name','Admin Panel','Position',[500 250 850 430]);
if isfile(p.logFile)
    data = readtable(p.logFile,'TextType','string');
else
    data = table();
end
uitable(fig,'Data',data,'Position',[10 10 830 410],'ColumnName',data.Properties.VariableNames,'RowName',[]);
end
