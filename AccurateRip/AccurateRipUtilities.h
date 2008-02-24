/*
 *  Copyright (C) 2007 - 2008 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#pragma once

#include <Foundation/Foundation.h>

// Calculate the AccurateRip checksum for the file at path
uint32 calculateAccurateRipChecksumForFile(NSString *path, BOOL firstTrack, BOOL lastTrack);

// Calculate the AccurateRip checksum for the specified range of CDDA sectors file at path
uint32 calculateAccurateRipChecksumForFileRegion(NSString *path, NSUInteger firstSector, NSUInteger lastSector, BOOL firstTrack, BOOL lastTrack);

// Generate the AccurateRip checksum for a sector (2352 bytes) of CDDA audio
uint32_t calculateAccurateRipChecksumForBlock(const void *block, NSUInteger blockNumber, NSUInteger totalBlocks, BOOL firstTrack, BOOL lastTrack);
