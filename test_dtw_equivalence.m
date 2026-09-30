function test_dtw_equivalence()
% Differential test against the original norm-per-cell recurrence.
rng(312); cases={[3 17 22],[13 55 48],[39 101 80],[39 350 300]};
for precision={'double','single'}
    for k=1:numel(cases)
        sz=cases{k};
        a=cast(randn(sz(1),sz(2)),precision{1});
        b=cast(randn(sz(1),sz(3)),precision{1});
        for band=[.1 .3 1]
            check_case(a,b,band,sprintf('%s random case %d band %.1f',precision{1},k,band));
        end
    end
end

% These hand-checked raw costs catch cancellation in the prefix recurrence
% and overflow/underflow from squaring before taking a Euclidean norm. The
% local-cost case has input magnitudes only 1..4, so an input-range guard
% alone cannot protect the small distance between nearly identical frames.
fixtures={ ...
    'prefix cancellation', [1e16 1], [1e16 0], 1; ...
    'local-cost cancellation', [4 1+eps(1)], [4 1], eps(1); ...
    'large scalar norm', 1e155, 0, 1e155; ...
    'tiny scalar norm', 1e-200, 0, 1e-200; ...
    'large vector norm', [3e154;4e154], [0;0], 5e154; ...
    'tiny vector norm', [3e-201;4e-201], [0;0], 5e-201; ...
    'single large scalar norm', single(1e20), single(0), double(single(1e20)); ...
    'single tiny scalar norm', single(1e-30), single(0), double(single(1e-30)); ...
    'single prefix cancellation', single([1e8 1]), single([1e8 0]), 1; ...
    'single local-cost cancellation', single([4 1+double(eps(single(1)))]), single([4 1]), double(eps(single(1))); ...
    'complex identity', 1+2i, 1+2i, 0; ...
    'complex frame norms', [1+2i 2-1i], [1+2i 3-1i], 1};
for k=1:size(fixtures,1)
    check_case(fixtures{k,2},fixtures{k,3},1,fixtures{k,1},fixtures{k,4});
end
[d,info]=dtw_distance_dsp(zeros(3,5),zeros(3,5),struct('ReturnPath',true));
assert(d==0 && isequal(info.Path,[1:5;1:5]));
assert(isinf(dtw_distance_dsp([],[])));
a=randn(39,350); b=randn(39,300); p=struct('SakoeChibaBand',.3,'Normalise',true);
dtw_distance_dsp(a,b,p); reference(a,b,p);
times=zeros(3,2);
for k=1:3
    tic; reference(a,b,p); times(k,1)=toc;
    tic; dtw_distance_dsp(a,b,p); times(k,2)=toc;
end
fprintf('DTW_EQUIVALENCE_PASS reference median %.6fs production %.6fs speedup %.2fx\n',median(times(:,1)),median(times(:,2)),median(times(:,1))/median(times(:,2)));
end

function check_case(a,b,band,label,knownRaw)
p=struct('SakoeChibaBand',band,'Normalise',false,'ReturnPath',true);
[expectedRaw,surface,cells]=reference(a,b,p);
if isa(a,'single') || isa(b,'single')
    relativeTolerance=2e-5;
else
    relativeTolerance=2e-11;
end
if nargin>=5
    check_close(expectedRaw,knownRaw,relativeTolerance,[label ' reference oracle']);
end
for normalise=[false true]
    p.Normalise=normalise;
    expected=expectedRaw;
    if normalise, expected=expected/(size(a,2)+size(b,2)); end
    [actual,info]=dtw_distance_dsp(a,b,p);
    check_close(actual,expected,relativeTolerance,[label ' distance']);
    check_close(info.RawDistance,expectedRaw,relativeTolerance,[label ' raw distance']);
    assert(isequal(isinf(surface),isinf(info.Accumulated)),'%s unreachable cells differ',label);
    mask=isfinite(surface);
    check_close(info.Accumulated(mask),surface(mask),relativeTolerance,[label ' accumulated surface']);
    assert(cells==info.CellsEvaluated,'%s evaluated-cell count differs',label);
    path=info.Path;
    assert(isequal(path(:,1),[1;1]) && isequal(path(:,end),[size(a,2);size(b,2)]),'%s path endpoints differ',label);
    steps=diff(path,1,2);
    assert(all(steps(:)>=0 & steps(:)<=1) && all(sum(steps,1)>=1),'%s path contains an illegal step',label);
    assert(all(abs(path(1,:)-path(2,:))<=info.Band),'%s path leaves the corridor',label);
    pathCost=0;
    for step=1:size(path,2)
        pathCost=pathCost+norm(a(:,path(1,step))-b(:,path(2,step)));
    end
    check_close(pathCost,info.RawDistance,relativeTolerance,[label ' recovered path cost']);
end
end

function check_close(actual,expected,relativeTolerance,label)
% Relative-only tolerance deliberately rejects zero for a positive tiny norm.
actual=double(actual); expected=double(expected);
assert(isreal(actual) && all(isfinite(actual(:))),'%s must be real and finite',label);
error=abs(actual-expected);
assert(all(error(:)<=relativeTolerance*abs(expected(:))),'%s exceeds relative tolerance %.3g',label,relativeTolerance);
end

function [d,surface,cells]=reference(a,b,p)
n=size(a,2); m=size(b,2); band=max([ceil(p.SakoeChibaBand*max(n,m)),abs(n-m)+1,1]);
D=Inf(n+1,m+1); D(1,1)=0; cells=0;
for i=1:n
    for j=max(1,i-band):min(m,i+band)
        D(i+1,j+1)=norm(a(:,i)-b(:,j))+min([D(i,j+1),D(i+1,j),D(i,j)]); cells=cells+1;
    end
end
d=D(end,end); if p.Normalise, d=d/(n+m); end
surface=D(2:end,2:end);
end
