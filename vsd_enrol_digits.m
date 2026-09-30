function [ok, files] = vsd_enrol_digits(sid, status, p, stopFcn)
%VSD_ENROL_DIGITS Record the ten isolated digits (zero..nine) of one student.
%
%   [OK, FILES] = VSD_ENROL_DIGITS(SID, STATUS, P) prompts the student to say
%   each digit once and writes DataRoot/Digits/<sid>/<sid>_<word>_NN.wav
%   (NN = next free take number, so older takes are kept; the newest is used).
%   The digits serve two purposes in v4.1.4_claude:
%     1. templates of the random-digit anti-replay challenge (VSD_CHALLENGE);
%     2. text-independent speech for the universal background model (UBM).
%   A student without digits can still be verified; the challenge then uses
%   the digits of the three closest voices ('cohort' mode), which is weaker.
%   STOPFCN (optional) returns true when the operator pressed Instant Stop.

if nargin < 3 || isempty(p), p = dsp_parameters(); end
if nargin < 4 || isempty(stopFcn), stopFcn = @() false; end
c = p.vsd;
words = {'zero','one','two','three','four','five','six','seven','eight','nine'};
folder = fullfile(c.DataRoot, 'Digits', sid);
if exist(folder,'dir') ~= 7, mkdir(folder); end
files = {};  ok = false;
for d = 1:10
    w = words{d};
    saved = false;
    for tryNo = 1:3
        if stopFcn(), update_status_text(status, 'Digit enrolment stopped.'); return; end
        [x, fs, dg] = vsd_record_phrase(sprintf('the digit "%s"', upper(w)), status, p, sprintf('Say %s', w));
        if strcmp(dg.Stage, 'user-stop'), update_status_text(status, 'Digit enrolment stopped.'); return; end
        if ~strcmp(dg.Stage, 'ok'), continue; end
        U = vsd_frontend(x, fs, c);
        if U.RawRms < c.MinRms || U.SpeechSec < 0.15
            update_status_text(status, sprintf('  "%s" too quiet/short (%.2f s) - again.', w, U.SpeechSec));
            continue;
        end
        n = next_take(folder, sid, w);
        f = fullfile(folder, sprintf('%s_%s_%02d.wav', sid, w, n));
        audiowrite(f, x(:) / max(1, max(abs(x))), fs, 'BitsPerSample', 16);
        files{end+1} = f; %#ok<AGROW>
        update_status_text(status, sprintf('  saved %s (%.2f s speech)', f, U.SpeechSec));
        saved = true;  break;
    end
    if ~saved
        update_status_text(status, sprintf('Could not record a usable "%s". Digit enrolment incomplete.', w));
        return;
    end
end
ok = true;
update_status_text(status, sprintf(['All ten digits of %s saved. The voice models update automatically ' ...
    'before the next verification.'], sid));
end

function n = next_take(folder, sid, w)
d = dir(fullfile(folder, sprintf('%s_%s_*.wav', sid, w)));
n = 1;
for k = 1:numel(d)
    t = regexp(d(k).name, '_(\d+)\.wav$', 'tokens', 'once');
    if ~isempty(t), n = max(n, str2double(t{1}) + 1); end
end
end
