function test_experiment_multitemplate()
% Real scalar-feature DTW fixtures: removing a holdout/hash/path exclusion,
% replacing mean/median with min, or choosing the best single template fails.
assert(exist('experiment_multitemplate','file')==2, ...
    'Missing experiment_multitemplate: retrospective multi-template comparison is not implemented.');
p=dsp_parameters(); p.dtw.Normalise=true;
[records,manifest,users]=fixture();
[results,distances]=experiment_multitemplate(records,manifest,users,p);
assert(height(results)==72,'Every student/take/phrase requires all three methods.');
assert(all(results.Scope=="retrospective_leave_one_take_out"));
assert(all(results.Status=="measured"));
assert(all(results.Top1Correct));
assert(all(results.GenuineComparisons==1 & results.ImpostorComparisons==3));
assert(all(distances.QueryTake~=distances.TemplateTake), ...
    'The query take must be held out for every enrolled student.');
assert(all(distances.QueryPath~=distances.TemplatePath));
assert(all(distances.QuerySHA256~=distances.TemplateSHA256));
assert(all(distances.Phrase==distances.TemplatePhrase));
q=results.ActualStudent==users(1) & results.QueryTake==1 & results.Phrase=="ID";
single=results(q & results.Method=="single",:);
average=results(q & results.Method=="multi_mean",:);
middle=results(q & results.Method=="multi_median",:);
assert(single.GenuineDistance==1 && single.NearestImpostorDistance==11);
assert(average.GenuineDistance==2.5 && average.NearestImpostorDistance==12.5);
assert(middle.GenuineDistance==2.5 && middle.NearestImpostorDistance==12.5);
assert(single.TemplateCount==4 && average.TemplateCount==8 && middle.TemplateCount==8);
assert(single.GenuineTemplateComparisons==1 && single.ImpostorTemplateComparisons==3);
assert(average.GenuineTemplateComparisons==2 && average.ImpostorTemplateComparisons==6);
selected=distances.QueryTake==1 & distances.Method=="single";
assert(all(distances.TemplateTake(selected)==2), ...
    'Single-template baseline uses the earliest eligible take, never the best score.');

% Byte-identical copies with another path/student/take cannot enter a library.
copy=find(manifest.Student==users(2) & manifest.Phrase=="ID" & manifest.Take==2);
query=find(manifest.Student==users(1) & manifest.Phrase=="ID" & manifest.Take==1);
copyManifest=manifest; copyManifest.SHA256(copy)=copyManifest.SHA256(query);
[r,d]=experiment_multitemplate(records,copyManifest,users,p);
q=r.ActualStudent==users(1) & r.QueryTake==1 & r.Phrase=="ID" & r.Method=="multi_mean";
assert(r.TemplateCount(q)==7 && r.NearestImpostorDistance(q)==14);
assert(all(d.QuerySHA256~=d.TemplateSHA256),'Duplicate content must be excluded globally.');

% Exact path exclusion must work independently of the supplied hash string.
pathRecords=records; pathManifest=manifest;
pathRecords(copy).Path=records(query).Path; pathManifest.Path(copy)=manifest.Path(query);
[r,d]=experiment_multitemplate(pathRecords,pathManifest,users,p);
q=r.ActualStudent==users(1) & r.QueryTake==1 & r.Phrase=="ID" & r.Method=="multi_mean";
assert(r.TemplateCount(q)==7 && r.NearestImpostorDistance(q)==14);
assert(all(d.QueryPath~=d.TemplatePath),'Exact query paths cannot enter a library.');

% A fourth take distinguishes robust median from arithmetic mean (4 vs 17/3).
extra=records(query); extra.Path="fixture/ID/2206141/4.wav"; extra.Features=24;
extraRow=manifest(query,:); extraRow.Path=extra.Path; extraRow.Take=4;
extraRow.SHA256="unique_fourth_take";
[r,~]=experiment_multitemplate([records extra],[manifest;extraRow],users,p);
q=r.ActualStudent==users(1) & r.QueryTake==1 & r.Phrase=="ID";
assert(abs(r.GenuineDistance(q & r.Method=="multi_mean")-17/3)<1e-12);
assert(r.GenuineDistance(q & r.Method=="multi_median")==4);

% Missing/invalid features stay visible as unsupported comparisons, never zero.
broken=records; broken(query).Features=[];
[r,~]=experiment_multitemplate(broken,manifest,users,p);
q=r.ActualStudent==users(1) & r.QueryTake==1 & r.Phrase=="ID";
assert(all(r.Status(q)=="query_features_unavailable"));
assert(all(isinf(r.GenuineDistance(q))) && all(~r.Top1Correct(q)));
assert(all(r.GenuineComparisons(q)==0 & r.ImpostorComparisons(q)==0));
fprintf('Retrospective multi-template invariants passed.\n');
end

function [records,manifest,users]=fixture()
users=["2206141";"2206149";"2206151";"2206161"];
records=struct('Student',{},'Phrase',{},'Role',{},'Path',{},'Features',{});
rows=cell(0,6); offsets=[0 2 8];
for student=1:numel(users)
    for phrase=["ID","Name"]
        for take=1:3
            path="fixture/"+phrase+"/"+users(student)+"/"+take+".wav";
            records(end+1)=struct('Student',users(student),'Phrase',phrase, ...
                'Role',"fixture",'Path',path,'Features',20*(student-1)+offsets(take)); %#ok<AGROW>
            rows(end+1,:)={users(student),phrase,take,"fixture",path,"sha_"+numel(records)}; %#ok<AGROW>
        end
    end
end
manifest=cell2table(rows,'VariableNames',{'Student','Phrase','Take','Role','Path','SHA256'});
end
