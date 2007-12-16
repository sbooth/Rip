/*
 *  Copyright (C) 2007 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#pragma once

#include <Foundation/Foundation.h>

// Calculate the AccurateRip CRC for the file at path
uint32 calculateAccurateRipCRCForFile(NSString *path, BOOL firstTrack, BOOL lastTrack);

// Calculate the AccurateRip CRC for the specified range of CDDA sectors file at path
uint32 calculateAccurateRipCRCForFileRegion(NSString *path, NSUInteger firstSector, NSUInteger lastSector, BOOL firstTrack, BOOL lastTrack);

// Generate the AccurateRip CRC for a sector (2352 bytes) of CDDA audio
uint32_t calculateAccurateRipCRCForBlock(const void *block, NSUInteger blockNumber, NSUInteger totalBlocks, BOOL firstTrack, BOOL lastTrack);
