function verify_dsp_pipeline()
%VERIFY_DSP_PIPELINE Regression checks for the meal-verification DSP pipeline.
%
%   VERIFY_DSP_PIPELINE() runs every check and reports pass or fail per group.  It
%   throws on the first failure, so a clean run means every assertion below held.
%
%   EEE 312 CO1 (implement DSP algorithms), CO2 (theoretical against experimental).
%   PO(a) Engineering knowledge, PO(e) Modern tool usage.
%
%   What this file is for
%   ---------------------
%   Each check states a property that follows from the theory, then measures whether
%   the code has it.  That is the CO2 pairing in its smallest form: a resampler with
%   a Kaiser anti-alias filter must attenuate any component above the new Nyquist
%   frequency, so a tone placed there must come out small.  If it does not, either
%   the filter is wrong or the claim is.
%
%   Configuration values are read from PARAMS rather than written here as literals,
%   except where the literal IS the property under test.  The previous revision of
%   this file could not run: it asserted an output rate of 16000 Hz with L/M =
%   160/441, from before the 8 kHz decision, and it called
%   CHECK_LOW_FREQUENCY_QUALITY, which CHECK_LIVENESS_LOWFREQ replaced.  A regression
%   suite that fails for reasons unrelated to any regression trains everyone to
%   ignore it.
%
%   The properties tested are chosen to be ones a plausible-looking bug would break.
%   Asserting that a distance is a number catches nothing; asserting that a
%   time-warped copy of an utterance scores closer than different content is the
%   reason DTW is in the system at all, and would fail if the warping band were
%   mis-scaled.
%
%   Why the test signals are synthesised voices and not tones
%   -------------------------------------------------------
%   An earlier revision of this file probed the chain with pure tone bursts, and three
%   of the checks then measured nothing.  A 700 Hz burst has no energy below 200 Hz, so
%   modification 2 rejected it as loudspeaker playback -- correctly.  A
%   constant-amplitude tone never exceeds four times its own mean energy, so
%   modification 4 found no speech in it -- correctly.  And a stationary tone has the
%   same spectrum in every frame, so the DFT front-end's per-utterance normalisation
%   drove its whole feature matrix to zero; the DTW assertions then compared two
%   all-zero matrices and passed on floating-point noise, which is worse than failing.
%   SYNTH_VOICED_SIGNAL exists to supply a signal the gates were designed to accept:
%   a harmonic stack on a swept fundamental, shaped by formants, with a syllabic
%   envelope.  Measured values for the signals used below are quoted where they matter.
%
%   See also DSP_PARAMETERS, SYNTH_VOICED_SIGNAL, PREPROCESS_TEMPLATE_AUDIO,
%   VERIFY_MEAL_WORKFLOW, EXPERIMENT_VERIFICATION_ACCURACY, DIAGNOSE_AUDIO_CORPUS.

rng(1);   % The noise below is pseudo-random; no threshold here may depend on luck.
p = dsp_parameters(false); % Known-answer diagnostic covers both reference frontends.
fprintf('\n=== DSP pipeline regression =====================================\n');

check_resampling(p);
check_agc(p);
check_spectral_subtraction(p);
check_endpoint_detection(p);
check_liveness(p);
check_features_and_dtw(p);
check_template_modes(p);
check_invalid_input(p);
check_quality_assessment(p);
check_corpus_agreement(p);
check_threshold_configuration(p);
% Exercise schedule semantics against explicit test hours. Administrators may
% extend the persisted Lunch window through 16:00; that is not a DSP failure.
p.meals=struct('Name',{'Breakfast','Lunch','Dinner'}, ...
    'Start',{[7 0],[12 0],[19 0]},'End',{[9 0],[14 0],[21 0]});
check_meal_windows(p);
check_meal_logging(p);
% The earlier private check below described obsolete spoken-name/coupon
% discovery. These regressions exercise the current claimed-ID + ID/name path.
r=runtests('test_speaker_verification');
assertSuccess(r);
assert(test_monthly_roster_backend(),'Current monthly roster workflow failed.');
assert(test_coupon_retirement(),'Retired coupon entry points must refuse access.');

fprintf('\nAll checks passed.\n');
fprintf('================================================================\n\n');
end

% =========================================================================
function check_resampling(p)
%CHECK_RESAMPLING Modification 1a: polyphase rational resampling to PROCESSINGFS.
%
%   The property: a component above the output Nyquist frequency must be attenuated
%   before decimation, or it folds back into the band as an alias that is
%   indistinguishable from real speech.  This is the Experiment 1 sampling theorem
%   used as an acceptance test rather than as a statement.
%
%   The probe tone is at 5500 Hz.  With PROCESSINGFS = 8000 the output Nyquist is
%   4000 Hz, and an unfiltered 5500 Hz component would fold to 8000 - 5500 = 2500 Hz.
%   That folded frequency is deliberately far from the 1000 Hz reference tone, so the
%   two cannot be confused.  A 12000 Hz probe would have been the more obvious choice
%   and is the wrong one: it folds to exactly 4000 Hz, landing on the folding
%   frequency itself where the filter response is by definition ambiguous.
fs = p.fs;
t = (0:fs-1)' / fs;
x = sin(2*pi*1000*t) + sin(2*pi*5500*t);

[y, fo, ri] = rational_resample_audio(x, fs, p.processingFs, p.resample);

assert(abs(fo - p.processingFs) < 1e-9, ...
    'resampler returned %g Hz, expected %g Hz', fo, p.processingFs);
[expL, expM] = rat(p.processingFs / fs, 1e-12);
g = gcd(expL, expM);
assert(ri.L == expL/g && ri.M == expM/g, ...
    'L/M = %d/%d, expected %d/%d from rat(%g/%g)', ri.L, ri.M, expL/g, expM/g, ...
    p.processingFs, fs);
% P and Q are retained as aliases for L and M. If they ever disagree, a caller
% reading the old names is silently working with a different ratio.
assert(ri.P == ri.L && ri.Q == ri.M, 'the P/Q aliases disagree with L/M');

Y = abs(fft(y));
f = (0:numel(Y)-1)' * fo / numel(Y);
kept  = max(Y(abs(f - 1000) < 20));
alias = max(Y(abs(f - (fo - 5500)) < 20));
assert(alias < kept * 0.01, ...
    'alias at %g Hz is %.2f %% of the 1000 Hz tone; the anti-alias filter is too weak', ...
    fo - 5500, 100*alias/kept);

pass('resampling  %g -> %g Hz, L/M = %d/%d, %d taps, alias %.3g %% of signal', ...
    fs, fo, ri.L, ri.M, ri.FilterLength, 100*alias/kept);
end

