function summary=verify_vsd_deployment(experimentDir)
%VERIFY_VSD_DEPLOYMENT Re-run held-out claims through the actual active workflow.
% Uses archive preprocessing, never labels archive WAVs as live/replay trials.
root=fileparts(mfilename('fullpath'));
if nargin<1 || islogical(experimentDir) || isempty(experimentDir), experimentDir=fullfile(root,'Results','experiments_20260927'); end
out=fullfile(root,'Results','security_20260927'); if ~isfolder(out), mkdir(out); end
p=dsp_parameters(); find_best_voice_match('reset');
assert(isfield(p,'voiceCalibration') && p.recordDur==8);
manifest=readtable(fullfile(experimentDir,'recording_manifest.csv'),'TextType','string');
manifest.Student=string(manifest.Student);
expected=readtable(fullfile(experimentDir,'decision_trials.csv'),'TextType','string');
expected.ActualStudent=string(expected.ActualStudent); expected.ClaimedStudent=string(expected.ClaimedStudent);
expected=expected(expected.Variant=="final_selected" & expected.Split=="final_test" & expected.Mode=="ID+Name",:);
distances=readtable(fullfile(experimentDir,'pair_distances.csv'),'TextType','string');
distances.ActualStudent=string(distances.ActualStudent); distances.CandidateStudent=string(distances.CandidateStudent);
distances=distances(distances.Variant==string(p.voiceCalibration.Variant) & distances.Split=="final_test",:);
test=manifest(manifest.Role=="final_test",:); users=unique(test.Student,'stable'); rows={};
allClaims={}; quality={};
for i=1:numel(users)
    features=cell(1,2); phrases=["ID","Name"];
    for ph=1:2
        row=test(test.Student==users(i) & test.Phrase==phrases(ph),:);
        assert(height(row)==1);
        filePath = char(string(row.Path));
        if ~isfile(filePath)
            relP = fullfile(fileparts(mfilename('fullpath')), 'VSD_Corpus', 'Train', char(string(row.Phrase)), char(string(row.Student)), sprintf('%d.wav', row.Take));
            if isfile(relP)
                filePath = relP;
            end
        end
        [features{ph},q]=enrol_template_features(filePath,[],p);
        quality(end+1,:)={users(i),phrases(ph),q.Usable,string(q.Reason),string(row.Path)}; %#ok<AGROW>
    end
    result=verify_meal_workflow([], '',p,struct('ClaimedID',char(users(i)), ...
        'IDFeatures',features{1},'NameFeatures',features{2},'SkipLogging',true));
    rows(end+1,:)=result_row(users(i),users(i),result,"final take3 own claim"); %#ok<AGROW>
    own=expected(expected.ActualStudent==users(i) & expected.ClaimedStudent==users(i),:);
    assert(height(own)==1 && result.Verified==logical(own.Accepted));
    % Audit both saved phrases independently even when the live workflow
    % correctly stops after ID. This does not claim Name was captured live.
    info=cell(1,2); folders={p.trainIdFolder,p.trainNameFolder};
    for ph=1:2, [~,~,info{ph}]=find_best_voice_match(folders{ph},features{ph},p); end
    for ph=1:2
        actual=info{ph};
        expectedPhrase=distances(distances.Phrase==phrases(ph) & distances.ActualStudent==users(i),:);
        assert(height(expectedPhrase)==numel(users) && isequal(sort(expectedPhrase.CandidateStudent),sort(users)));
        if isempty(features{ph})
            assert(isempty(actual.Users) && all(isinf(expectedPhrase.Distance)));
            continue;
        end
        assert(isequal(sort(string(actual.Users(:))),sort(users)), ...
            'deployment:rosterMismatch','Deployed candidate roster differs from the experiment.');
        for c=1:numel(actual.Users)
            d=distances(distances.Phrase==phrases(ph) & distances.ActualStudent==users(i) & ...
                distances.CandidateStudent==actual.Users(c),:);
            assert(height(d)==1 && (abs(d.Distance-actual.Scores(c))<1e-9 || ...
                (isinf(d.Distance) && isinf(actual.Scores(c)))), ...
                'deployment:scoreMismatch','Deployed scorer differs from the frozen evaluation.');
        end
    end
    for claim=users'
        decision=speaker_verification_decision(char(claim),info{1},info{2},p);
        e=expected(expected.ActualStudent==users(i) & expected.ClaimedStudent==claim,:);
        assert(height(e)==1 && logical(e.Accepted)==decision.Verified, ...
            'deployment:decisionMismatch','Deployed decision differs from the frozen evaluation.');
        allClaims(end+1,:)={users(i),claim,users(i)==claim,decision.Verified,string(decision.Stage)}; %#ok<AGROW>
    end
    if users(i)=="2206150"
        challenge=verify_meal_workflow([], '',p,struct('ClaimedID','2206149', ...
            'IDFeatures',features{1},'NameFeatures',features{2},'SkipLogging',true));
        rows(end+1,:)=result_row(users(i),"2206149",challenge,"final take3 own-content false claim"); %#ok<AGROW>
        assert(~challenge.Verified && ~challenge.Granted,'deployment:falseClaim','150 was accepted as149.');
    end
end
t=cell2table(rows,'VariableNames',{'ActualStudent','ClaimedStudent','Verified','Granted', ...
    'IDCandidate','NameCandidate','IDDistance','NameDistance','IDMargin','NameMargin','Stage','Reason','NameCaptured','IdentifiedBy','Evidence'});
claims=cell2table(allClaims,'VariableNames',{'ActualStudent','ClaimedStudent','Genuine','Verified','Stage'});
q=cell2table(quality,'VariableNames',{'Student','Phrase','Usable','Reason','Path'});
writetable(t,fullfile(out,'deployed_workflow_trials.csv'));
writetable(claims,fullfile(out,'deployed_claim_matrix.csv'));
writetable(q,fullfile(out,'deployed_query_quality.csv'));
summary=struct('Profiles',numel(users),'CaptureSeconds',p.recordDur, ...
    'GenuineAccepted',sum(claims.Genuine & claims.Verified),'GenuineAttempts',sum(claims.Genuine), ...
    'FalseAccepted',sum(~claims.Genuine & claims.Verified),'FalseClaimAttempts',sum(~claims.Genuine), ...
    'DeployedScoresMatchFrozenExperiment',true,'EnrollmentTake',1,'FinalTake',3, ...
    'Evidence','Recording-disjoint own-content offline verification; not a microphone or phone-replay test');
fid=fopen(fullfile(out,'deployed_validation.json'),'w'); assert(fid>=0); close=onCleanup(@()fclose(fid)); %#ok<NASGU>
fprintf(fid,'%s\n',jsonencode(summary,'PrettyPrint',true));
disp(summary); disp('VSD_DEPLOYMENT_VERIFIED');
end

function row=result_row(actual,claim,r,evidence)
id=""; name="";
if isfield(r.IDInfo,'BestUser'), id=string(r.IDInfo.BestUser); end
if isfield(r.NameInfo,'BestUser'), name=string(r.NameInfo.BestUser); end
row={actual,claim,r.Verified,r.Granted,id,name,r.IDDistance,r.NameDistance, ...
    r.IDMargin,r.NameMargin,string(r.Stage),string(r.Reason),r.NameCaptured,string(r.IdentifiedBy),evidence};
end
