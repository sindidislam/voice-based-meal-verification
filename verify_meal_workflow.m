function result = verify_meal_workflow(status, typedCode, params, options) %#ok<INUSD>
%VERIFY_MEAL_WORKFLOW Verify identity, then check the current monthly roster.
% v4.1.4_claude: identity is decided by VSD_VERIFY_TRANSACTION (phrase content
% + GMM-UBM voice + imposter identification + anti-replay challenge) whenever
% params.vsd.Enable is true; OPTIONS.VsdFiles / VsdAudio / VsdCaptureFcn,
% HoldOut, SkipChallenge, ChallengeCode and NoAdapt are passed to it.
% Both ID and Name must independently verify the same student. An optional
% typed ClaimedID binds the result without weakening either biometric gate.
% Options.ClaimedID is independent of voice ranking. Supplied IDFeatures and
% NameFeatures evaluate one saved round; absent features never open a microphone.
% CaptureFcn(phrase,status,params,attempt) is an explicit acquisition test seam.
% SkipLogging performs biometrics only, with no CSV/payment writes.
% Granted means meal service; Verified means the biometric gates passed.
if nargin<3 || isempty(params), params=dsp_parameters(); end
if nargin<4, options=struct(); end
if nargin<1, status=[]; end
result=struct('Granted',false,'Verified',false,'Decision','UNCERTAIN / RETRY', ...
    'Student','','StudentName','','ClaimedID','','Stage','claim','FailureStage','','Reason','', ...
    'IDDistance',NaN,'NameDistance',NaN,'CouponDistance',NaN, ...
    'IDMargin',NaN,'NameMargin',NaN,'Margin',NaN,'NormalizedScore',Inf, ...
    'IDInfo',struct(),'NameInfo',struct(),'IDDiagnostics',struct(),'NameDiagnostics',struct(), ...
    'Meal','','Logged',false,'LogMessage','','Threshold',params.dtwThreshold, ...
    'Method','Voice-ID+Name','MonthlyPaid',false,'CouponRequired',false, ...
    'IdentifiedBy','','Similarity',NaN,'AttemptCount',0,'Attempts',{{}}, ...
    'NameCaptured',false,'IDStage','','NameStage','not-requested', ...
    'Engine','legacy','ImposterSuspect','','ImposterName','','ReplayFlag',false, ...
    'Challenge',struct('Used',false,'Passed',false,'Code',[]),'Advisory','','VoiceScore',NaN);
nowValue=opt(options,'NowValue',datetime('now'));
isExplicitClaim = isfield(options, 'ClaimedID');
if isExplicitClaim
    [claim,valid,reason]=student_id_contract(options.ClaimedID);
    if ~valid
        result.Stage='claim';
        result.Reason=['Enter the Student ID to verify. ' reason];
        update_status_text(status,result.Reason); return;
    end
    result.ClaimedID=claim;
    if ~isfolder(fullfile(params.trainIdFolder,claim)) || ...
            ~isfolder(fullfile(params.trainNameFolder,claim))
        result.Stage='enrollment';
        result.Reason='This student needs both ID and name enrollment before verification.';
        finish_attempt(); return;
    end
else
    claim = '';
end
customCapture=isfield(options,'CaptureFcn') && isa(options.CaptureFcn,'function_handle');
offline=~customCapture && (isfield(options,'IDFeatures') || isfield(options,'NameFeatures'));
% v4.1.4_claude: the VSD engine handles every live / file / audio transaction.
% The legacy matcher below is kept only for the legacy feature-injection seams
% (IDFeatures/NameFeatures/CaptureFcn) and when params.vsd.Enable is false.
useVsd = isfield(params,'vsd') && isstruct(params.vsd) && isfield(params.vsd,'Enable') && ...
    params.vsd.Enable && ~offline && ~customCapture;
if useVsd
    result = run_vsd_engine(result, status, params, options, claim);
    if ~result.Verified
        finish_attempt(); return;
    end
    claim = result.Student;
    if isExplicitClaim, result.ClaimedID = claim; end
end
limit=1; % Latest requested workflow: exactly one opportunity per phrase.
if useVsd, limit=0; else
    update_status_text(status,'(legacy v4.1.4 matcher: fixed distance limits; the new engine is disabled)');
