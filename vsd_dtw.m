function [dist, pathLen, info] = vsd_dtw(A, B, band)
%VSD_DTW Dynamic time warping distance, normalised by the warping-path length.
%
%   DIST = VSD_DTW(A, B) aligns two feature sequences A [n x d] and B [m x d]
%   (rows = frames) and returns the mean local Euclidean distance along the
%   optimal monotone path
%
%       D(i,j) = ||a_i - b_j|| + min{ D(i-1,j-1), D(i-1,j), D(i,j-1) }
%       DIST   = D(n,m) / K,     K = number of cells on the optimal path.
%
%   Dividing by the actual path length K (not by n+m) makes DIST the average
%   frame-to-frame mismatch of the aligned utterances, so long and short
%   phrases share one scale.  BAND (default 0.40) is the Sakoe-Chiba corridor
%   |i - j| <= BAND*max(n,m), widened to |n-m|+1 when needed.
%
%   Implementation: the recursion is evaluated one ANTI-DIAGONAL (i+j = s) at a
%   time.  Every cell of diagonal s depends only on diagonals s-1 and s-2, so a
%   whole diagonal is one vector operation -- O(n+m) interpreted steps instead
%   of O(n*m), which keeps MATLAB and GNU Octave fast without MEX files.
%   Ties prefer the diagonal step, then the vertical step (as in proto/feat.py).

if nargin < 3 || isempty(band), band = 0.40; end
n = size(A,1);  m = size(B,1);
info = struct('Band',NaN,'Cells',0);
if n == 0 || m == 0 || size(A,2) ~= size(B,2)
    dist = Inf; pathLen = 0; return;
end
bw = max([ceil(band * max(n,m)), abs(n-m) + 1, 1]);
info.Band = bw;
% local cost matrix (Euclidean)
C = sqrt(max(sum(A.^2,2) + sum(B.^2,2).' - 2 * (A * B.'), 0));
R = n + 1;
D = inf(R, m + 1);  Lp = zeros(R, m + 1);
D(1,1) = 0;
for s = 2:(n + m)
    iLo = max([1, s - m, ceil((s - bw)/2)]);
    iHi = min([n, s - 1, floor((s + bw)/2)]);
    if iLo > iHi, continue; end
    I = (iLo:iHi)';  J = s - I;
    kC  = (I + 1) + J * R;          % cell (i,j)      -> D(i+1, j+1)
    kD  = I + (J - 1) * R;          % (i-1, j-1)      -> D(i,   j)
    kU  = I + J * R;                % (i-1, j)        -> D(i,   j+1)
    kL  = (I + 1) + (J - 1) * R;    % (i, j-1)        -> D(i+1, j)
    x1 = D(kD);  x2 = D(kU);  x3 = D(kL);
    useD = (x1 <= x2) & (x1 <= x3);
    useU = ~useD & (x2 <= x3);
    best = x3;  lp = Lp(kL);
    best(useU) = x2(useU);  lp(useU) = Lp(kU(useU));
    best(useD) = x1(useD);  lp(useD) = Lp(kD(useD));
    D(kC) = C(I + (J - 1) * n) + best;
    Lp(kC) = lp + 1;
    info.Cells = info.Cells + numel(I);
end
pathLen = Lp(R, m + 1);
dist = D(R, m + 1) / max(pathLen, 1);
end
