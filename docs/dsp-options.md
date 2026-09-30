# Controlled DSP options

These are opt-in experiment parameters. Existing `dsp_parameters` settings remain the deployed defaults; any feature or scoring change requires its own calibration.

| Parameter | Choices / default fallback |
| --- | --- |
| `processingFs` | Existing: 8000, 16000, 44100 Hz |
| `agc.Enable` | `true`; `false` preserves DC removal, bypasses RMS gain and limiter |
| `noise.Method` | `'spectral'`; `'none'`, `'wiener'`; existing `noise.Enable=false` overrides |
| `endpoint.Mode` | `'hybrid'`; `'energy'` uses the same threshold/run/gap rules without ZCR gating |
| `endpoint.ZcrReferenceFs` | Optional calibration rate for crossings/sample thresholds; set 8000 for matched physical ZCR boundaries in rate comparisons. Absent preserves historical behavior. |
| `mfcc.IncludeDelta`, `IncludeDeltaDelta` | Existing: true/true; static false/false; static + delta true/false |
| `mfcc.CmsNormalise`, `CmvNormalise` | Existing: false/false; CMVN normalizes each static coefficient before derivatives |
| `mfcc.Rasta` | `false`; causal RASTA-like filter on log-mel energies, initialized from the first frame |
| `mfcc.IncludePitch` | `false`; append voiced log2(F0/150 Hz) and autocorrelation confidence |
| `mfcc.IncludeSpectral` | `false`; append Nyquist-normalized centroid, rolloff, and spectral flatness |
| `mfcc.StaticWeight`, `DeltaWeight`, `DeltaDeltaWeight`, `PitchWeight`, `SpectralWeight` | `1`; fixed block weights, no data-learned parameters |
| `dtw.SakoeChibaBand` | Existing: fraction of longer frame sequence, default 0.30; widened for length difference |
| `templateAggregation` | `'mean'`; `'median'`, `'min'` for multiple templates per identity |

Call `dtw_distance_dsp(F,T,p.dtw)`, not with the full parameter structure.

The legacy cropped template adapter continues to disable suppression because there is no measured ambient lead-in. A suppression comparison on those files must say that the option had no effect; a separate synthetic stress experiment may prepend an explicitly labeled synthetic noise interval. No synthetic corruption is evidence of real microphone, replay, or impostor performance.

Preprocessing reports `Timings.Resample`, `Agc`, `Noise`, `Endpoint`, `AgcSpeech`, `Liveness`, and `Total` in seconds. Feature timing is reported by `extract_features`. The same time-based framing produces nearly the same frame counts at each sample rate; DTW complexity is driven by frame counts, not raw sample rate.

## Implementation checklist

- [x] Inspect original DSP and capture/cache paths.
- [x] Define parameter interface with experiment owner.
- [x] Write tests before implementation.
- [ ] Generate immutable-source default reference and observe RED in MATLAB.
- [ ] Implement optional switches and feature blocks.
- [ ] Repair demonstrated capture quality and cache defects.
- [ ] Verify default numerical equivalence and GREEN tests.
- [ ] Report files, tests, and limits for parent review.
