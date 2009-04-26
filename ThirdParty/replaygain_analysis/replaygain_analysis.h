/*
 *  ReplayGainAnalysis - analyzes input samples and give the recommended dB change
 *  Copyright (C) 2001 David Robinson and Glen Sawyer
 *
 *  This library is free software; you can redistribute it and/or
 *  modify it under the terms of the GNU Lesser General Public
 *  License as published by the Free Software Foundation; either
 *  version 2.1 of the License, or (at your option) any later version.
 *
 *  This library is distributed in the hope that it will be useful,
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 *  Lesser General Public License for more details.
 *
 *  You should have received a copy of the GNU Lesser General Public
 *  License along with this library; if not, write to the Free Software
 *  Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
 *
 *  concept and filter values by David Robinson (David@Robinson.org)
 *    -- blame him if you think the idea is flawed
 *  coding by Glen Sawyer (glensawyer@hotmail.com) 442 N 700 E, Provo, UT 84606 USA
 *    -- blame him if you think this runs too slowly, or the coding is otherwise flawed
 *  minor cosmetic tweaks to integrate with FLAC by Josh Coalson
 *
 *  For an explanation of the concepts and the basic algorithms involved, go to:
 *    http://www.replaygain.org/
 */

#ifndef GAIN_ANALYSIS_H
#define GAIN_ANALYSIS_H

#include <stddef.h>

#define GAIN_NOT_ENOUGH_SAMPLES  -24601
#define GAIN_ANALYSIS_ERROR           0
#define GAIN_ANALYSIS_OK              1

#define INIT_GAIN_ANALYSIS_ERROR      0
#define INIT_GAIN_ANALYSIS_OK         1


#define YULE_ORDER			10
#define BUTTER_ORDER		2
#define RMS_PERCENTILE		0.95		/* percentile which is louder than the proposed level */
#define MAX_SAMP_FREQ		48000.		/* maximum allowed sample frequency [Hz] */
#define RMS_WINDOW_TIME		0.050		/* Time slice size [s] */
#define STEPS_per_dB		100.		/* Table entries per dB */
#define MAX_dB				120.		/* Table entries for 0...MAX_dB (normal max. values are 70...80 dB) */

#define MAX_ORDER			(BUTTER_ORDER > YULE_ORDER ? BUTTER_ORDER : YULE_ORDER)
/* [JEC] the following was originally #defined as:
 *   (size_t) (MAX_SAMP_FREQ * RMS_WINDOW_TIME)
 * but that seemed to fail to take into account the ceil() part of the
 * sampleWindow calculation in ResetSampleFrequency(), and was causing
 * buffer overflows for 48kHz analysis, hence the +1.
 */
#define MAX_SAMPLES_PER_WINDOW  (size_t) (MAX_SAMP_FREQ * RMS_WINDOW_TIME + 1.)   /* max. Samples per Time slice */
#define PINK_REF                64.82 /* 298640883795 */                          /* calibration value */


#ifdef __cplusplus
extern "C" {
#endif

extern float ReplayGainReferenceLoudness; /* in dB SPL, currently == 89.0 */

struct replaygain_t {
	float			linprebuf	[MAX_ORDER * 2];
	float			*linpre;                                          // left input samples, with pre-buffer
	float			lstepbuf	[MAX_SAMPLES_PER_WINDOW + MAX_ORDER];
	float			*lstep;                                           // left "first step" (i.e. post first filter) samples
	float			loutbuf		[MAX_SAMPLES_PER_WINDOW + MAX_ORDER];
	float			*lout;                                            // left "out" (i.e. post second filter) samples
	float			rinprebuf	[MAX_ORDER * 2];
	float			*rinpre;                                          // right input samples ...
	float			rstepbuf	[MAX_SAMPLES_PER_WINDOW + MAX_ORDER];
	float			*rstep;
	float			routbuf		[MAX_SAMPLES_PER_WINDOW + MAX_ORDER];
	float			*rout;
	unsigned int	sampleWindow;                                    // number of samples required to reach number of milliseconds required for RMS window
	unsigned long	totsamp;
	double			lsum;
	double			rsum;
	int				freqindex;
	uint32_t		A [(size_t)(STEPS_per_dB * MAX_dB)];
	uint32_t		B [(size_t)(STEPS_per_dB * MAX_dB)];
	float			title_peak;
	float			album_peak;
};
	
int replaygain_analysis_init ( struct replaygain_t *rg, long samplefreq );
int replaygain_analysis_analyze_samples   ( struct replaygain_t *rg, const float* left_samples, const float* right_samples, size_t num_samples, int num_channels );
int replaygain_analysis_reset_sample_frequency ( struct replaygain_t *rg, long samplefreq );

float replaygain_analysis_get_title_gain     ( struct replaygain_t *rg );
float replaygain_analysis_get_album_gain     ( struct replaygain_t *rg );

float replaygain_analysis_get_title_peak     ( struct replaygain_t *rg );
float replaygain_analysis_get_album_peak     ( struct replaygain_t *rg );

#ifdef __cplusplus
}
#endif

#endif /* GAIN_ANALYSIS_H */
