function [distance, info] = dtw_distance_dsp(a, b, opts)
%DTW_DISTANCE_DSP Dynamic time warping distance between two feature sequences.
%
%   [DISTANCE, INFO] = DTW_DISTANCE_DSP(A, B, OPTS) returns the normalised
%   accumulated distance between the feature sequences A and B.  Each column of
%   A and B is one frame; rows are feature dimensions.
%
%   Proposal Goal 2.  EEE 312 Experiment 5/6 (comparison of discrete-time
%   sequences; correlation and distance measures).
%
%   Why DTW rather than cross-correlation
%   -------------------------------------
%   Two recordings of the same person saying "three seven one" are never the
%   same length: speaking rate varies by tens of per cent between attempts, and
%   individual phonemes stretch and compress independently of one another.
%   Cross-correlation searches over a single global time SHIFT, so it can align
%   two signals that differ by a constant delay but cannot align two signals
%   that differ by a time-varying rate.  When the rates differ, the correlation
%   peak collapses and a genuine speaker is rejected.  This is precisely the
%   baseline failure that XCORR_DISTANCE_DSP reproduces for the comparison
%   required by CO2.
%
%   DTW instead finds the monotone alignment path that minimises total distance,
%   so it absorbs the local rate variation.
%
%   The recursion
%   -------------
%   With d(i,j) the local distance between frame i of A and frame j of B,
%
%       D(i,j) = d(i,j) + min{ D(i-1,j), D(i,j-1), D(i-1,j-1) }
%
%   evaluated by dynamic programming with D(0,0) = 0 and the borders at
%   infinity.  The three predecessors encode the three permitted steps:
%   D(i-1,j) lets A advance while B waits, D(i,j-1) lets B advance while A
%   waits, and D(i-1,j-1) advances both.  Restricting the step set this way is
%   what enforces monotonicity and continuity -- the alignment can never run
%   backwards in time or skip a frame.
%
%   Cost is O(N*M), where N and M count feature frames. With fixed-duration
%   frame hops these counts are approximately independent of sample rate.
%   Reducing sample rate saves front-end sample/FFT work, not DTW cells.
%
%   Normalisation and the band constraint
%   -------------------------------------
%   The raw accumulated distance grows with path length, so a long utterance
%   would always look less similar than a short one.  Dividing by (N+M), an
%   upper bound on the number of steps in any admissible path, makes the score
%   comparable across utterance lengths so that a single threshold can be used.
%
%   OPTS.SakoeChibaBand restricts the path to a diagonal corridor whose
%   half-width is that fraction of the longer sequence.  It removes pathological
%   alignments in which a single frame of one signal is stretched across most of
%   the other -- a real risk when comparing against an impostor, because such
%   degenerate paths can produce a misleadingly small distance -- and it also
%   reduces the number of cells evaluated.
%
%   INFO reports Rows, Cols, Band, CellsEvaluated and RawDistance.  Setting
%   OPTS.ReturnPath = true additionally returns INFO.Accumulated (the D matrix
%   above, with the unreachable cells left at infinity) and INFO.Path (a 2-by-K
%   list of the [i; j] cells the optimal alignment passes through, in time order).
%   Both are for display and teaching -- MEAL_VERIFICATION_GUI draws the corridor,
%   the cost surface and the path on one axes -- and both are off by default so
%   that CALIBRATE_DTW_THRESHOLD, which calls this function tens of thousands of
%   times, never allocates an output it does not read.
%
%   See also XCORR_DISTANCE_DSP, FIND_BEST_VOICE_MATCH, CALIBRATE_DTW_THRESHOLD.

if nargin < 3, opts = struct(); end
if ~isfield(opts,'SakoeChibaBand'), opts.SakoeChibaBand = 0.30; end
if ~isfield(opts,'Normalise'),      opts.Normalise      = true; end
if ~isfield(opts,'ReturnPath'),     opts.ReturnPath     = false; end

n = size(a,2);
m = size(b,2);
info = struct('Rows',n,'Cols',m,'Band',NaN,'CellsEvaluated',0,'RawDistance',NaN);

if n == 0 || m == 0 || size(a,1) ~= size(b,1)
    distance = Inf;
    return;