end
for attempt=1:limit
    result.AttemptCount=attempt; result.NameCaptured=false;
    result.IDInfo=struct(); result.NameInfo=struct();
    result.IDDiagnostics=struct(); result.NameDiagnostics=struct();
    liveIdFeatures=[]; liveNameFeatures=[];
    for k=1:2
        phrases={'ID','Name'}; labels={'Student ID','full name'};
        fields={'IDFeatures','NameFeatures'}; folders={params.trainIdFolder,params.trainNameFolder};
        result.Stage=['capture-' lower(phrases{k})];
        update_status_text(status,sprintf('Attempt %d of %d: say your %s once.',attempt,limit,labels{k}));
        diagnostics=struct();
        if offline
            features=opt(options,fields{k},[]); ok=usable(features);
        elseif customCapture
            [features,ok,diagnostics]=options.CaptureFcn(phrases{k},status,params,attempt);
        else
            [features,ok,diagnostics]=capture_voice_features(labels{k},status,params);
        end
        if k==1
            result.IDDiagnostics=diagnostics;
            liveIdFeatures = features;
        else
            result.NameDiagnostics=diagnostics;
            result.NameCaptured=true;
            liveNameFeatures = features;
        end
        if is_user_stopped(status) || strcmp(opt(diagnostics,'Stage',''),'user-stop')
            result.Stage='user-stop'; result.Reason='Recording stopped by user.'; finish_attempt(); return;
        end
        info=struct();
        if ok && usable(features), [~,~,info]=find_best_voice_match(folders{k},features,params); end
        if k==1, result.IDInfo=info; else, result.NameInfo=info; end
        if isfield(info,'Scores') && ~isempty(info.Scores) && isfield(info,'Users') && ~isempty(info.Users)
            finiteIdx = find(isfinite(info.Scores));
            if ~isempty(finiteIdx)
                [sortedDists, sortOrder] = sort(info.Scores(finiteIdx), 'ascend');
                topCount = min(4, numel(sortedDists));
                topLines = cell(topCount, 1);
                for m = 1:topCount
                    u = char(info.Users(finiteIdx(sortOrder(m))));
                    d = sortedDists(m);
                    topLines{m} = sprintf('    #%d: %s (distance = %.2f)', m, u, d);
                end
                update_status_text(status, sprintf('  Closest matches for %s (Top %d):\n%s', labels{k}, topCount, strjoin(topLines, '\n')));
            end
        end
        if k == 2 && isfield(result.IDInfo, 'Scores') && ~isempty(result.IDInfo.Scores) && ...
                isfield(result.NameInfo, 'Scores') && ~isempty(result.NameInfo.Scores) && ...
                isfield(result.IDInfo, 'Users') && isfield(result.NameInfo, 'Users')
            idThresh = opt(params, 'idDtwThreshold', opt(params, 'dtwThreshold', 31.35));
            nameThresh = opt(params, 'nameDtwThreshold', opt(params, 'dtwThreshold', 30.35));
            [commonU, idI, nameI] = intersect(string(result.IDInfo.Users), string(result.NameInfo.Users), 'stable');
            if ~isempty(commonU)
                normId = result.IDInfo.Scores(idI) / idThresh;
                normNm = result.NameInfo.Scores(nameI) / nameThresh;
                fused = 0.40 * normId + 0.60 * normNm;
                fin = find(isfinite(fused));
                if ~isempty(fin)
                    [sFused, ord] = sort(fused(fin), 'ascend');
                    cnt = min(4, numel(sFused));
                    fLines = cell(cnt, 1);
                    for m = 1:cnt
                        uChar = char(commonU(fin(ord(m))));
                        fLines{m} = sprintf('    #%d: %s (fused score = %.2f, ID = %.2f, Name = %.2f)', ...
                            m, uChar, sFused(m), result.IDInfo.Scores(idI(fin(ord(m)))), result.NameInfo.Scores(nameI(fin(ord(m)))));
                    end
                    if opt(params, 'enableScoreFusion', false)
                        update_status_text(status, sprintf('  Multi-modal joint biometric ranking (Top %d):\n%s', cnt, strjoin(fLines, '\n')));
                    else
                        update_status_text(status, sprintf('  Diagnostic joint ranking only (not authorization; Top %d):\n%s', cnt, strjoin(fLines, '\n')));
                    end
                end
            end
        end
        if k==2
            voiceReport = opt(options, 'VoiceReport', []);
            projectRoot = fileparts(mfilename('fullpath'));
            defaultTrainFolder = fullfile(projectRoot, 'Train', 'ID');
            isCustomFolder = isfield(params, 'trainIdFolder') && ~strcmpi(params.trainIdFolder, defaultTrainFolder);
            if isempty(voiceReport) && isfield(params, 'voiceGMM') && isfield(params.voiceGMM, 'Enable') && params.voiceGMM.Enable && ~isCustomFolder
                if isfile(params.voiceGMM.ModelFile)
                    try
                        vData = load(params.voiceGMM.ModelFile);
                        if isfield(vData, 'UBM') && isfield(vData, 'SpeakerMeans') && isfield(vData, 'Users')
                            combFeat = [];
                            idF = opt(options, 'IDFeatures', liveIdFeatures);
                            nmF = opt(options, 'NameFeatures', liveNameFeatures);
                            if usable(idF)
                                if size(idF, 1) < size(idF, 2), idF = idF.'; end
                                combFeat = [combFeat; idF];
                            end
                            if usable(nmF)
                                if size(nmF, 1) < size(nmF, 2), nmF = nmF.'; end
                                combFeat = [combFeat; nmF];
                            end
                            if ~isempty(combFeat)
                                [llrs, ranks, best] = voice_gmm_ubm('score', combFeat, vData.SpeakerMeans, vData.UBM);
                                targetIdx = find(strcmp(vData.Users, claim), 1);
                                claimedRank = inf;
                                if ~isempty(targetIdx) && targetIdx <= numel(ranks)
                                    claimedRank = ranks(targetIdx);
                                end
                                topUser = '';
                                if best > 0 && best <= numel(vData.Users)
                                    topUser = char(vData.Users(best));
                                end
                                voiceReport = struct();
                                voiceReport.VoiceRank = claimedRank;
                                voiceReport.Ranks = ranks;
                                voiceReport.TopUser = topUser;
                                voiceReport.LLRs = llrs;
                                voiceReport.Users = vData.Users;
                            end
                        end
                    catch
                        voiceReport = [];
                    end
                end
            end
            decision=speaker_verification_decision(claim,result.IDInfo,result.NameInfo,params,voiceReport);
            names=fieldnames(decision);
            for n=1:numel(names), result.(names{n})=decision.(names{n}); end
            % v4.1.4_claude: the legacy matcher compares only the words, so a
            % student saying a friend's roll number and name could be accepted.
            % Before accepting, the GMM-UBM voice models must agree (VSD_VOICE_VETO).
            if result.Verified && isfield(params,'vsd') && isstruct(params.vsd) && ~offline
                xI=opt(result.IDDiagnostics,'RawAudio',[]); xN=opt(result.NameDiagnostics,'RawAudio',[]);
                [vok,vmsg,vsus]=vsd_voice_veto(result.Student,xI,opt(result.IDDiagnostics,'RawFs',params.fs), ...
                    xN,opt(result.NameDiagnostics,'RawFs',params.fs),params.vsd);
                update_status_text(status, ['  ' vmsg]);
                if ~vok
                    result.Verified=false; result.Stage='voice'; result.Reason=vmsg;
                    result.ImposterSuspect=vsus; decision.Reason=vmsg; decision.Verified=false;
                end
            end
            if result.Verified
                claim=result.Student;
                if isExplicitClaim, result.ClaimedID=claim; end
            else
                update_status_text(status, sprintf('● %s', decision.Reason));
            end
        end
    end
    result.Attempts{end+1}=struct('Number',attempt,'Verified',result.Verified, ...
        'IDStage',result.IDStage,'NameStage',result.NameStage,'IdentifiedBy',result.IdentifiedBy);
    if result.Verified, break; end
    result.FailureStage=result.Stage;
    if ~offline
        result.Stage='failed'; result.Decision='FAILED';
        if ~isempty(result.ImposterSuspect), result.Decision='IMPOSTER'; end
        if exist('decision','var') && isfield(decision,'Reason') && ~isempty(decision.Reason) && ~strcmp(decision.Reason,'Phrase verified.')
            result.Reason=decision.Reason;
        else
            result.Reason='Both ID and Name must independently verify the same student.';
        end
        update_status_text(status, sprintf('● VERIFICATION FAILED: %s', result.Reason));
    end
    finish_attempt(); return;
