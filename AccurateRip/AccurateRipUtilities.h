/*
 *  Copyright (C) 2007 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#pragma once

#include <Foundation/Foundation.h>

// Calculate and AccurateRip CRC for the file at path (must be raw 16-bit little-endian signed PCM)
uint32 calculateAccurateRipCRCForFile(NSString *path, BOOL firstTrack, BOOL lastTrack);

// Generate an AccurateRip CRC for a sector (2352 bytes) of CDDA audio
uint32_t calculateAccurateRipCRCForBlock(const void *block, NSUInteger blockNumber, NSUInteger totalBlocks, BOOL firstTrack, BOOL lastTrack);
