function [bestDist, bestUser, info] = voice_match_scores(library, testFeatures, p, varargin)
%VOICE_MATCH_SCORES Score one capture against a library of enrolled students.
%
%   [BESTDIST, BESTUSER, INFO] = VOICE_MATCH_SCORES(LIBRARY, TESTFEATURES, P)
%   returns the closest enrolled student, that student's score, and the runner-up
%   margin.  LIBRARY is a struct with fields:
%       Users     n-by-1 string array of student names
%       Templates n-by-1 cell array; each cell is a cell array of feature matrices
%
%   This function holds the scoring and ranking rule for the whole system.
%   FIND_BEST_VOICE_MATCH builds a library from the enrolment folders and calls
%   it; EXPERIMENT_VERIFICATION_ACCURACY builds libraries in memory with students
%   or recordings deliberately held out and calls the same function.  Keeping one
%   copy is what makes the measured error rates apply to the deployed decision:
%   if the experiment reimplemented the ranking, it would be measuring a different
%   system from the one that serves meals.
%
%   The per-student score is the MEAN of the distances to that student's
%   templates.  The minimum would let one unusually lucky template speak for the
%   student, and would make the score depend on how many recordings that student
%   happens to have stored -- a student with six templates would score better than
%   an identical student with two, for no reason connected to their voice.
%
%   INFO.Margin is the runner-up's score divided by the winner's, so it is 1 when
%   two students are equally close and grows as the winner pulls ahead.  It is Inf
%   when only one student is enrolled, which correctly means "no competition"
%   rather than "ambiguous".
%
%   See also FIND_BEST_VOICE_MATCH, DTW_DISTANCE_DSP, EXPERIMENT_VERIFICATION_ACCURACY.

if nargin >= 1 && (ischar(library) || isstring(library)) && strcmpi(library, 'cohort_ratio')
    cohortSize = 4;
    if ~isempty(varargin), cohortSize = varargin{1}; end
    bestDist = cohort_ratio(testFeatures, p, cohortSize);
    bestUser = ''; info = struct();
    return;
end

if nargin < 3 || isempty(p), p = dsp_parameters(); end
aggregation = 'mean';
if isfield(p,'templateAggregation'), aggregation = p.templateAggregation; end
aggregation = validatestring(aggregation, {'mean','median','min'});

info = struct('Scores',[],'Users',strings(0,1),'BestUser','','BestDistance',Inf, ...
    'RunnerUpUser','','RunnerUpDistance',Inf,'Margin',Inf, ...
    'TemplatesUsed',0,'TemplatesRejected',0,'FrontEnd',p.featureFrontEnd);
info.Aggregation = aggregation;

bestDist = Inf;
bestUser = '';

if isempty(testFeatures) || isempty(library.Users)
    return;
end

n = numel(library.Users);
scores = Inf(n,1);

for i = 1:n
    templates = library.Templates{i};
    distances = Inf(numel(templates),1);
    for j = 1:numel(templates)
        f = templates{j};
        if isempty(f) || size(f,1) ~= size(testFeatures,1)
            % A feature-dimension mismatch means the template was extracted under
            % a different configuration. Comparing them would produce a number,
            % but not a meaningful one, so the template is skipped and counted.
            info.TemplatesRejected = info.TemplatesRejected + 1;
            continue;
        end
        distances(j) = dtw_distance_dsp(f, testFeatures, p.dtw);
        info.TemplatesUsed = info.TemplatesUsed + 1;
    end
    valid = distances(isfinite(distances));
    if ~isempty(valid)
        switch aggregation
            case 'mean', scores(i) = mean(valid);
            case 'median', scores(i) = median(valid);
            case 'min', scores(i) = min(valid);
        end
    end
end

info.Scores = scores;
info.Users = library.Users(:);

finite = find(isfinite(scores));
if isempty(finite)
    return;
end

[sorted, order] = sort(scores(finite), 'ascend');
bestIdx = finite(order(1));
bestDist = sorted(1);
bestUser = char(library.Users(bestIdx));

info.BestUser = bestUser;
info.BestDistance = bestDist;
info.CohortRatio = cohort_ratio(scores, bestIdx, 4);

if numel(sorted) > 1
    runnerIdx = finite(order(2));
    info.RunnerUpUser = char(library.Users(runnerIdx));
    info.RunnerUpDistance = sorted(2);
    info.Margin = sorted(2) / max(bestDist, eps);
end
end

% -------------------------------------------------------------------------
function S = cohort_ratio(distances, targetIdx, cohortSize)
if nargin < 3 || isempty(cohortSize), cohortSize = 4; end
if targetIdx < 1 || targetIdx > numel(distances)
    S = 0; return;
end
dTarget = distances(targetIdx);
competitors = distances([1:targetIdx-1, targetIdx+1:end]);
valid = sort(competitors(isfinite(competitors)), 'ascend');
if isempty(valid) || ~isfinite(dTarget)
    S = 0; return;
end
k = min(cohortSize, numel(valid));
meanCompetitor = mean(valid(1:k));
S = log(meanCompetitor / max(dTarget, 1e-9));
end
% end of file

%
%
