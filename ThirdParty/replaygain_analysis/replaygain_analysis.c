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
 *  original coding by Glen Sawyer (glensawyer@hotmail.com)
 *    -- blame him if you think this runs too slowly, or the coding is otherwise flawed
 *
 *  lots of code improvements by Frank Klemm ( http://www.uni-jena.de/~pfk/mpp/ )
 *    -- credit him for all the _good_ programming ;)
 *
 *  minor cosmetic tweaks to integrate with FLAC by Josh Coalson
 *
 *
 *  For an explanation of the concepts and the basic algorithms involved, go to:
 *    http://www.replaygain.org/
 */

/*
 *  Here's the deal. Call
 *
 *    InitGainAnalysis ( long samplefreq );
 *
 *  to initialize everything. Call
 *
 *    AnalyzeSamples ( const float*  left_samples,
 *                     const float*  right_samples,
 *                     size_t          num_samples,
 *                     int             num_channels );
 *
 *  as many times as you want, with as many or as few samples as you want.
 *  If mono, pass the sample buffer in through left_samples, leave
 *  right_samples NULL, and make sure num_channels = 1.
 *
 *    GetTitleGain()
 *
 *  will return the recommended dB level change for all samples analyzed
 *  SINCE THE LAST TIME you called GetTitleGain() OR InitGainAnalysis().
 *
 *    GetAlbumGain()
 *
 *  will return the recommended dB level change for all samples analyzed
 *  since InitGainAnalysis() was called and finalized with GetTitleGain().
 *
 *  Pseudo-code to process an album:
 *
 *    float       l_samples [4096];
 *    float       r_samples [4096];
 *    size_t        num_samples;
 *    unsigned int  num_songs;
 *    unsigned int  i;
 *
 *    InitGainAnalysis ( 44100 );
 *    for ( i = 1; i <= num_songs; i++ ) {
 *        while ( ( num_samples = getSongSamples ( song[i], left_samples, right_samples ) ) > 0 )
 *            AnalyzeSamples ( left_samples, right_samples, num_samples, 2 );
 *        fprintf ("Recommended dB change for song %2d: %+6.2f dB\n", i, GetTitleGain() );
 *    }
 *    fprintf ("Recommended dB change for whole album: %+6.2f dB\n", GetAlbumGain() );
 */

/*
 *  So here's the main source of potential code confusion:
 *
 *  The filters applied to the incoming samples are IIR filters,
 *  meaning they rely on up to <filter order> number of previous samples
 *  AND up to <filter order> number of previous filtered samples.
 *
 *  I set up the AnalyzeSamples routine to minimize memory usage and interface
 *  complexity. The speed isn't compromised too much (I don't think), but the
 *  internal complexity is higher than it should be for such a relatively
 *  simple routine.
 *
 *  Optimization/clarity suggestions are welcome.
 */

#if HAVE_CONFIG_H
#  include <config.h>
#endif

#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include <math.h>

#include "replaygain_analysis.h"

float ReplayGainReferenceLoudness = 89.0f; /* in dB SPL */

