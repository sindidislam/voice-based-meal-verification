function import_and_enroll_database()
%IMPORT_AND_ENROLL_DATABASE Import 33-student multi-sample database (17 samples/student) and train GMM-UBM.
fprintf('\n=======================================================\n');
fprintf('   IMPORTING 33-STUDENT DATABASE (ALL 17 SAMPLES/PERSON) \n');
fprintf('=======================================================\n');

currDir = fileparts(mfilename('fullpath'));
parentDir = fileparts(currDir);
g2DbDir = fullfile(parentDir, '312 PROJECT-another group', '312 PROJECT', 'Database');

if ~isfolder(g2DbDir)
    error('import_and_enroll_database:notFound', 'Cannot find Group 2 Database at: %s', g2DbDir);
end

p = dsp_parameters();
% Populate both the local Train folder and the active calibrated deployment root
targetRoots = unique({fullfile(currDir, 'Train'), p.trainBaseFolder});

for b = 1:numel(targetRoots)
    bDir = targetRoots{b};
    if ~isfolder(fullfile(bDir, 'ID')), mkdir(fullfile(bDir, 'ID')); end
    if ~isfolder(fullfile(bDir, 'Name')), mkdir(fullfile(bDir, 'Name')); end
    if ~isfolder(fullfile(bDir, 'Coupon')), mkdir(fullfile(bDir, 'Coupon')); end
    if ~isfolder(fullfile(bDir, 'Digits')), mkdir(fullfile(bDir, 'Digits')); end
    if ~isfolder(fullfile(bDir, 'AllSamples')), mkdir(fullfile(bDir, 'AllSamples')); end
end

% Look for 3-digit student directories: 131 to 164
subdirs = dir(g2DbDir);
subdirs = subdirs([subdirs.isdir] & ~startsWith({subdirs.name}, '.'));

count = 0;
totalFilesCopied = 0;

for s = 1:numel(subdirs)
    sName = subdirs(s).name;
    % Match 3-digit directory names like '131' or 7-digit '2206131'
    if ~isempty(regexp(sName, '^\d{3}$', 'once'))
        roll = ['2206' sName];
    elseif ~isempty(regexp(sName, '^2206\d{3}$', 'once'))
        roll = sName;
    else
        continue;
    end
    
    srcStudentDir = fullfile(g2DbDir, sName);
    allWavs = dir(fullfile(srcStudentDir, '*.wav'));
    studentWavCount = numel(allWavs);
    rollWavs = dir(fullfile(srcStudentDir, '*roll*.wav'));
    nameWavs = dir(fullfile(srcStudentDir, '*name*.wav'));
    
    for b = 1:numel(targetRoots)
        bDir = targetRoots{b};
        dstIdDir = fullfile(bDir, 'ID', roll);
        dstNameDir = fullfile(bDir, 'Name', roll);
        dstCouponDir = fullfile(bDir, 'Coupon', roll);
        dstDigitsDir = fullfile(bDir, 'Digits', roll);
        dstAllDir = fullfile(bDir, 'AllSamples', roll);
        
        if ~isfolder(dstIdDir), mkdir(dstIdDir); end
        if ~isfolder(dstNameDir), mkdir(dstNameDir); end
        if ~isfolder(dstCouponDir), mkdir(dstCouponDir); end
        if ~isfolder(dstDigitsDir), mkdir(dstDigitsDir); end
        if ~isfolder(dstAllDir), mkdir(dstAllDir); end
        
        % 1. Copy ALL available WAV files (all 17 samples) into AllSamples
        for w = 1:studentWavCount
            copyfile(fullfile(srcStudentDir, allWavs(w).name), fullfile(dstAllDir, allWavs(w).name));
        end
        
        % 2. Copy roll takes -> ID/roll/1.wav, 2.wav, 3.wav
        for r = 1:numel(rollWavs)
            copyfile(fullfile(srcStudentDir, rollWavs(r).name), fullfile(dstIdDir, sprintf('%d.wav', r)));
        end
        
        % 3. Copy name takes -> Name/roll/1.wav, 2.wav, 3.wav and Coupon
        for n = 1:numel(nameWavs)
            copyfile(fullfile(srcStudentDir, nameWavs(n).name), fullfile(dstNameDir, sprintf('%d.wav', n)));
            copyfile(fullfile(srcStudentDir, nameWavs(n).name), fullfile(dstCouponDir, sprintf('%d.wav', n)));
        end
        
        % 4. Copy digit files (0-9 and full digits sequence) -> Digits/roll/
        for w = 1:studentWavCount
            fName = lower(allWavs(w).name);
            if contains(fName, 'zero') || contains(fName, 'one') || contains(fName, 'two') || ...
               contains(fName, 'three') || contains(fName, 'four') || contains(fName, 'five') || ...
               contains(fName, 'six') || contains(fName, 'seven') || contains(fName, 'eight') || ...
               contains(fName, 'nine') || contains(fName, 'digits')
                copyfile(fullfile(srcStudentDir, allWavs(w).name), fullfile(dstDigitsDir, allWavs(w).name));
            end
        end
        
        % Save profile.mat
        profileMat = fullfile(dstIdDir, 'profile.mat');
        if ~isfile(profileMat)
            profile = struct('Id', roll, 'Name', roll, 'Active', true); %#ok<NASGU>
            save(profileMat, 'profile');
        end
    end
    
    totalFilesCopied = totalFilesCopied + studentWavCount;
    count = count + 1;
    fprintf('  Enrolled student %s (%d total samples: %d ID, %d Name, %d Digits)\n', ...
        roll, studentWavCount, numel(rollWavs), numel(nameWavs), studentWavCount - numel(rollWavs) - numel(nameWavs));
end

% Preserve existing profiles that may not be in Group 2 DB (e.g. 2206148, 2206149)
for b = 1:numel(targetRoots)
    bDir = targetRoots{b};
    tId = fullfile(bDir, 'ID');
    tName = fullfile(bDir, 'Name');
    tAll = fullfile(bDir, 'AllSamples');
    existingIdDirs = dir(tId);
    existingIdDirs = existingIdDirs([existingIdDirs.isdir] & ~startsWith({existingIdDirs.name}, '.'));
    for e = 1:numel(existingIdDirs)
        eRoll = existingIdDirs(e).name;
        eAllDir = fullfile(tAll, eRoll);
        if ~isfolder(eAllDir), mkdir(eAllDir); end
        eWavs = dir(fullfile(tId, eRoll, '*.wav'));
        for ew = 1:numel(eWavs)
            srcF = fullfile(tId, eRoll, eWavs(ew).name);
            dstF = fullfile(eAllDir, ['id_' eWavs(ew).name]);
            if ~isfile(dstF), copyfile(srcF, dstF); end
        end
        if isfolder(fullfile(tName, eRoll))
            eNameWavs = dir(fullfile(tName, eRoll, '*.wav'));
            for ew = 1:numel(eNameWavs)
                srcF = fullfile(tName, eRoll, eNameWavs(ew).name);
                dstF = fullfile(eAllDir, ['name_' eNameWavs(ew).name]);
                if ~isfile(dstF), copyfile(srcF, dstF); end
            end
        end
    end
end

fprintf('\nSuccessfully imported %d students and %d audio files into Train and VSD_Enrollment/Train.\n', count, totalFilesCopied);

% Now train the Universal Background Model (GMM-UBM) across ALL voice samples
fprintf('Training GMM-UBM voice models for all enrolled students using ALL voice samples...\n');
train_voice_gmm(p);
fprintf('Voice GMM-UBM training complete!\n');
end
