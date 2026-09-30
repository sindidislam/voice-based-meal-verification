function ok = admin_authorised(fig, adminId, pass, message)
%ADMIN_AUTHORISED Check admin credentials and set message text if unauthorized.
%
%   OK = ADMIN_AUTHORISED(FIG, ADMINID, PASS, MESSAGE) checks that ADMINID
%   matches FIG.UserData.params.adminId (default 'admin') and PASS matches
%   FIG.UserData.params.adminPassword (default 'admin').

ok = false;
if isempty(fig) || ~isvalid(fig) || ~isfield(fig.UserData, 'params')
    if ~isempty(message) && isvalid(message)
        message.Text = 'Invalid application state. Private data stays locked.';
        message.FontColor = [0.70 0.05 0.05];
    end
    return;
end

p = fig.UserData.params;
configuredId = 'admin';
if isfield(p, 'adminId') && ~isempty(p.adminId), configuredId = char(string(p.adminId)); end

idVal = '';
passVal = '';
if isprop(adminId, 'Value'), idVal = char(string(adminId.Value)); else, idVal = char(string(adminId)); end
if isprop(pass, 'Value'), passVal = char(string(pass.Value)); else, passVal = char(string(pass)); end

ok = strcmp(idVal, configuredId) && strcmp(passVal, p.adminPassword);
if ~ok
    if ~isempty(message) && isvalid(message)
        message.Text = 'Incorrect admin ID or password. Private data stays locked.';
        message.FontColor = [0.70 0.05 0.05];
    end
end
end
