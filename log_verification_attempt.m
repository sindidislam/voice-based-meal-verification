function log_verification_attempt(r,p,nowValue)
%LOG_VERIFICATION_ATTEMPT Save retry/verification evidence separately from meals.
% Contains no waveform; rejected candidates are diagnostics, never identities.
% v4.1.4_Final adds Engine, VoiceScore, ImposterSuspect, ReplayFlag and
% Challenge columns.  A log written by v4.1.4 (old header) is archived as
% VerificationAttempts_v4.1.4.csv so the two schemas are never mixed.
file=fullfile(fileparts(p.logFile),'VerificationAttempts.csv');
if isfield(p,'verificationLogFile'), file=p.verificationLogFile; end
row=table(string(nowValue,'yyyy-MM-dd HH:mm:ss'),string(r.ClaimedID), ...
    string(r.Student),string(r.Decision),logical(r.Verified),logical(r.Granted), ...
    string(r.Stage),string(r.Reason),r.IDDistance,r.NameDistance,r.IDMargin,r.NameMargin, ...
    string(ranking(r.IDInfo)),string(ranking(r.NameInfo)), ...
    string(field(r,'Engine','legacy')),double(field(r,'VoiceScore',NaN)), ...
    string(field(r,'ImposterSuspect','')),logical(field(r,'ReplayFlag',false)), ...
    string(challenge_text(r)), ...
    'VariableNames',{'Time','ClaimedID','VerifiedStudent','Decision','Verified','Served', ...
    'Stage','Reason','IDDistance','NameDistance','IDMargin','NameMargin','IDTop5','NameTop5', ...
    'Engine','VoiceScore','ImposterSuspect','ReplayFlag','Challenge'});
try
    if isfile(file)
        fid=fopen(file,'r'); header=fgetl(fid); fclose(fid);
        if ~ischar(header) || ~contains(header,'ImposterSuspect')
            [folder,base,ext]=fileparts(file);
            movefile(file, fullfile(folder,[base '_v4.1.4' ext]));
        end
    end
    if isfile(file)
        writetable(row,file,'WriteMode','append','WriteVariableNames',false);
    else
        folder=fileparts(file); if ~isempty(folder) && ~isfolder(folder), mkdir(folder); end
        writetable(row,file);
    end
catch err
    warning('meal:AttemptLog','Could not save verification diagnostics: %s',err.message);
end
end

function v=field(r,name,default)
v=default;
if isfield(r,name) && ~isempty(r.(name)), v=r.(name); end
end

function s=challenge_text(r)
s='';
if ~isfield(r,'Challenge') || ~isstruct(r.Challenge) || ~isfield(r.Challenge,'Used') || ~r.Challenge.Used
    return;
end
state='FAILED'; if r.Challenge.Passed, state='passed'; end
s=sprintf('%s %s', sprintf('%d',r.Challenge.Code), state);
end

function s=ranking(info)
s='';
if ~isfield(info,'Scores') || ~isfield(info,'Users'), return; end
[d,k]=sort(info.Scores(:)); n=min(5,sum(isfinite(d)));
rows=cell(1,n);
for j=1:n, rows{j}=sprintf('%s:%.6g',info.Users(k(j)),d(j)); end
s=strjoin(rows,'; ');
end
