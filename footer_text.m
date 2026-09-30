function text = footer_text(p)
%FOOTER_TEXT Every value formatted from PARAMS, so the footer cannot go stale.
%
%   TEXT = FOOTER_TEXT(P) builds the status bar text shown at the bottom of
%   the GUI figure, summarizing the active front-end, sample rate, DTW
%   decision threshold, runner-up margin, and all meal service windows.

if nargin < 1 || isempty(p)
    p = dsp_parameters();
end

windows = cell(1, numel(p.meals));
for k = 1:numel(p.meals)
    windows{k} = sprintf('%s %02d:%02d-%02d:%02d', p.meals(k).Name, ...
        p.meals(k).Start(1), p.meals(k).Start(2), ...
        p.meals(k).End(1), p.meals(k).End(2));
end

text = sprintf('%s at %g Hz | DTW threshold %.4f, margin %.2f | %s', ...
    upper(p.featureFrontEnd), p.processingFs, p.dtwThreshold, p.dtwMarginRatio, ...
    strjoin(windows, '  '));
end