static const float  AYule [9] [11] = {
    { 1.f, -3.84664617118067f,  7.81501653005538f,-11.34170355132042f, 13.05504219327545f,-12.28759895145294f,  9.48293806319790f, -5.87257861775999f,  2.75465861874613f, -0.86984376593551f, 0.13919314567432f },
    { 1.f, -3.47845948550071f,  6.36317777566148f, -8.54751527471874f,  9.47693607801280f, -8.81498681370155f,  6.85401540936998f, -4.39470996079559f,  2.19611684890774f, -0.75104302451432f, 0.13149317958808f },
    { 1.f, -2.37898834973084f,  2.84868151156327f, -2.64577170229825f,  2.23697657451713f, -1.67148153367602f,  1.00595954808547f, -0.45953458054983f,  0.16378164858596f, -0.05032077717131f, 0.02347897407020f },
    { 1.f, -1.61273165137247f,  1.07977492259970f, -0.25656257754070f, -0.16276719120440f, -0.22638893773906f,  0.39120800788284f, -0.22138138954925f,  0.04500235387352f,  0.02005851806501f, 0.00302439095741f },
    { 1.f, -1.49858979367799f,  0.87350271418188f,  0.12205022308084f, -0.80774944671438f,  0.47854794562326f, -0.12453458140019f, -0.04067510197014f,  0.08333755284107f, -0.04237348025746f, 0.02977207319925f },
    { 1.f, -0.62820619233671f,  0.29661783706366f, -0.37256372942400f,  0.00213767857124f, -0.42029820170918f,  0.22199650564824f,  0.00613424350682f,  0.06747620744683f,  0.05784820375801f, 0.03222754072173f },
    { 1.f, -1.04800335126349f,  0.29156311971249f, -0.26806001042947f,  0.00819999645858f,  0.45054734505008f, -0.33032403314006f,  0.06739368333110f, -0.04784254229033f,  0.01639907836189f, 0.01807364323573f },
    { 1.f, -0.51035327095184f, -0.31863563325245f, -0.20256413484477f,  0.14728154134330f,  0.38952639978999f, -0.23313271880868f, -0.05246019024463f, -0.02505961724053f,  0.02442357316099f, 0.01818801111503f },
    { 1.f, -0.25049871956020f, -0.43193942311114f, -0.03424681017675f, -0.04678328784242f,  0.26408300200955f,  0.15113130533216f, -0.17556493366449f, -0.18823009262115f,  0.05477720428674f, 0.04704409688120f }
};

static const float  BYule [9] [11] = {
    { 0.03857599435200f, -0.02160367184185f, -0.00123395316851f, -0.00009291677959f, -0.01655260341619f,  0.02161526843274f, -0.02074045215285f,  0.00594298065125f,  0.00306428023191f,  0.00012025322027f,  0.00288463683916f },
    { 0.05418656406430f, -0.02911007808948f, -0.00848709379851f, -0.00851165645469f, -0.00834990904936f,  0.02245293253339f, -0.02596338512915f,  0.01624864962975f, -0.00240879051584f,  0.00674613682247f, -0.00187763777362f },
    { 0.15457299681924f, -0.09331049056315f, -0.06247880153653f,  0.02163541888798f, -0.05588393329856f,  0.04781476674921f,  0.00222312597743f,  0.03174092540049f, -0.01390589421898f,  0.00651420667831f, -0.00881362733839f },
    { 0.30296907319327f, -0.22613988682123f, -0.08587323730772f,  0.03282930172664f, -0.00915702933434f, -0.02364141202522f, -0.00584456039913f,  0.06276101321749f, -0.00000828086748f,  0.00205861885564f, -0.02950134983287f },
    { 0.33642304856132f, -0.25572241425570f, -0.11828570177555f,  0.11921148675203f, -0.07834489609479f, -0.00469977914380f, -0.00589500224440f,  0.05724228140351f,  0.00832043980773f, -0.01635381384540f, -0.01760176568150f },
    { 0.44915256608450f, -0.14351757464547f, -0.22784394429749f, -0.01419140100551f,  0.04078262797139f, -0.12398163381748f,  0.04097565135648f,  0.10478503600251f, -0.01863887810927f, -0.03193428438915f,  0.00541907748707f },
    { 0.56619470757641f, -0.75464456939302f,  0.16242137742230f,  0.16744243493672f, -0.18901604199609f,  0.30931782841830f, -0.27562961986224f,  0.00647310677246f,  0.08647503780351f, -0.03788984554840f, -0.00588215443421f },
    { 0.58100494960553f, -0.53174909058578f, -0.14289799034253f,  0.17520704835522f,  0.02377945217615f,  0.15558449135573f, -0.25344790059353f,  0.01628462406333f,  0.06920467763959f, -0.03721611395801f, -0.00749618797172f },
    { 0.53648789255105f, -0.42163034350696f, -0.00275953611929f,  0.04267842219415f, -0.10214864179676f,  0.14590772289388f, -0.02459864859345f, -0.11202315195388f, -0.04060034127000f,  0.04788665548180f, -0.02217936801134f }
};