end
result.Method=['Voice-' upper(result.IdentifiedBy)];
meta=student_profile(params,claim);
if ~isempty(meta.Name) && (isempty(result.StudentName) || strcmp(result.StudentName, claim))
    result.StudentName=meta.Name;
end
if useVsd
    update_status_text(status,sprintf('VERIFIED: %s (%s) by phrase content + voice biometrics.',claim,result.StudentName));
else
    update_status_text(status,sprintf('VERIFIED: %s using %s on attempt %d.',claim,upper(result.IdentifiedBy),result.AttemptCount));
end
if is_user_stopped(status)
    result.Stage='user-stop'; result.Reason='Stopped before meal service.'; finish_attempt(); return;
end
if opt(options,'SkipLogging',false)
    result.Granted=true; result.Reason='Biometric verification passed; business operations skipped.';
    return;
end

% Every meal requires admin assignment for this calendar month. Legacy coupon
% and requireMonthlyRoster flags cannot disable this mandatory business gate.
result.Stage='roster';
[paid,message]=monthly_fee_entitlement(claim,params,nowValue,'check');
result.MonthlyPaid=paid;
if ~paid
    result.Reason=['DENIED: ' message];
    update_status_text(status,['● ' result.Reason]);
    finish_attempt(); return;
end
result.Stage='entitlement';
if is_user_stopped(status)
    result.Stage='user-stop'; result.Reason='Stopped before meal service.'; finish_attempt(); return;
