/*
 *  Copyright (C) 2007 - 2008 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#pragma once

#include <Foundation/Foundation.h>

// Calculate the AccurateRip checksum for the file at path
uint32_t calculateAccurateRipChecksumForFile(NSURL *fileURL, BOOL firstTrack, BOOL lastTrack);

// Calculate the AccurateRip checksum for the specified range of CDDA sectors file at path
uint32_t calculateAccurateRipChecksumForFileRegion(NSURL *fileURL, NSRange sectorsToProcess, BOOL firstTrack, BOOL lastTrack);

// Calculate the AccurateRip checksum for the specified range of CDDA sectors file at path using the specified offset
uint32_t calculateAccurateRipChecksumForFileRegionUsingOffset(NSURL *fileURL, NSRange sectorsToProcess, BOOL firstTrack, BOOL lastTrack, NSInteger readOffsetInFrames);

// Generate the AccurateRip checksum for a sector (2352 bytes) of CDDA audio
uint32_t calculateAccurateRipChecksumForBlock(const void *block, NSUInteger blockNumber, NSUInteger totalBlocks, BOOL firstTrack, BOOL lastTrack);
