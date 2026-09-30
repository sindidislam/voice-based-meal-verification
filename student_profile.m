function profile = student_profile(params, studentId, studentName, couponCode)
%STUDENT_PROFILE Read or write the canonical metadata for one Student ID.
%
%   PROFILE = STUDENT_PROFILE(PARAMS, STUDENTID) reads the stored metadata for
%   STUDENTID and returns a struct with fields Id, Name, and CouponCode. When no
%   metadata file exists yet the Name and CouponCode fields are empty, so a
%   caller can still learn the ID exists from its folders.
%
%   PROFILE = STUDENT_PROFILE(PARAMS, STUDENTID, STUDENTNAME) and
%   PROFILE = STUDENT_PROFILE(PARAMS, STUDENTID, STUDENTNAME, COUPONCODE) write
%   the metadata file under Train/ID/<id>/profile.mat and return what was saved.
%   The display name is stored as free text; it is metadata only and is never
%   used as a lookup key. Passing COUPONCODE stores a six-digit code alongside
%   the name so the ID folder is self-describing; the authoritative coupon file
%   is still written by the enrolment code path.
%
%   The ID is always validated through STUDENT_ID_CONTRACT first, so a bad ID
%   can never create or read a stray metadata file.
%
%   See also STUDENT_ID_CONTRACT, STUDENT_PROFILE_PATHS, LIST_ID_PROFILES.

if nargin < 1 || isempty(params)
    params = dsp_parameters();
end

[id, ok, message] = student_id_contract(studentId);
if ~ok
    error('student_profile:invalidId', '%s', message);
end

paths = student_profile_paths(params, id);

writing = nargin >= 3;
if writing
    name = strtrim(char(string(studentName)));
    if nargin >= 4 && ~isempty(couponCode)
        code = strtrim(char(string(couponCode)));
    else
        code = read_existing_code(paths.Metadata);
    end
    profile = struct('Id', id, 'Name', name, 'CouponCode', code);
    if ~isfolder(paths.Id)
        mkdir(paths.Id);
    end
    save(paths.Metadata, '-struct', 'profile');
    return;
end

% Reading.
profile = struct('Id', id, 'Name', '', 'CouponCode', '');
if isfile(paths.Metadata)
    stored = load(paths.Metadata);
    if isfield(stored, 'Name'), profile.Name = char(string(stored.Name)); end
    if isfield(stored, 'CouponCode'), profile.CouponCode = char(string(stored.CouponCode)); end
end
end

function code = read_existing_code(metadataPath)
code = '';
if isfile(metadataPath)
    stored = load(metadataPath);
    if isfield(stored, 'CouponCode')
        code = char(string(stored.CouponCode));
    end
end
end
