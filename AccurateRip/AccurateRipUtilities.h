/*
 *  Copyright (C) 2007 - 2009 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#pragma once

#include <Foundation/Foundation.h>

// Calculate the AccurateRip checksum for the file at path
uint32_t calculateAccurateRipChecksumForFile(NSURL *fileURL, BOOL isFirstTrack, BOOL isLastTrack);

// Calculate the AccurateRip checksum for the specified range of CDDA sectors file at path
uint32_t calculateAccurateRipChecksumForFileRegion(NSURL *fileURL, NSRange sectorsToProcess, BOOL isFirstTrack, BOOL isLastTrack);

// Calculate the AccurateRip checksum for the specified range of CDDA sectors file at path using the specified offset
uint32_t calculateAccurateRipChecksumForFileRegionUsingOffset(NSURL *fileURL, NSRange sectorsToProcess, BOOL isFirstTrack, BOOL isLastTrack, NSInteger readOffsetInFrames);

// Generate the AccurateRip checksum for a sector (2352 bytes) of CDDA audio
uint32_t calculateAccurateRipChecksumForBlock(const void *block, NSUInteger blockNumber, NSUInteger totalBlocks, BOOL isFirstTrack, BOOL isLastTrack);

// Calculate the AccurateRip checksums for the file at path
NSData * calculateAccurateRipChecksumsForFile(NSURL *fileURL, NSRange trackSectors, BOOL isFirstTrack, BOOL isLastTrack, NSUInteger maximumOffsetInBlocks);
