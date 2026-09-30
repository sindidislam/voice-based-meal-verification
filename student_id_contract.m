function [id, ok, message] = student_id_contract(value)
%STUDENT_ID_CONTRACT Normalise and validate a seven-digit Student ID.
%
%   [ID, OK, MESSAGE] = STUDENT_ID_CONTRACT(VALUE) trims surrounding whitespace
%   from VALUE and accepts it only when it is exactly seven ASCII numeric
%   digits, for example '2206147'. ID is the normalised character vector when
%   OK is true, and '' otherwise. MESSAGE explains any rejection so the caller
%   can show it to an operator.
%
%   The Student ID is the canonical identity for the whole meal system: it names
%   the voice-profile folders, the coupon and fee records, and every log row.
%   Because a wrong ID silently attaches one student's meals to another, the
%   rule is deliberately strict -- no partial IDs, no letters, no separators.
%
%   See also STUDENT_PROFILE_PATHS, STUDENT_PROFILE, LIST_ID_PROFILES.

id = '';
ok = false;

if nargin < 1
    message = 'No Student ID was supplied.';
    return;
end

raw = strtrim(char(string(value)));
if isempty(raw)
    message = 'The Student ID is empty.';
    return;
end

if numel(raw) ~= 7
    message = sprintf('The Student ID must be exactly seven digits (got %d characters).', numel(raw));
    return;
end

if ~all(isstrprop(raw, 'digit'))
    message = 'The Student ID must contain only the digits 0-9.';
    return;
end

id = raw;
ok = true;
message = '';
end