static const float  AButter [9] [3] = {
    { 1.f, -1.97223372919527f, 0.97261396931306f },
    { 1.f, -1.96977855582618f, 0.97022847566350f },
    { 1.f, -1.95835380975398f, 0.95920349965459f },
    { 1.f, -1.95002759149878f, 0.95124613669835f },
    { 1.f, -1.94561023566527f, 0.94705070426118f },
    { 1.f, -1.92783286977036f, 0.93034775234268f },
    { 1.f, -1.91858953033784f, 0.92177618768381f },
    { 1.f, -1.91542108074780f, 0.91885558323625f },
    { 1.f, -1.88903307939452f, 0.89487434461664f }
};

static const float  BButter [9] [3] = {
    { 0.98621192462708f, -1.97242384925416f, 0.98621192462708f },
    { 0.98500175787242f, -1.97000351574484f, 0.98500175787242f },
    { 0.97938932735214f, -1.95877865470428f, 0.97938932735214f },
    { 0.97531843204928f, -1.95063686409857f, 0.97531843204928f },
    { 0.97316523498161f, -1.94633046996323f, 0.97316523498161f },
    { 0.96454515552826f, -1.92909031105652f, 0.96454515552826f },
    { 0.96009142950541f, -1.92018285901082f, 0.96009142950541f },
    { 0.95856916599601f, -1.91713833199203f, 0.95856916599601f },
    { 0.94597685600279f, -1.89195371200558f, 0.94597685600279f }
};

/* When calling this procedure, make sure that ip[-order] and op[-order] point to real data! */

static void
filter ( const float* input, float* output, size_t nSamples, const float* a, const float* b, size_t order )
{
    double  y;
    size_t  i;
    size_t  k;

    for ( i = 0; i < nSamples; i++ ) {
        y = input[i] * b[0];
        for ( k = 1; k <= order; k++ )
            y += input[i-k] * b[k] - output[i-k] * a[k];
        output[i] = (float)y;
    }
}

/* returns a INIT_GAIN_ANALYSIS_OK if successful, INIT_GAIN_ANALYSIS_ERROR if not */

int
replaygain_analysis_reset_sample_frequency ( struct replaygain_t *rg, long samplefreq ) {
	if(NULL == rg)
		return INIT_GAIN_ANALYSIS_ERROR;
	
    int  i;

    /* zero out initial values */
    for ( i = 0; i < MAX_ORDER; i++ )
        rg->linprebuf[i] = rg->lstepbuf[i] = rg->loutbuf[i] = rg->rinprebuf[i] = rg->rstepbuf[i] = rg->routbuf[i] = 0.f;

    switch ( (int)(samplefreq) ) {
        case 48000: rg->freqindex = 0; break;
        case 44100: rg->freqindex = 1; break;
        case 32000: rg->freqindex = 2; break;
        case 24000: rg->freqindex = 3; break;
        case 22050: rg->freqindex = 4; break;
        case 16000: rg->freqindex = 5; break;
        case 12000: rg->freqindex = 6; break;
        case 11025: rg->freqindex = 7; break;
        case  8000: rg->freqindex = 8; break;
        default:    return INIT_GAIN_ANALYSIS_ERROR;
    }

    rg->sampleWindow = (int) ceil (samplefreq * RMS_WINDOW_TIME);

    rg->lsum         = 0.;
    rg->rsum         = 0.;
    rg->totsamp      = 0;

    memset ( rg->A, 0, sizeof(rg->A) );

	return INIT_GAIN_ANALYSIS_OK;
}

