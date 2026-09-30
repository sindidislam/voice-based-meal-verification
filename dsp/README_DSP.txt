DIGITAL SIGNAL PROCESSING PIPELINE
==================================
Core Algorithms:
  - preprocess_audio.m: Rational resampling (80/441), VAD, AGC
  - extract_mfcc_dsp.m: 13 MFCC + Delta + DeltaDelta + CMVN
  - extractCQCC.m: Constant-Q Cepstral Coefficients (CQT)
  - dtw_distance_dsp.m: Tempo-invariant dynamic time warping with optimal path normalization
  - voice_gmm_ubm.m: 16-mixture Universal Background Model with MAP adaptation
  - livenessFeatures.m: 8 physical acoustic replay cues (Witkowski et al. 2017)
  - calibrateLiveness.m: Shrinkage regularized Fisher LDA classifier
  - verifyLiveness.m: Native-rate wideband anti-spoofing verification
  - mic_check.m: Real-time microphone level, clipping, and SNR diagnostic
  - speak_text.m: Windows .NET interactive voice prompt engine
