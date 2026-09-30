function admin_roster_action(fig, action, event)
%ADMIN_ROSTER_ACTION Search, mark and assign enrolled IDs for the current month.
if nargin<3, event=[]; end
view=findobj(fig,'Tag','adminTable');
search=findobj(fig,'Tag','adminRosterSearch');
drop=findobj(fig,'Tag','adminRosterDropdown');
message=findobj(fig,'Tag','adminMessage');
if strcmp(action,'lock')
    fig.UserData.rosterSelectedIDs={};
    search.Value=''; drop.Items={'-- Select Student ID --'};
    view.CellEditCallback=[]; view.ColumnEditable=false;
    return;
end
adminId=findobj(fig,'Tag','adminId'); pass=findobj(fig,'Tag','adminPass');
if ~admin_authorised(fig,adminId,pass,message), return; end
p=fig.UserData.params;
nowValue=datetime('now'); % Month is resolved at each action, including after midnight.
monthText=char(string(nowValue,'yyyy-MM'));
monthLabel=findobj(fig,'Tag','adminRosterMonth');
monthLabel.Text=['Current month: ' monthText ' | Select an ID or mark several students below'];
ids=list_enrolled_student_ids(p);
if ~isfield(fig.UserData,'rosterSelectedIDs'), fig.UserData.rosterSelectedIDs={}; end
selected=intersect(fig.UserData.rosterSelectedIDs,ids,'stable');
query=strtrim(char(string(search.Value)));
if strcmp(action,'search-live'), query=strtrim(char(string(event.Value))); end
if strcmp(action,'dropdown')
    if startsWith(drop.Value,'--'), return; end
    query=drop.Value; search.Value=query;
end
if strcmp(action,'mark')
    if ~isfield(fig.UserData,'adminCurrentView') || ...
            ~strcmp(fig.UserData.adminCurrentView,'monthly_roster') || event.Indices(2)~=1
        return;
    end
    sid=view.Data{event.Indices(1),2};
    selected=setdiff(selected,{sid},'stable');
    if event.NewData, selected{end+1}=sid; end
elseif strcmp(action,'select-visible')
    selected=union(selected,ids(contains(ids,query)),'stable');
elseif strcmp(action,'clear-selection')
    selected={};
end
fig.UserData.rosterSelectedIDs=selected;
feedback=''; operationOK=true;
if strcmp(action,'assign-one')
    % A partial search never silently uses a previous dropdown selection.
    [sid,valid]=student_id_contract(query);
    if ~valid || ~ismember(sid,ids)
        feedback='Select or enter one complete enrolled seven-digit ID before assigning.';
        operationOK=false;
    else
        [operationOK,feedback]=monthly_roster_assign({sid},p,nowValue);
    end
elseif strcmp(action,'assign-selected')
    [operationOK,feedback]=monthly_roster_assign(selected,p,nowValue);
elseif strcmp(action,'remove-one')
    [sid,valid]=student_id_contract(query);
    if ~valid || ~ismember(sid,ids)
        feedback='Select one complete enrolled ID to remove from this month.'; operationOK=false;
    else
        choice=uiconfirm(fig,sprintf('Remove %s from the %s roster?',sid,monthText), ...
            'Remove current-month assignment','Options',{'Remove','Cancel'}, ...
            'DefaultOption','Cancel','CancelOption','Cancel');
        if strcmp(choice,'Remove')
            [operationOK,feedback]=monthly_fee_entitlement(sid,p,nowValue,'remove');
        else
            feedback='Assignment removal cancelled.';
        end
    end
end
shown=ids(contains(ids,query));
drop.Items=[{'-- Select Student ID --'},shown(:)'];
if ismember(query,shown), drop.Value=query; else, drop.Value=drop.Items{1}; end
assignedIDs={};
try
    if isfile(p.monthlyEntitlementFile)
        opts=detectImportOptions(p.monthlyEntitlementFile,'TextType','string','VariableNamingRule','preserve');
        if ~all(ismember({'Student','Month','PaidDate','PaidTime','Method'},opts.VariableNames))
            error('admin_roster_action:Schema','Roster file has invalid columns.');
        end
        opts=setvartype(opts,{'Student','Month'},'string');
        roster=readtable(p.monthlyEntitlementFile,opts);
        months=cellstr(strtrim(roster.Month));
        if any(ismissing(roster.Student) | ismissing(roster.Month)) || ...
                any(cellfun(@(s)isempty(regexp(s,'^\d{4}-(0[1-9]|1[0-2])$','once')),months))
            error('admin_roster_action:Rows','Roster file has invalid identities or months.');
        end
        assignedIDs=cellstr(strtrim(roster.Student(strtrim(roster.Month)==string(monthText))));
    end
catch err
    feedback=['Could not read roster: ' err.message]; operationOK=false;
end
rows=cell(numel(shown),3);
for k=1:numel(shown)
    rows(k,:)={ismember(shown{k},selected),shown{k},ismember(shown{k},assignedIDs)};
end
fig.UserData.adminCurrentView='monthly_roster';
view.Data=rows; view.ColumnName={'Select','Student ID',['Assigned for ' monthText]};
view.ColumnFormat={'logical','char','logical'};
view.ColumnEditable=[true false false]; view.ColumnWidth={70,180,240};
view.CellEditCallback=@(~,e)admin_roster_action(fig,'mark',e);
view.Visible='on';
assignSelected=findobj(fig,'Tag','adminAssignSelectedBtn');
assignSelected.Text=sprintf('Assign selected (%d)',numel(selected));
if isempty(feedback)
    feedback=sprintf('%s: %d enrolled, %d assigned, %d shown, %d marked.', ...
        monthText,numel(ids),numel(intersect(ids,assignedIDs)),numel(shown),numel(selected));
end
message.Text=feedback;
if operationOK, message.FontColor=[.05 .40 .05]; else, message.FontColor=[.70 .05 .05]; end
end