int
replaygain_analysis_init ( struct replaygain_t *rg, long samplefreq )
{
	if (replaygain_analysis_reset_sample_frequency(rg, samplefreq) != INIT_GAIN_ANALYSIS_OK) {
		return INIT_GAIN_ANALYSIS_ERROR;
	}

    rg->linpre       = rg->linprebuf + MAX_ORDER;
    rg->rinpre       = rg->rinprebuf + MAX_ORDER;
    rg->lstep        = rg->lstepbuf  + MAX_ORDER;
    rg->rstep        = rg->rstepbuf  + MAX_ORDER;
    rg->lout         = rg->loutbuf   + MAX_ORDER;
    rg->rout         = rg->routbuf   + MAX_ORDER;

    memset ( rg->B, 0, sizeof(rg->B) );

    return INIT_GAIN_ANALYSIS_OK;
}

/* returns GAIN_ANALYSIS_OK if successful, GAIN_ANALYSIS_ERROR if not */

int
replaygain_analysis_analyze_samples ( struct replaygain_t *rg, const float* left_samples, const float* right_samples, size_t num_samples, int num_channels )
{
    const float*  curleft;
    const float*  curright;
    long            batchsamples;
    long            cursamples;
    long            cursamplepos;
    int             i;

    if ( num_samples == 0 )
        return GAIN_ANALYSIS_OK;

    cursamplepos = 0;
    batchsamples = num_samples;

    switch ( num_channels) {
    case  1: right_samples = left_samples;
    case  2: break;
    default: return GAIN_ANALYSIS_ERROR;
    }

    if ( num_samples < MAX_ORDER ) {
        memcpy ( rg->linprebuf + MAX_ORDER, left_samples , num_samples * sizeof(float) );
        memcpy ( rg->rinprebuf + MAX_ORDER, right_samples, num_samples * sizeof(float) );
    }
    else {
        memcpy ( rg->linprebuf + MAX_ORDER, left_samples,  MAX_ORDER   * sizeof(float) );
        memcpy ( rg->rinprebuf + MAX_ORDER, right_samples, MAX_ORDER   * sizeof(float) );
    }

    while ( batchsamples > 0 ) {
        cursamples = batchsamples > (long)(rg->sampleWindow-rg->totsamp)  ?  (long)(rg->sampleWindow - rg->totsamp)  :  batchsamples;
        if ( cursamplepos < MAX_ORDER ) {
            curleft  = rg->linpre+cursamplepos;
            curright = rg->rinpre+cursamplepos;
            if (cursamples > MAX_ORDER - cursamplepos )
                cursamples = MAX_ORDER - cursamplepos;
        }
        else {
            curleft  = left_samples  + cursamplepos;
            curright = right_samples + cursamplepos;
        }

        filter ( curleft , rg->lstep + rg->totsamp, cursamples, AYule[rg->freqindex], BYule[rg->freqindex], YULE_ORDER );
        filter ( curright, rg->rstep + rg->totsamp, cursamples, AYule[rg->freqindex], BYule[rg->freqindex], YULE_ORDER );

        filter ( rg->lstep + rg->totsamp, rg->lout + rg->totsamp, cursamples, AButter[rg->freqindex], BButter[rg->freqindex], BUTTER_ORDER );
        filter ( rg->rstep + rg->totsamp, rg->rout + rg->totsamp, cursamples, AButter[rg->freqindex], BButter[rg->freqindex], BUTTER_ORDER );

        for ( i = 0; i < cursamples; i++ ) {             /* Get the squared values */
            rg->lsum += rg->lout [rg->totsamp+i] * rg->lout [rg->totsamp+i];
            rg->rsum += rg->rout [rg->totsamp+i] * rg->rout [rg->totsamp+i];
        }

        batchsamples -= cursamples;
        cursamplepos += cursamples;
        rg->totsamp += cursamples;
        if ( rg->totsamp == rg->sampleWindow ) {  /* Get the Root Mean Square (RMS) for this set of samples */
            double  val  = STEPS_per_dB * 10. * log10 ( (rg->lsum+rg->rsum) / rg->totsamp * 0.5 + 1.e-37 );
            int     ival = (int) val;
            if ( ival <                     0 ) ival = 0;
            if ( ival >= (int)(sizeof(rg->A)/sizeof(*(rg->A))) ) ival = (int)(sizeof(rg->A)/sizeof(*(rg->A))) - 1;
            rg->A [ival]++;
            rg->lsum = rg->rsum = 0.;
            memmove ( rg->loutbuf , rg->loutbuf  + rg->totsamp, MAX_ORDER * sizeof(float) );
            memmove ( rg->routbuf , rg->routbuf  + rg->totsamp, MAX_ORDER * sizeof(float) );
            memmove ( rg->lstepbuf, rg->lstepbuf + rg->totsamp, MAX_ORDER * sizeof(float) );
            memmove ( rg->rstepbuf, rg->rstepbuf + rg->totsamp, MAX_ORDER * sizeof(float) );
            rg->totsamp = 0;
        }
        if ( rg->totsamp > rg->sampleWindow )   /* somehow I really screwed up: Error in programming! Contact author about totsamp > sampleWindow */
            return GAIN_ANALYSIS_ERROR;
    }
    if ( num_samples < MAX_ORDER ) {
        memmove ( rg->linprebuf,                           rg->linprebuf + num_samples, (MAX_ORDER-num_samples) * sizeof(float) );
        memmove ( rg->rinprebuf,                           rg->rinprebuf + num_samples, (MAX_ORDER-num_samples) * sizeof(float) );
        memcpy  ( rg->linprebuf + MAX_ORDER - num_samples, left_samples,          num_samples             * sizeof(float) );
        memcpy  ( rg->rinprebuf + MAX_ORDER - num_samples, right_samples,         num_samples             * sizeof(float) );
    }
    else {
        memcpy  ( rg->linprebuf, left_samples  + num_samples - MAX_ORDER, MAX_ORDER * sizeof(float) );
        memcpy  ( rg->rinprebuf, right_samples + num_samples - MAX_ORDER, MAX_ORDER * sizeof(float) );
    }

    return GAIN_ANALYSIS_OK;
}


