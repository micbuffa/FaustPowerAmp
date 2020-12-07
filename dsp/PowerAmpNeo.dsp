import("stdfaust.lib");
wa = library("webaudio.lib");

// Modified version of https://github.com/creativeintent/temper/blob/master/Dsp/temper.dsp
// Adapted for PowerAmp simulation (addition of presence filter, param adaptation, small changes...)

// Distortion parameters
pdrive = hslider("Drive gain[style:knob]", 4.0, -10.0, 10.0, 0.001) : si.smooth(0.995);
psat = hslider("Saturation dry wet[style:knob]", 1.0, 0.0, 1.0, 0.001) : si.smooth(0.995);
pcurve = hslider("Curve k[style:knob]", 1.0, 0.1, 4.0, 0.001) : si.smooth(0.995);

// Output parameters
plevel = hslider("Level[style:knob]", -3, -24, 24, 1) : ba.db2linear : si.smooth(0.995);

// A fairly standard wave shaping curve; we use this to shape the input signal
// before modulating the filter coefficients by this signal. Which shaping curve
// we use here is pretty unimportant; as long as we can introduce higher harmonics,
// the coefficient modulation will react. Which harmonics we introduce here seems
// to affect the resulting sound pretty minimally.
//
// Also note here that we use an approximation of the `tanh` function for computational
// improvement. See `http://www.musicdsp.org/showone.php?id=238`.
tanh(x) = x * (27 + x * x) / (27 + 9 * x * x);
transfer(x) = tanh(pcurve * x) / tanh(pcurve);

// The allpass filter is stable for `|m(x)| <= 1`, but should not linger
// near +/-1.0 for very long. We therefore clamp the driven signal with a tanh
// function to ensure smooth coefficient calculation. We also here introduce
// a modulated DC offset in the signal before the curve.
drive(x) = x : *(pdrive) : +(fol(x)) : max(-3) : min(3) with {
	fol = an.amp_follower(0.04);
};

// Our modulated filter is an allpass with coefficients governed by the input
// signal applied through our wave shaper. Before the filter, we mix the dry
// input signal with the raw waveshaper output according to the `psat` parameter.
// Note the constant gain coefficient on the waveshaper; that number is to offset
// the global gain from the waveshaper to make sure the shaping process stays
// under unity gain. The maximum differential gain of the waveshaper can be found
// by evaluating the derivative of the transfer function at x0 where x0 is the
// steepest part of the slope. Here that number is ~4, so we multiply by ~1/4.
waveshaper(x) = x <: _, tap(x) : *(1.0 - psat), *(psat) : + : fi.tf1(b0(x), b1(x), a1(x)) with {
	b0(x) = m(x);
	b1(x) = 1.0;
	a1(x) = m(x);
	m(x) = drive(x) : transfer : *(0.24);
	tap(x) = m(x);
};

// A fork of the `tf2s` function from the standard filter library which uses a
// smoothing function after the `tan` computation to move that expensive call
// outside of the inner loop of the filter function.
tf2s(b2,b1,b0,a1,a0,w1) = fi.tf2(b0d,b1d,b2d,a1d,a2d)
with {
	c   = 1/tan(w1*0.5/ma.SR) : si.smooth(0.995); // bilinear-transform scale-factor
	csq = c*c;
	d   = a0 + a1 * c + csq;
	b0d = (b0 + b1 * c + b2 * csq)/d;
	b1d = 2 * (b0 - b2 * csq)/d;
	b2d = (b0 - b1 * c + b2 * csq)/d;
	a1d = 2 * (a0 - csq)/d;
	a2d = (a0 - a1*c + csq)/d;
};

// A fork of the `resonlp` function from the standard filter library which uses
// a local `tf2s` implementation.
resonlp(fc,Q,gain) = tf2s(b2,b1,b0,a1,a0,wc)
with {
	wc = 2*ma.PI*fc;
	a1 = 1/Q;
	a0 = 1;
	b2 = 0;
	b1 = 0;
	b0 = gain;
};



feedbackCircuit = presence:*(gainNFL) 
with {
    p1gain = hslider("Presence[name:p1Gain][style:knob]", 0, -15, 15, 0.1);
    presence =wa.peaking(2000, p1gain, 1, 1) : wa.peaking(4000, p1gain, 1, 1);
    gainNFL = hslider("Negative gain[name:Level][style:knob]", -0.4, -0.8, 1, 0.01) :  si.smoo;
};

// Our main processing block.
main = *(masterVolume) :(+ : waveshaper : fi.dcblocker) ~ feedbackCircuit : gain with {
	// This explicit gain multiplier of 4.0 accounts for the loss of gain that
	// occurs from oversampling by a factor of 2, and for the loss of gain that
	// occurs from the prefilter and modulation step. Then we apply the output
	// level parameter.
	gain = *(4.0) : *(plevel);
    masterVolume = hslider("Master Volume[name:MV][style:knob]", 1, 0, 4, 0.1)  : si.smoo;
};

// And the overall process declaration.
poweramp =  main;

finalPWAMono = hgroup("PowerAmp FAUST / WebAudio",ba.bypass_fade(ma.SR/10, checkbox("bypass"), poweramp)); 

process = finalPWAMono, finalPWAMono;

