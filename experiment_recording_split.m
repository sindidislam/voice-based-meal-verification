function manifest = experiment_recording_split(projectRoot)
%EXPERIMENT_RECORDING_SPLIT Fixed recording-disjoint retrospective protocol.
% Only canonical students having three ID and three Name takes participate.
% Extra files and unmatched students are not silently assigned to a role.
if nargin<1, projectRoot=fileparts(mfilename('fullpath')); end
idFolder=fullfile(projectRoot,'Train','ID');
listing=dir(idFolder); students=strings(0,1);
for k=1:numel(listing)
    if listing(k).isdir && ~isempty(regexp(listing(k).name,'^\d{7}$','once'))
        students(end+1,1)=string(listing(k).name); %#ok<AGROW>
    end
end
students=sort(students); rows=cell(0,7); bytes={};
roles=["enrollment","development","final_test"];
for s=1:numel(students)
    paths=cell(2,3); complete=true;
    for ph=1:2
        phrase=["ID","Name"];
        for take=1:3
            paths{ph,take}=fullfile(projectRoot,'Train',phrase(ph),students(s),sprintf('%d.wav',take));
            complete=complete && isfile(paths{ph,take});
        end
    end
    if ~complete, continue; end
    for ph=1:2
        for take=1:3
            file=paths{ph,take}; fid=fopen(file,'rb');
            if fid<0, error('experiment:unreadableRecording','Cannot read %s',file); end
            closer=onCleanup(@() fclose(fid)); raw=fread(fid,Inf,'*uint8'); clear closer;
            for j=1:numel(bytes)
                if isequal(raw,bytes{j})
                    error('experiment:duplicateRecording', ...
                        'Duplicate WAV contents: %s and %s. Resolve provenance before testing.',file,rows{j,5});
                end
            end
            bytes{end+1}=raw; %#ok<AGROW>
            digest=java.security.MessageDigest.getInstance('SHA-256');
            digest.update(raw);
            hash=string(lower(reshape(dec2hex(typecast(digest.digest(),'uint8'),2)',1,[])));
            rows(end+1,:)={students(s),phrase(ph),take,roles(take),string(file),numel(raw),hash}; %#ok<AGROW>
        end
    end
end
if isempty(rows), error('experiment:noCompleteStudents','No students have three takes of both phrases.'); end
manifest=cell2table(rows,'VariableNames',{'Student','Phrase','Take','Role','Path','Bytes','SHA256'});
end