end

% Band half-width in cells. It must be at least the length difference,
% otherwise no admissible path can reach the far corner.
band = max([ceil(opts.SakoeChibaBand * max(n,m)), abs(n-m) + 1, 1]);
info.Band = band;

D = Inf(n+1, m+1);
D(1,1) = 0;
cells = 0;
% Preserve norm's range/precision behavior outside the ordinary real-double
% feature domain. Squaring extreme inputs can overflow or erase tiny norms.
stable = ~isa(a,'double') || ~isa(b,'double') || ~isreal(a) || ~isreal(b);
if ~stable
    magnitudes=abs([a(:);b(:)]); nonzero=magnitudes(magnitudes>0);
    stable=any(~isfinite(magnitudes)) || any(nonzero>1e100) || any(nonzero<1e-100);
end
% Accumulate squared feature differences in contiguous matrices. Unlike the
% dot-product distance identity this stays exactly zero for identical frames.
if ~stable
    localCosts = zeros(n,m);
    for feature = 1:size(a,1)
        difference = a(feature,:)' - b(feature,:);
        localCosts = localCosts + difference.^2;
    end
    localCosts = sqrt(localCosts);
    positiveCosts=localCosts(localCosts>0);
    % Even modest input values can produce a tiny distance between nearly
    % equal frames. Prefix subtraction must not erase that evidence.
    stable=any(~isfinite(localCosts(:))) || (~isempty(positiveCosts) && ...
        max(positiveCosts)/min(positiveCosts)>1e6);
end

for i = 1:n
    % Column range inside the corridor for this row.
    jLow  = max(1, i - band);
    jHigh = min(m, i + band);
    if stable
        for j=jLow:jHigh
            D(i+1,j+1)=norm(a(:,i)-b(:,j))+min([D(i,j+1),D(i+1,j),D(i,j)]);
        end
        cells=cells+jHigh-jLow+1;
        continue;
    end
    costs = localCosts(i,jLow:jHigh);
    % Unroll the left-neighbor recurrence algebraically. If S is cumulative
    % row cost and B=min(up,diagonal), then D_j=S_j+min_{k<=j}(B_k-S_{k-1}).
    % cummin evaluates that prefix minimum in compiled code, keeping the same
    % allowed DTW paths without a MATLAB loop for every alignment cell.
    cumulative = cumsum(costs);
    entry = min(D(i,jLow+1:jHigh+1),D(i,jLow:jHigh));
    D(i+1,jLow+1:jHigh+1) = cumulative + cummin(entry-[0 cumulative(1:end-1)]);
    cells = cells + jHigh-jLow+1;
end

info.CellsEvaluated = cells;
raw = D(end,end);
info.RawDistance = raw;

if opts.ReturnPath
    info.Accumulated = D(2:end, 2:end);
    info.Path = trace_back(D);
end

if opts.Normalise
    if isfield(opts,'PathLengthNorm') && opts.PathLengthNorm
        p = trace_back(D);
        pathLen = max(size(p, 2), 1);
        distance = raw / pathLen;
    else
        distance = raw / (n + m);
    end
else
    distance = raw;
end
end

% -------------------------------------------------------------------------
function path = trace_back(D)
%TRACE_BACK Recover the optimal alignment by re-choosing the same minima.
%   Walking backwards from the far corner and stepping to whichever predecessor
%   the forward recursion must have used reconstructs the path without storing a
%   pointer per cell.  Ties are broken towards the diagonal, which is the step
%   that advances both sequences and so is the one a reader expects to see when
%   the two recordings are the same length.
i = size(D,1) - 1;
j = size(D,2) - 1;
path = zeros(2, i + j);
k = 0;
while i >= 1 && j >= 1
    k = k + 1;
    path(:,k) = [i; j];
    if i == 1 && j == 1
        break;
    end
    candidates = [D(i,j), D(i,j+1), D(i+1,j)];   % diagonal, up, left
    [~, best] = min(candidates);
    switch best
        case 1, i = i - 1; j = j - 1;
        case 2, i = i - 1;
        case 3, j = j - 1;
    end
end
path = fliplr(path(:,1:k));
end
