/*
 *  Copyright (C) 2007 - 2008 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#include <CoreAudio/CoreAudioTypes.h>
#include <IOKit/storage/IOCDTypes.h>

// ========================================
// Useful macros
// ========================================
#define AUDIO_FRAMES_PER_CDDA_SECTOR	588
#define CDDA_SECTORS_PER_SECOND			75

// ========================================
// Create an AudioStreamBasicDescription that describes CDDA audio
// ========================================
AudioStreamBasicDescription getStreamDescriptionForCDDA();

// ========================================
// Verify an AudioStreamBasicDescription describes CDDA audio
// ========================================
BOOL streamDescriptionIsCDDA(const AudioStreamBasicDescription *asbd);

// ========================================
// Utility function for adding CDMSF structures
// ========================================
CDMSF addCDMSF(CDMSF a, CDMSF b);
