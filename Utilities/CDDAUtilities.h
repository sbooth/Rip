/*
 *  Copyright (C) 2007 - 2009 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#pragma once

#include <CoreAudio/CoreAudioTypes.h>
#include <IOKit/storage/IOCDTypes.h>

// ========================================
// Useful macros
// ========================================
#define AUDIO_FRAMES_PER_CDDA_SECTOR	588
#define CDDA_SECTORS_PER_SECOND			75
#define CDDA_SAMPLE_RATE				44100
#define CDDA_CHANNELS_PER_FRAME			2
#define CDDA_BITS_PER_CHANNEL			16

// ========================================
// Create an AudioStreamBasicDescription that describes CDDA audio
// ========================================
AudioStreamBasicDescription getStreamDescriptionForCDDA(void);

// ========================================
// Verify an AudioStreamBasicDescription describes CDDA audio
// ========================================
BOOL streamDescriptionIsCDDA(const AudioStreamBasicDescription *asbd);

// ========================================
// Utility function for adding/subtracting CDMSF structures
// addCDMSF returns a + b
// subtractCDMSF returns a - b
// ========================================
CDMSF addCDMSF(CDMSF a, CDMSF b);
CDMSF subtractCDMSF(CDMSF a, CDMSF b);
