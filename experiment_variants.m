function variants=experiment_variants(p)
%EXPERIMENT_VARIANTS Preregistered candidate catalog; no final scores consulted.
% Base already has AGC, resampling, STE/ZCR, derivatives and constrained DTW.
% Rate-only rows fix MFCC band and physical ZCR limits. Wideband is separate.
p.endpoint.ZcrReferenceFs=8000;
p.agc.Enable=true; p.noise.Method='spectral'; p.noise.Enable=true;
p.endpoint.Mode='hybrid'; p.templateAggregation='mean';
p.mfcc.Rasta=false; p.mfcc.IncludePitch=false; p.mfcc.IncludeSpectral=false;
p.mfcc.StaticWeight=1; p.mfcc.DeltaWeight=1; p.mfcc.DeltaDeltaWeight=1;
p.mfcc.PitchWeight=1; p.mfcc.SpectralWeight=1;
variants=struct('Name',{},'Group',{},'Change',{},'Params',{});
variants=add(variants,'current_dsp','Current existing DSP','Unchanged DSP; conservative policy evaluated separately',p);
q=p; q.agc.Enable=false; variants=add(variants,'agc_off','AGC','Disable capture and speech gain; retain DC removal',q);
for fs=[16000 44100]
    q=p; q.processingFs=fs;
    variants=add(variants,sprintf('rate_%d',fs),'Resampling','Rate only; fixed 300-3700 Hz MFCC band, physical ZCR limits',q);
end
q=p; q.processingFs=16000; q.R=[300 7600];
variants=add(variants,'rate_16000_wideband','Resampling','Separate 16 kHz + wider MFCC band; two factors explicitly changed',q);
q=p; q.noise.Method='none'; variants=add(variants,'noise_none','Noise suppression','No suppression; legacy cropped adapter may already bypass it',q);
q=p; q.noise.Method='wiener'; variants=add(variants,'noise_wiener','Noise suppression','Wiener; only exercised when valid noise pre-roll exists',q);
q=p; q.endpoint.Mode='energy'; variants=add(variants,'vad_energy','STE/ZCR','Energy-only current endpoint implementation; not original senior code',q);
q=p; q.mfcc.IncludeDelta=false; q.mfcc.IncludeDeltaDelta=false;
variants=add(variants,'mfcc_static','MFCC derivatives','Static MFCC only',q);
q=p; q.mfcc.IncludeDeltaDelta=false; variants=add(variants,'mfcc_delta','MFCC derivatives','MFCC plus delta',q);
q=p; q.mfcc.CmvNormalise=true; variants=add(variants,'cmvn','CMVN','Add per-utterance cepstral variance normalization',q);
for weight=[1 5]
    q=p; q.mfcc.IncludePitch=true; q.mfcc.PitchWeight=weight;
    variants=add(variants,sprintf('pitch_w%d',weight),'Pitch','Autocorrelation pitch and voicing; declared candidate weight',q);
    q=p; q.mfcc.IncludeSpectral=true; q.mfcc.SpectralWeight=weight;
    variants=add(variants,sprintf('spectral_w%d',weight),'Spectral features','Centroid rolloff flatness; declared candidate weight',q);
end
q=p; q.mfcc.Rasta=true; variants=add(variants,'rasta','RASTA','Temporal cepstral filter',q);
for band=[.1 .2 .5 1]
    q=p; q.dtw.SakoeChibaBand=band;
    variants=add(variants,sprintf('dtw_band_%03d',round(100*band)),'Constrained DTW','Sakoe-Chiba fraction; 1 means unrestricted',q);
end
q=p; q.mfcc.DeltaWeight=.5; q.mfcc.DeltaDeltaWeight=.25;
variants=add(variants,'derivative_weights','Feature weights','Declared candidate delta=0.5 delta-delta=0.25',q);
end

function variants=add(variants,name,group,change,p)
variants(end+1)=struct('Name',string(name),'Group',string(group),'Change',string(change),'Params',p);
end