static float
analyzeResult ( uint32_t* Array, size_t len )
{
    uint32_t  elems;
    int32_t   upper;
    size_t    i;

    elems = 0;
    for ( i = 0; i < len; i++ )
        elems += Array[i];
    if ( elems == 0 )
        return GAIN_NOT_ENOUGH_SAMPLES;

    upper = (int32_t) ceil (elems * (1. - RMS_PERCENTILE));
    for ( i = len; i-- > 0; ) {
        if ( (upper -= Array[i]) <= 0 )
            break;
    }

    return (float) ((float)PINK_REF - (float)i / (float)STEPS_per_dB);
}


float
replaygain_analysis_get_title_gain ( struct replaygain_t *rg )
{
	assert(NULL != rg);

    float  retval;
    unsigned int    i;

    retval = analyzeResult ( rg->A, sizeof(rg->A)/sizeof(*(rg->A)) );

    for ( i = 0; i < sizeof(rg->A)/sizeof(*(rg->A)); i++ ) {
        rg->B[i] += rg->A[i];
        rg->A[i]  = 0;
    }

    for ( i = 0; i < MAX_ORDER; i++ )
        rg->linprebuf[i] = rg->lstepbuf[i] = rg->loutbuf[i] = rg->rinprebuf[i] = rg->rstepbuf[i] = rg->routbuf[i] = 0.f;

    rg->totsamp = 0;
    rg->lsum    = rg->rsum = 0.;
    return retval;
}


float
replaygain_analysis_get_album_gain ( struct replaygain_t *rg )
{
	assert(NULL != rg);
    return analyzeResult ( rg->B, sizeof(rg->B)/sizeof(*(rg->B)) );
}

/* end of replaygain_analysis.c */