% -------------------------------------------------------------------------
function check_agc(p)
%CHECK_AGC Modification 1b: RMS normalisation, and the guard that stops it
%   amplifying silence.
%
%   Two properties.  Loud and quiet versions of the same signal must come out at the
%   same level, which is the entire purpose: it removes the distance-from-microphone
%   difference that would otherwise appear to the matcher as a speaker difference.
%   And a signal below MinRms must be left alone, because scaling near-silence to the
%   target level amplifies nothing but the noise floor, and the endpoint detector then
%   has to decide whether amplified hiss is speech.
fo = p.processingFs;
base = 0.2 * sin(2*pi*600*(0:fo-1)'/fo);

[loud,  loudInfo]  = agc_normalize(base * 4,    p.agc);
[quiet, quietInfo] = agc_normalize(base * 0.05, p.agc);
assert(~loudInfo.Silent && ~quietInfo.Silent, 'AGC treated a clear tone as silence');
assert(abs(rms_of(loud) - rms_of(quiet)) < 1e-9 + 1e-6*rms_of(loud), ...
    'AGC left a level difference: loud RMS %.6f vs quiet RMS %.6f', ...
    rms_of(loud), rms_of(quiet));
assert(abs(rms_of(loud) - p.agc.TargetRms) < 1e-6, ...
    'AGC output RMS %.6f, target %.6f', rms_of(loud), p.agc.TargetRms);

nearSilence = 1e-7 * randn(fo, 1);
[guarded, guardInfo] = agc_normalize(nearSilence, p.agc);
assert(guardInfo.Silent, 'AGC did not recognise a signal below MinRms as silence');
assert(rms_of(guarded) <= rms_of(nearSilence) * (1 + 1e-6), ...
    'AGC amplified a signal below MinRms (gain %.3g)', guardInfo.Gain);

pass('AGC         80:1 level ratio -> equal RMS %.4f, refuses to amplify below %.0e', ...
    p.agc.TargetRms, p.agc.MinRms);
end

% -------------------------------------------------------------------------
function check_spectral_subtraction(p)
%CHECK_SPECTRAL_SUBTRACTION Modification 3: the noise estimate comes from the
%   pre-roll, and subtracting it must move the signal towards the clean version.
%
%   The property is stated as a comparison rather than as an absolute error, because
%   spectral subtraction leaves residual musical noise and never recovers the clean
%   signal exactly.  What it must do is reduce the error.  Claiming more than that
%   would be a claim the method cannot support.
%
%   The error is measured only where speech actually is.  Inside the pre-roll the
%   "error" against the clean signal is the noise itself, and any noise reduction
%   there would flatter the result without saying anything about speech.
%
%   The clean signal is a synthesised voice rather than a sinusoid, because "the error
%   fell" is a much weaker claim about a single sinusoid than it looks.  A narrowband
%   signal occupies one or two of the 24 analysis bins, so subtracting a noise floor
%   from the other twenty-two removes noise and cannot touch the signal -- a plain
%   notch would score well on that test.  A voiced utterance has energy spread across
%   the band the subtraction operates on, so the measurement is of the thing actually
%   deployed.
fo = p.processingFs;
preRoll = round(p.noise.NoiseDuration * fo);
clean = [zeros(preRoll,1); synth_voiced_signal(fo, 1.0, [], [], 0.20)];
noisy = clean + 0.03 * randn(size(clean));

cleaned = spectral_subtract_noise(noisy, fo, p.noise);

active = (preRoll + round(0.1*fo)) : numel(clean);
before = rms_of(noisy(active) - clean(active));
after  = rms_of(cleaned(active) - clean(active));
assert(after < before, ...
    'spectral subtraction increased the error: %.5f -> %.5f', before, after);

pass('noise       subtraction cuts error %.5f -> %.5f (%.0f %% reduction)', ...
    before, after, 100*(1 - after/before));
end

% -------------------------------------------------------------------------
function check_endpoint_detection(p)
%CHECK_ENDPOINT_DETECTION Modification 4: hybrid short-time energy AND zero-crossing
%   endpointing.
%
%   Two properties, and the second is the whole reason the detector is hybrid.  A
%   voiced burst must be found.  A single-sample impulse must NOT be: its energy is
%   far above the noise floor, so an energy-only detector marks it as speech, but its
%   zero-crossing rate is nothing like voiced speech and it lasts one sample.
%   Requiring energy and a zero-crossing band to agree is what rejects it, and a
%   dropped steel tray in a dining hall is exactly that signal.
%
%   The burst is a synthesised voice, which matters twice over.  Its amplitude varies,
%   so frames inside it exceed four times the noise floor while a constant-level tone
%   would not.  And its zero-crossing rate, measured at 0.245, sits inside the
%   [0.008, 0.450] band the detector requires -- so if the burst were missed it would
%   be the detector at fault and not the probe.
fo = p.processingFs;
z = with_utterance(fo, 2.00, 0.80, 0.50, 0.002, 0.15);

[~, ep] = hybrid_endpoint_detect(z, fo, p.endpoint);
assert(ep.HasSpeech, 'endpoint detector missed a 0.5 s voiced burst');
assert(ep.StartSample > 0.5*fo, ...
    'speech start %.2f s is too early for a burst beginning at 0.80 s', ep.StartSample/fo);
assert(ep.EndSample < 1.6*fo, ...
    'speech end %.2f s is too late for a burst ending at 1.30 s', ep.EndSample/fo);
% Neither zero-crossing edge may be what found the burst's boundaries: if the voiced
% frames were being trimmed by the ZCR test, the detector would be endpointing on the
% wrong evidence and would behave differently on a real voice.
assert(ep.RejectedLowZcr == 0 && ep.RejectedHighZcr == 0, ...
    'the ZCR band discarded %d loud voiced frames, so the band is mis-set', ...
    ep.RejectedLowZcr + ep.RejectedHighZcr);

impulse = 0.002 * randn(2*fo, 1);
impulse(round(0.35*fo)) = 1;
[~, epImpulse] = hybrid_endpoint_detect(impulse, fo, p.endpoint);
found = 0;
if epImpulse.HasSpeech
    found = (epImpulse.EndSample - epImpulse.StartSample + 1) / fo;
end
assert(~epImpulse.HasSpeech || found < p.liveness.MinDuration, ...
    'a single-sample impulse was reported as %.3f s of speech', found);

pass('endpoint    burst found at %.2f-%.2f s, single-sample impulse rejected', ...
    ep.StartSample/fo, ep.EndSample/fo);
end

% -------------------------------------------------------------------------
function check_liveness(p)
%CHECK_LIVENESS Modification 2: sub-200 Hz band-energy ratio.
%
%   The physical claim: a phone loudspeaker is a driver a few millimetres across and
%   cannot displace enough air to radiate much energy below about 300 Hz, whereas a
%   human chest and vocal tract can.  So the discriminating test is a LOWER bound on
%   the ratio of sub-200 Hz energy to total speech-band energy, and a signal with
%   strong low-frequency content must score HIGHER than one without.
%
%   This checks the ordering, which is the physics.  It deliberately does NOT check
%   the two numeric bounds, and the reason is worth stating: PARAMS.liveness is
%   currently fitted to genuine speech alone, so it has a measured false-reject rate
%   and an entirely unmeasured detection rate.  Asserting those bounds here would
%   dress an uncalibrated gate up as a tested one.  They become testable once
%   RECORD_CORPUS_TOOL(...,'Mode','replay') has collected the attack half of the data
%   and CALIBRATE_LIVENESS_BAND has been re-run against it.
fo = p.processingFs;
t = (0:fo-1)' / fo;
opts = p.liveness;

[~, ratioLow] = check_liveness_lowfreq(0.2*sin(2*pi*100*t),  fo, opts);
[~, ratioMid] = check_liveness_lowfreq(0.2*sin(2*pi*1000*t), fo, opts);
assert(ratioLow > ratioMid, ...
    'a 100 Hz tone scored %.5f, below the 1000 Hz tone at %.5f', ratioLow, ratioMid);

% A tone inside the low band should sit near the top of the range and one outside it
% near the bottom, so the statistic spans most of [0,1] and has room to separate.
assert(ratioLow > 0.5, '100 Hz tone scored only %.5f in the sub-200 Hz band', ratioLow);
assert(ratioMid < 0.01, '1000 Hz tone scored %.5f in the sub-200 Hz band', ratioMid);

% Too short to judge: one glottal cycle at 120 Hz is 8 ms, so a 50 ms window spans
% six cycles and the estimate has more variance than the effect it measures. The gate
% must refuse rather than guess, and must return no ratio at all.
shortBurst = 0.2*sin(2*pi*300*(0:round(0.05*fo)-1)'/fo);
[rejectShort, ~, shortInfo] = check_liveness_lowfreq(shortBurst, fo, opts);
assert(rejectShort && isnan(shortInfo.Ratio), ...
    'a %.0f ms fragment was given a liveness verdict', 1000*shortInfo.Duration);

% A signal built from the source-filter model of voiced speech must be ACCEPTED. This
% is the one direction the gate can be held to without replay data: whatever its
% detection rate turns out to be, a gate that refuses a harmonic stack on a glottal
% fundamental is refusing the physics it was derived from. Two vowels are checked
% because the first formant sets how much of the series falls below 200 Hz, and that
% is what the ratio measures -- 0.059 for a low-F1 vowel, 0.562 for a high one, so the
% accepted band has to be wide enough to hold both. It is the widest span the deployed
% bounds are asked to cover here.
for vowel = {{'low F1', [110 150], [700 1200 2600]}, {'high F1', [150 190], [300 2300 3000]}}
    voiced = synth_voiced_signal(fo, 0.60, vowel{1}{2}, vowel{1}{3}, 0.35);
    [rejectVoiced, ratioVoiced] = check_liveness_lowfreq(voiced, fo, opts);
    assert(~rejectVoiced, ...
        'a synthesised voice (%s, ratio %.5f) was refused by the liveness gate', ...
        vowel{1}{1}, ratioVoiced);
end

pass('liveness    100 Hz ratio %.4f > 1000 Hz ratio %.5f, 50 ms fragment refused', ...
    ratioLow, ratioMid);
end

% -------------------------------------------------------------------------
function check_features_and_dtw(p)
%CHECK_FEATURES_AND_DTW Both front-ends produce usable sequences, and the DTW
%   distance behaves like a distance.
%
%   Properties: a sequence matched against itself gives zero; the distance is
%   symmetric; and a time-warped copy of an utterance costs less than a different
%   utterance.  That last one is the entire reason DTW replaced the senior baseline's
%   cross-correlation match, and it is the property a mis-scaled Sakoe-Chiba band
%   would break while leaving the first two intact.
%
%   Both front-ends are tested because both are selectable.  PARAMS.featureFrontEnd
%   chooses which one deploys; neither is allowed to rot, because the DFT front-end
%   is the proposal's own and the comparison against it is a reportable result.
%
%   The two utterances differ in BOTH fundamental frequency and formant pattern, and
%   both differences are needed -- one per front-end.  Measured while choosing them:
%   two vowels at the same f0 separate cleanly under MFCC (1.32 against 43.5) and
%   almost not at all under the DFT front-end (0.208 against 0.270), because that
%   front-end normalises each band to zero mean over the utterance and the per-band
%   mean of a sustained vowel IS its formant pattern.  Changing f0 as well restores the
%   DFT separation to 0.208 against 0.868.  This is the same degeneracy that made a
%   stationary tone useless here, one step milder, and it is worth knowing about: it
%   says the DFT front-end with per-utterance normalisation is weaker at telling
%   sustained sounds apart than the mel cepstrum is, which is consistent with the
%   front-end comparison the report carries.
fo = p.processingFs;
a = synth_voiced_signal(fo, 0.60, [110 150], [700 1200 2600], 0.35);
b = synth_voiced_signal(fo, 0.60, [150 190], [300 2300 3000], 0.35);

for frontEnd = {'mfcc','dft'}
    q = select_feature_frontend(p, frontEnd{1});

    fa = extract_features(a, fo, q);
    fb = extract_features(b, fo, q);
    assert(~isempty(fa) && all(isfinite(fa(:))), ...
        '%s front-end produced empty or non-finite features', q.featureFrontEnd);
    assert(size(fa,2) > 1, '%s front-end produced only one frame', q.featureFrontEnd);
    % A degenerate feature matrix is how the distance assertions below get to pass
    % without measuring anything: two all-zero matrices are zero apart, and
    % 0 < 0 + floating-point noise is satisfiable. The DFT front-end reaches that state
    % on any stationary input, because it subtracts each band's mean over the
    % utterance. Measured on the signals above: 590 for MFCC, 30 for the DFT bands.
    assert(norm(fa(:)) > 1, ...
        ['%s: the whole feature matrix collapsed to %.3g, so every distance below ' ...
         'would be zero and would prove nothing'], q.featureFrontEnd, norm(fa(:)));

    dSelf  = dtw_distance_dsp(fa, fa, q.dtw);
    dCross = dtw_distance_dsp(fa, fb, q.dtw);
    dBack  = dtw_distance_dsp(fb, fa, q.dtw);

    assert(dSelf < 1e-9, '%s: self-distance %.6g is not zero', q.featureFrontEnd, dSelf);
    assert(abs(dCross - dBack) < 1e-9 * max(1,dCross), ...
        '%s: distance is asymmetric, %.6f vs %.6f', q.featureFrontEnd, dCross, dBack);
    assert(dCross > dSelf, ...
        '%s: a different signal was no farther than the signal itself', q.featureFrontEnd);

    % The same content spoken 25 % more slowly, made by stretching the feature
    % sequence. DTW must find this much closer than different content -- and the
    % factor of two is deliberate. "Merely closer" is satisfiable by two distances
    % that are both numerically zero, which is precisely the failure this check used
    % to have. Measured margins are 35x for MFCC and 4.2x for the DFT bands, so
    % demanding 2x tests the property without encoding either measurement as a limit.
    slow = interp1(1:size(fa,2), fa', linspace(1, size(fa,2), round(1.25*size(fa,2))))';
    dWarp = dtw_distance_dsp(fa, slow, q.dtw);
    assert(dWarp < dCross / 2, ...
        ['%s: a time-warped copy scored %.4f against %.4f for different content, ' ...
         'less than a factor of two apart -- the warping band is not doing its job'], ...
        q.featureFrontEnd, dWarp, dCross);

    pass('%-11s %2d coeffs x %d frames, self 0, warped %.4f < different %.4f', ...
        q.featureFrontEnd, size(fa,1), size(fa,2), dWarp, dCross);
end
end

% -------------------------------------------------------------------------
function check_template_modes(p)
%CHECK_TEMPLATE_MODES Stored audio takes one of two paths, and taking the wrong one
%   silently damages the template.
%
%   A recording that begins with speech has no noise to profile.  Subtracting a
%   profile measured over speech removes part of the talker from every frame, so
%   PREPROCESS_TEMPLATE_AUDIO detects the missing pre-roll and skips subtraction
%   instead.  That is what 'LegacyCropped' means, and 51 of the 61 name recordings in
%   the corpus go down it -- so this is not a corner case, it is the majority path.
%
%   The two test signals are synthesised voices with an amplitude envelope, not
%   constant-level tones.  A constant-level tone is pathological here: the endpoint
%   detector learns its noise statistics from the first 0.5 s, and nothing in a signal
%   of uniform energy can exceed four times its own mean, so the detector would
%   correctly report no speech and the test would fail for a reason having nothing to
%   do with template modes.  The live-capture path also enforces the liveness gate,
%   which a tone fails for want of a glottal fundamental.
fo = p.processingFs;

% 0.70 s: shorter than 1.5 x the pre-roll length, so the duration test alone sends
% this down the legacy path regardless of how quiet its lead-in is.
cropped = with_utterance(fo, 0.70, 0.50, 0.20, 0.002, 0.15);

[cropOut, cropFs, cropDiag] = preprocess_template_audio(cropped, fo, p);
assert(strcmp(cropDiag.TemplateMode, 'LegacyCropped'), ...
    'a 0.70 s recording took the %s path', cropDiag.TemplateMode);
assert(~cropDiag.Rejected && cropDiag.Endpoint.HasSpeech, ...
    'legacy cropped template was rejected: %s', cropDiag.Reason);
assert(cropFs == fo && ~isempty(cropOut), 'legacy cropped template produced no audio');

% 1.30 s with a genuinely quiet first 0.5 s: long enough and quiet enough for the
% live-capture path, which is the one that applies spectral subtraction AND the one
% that enforces liveness. Asserting it is not rejected is what ties this check to
% modification 2: the previous revision omitted that assertion and so kept passing
% with a signal the gate was throwing away.
withPreRoll = with_utterance(fo, 1.30, 0.50, 0.80, 0.002, 0.15);

[~, ~, rawDiag] = preprocess_template_audio(withPreRoll, fo, p);
assert(strcmp(rawDiag.TemplateMode, 'RawWithQuietLeadIn'), ...
    'a recording with a silent pre-roll took the %s path', rawDiag.TemplateMode);
assert(~rawDiag.Rejected && rawDiag.Endpoint.HasSpeech, ...
    'the live-capture template path rejected a synthesised voice: %s', rawDiag.Reason);
assert(rawDiag.QuietLeadInRatio < p.templateQuietLeadInRatio, ...
    'lead-in ratio %.3f is not below the %.3f limit that selected this path', ...
    rawDiag.QuietLeadInRatio, p.templateQuietLeadInRatio);

pass('template    0.70 s -> LegacyCropped, 1.30 s with pre-roll -> RawWithQuietLeadIn');
end

% -------------------------------------------------------------------------
function check_invalid_input(p)
%CHECK_INVALID_INPUT Bad audio is refused as data, not raised as an exception.
%
%   A microphone that returns nothing is an ordinary event at a serving counter, not
%   a program error.  The chain must report it in the diagnostics so the caller can
%   tell the student to try again, rather than throwing and taking the counter
%   application down mid-transaction.
[y, fsOut, d] = preprocess_audio([], p.processingFs, p);
assert(isempty(y), 'empty input produced %d samples', numel(y));
assert(fsOut == p.processingFs, 'empty input returned rate %g', fsOut);
assert(d.Rejected, 'empty input was not marked as rejected');
assert(~isempty(d.Reason), 'empty input was rejected without a reason');

[~, ~, dTemplate] = preprocess_template_audio([], p.processingFs, p);
assert(dTemplate.Rejected && ~isempty(dTemplate.Reason), ...
    'an empty template was not rejected with a reason');

pass('bad input   empty capture and empty template -> Rejected with a reason');
end

% -------------------------------------------------------------------------
function check_quality_assessment(p)
%CHECK_QUALITY_ASSESSMENT ASSESS_RECORDING_QUALITY must agree with the enrolment test
%   the experiments use, and must grade rather than simply refuse.
%
%   USABLE means "the chain produced features", which is exactly what
%   EXPERIMENT_VERIFICATION_ACCURACY checks before enrolling a file.  An earlier
%   revision made clipping fatal instead, and the corpus audit then reported that a
%   student had no usable name recording while the accuracy experiment was busy
%   verifying him from it.  An audit that contradicts the system it audits is worse
%   than no audit, so the two definitions are pinned together here and file by file
%   in DIAGNOSE_AUDIO_CORPUS.
%
%   The Strict switch is the other half.  A fresh capture, with the student still at
%   the microphone, is held to the higher standard because a defect costs one retake.
%   A file already on disk is held to the lower one because the alternative is
%   discarding data that cannot be recreated.
fo = p.processingFs;
withPreRoll = with_utterance(fo, 1.30, 0.50, 0.80, 0.002, 0.15);
cropped = withPreRoll(round(0.50*fo)+1 : end);

good = assess_recording_quality(withPreRoll, fo, p);
assert(good.Usable, 'a clean synthetic capture was refused: %s', good.Reason);
assert(good.WellRecorded, ...
    'a clean synthetic capture was flagged with a problem: %s', good.Reason);

% Clipping: degraded but still usable, and named as a problem in both modes.
loud = max(min(withPreRoll*20, 1), -1);
lax = assess_recording_quality(loud, fo, p, struct('Strict', false));
assert(lax.Clipped, 'a hard-limited signal was not detected as clipped');
assert(lax.Usable, 'the audit refused a clipped file the system would enrol');
assert(any(contains(lax.Problems, 'clipped')), 'clipping was not reported');
strict = assess_recording_quality(loud, fo, p, struct('Strict', true));
assert(~strict.Usable, 'a fresh clipped capture was accepted');
% Clipping is unrecoverable and a missing pre-roll is not, so clipping must be listed
% first. Reporting the recoverable defect first is how an operator ends up fixing the
% wrong thing and retaking a shot that is still distorted.
assert(contains(strict.Problems{1}, 'clipped'), ...
    'clipping was listed behind a recoverable defect: %s', strict.Problems{1});

% Missing pre-roll: fatal for a fresh capture, advisory for a stored file.
assert(~assess_recording_quality(cropped, fo, p, struct('Strict',true)).Usable, ...
    'a fresh capture with no silent pre-roll was accepted');
assert(assess_recording_quality(cropped, fo, p, struct('Strict',false)).Usable, ...
    'a stored file with no silent pre-roll was refused');

% Unrecoverable: no features come out, so these are fatal in either mode.
assert(~assess_recording_quality([], fo, p).Usable, 'an empty capture was accepted');
assert(~assess_recording_quality(zeros(3*fo,1), fo, p).Usable, 'silence was accepted');
assert(~assess_recording_quality(withPreRoll*1e-4, fo, p).Usable, ...
    'a signal far below MinRms was accepted');

pass('quality     clean OK, clipping graded and listed first, pre-roll strict-only');
end

% -------------------------------------------------------------------------
function check_corpus_agreement(p)
%CHECK_CORPUS_AGREEMENT The enrolment decision must keep its contract over the whole
%   real corpus, and the deployed matcher must load exactly the files the audit passes.
%
%   The synthetic cases above pin the pipeline at a handful of constructed points.
%   This one runs it over the 123 recordings that actually exist -- clipped ones,
%   ones with no silent pre-roll, one 95 ms fragment, one file 5x below the AGC's
%   silence floor -- which is the only place in the suite where EXTRACT_FEATURES is
%   exercised on real speech at real corpus scale.
%
%   What this check used to do, and why it no longer can
%   --------------------------------------------------
%   It compared ASSESS_RECORDING_QUALITY's verdict against the experiments' inline
%   test (~Rejected && Endpoint.HasSpeech), file by file, because a revision that made
%   clipping fatal had once caused the audit to announce that Al Imran Limon had no
%   usable name recording while the accuracy experiment was verifying him from both of
%   them.  The comparison worked: it found two files where the two disagreed, the audit
%   was right about both, and the fix was to delete the inline copies and route
%   everything through ENROL_TEMPLATE_FEATURES.
%
%   That fix retires the comparison.  With one definition left there is no second
%   opinion to compare against, and asserting that a function agrees with itself
%   passes unconditionally -- a test that cannot fail is not a test.  So this checks
%   the two things that are still falsifiable:
%
%     The contract.  USABLE promises that features can be extracted; NOT USABLE
%     promises a stated reason.  Both are claims about real files that real code can
%     break, and the first one is what the whole downstream measurement chain assumes.
%
%     The deployed path.  FIND_BEST_VOICE_MATCH reaches the same decision through its
%     own folder walk and its own parameter-keyed cache, and reports how many
%     templates it loaded.  That count must equal the audit's usable count.  It is a
%     genuinely independent route to the same number: a cache key that missed a
%     parameter, or a folder walk that skipped a student, shows up here and nowhere
%     else.
%
%   Hard-coding the two known-bad filenames was considered and rejected: it would pass
%   for the wrong reason the moment those students re-record.
if ~isfolder(p.trainNameFolder) || ~isfolder(p.trainCouponFolder)
    fprintf('  --  corpus: skipped, enrolment folders not present\n');
    return;
end

folders = {p.trainNameFolder, p.trainCouponFolder};
phrases = {'Name', 'Coupon'};
strictOpt = struct('Strict', true);

nUsable = 0; nStrict = 0; nUnreadable = 0; nRead = 0;
usableByFolder = zeros(1, numel(folders));
breaches = {};
sampleFeatures = [];

for r = 1:numel(folders)
    files = dir(fullfile(folders{r}, '**', '*.wav'));
    for k = 1:numel(files)
        filePath = fullfile(files(k).folder, files(k).name);
        [~, who] = fileparts(files(k).folder);
        label = sprintf('%s/%s/%s', phrases{r}, who, files(k).name);

        try
            [x, fs] = audioread(filePath);
        catch
            nUnreadable = nUnreadable + 1;
            continue;
        end
        nRead = nRead + 1;

        [f, dg] = enrol_template_features(x, fs, p);

        if dg.Usable
            % The promise USABLE makes. A NaN or a single frame here would sail
            % through every aggregate count and then quietly corrupt one DTW score.
            if isempty(f)
                breaches{end+1} = sprintf('%s: usable, but no features came out', label);   %#ok<AGROW>
            elseif ~all(isfinite(f(:)))
                breaches{end+1} = sprintf('%s: usable, but %d of %d feature values are not finite', ...
                    label, sum(~isfinite(f(:))), numel(f));   %#ok<AGROW>
            elseif size(f,2) < 2
                breaches{end+1} = sprintf(['%s: usable, but only %d feature frame(s) -- ' ...
                    'DTW needs a sequence to warp'], label, size(f,2));   %#ok<AGROW>
            end
            if isempty(sampleFeatures) && ~isempty(f)
                sampleFeatures = f;
            end
        else
            % The promise NOT USABLE makes. A refusal with no reason is a student
            % turned away at the counter with nothing to act on.
            if isempty(dg.Reason) || strcmp(dg.Reason, 'OK') || isempty(dg.Problems)
                breaches{end+1} = sprintf('%s: refused with no stated reason (Reason ''%s'', %d problem(s))', ...
                    label, dg.Reason, numel(dg.Problems));   %#ok<AGROW>
            end
            if ~isempty(f)
                breaches{end+1} = sprintf('%s: refused, yet features were returned', label);   %#ok<AGROW>
            end
        end

        nUsable = nUsable + dg.Usable;
        usableByFolder(r) = usableByFolder(r) + dg.Usable;
        nStrict = nStrict + assess_recording_quality(x, fs, p, strictOpt).Usable;
    end
end

assert(nRead > 0, 'none of the enrolment files could be read');
assert(isempty(breaches), ...
    '%d recording(s) where the enrolment contract was broken:\n    %s', ...
    numel(breaches), strjoin(breaches, sprintf('\n    ')));

% The deployed matcher, by its own route. Reset first: a cached entry from an earlier
% parameter set would make this agree without having loaded anything.
find_best_voice_match('reset');
for r = 1:numel(folders)
    [~, ~, info] = find_best_voice_match(folders{r}, sampleFeatures, p);
    assert(info.TemplatesUsed == usableByFolder(r), ...
        ['the deployed matcher loaded %d %s template(s) but the audit calls %d usable. ' ...
        'One of the two is walking the corpus differently.'], ...
        info.TemplatesUsed, phrases{r}, usableByFolder(r));
end

% Strict can only ever be more demanding, never less. If it accepted more, the two
% problem lists have been assembled in the wrong order somewhere.
assert(nStrict <= nUsable, ...
    'Strict accepted %d files, more than the lax audit accepted (%d)', nStrict, nUsable);

% The whole reason the Strict switch exists is that the stored corpus stays usable.
assert(nUsable > 0.8 * nRead, ...
    'only %d of %d stored recordings are usable; the corpus has become unenrollable', ...
    nUsable, nRead);

pass('corpus      %d/%d stored files enrolled (%d name, %d coupon; %d pass as fresh captures)', ...
    nUsable, nRead, usableByFolder(1), usableByFolder(2), nStrict);
end

% -------------------------------------------------------------------------
function check_threshold_configuration(p)
%CHECK_THRESHOLD_CONFIGURATION The threshold in force must be the one calibrated for
%   the front-end in force.
%
%   A DTW distance has no absolute scale: it is the accumulated Euclidean distance
%   along the warping path divided by the path length, so its numeric range is set by
%   the dimension and scaling of the feature vectors.  The 39-dimensional MFCC gives
%   distances around 20 to 50, the 24-band log spectrum around 1 to 4.  A threshold
%   copied between them is not merely suboptimal, it is either "accept everyone" or
%   "accept nobody".
%
%   This is not hypothetical.  A threshold calibrated for one feature scale, left in
%   place after the features changed, is what made a previous revision of this system
%   accept 89.9 % of impostors.  PARAMS.dtwThreshold is now selected from the same
%   field that selects the front-end, so the two cannot drift apart; this check is
%   what fails if anyone reintroduces a hand-written value.
assert(isfield(p, 'dtwThresholdByFrontEnd'), 'dtwThresholdByFrontEnd is missing');
for frontEnd = {'mfcc','dft'}
    assert(isfield(p.dtwThresholdByFrontEnd, frontEnd{1}), ...
        'no calibrated threshold for the %s front-end', frontEnd{1});
    % Every front-end with a deployed threshold must also carry the per-phrase
    % operating point it was derived from, or the report cannot say where the number
    % came from and the calibration is unfalsifiable.
    assert(isfield(p.perPhraseReference, frontEnd{1}), ...
        'no per-phrase reference operating point recorded for %s', frontEnd{1});
end
assert(abs(p.dtwThreshold - p.dtwThresholdByFrontEnd.(p.featureFrontEnd)) < 1e-9, ...
    'dtwThreshold is %.4f but the %s front-end is calibrated to %.4f', ...
    p.dtwThreshold, p.featureFrontEnd, p.dtwThresholdByFrontEnd.(p.featureFrontEnd));

% If the two front-ends ever carry the same threshold, one was pasted over the other
% rather than measured, because their distance scales differ by an order of magnitude.
assert(abs(p.dtwThresholdByFrontEnd.mfcc - p.dtwThresholdByFrontEnd.dft) > 1e-6, ...
    'both front-ends carry the same threshold, which cannot be correct for both');

assert(p.dtwMarginRatio >= 1, ...
    'a margin ratio below 1 accepts a match the runner-up beat');

pass('threshold   %s -> %.4f (mfcc %.4f, dft %.4f), margin ratio %.2f', ...
    p.featureFrontEnd, p.dtwThreshold, p.dtwThresholdByFrontEnd.mfcc, ...
    p.dtwThresholdByFrontEnd.dft, p.dtwMarginRatio);
end

% -------------------------------------------------------------------------
function check_meal_windows(p)
%CHECK_MEAL_WINDOWS Modification 5: the clock decides which meal is being served.
%
%   Windows are half-open, start <= t < end.  That convention is the point of the
%   test: with an inclusive upper bound the closing minute would belong to two windows
%   at once, and the one-meal-per-window check could then be satisfied twice for the
%   same serving.  So the closing instant must fall OUTSIDE the window and the minute
%   before it must fall inside.  Both sides of every edge are checked, because an
%   off-by-one there either turns away a student who arrived on time or admits one
%   twice.
day = datetime(2026, 3, 5);

for k = 1:numel(p.meals)
    name = p.meals(k).Name;
    openAt  = day + minutes(p.meals(k).Start(1)*60 + p.meals(k).Start(2));
    closeAt = day + minutes(p.meals(k).End(1)*60   + p.meals(k).End(2));

    assert(strcmp(meal_window_now(p, openAt), name), ...
        '%s: the opening instant %s fell outside the window', name, string(openAt,'HH:mm'));
    assert(strcmp(meal_window_now(p, openAt + minutes(1)), name), ...
        '%s: one minute after opening was outside the window', name);
    assert(strcmp(meal_window_now(p, closeAt - minutes(1)), name), ...
        '%s: the last minute before closing was outside the window', name);

    % Half-open upper bound: the closing instant belongs to no window.
    assert(~strcmp(meal_window_now(p, closeAt), name), ...
        ['%s: the closing instant %s was still inside the window, so the boundary ' ...
         'minute belongs to two windows at once'], name, string(closeAt,'HH:mm'));
    assert(~strcmp(meal_window_now(p, openAt - minutes(1)), name), ...
        '%s: the window was already open one minute early', name);
end

% Between services there is no meal to serve, and the system must say so rather than
% serve the previous one again.
[betweenName, betweenInfo] = meal_window_now(p, day + hours(16));
assert(isempty(betweenName), '16:00 was assigned the %s window', betweenName);
assert(betweenInfo.Index == 0, 'a closed instant reported window index %d', betweenInfo.Index);
assert(strcmp(betweenInfo.NextWindow, 'Dinner'), ...
    'at 16:00 the next window was reported as "%s", expected Dinner', betweenInfo.NextWindow);

% After the last window closes there is nothing left today, and MinutesToNext must be
% NaN rather than a negative number pointing back at this morning.
[~, lateInfo] = meal_window_now(p, day + hours(23));
assert(isempty(lateInfo.NextWindow) && isnan(lateInfo.MinutesToNext), ...
    'at 23:00 the next window was reported as "%s" in %g minutes', ...
    lateInfo.NextWindow, lateInfo.MinutesToNext);

pass('meals       %s; edges half-open, 16:00 closed with Dinner next', betweenInfo.AllWindows);
end

% -------------------------------------------------------------------------
function check_meal_logging(p)
%CHECK_MEAL_LOGGING Modification 5: one meal per student per window per day.
%
%   The rule is scoped to the window, not to the day.  A student who ate breakfast is
%   entitled to lunch, and is not entitled to a second breakfast.  Both halves are
%   checked, because enforcing only the first allows double servings and enforcing
%   only the second starves everyone after breakfast.
%
%   The log file is a temporary one.  Writing to PARAMS.logFile would put test rows
%   into the hall's actual records, and a regression suite that damages production
%   data is not one anybody will run twice.
q = p;
q.logFile = [tempname '.csv'];
% CLEANUP looks unused and is not: the temporary log is deleted when this object
% goes out of scope, including on an assertion failure part-way through.
cleanup = onCleanup(@() delete_if_present(q.logFile));

info = struct('Method','Voice+Coupon', 'NameDistance',20.1, ...
    'CouponDistance',22.8, 'Margin',2.4);
day = datetime(2026, 3, 5);
breakfast = day + minutes(p.meals(1).Start(1)*60 + p.meals(1).Start(2) + 30);
lunch     = day + minutes(p.meals(2).Start(1)*60 + p.meals(2).Start(2) + 30);

[first, msg1, info1] = log_meal_csv('Test Student', info, q, breakfast);
assert(first, 'the first breakfast was refused: %s', msg1);
assert(strcmp(info1.Meal, p.meals(1).Name), ...
    'the row was logged against the %s window', info1.Meal);

[repeat, msg2, info2] = log_meal_csv('Test Student', info, q, breakfast + minutes(20));
assert(~repeat && info2.Duplicate, 'a second breakfast was served in the same window');
assert(~isempty(msg2), 'the repeat was refused without a message');

% Case and surrounding space must not create a second identity. "test student" is the
% same person as "Test Student", and a log keyed on the exact string would let a typo
% through as a new student entitled to another meal.
aliased = log_meal_csv('  test student  ', info, q, breakfast + minutes(25));
assert(~aliased, 'a differently-spelled form of the same name got a second breakfast');

[nextMeal, msg3, info3] = log_meal_csv('Test Student', info, q, lunch);
assert(nextMeal, 'lunch was refused after breakfast: %s', msg3);
assert(strcmp(info3.Meal, p.meals(2).Name), 'lunch was logged as %s', info3.Meal);

other = log_meal_csv('Another Student', info, q, breakfast + minutes(30));
assert(other, 'a different student was refused their own breakfast');

% Outside every window nothing is logged, however well the student verified.
[closed, msg4, info4] = log_meal_csv('Test Student', info, q, day + hours(16));
assert(~closed && info4.OutsideWindow, 'a meal was logged at 16:00: %s', msg4);

logged = readtable(q.logFile, 'TextType', 'string');
assert(height(logged) == 3, 'expected 3 served rows, found %d', height(logged));
% The distances have to be in the file, or a disputed refusal cannot be audited after
% the fact -- which is the whole reason the log carries numbers and not just verdicts.
assert(all(ismember({'NameDistance','CouponDistance','Margin'}, ...
    logged.Properties.VariableNames)), 'the log did not record the decision distances');
assert(abs(logged.NameDistance(1) - info.NameDistance) < 1e-9, ...
    'the logged name distance does not match the one supplied');

pass('logging     repeat refused (incl. case and space variants), next window allowed');
end

% -------------------------------------------------------------------------
function check_workflow_decision(p)
%CHECK_WORKFLOW_DECISION The composite decision, with features injected so that no
%   microphone is needed.
%
%   The decision is not one distance against one threshold.  Two phrases are
%   captured, each identifies a student independently, and they must agree; then the
%   typed coupon code is checked against the student the VOICE identified; and only
%   then is entitlement considered.  Naming the gate that refused is as important as
%   the refusal, which is why every case below asserts RESULT.Stage and not just
%   RESULT.Granted -- a transaction refused for the right reason and one refused for
%   the wrong reason look identical from the verdict alone.
%
%   Checking the gates one at a time is how EXPERIMENT_VERIFICATION_ACCURACY
%   established that all of them are load-bearing: at the deployed operating point,
%   cross-phrase agreement stops 47 of 56 proxy attacks, the runner-up margin 7, and
%   the threshold 2.
%
%   SkipLogging bypasses the entitlement gate entirely, so the closed-hours case must
%   run with logging enabled against a temporary file.  Testing it with SkipLogging
%   would assert nothing at all.
q = p;
q.logFile = [tempname '.csv'];
q.monthlyEntitlementFile = [tempname '.csv'];
q.monthlyCouponFile = [tempname '.csv'];
% All persistent authorities are redirected so one test cannot affect another.
cleanup = onCleanup(@() delete_workflow_files(q.logFile, q.monthlyEntitlementFile, q.monthlyCouponFile));

find_best_voice_match('reset');
lib = load_two_students(q);
if isempty(lib)
    fprintf('  --  workflow: skipped, fewer than two enrollable students in the corpus\n');
    return;
end

lunch  = datetime(2026,3,5) + minutes(q.meals(2).Start(1)*60 + q.meals(2).Start(2) + 30);
closed = datetime(2026,3,5) + hours(16);
[assigned1, assignMsg1] = assign_monthly_coupon(lib.student{1}, lib.code{1}, q, lunch);
assert(assigned1, 'test admin could not assign first coupon: %s', assignMsg1);
[assigned2, assignMsg2] = assign_monthly_coupon(lib.student{2}, lib.code{2}, q, closed);
assert(assigned2, 'test admin could not assign second coupon: %s', assignMsg2);

% 1. Both phrases from one student, with that student's own code typed. Logging is
%    left on, so this exercises the entitlement gate and the CSV write as well.
granted = run_workflow(q, lib.nameFeatures{1}, lib.couponFeatures{1}, lib.code{1}, lunch, false);
assert(granted.Granted, 'a genuine student was refused at the %s gate: %s', ...
    granted.Stage, granted.Reason);
assert(strcmpi(granted.Student, lib.student{1}), ...
    'granted the wrong student: %s instead of %s', granted.Student, lib.student{1});
assert(granted.Logged && strcmp(granted.Meal, q.meals(2).Name), ...
    'the served meal was recorded as "%s"', granted.Meal);

% 2. The same transaction again in the same window: identified correctly, refused on
%    entitlement. Verification succeeding and service being refused are different
%    outcomes, and a refusal here is not a failure of the DSP.
again = run_workflow(q, lib.nameFeatures{1}, lib.couponFeatures{1}, lib.code{1}, lunch, false);
assert(~again.Granted && strcmp(again.Stage, 'entitlement'), ...
    'a second lunch was served, or was refused at the %s gate instead', again.Stage);
assert(strcmpi(again.Student, lib.student{1}), ...
    'the repeat transaction lost the identification it had already made');

% 3. Two phrases naming different people. Reset payment state so this negative
%    case exercises the coupon voice agreement gate under the new monthly rule.
q.monthlyEntitlementFile = [tempname '.csv'];
cleanupCrossed = onCleanup(@() delete_if_present(q.monthlyEntitlementFile));
crossed = run_workflow(q, lib.nameFeatures{1}, lib.couponFeatures{2}, lib.code{1}, lunch, true);
assert(~crossed.Granted && strcmp(crossed.Stage, 'agreement'), ...
    'crossed phrases were refused at the %s gate, expected agreement', crossed.Stage);

% 4. Right voice, wrong typed code. The voice is not the only evidence: the code
%    proves possession of the coupon, and it is checked against the student the voice
%    identified rather than being used to look that student up.
wrongCode = repmat('0', 1, numel(lib.code{1}));
if strcmp(wrongCode, lib.code{1}), wrongCode = repmat('1', 1, numel(lib.code{1})); end
mistyped = run_workflow(q, lib.nameFeatures{1}, lib.couponFeatures{1}, wrongCode, lunch, true);
assert(~mistyped.Granted && strcmp(mistyped.Stage, 'code'), ...
    'a mistyped coupon code was refused at the %s gate, expected code', mistyped.Stage);

% 5. A malformed code is refused only after identity matching because an empty
%    coupon is valid for students already paid this month.
malformed = run_workflow(q, lib.nameFeatures{1}, lib.couponFeatures{1}, '12ab', lunch, true);
assert(~malformed.Granted && strcmp(malformed.Stage, 'code'), ...
    'a malformed code reached the %s gate, expected code', malformed.Stage);

% 6. Outside every serving window, an otherwise perfect transaction is refused -- and
%    the student is still identified first, so the log and the operator both know who
%    was turned away.
outOfHours = run_workflow(q, lib.nameFeatures{2}, lib.couponFeatures{2}, lib.code{2}, closed, false);
assert(~outOfHours.Granted && strcmp(outOfHours.Stage, 'entitlement'), ...
    'a meal was served at 16:00, or refused at the %s gate instead', outOfHours.Stage);
assert(strcmpi(outOfHours.Student, lib.student{2}), ...
    'the closed-hours transaction failed to identify the student first');

pass('workflow    %s granted at %.3f/%.3f; repeat, crossed phrases, wrong and', ...
    lib.student{1}, granted.NameDistance, granted.CouponDistance);
pass('            malformed code, and closed hours each refused at the right gate');
end

% =========================================================================
function y = with_utterance(fo, totalDur, startDur, uttDur, noiseRms, peak)
%WITH_UTTERANCE A quiet room with one synthesised voiced utterance in it.
%
%   Y = WITH_UTTERANCE(FO, TOTALDUR, STARTDUR, UTTDUR, NOISERMS, PEAK) returns
%   TOTALDUR seconds of low-level noise at FO Hz with a UTTDUR-second voice inserted
%   STARTDUR seconds in.
%
%   The noise floor is not decoration.  Modification 3 estimates the noise spectrum
%   from the first 0.5 s and modification 4 learns its energy threshold from the same
%   region; a floor of exactly zero makes both estimate from nothing, and
%   HYBRID_ENDPOINT_DETECT then falls back to its percentile estimator, which is a
%   different code path from the one a real recording takes.
%
%   The utterance is clipped to fit rather than assumed to fit, so changing a duration
%   above cannot silently index past the end.
y = noiseRms * randn(round(totalDur*fo), 1);
u = synth_voiced_signal(fo, uttDur, [], [], peak);
first = round(startDur*fo) + 1;
last  = min(numel(y), first + numel(u) - 1);
y(first:last) = y(first:last) + u(1 : last-first+1);
end

function result = run_workflow(p, nameFeatures, couponFeatures, typedCode, nowValue, skipLogging)
%RUN_WORKFLOW One transaction with the two recordings replaced by supplied features.
options = struct('NowValue', nowValue, 'NameFeatures', nameFeatures, ...
    'CouponFeatures', couponFeatures, 'SkipLogging', skipLogging);
result = verify_meal_workflow([], typedCode, p, options);
end

function lib = load_two_students(p)
%LOAD_TWO_STUDENTS Features and coupon codes for the first two enrollable students.
%
%   Real corpus audio is used rather than synthetic tones, because the workflow has to
%   rank one student above another and two synthetic tones would not exercise that.
%
%   A student counts as enrollable only if BOTH phrases yield a template and a coupon
%   code is on file -- the same three things VERIFY_MEAL_WORKFLOW needs. That is why
%   Train/Name/Siam Ahmed, which holds a code.txt and no audio at all, is skipped
%   here rather than causing a failure: an incomplete enrolment is a finding for
%   DIAGNOSE_AUDIO_CORPUS to report, not a regression in the pipeline.
lib = [];
if ~isfolder(p.trainNameFolder), return; end
users = dir(p.trainNameFolder);
users = users([users.isdir] & ~startsWith({users.name},'.'));

found = struct('student',{{}},'nameFeatures',{{}},'couponFeatures',{{}},'code',{{}});
for i = 1:numel(users)
    who = users(i).name;
    nf = first_template(fullfile(p.trainNameFolder, who), p);
    cf = first_template(fullfile(p.trainCouponFolder, who), p);
    code = read_code(fullfile(p.trainNameFolder, who, p.codeFileName));
    if isempty(nf) || isempty(cf) || isempty(code), continue; end

    % Growing these four cells is fine: the loop returns as soon as it has two.
    found.student{end+1}        = who;
    found.nameFeatures{end+1}   = nf;
    found.couponFeatures{end+1} = cf;
    found.code{end+1}           = code;
    if numel(found.student) == 2
        lib = found;
        return;
    end
end
end

function f = first_template(folder, p)
%FIRST_TEMPLATE Features from the first enrollable WAV in FOLDER, or [].
%   Through ENROL_TEMPLATE_FEATURES, so the workflow trace below is driven by a file
%   the deployed matcher would also have loaded. An earlier inline copy of the
%   enrolment test could have picked a template the system itself refuses, and the
%   trace would then have been proving something about a library that does not exist.
f = [];
files = dir(fullfile(folder, '*.wav'));
for k = 1:numel(files)
    f = enrol_template_features(fullfile(files(k).folder, files(k).name), [], p);
    if ~isempty(f)
        return;
    end
end
end

function code = read_code(path)
code = '';
if ~isfile(path), return; end
fid = fopen(path, 'r');
if fid < 0, return; end
code = strtrim(fscanf(fid, '%s'));
fclose(fid);
end

function r = rms_of(x)
r = sqrt(mean(double(x(:)).^2));
end

function delete_if_present(path)
if isfile(path), delete(path); end
end

function delete_workflow_files(logFile, entitlementFile, couponFile)
delete_if_present(logFile);
delete_if_present(entitlementFile);
delete_if_present(couponFile);
end

function pass(fmt, varargin)
fprintf('  ok  %s\n', sprintf(fmt, varargin{:}));
end