end
[result.Logged,result.LogMessage,logInfo]=log_meal_csv(claim,result,params,nowValue);
result.Meal=logInfo.Meal; result.Granted=result.Logged;
if result.Logged
    result.Reason='Verified and meal recorded.';
    update_status_text(status,sprintf('SERVE %s to %s.',result.Meal,claim));
else
    result.Reason=result.LogMessage;
    update_status_text(status,['DO NOT SERVE: ' result.Reason]);
end
finish_attempt();

    function finish_attempt()
        update_status_text(status,[result.Decision ': ' result.Reason]);
        if ~opt(options,'SkipLogging',false)
            log_verification_attempt(result,params,nowValue);
        end
    end
end

function result=run_vsd_engine(result,status,params,options,claim)
%RUN_VSD_ENGINE Run VSD_VERIFY_TRANSACTION and map its output onto RESULT.
v=struct();
if ~isempty(claim), v.ClaimedID=claim; end
map={'VsdFiles','Files';'VsdAudio','Audio';'VsdCaptureFcn','CaptureFcn';'HoldOut','HoldOut'; ...
    'SkipChallenge','SkipChallenge';'ChallengeCode','ChallengeCode';'NoAdapt','NoAdapt'};
for k=1:size(map,1)
    if isfield(options,map{k,1}), v.(map{k,2})=options.(map{k,1}); end
end
T=vsd_verify_transaction(status,params,v);
result.Engine='vsd';
result.VSD=T;
result.AttemptCount=1;
result.Verified=T.Verified;
result.Decision=T.Decision;
if strcmp(result.Decision,'RETRY'), result.Decision='UNCERTAIN / RETRY'; end
result.Student=T.Student;
result.StudentName=T.StudentName;
result.Stage=T.Stage;
result.FailureStage=T.Stage;
result.Reason=T.Reason;
result.ImposterSuspect=T.ImposterSuspect;
result.ImposterName=T.ImposterName;
result.ReplayFlag=T.ReplayFlag;
result.Challenge=T.Challenge;
result.Advisory=T.Advisory;
result.IdentifiedBy='id+name+voice';
result.NameCaptured=~isempty(T.NameU);
if isfield(T,'ScoreVectors') && ~isempty(T.Student)
    S=T.ScoreVectors; k=find(strcmp(S.Students,T.Student),1);
    if ~isempty(k)
        result.IDDistance=S.Did(k); result.NameDistance=S.Dname(k);
        result.IDMargin=S.Pid(k);   result.NameMargin=S.Pname(k);
        result.VoiceScore=S.V(k);
        result.Margin=T.Scores.FMargin;
        % 0-100 display confidence: logistic of the fused score F (F=0 -> 50 %)
        result.Similarity=100./(1+exp(-6*T.Scores.F));
    end
    result.IDInfo=struct('Users',{string(S.Students)},'Scores',S.Did);
    result.NameInfo=struct('Users',{string(S.Students)},'Scores',S.Dname);
end
end

function tf=usable(f)
tf=isnumeric(f) && isreal(f) && ismatrix(f) && ~isempty(f) && ...
    size(f,2)>=2 && all(isfinite(f(:)));
end

function v=opt(s,n,d)
v=d;
if isstruct(s) && isfield(s,n) && ~isempty(s.(n)), v=s.(n); end
end

function tf=is_user_stopped(status)
tf=false;
if isempty(status), return; end
try
    fig=ancestor(status,'figure');
    tf=isfield(fig.UserData,'stopRequested') && fig.UserData.stopRequested;
catch
end
try
    if isprop(status,'UserData') && isstruct(status.UserData) && ...
            isfield(status.UserData,'stopRequested') && status.UserData.stopRequested
        tf=true;
    end
catch
end
end
