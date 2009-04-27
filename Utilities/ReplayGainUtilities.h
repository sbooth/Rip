/*
 *  Copyright (C) 2009 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#pragma once

#import <Cocoa/Cocoa.h>
#include "replaygain_analysis.h"

// ========================================
// Compare two files for differences
// ========================================
BOOL addReplayGainDataForTrack(struct replaygain_t *rg, NSURL *fileURL);
