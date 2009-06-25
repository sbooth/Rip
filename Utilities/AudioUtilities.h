/*
 *  Copyright (C) 2008 - 2009 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#pragma once

#import <Cocoa/Cocoa.h>

// ========================================
// Create an audio file containing CDDA audio at the specified URL
// ========================================
BOOL createCDDAFileAtURL(NSURL *fileURL, NSError **error);

// ========================================
// Copy sectors from one file to another
// ========================================
BOOL copyAllSectorsFromURLToURL(NSURL *inputURL, NSURL *outputURL, NSUInteger outputLocation);
BOOL copySectorsFromURLToURL(NSURL *inputURL, NSRange sectorsToCopy, NSURL *outputURL, NSUInteger outputLocation);

// ========================================
// Compare two files for differences
// ========================================
NSIndexSet * compareFilesForNonMatchingSectors(NSURL *leftFileURL, NSURL *rightFileURL);

NSIndexSet * compareFileRegionsForNonMatchingSectors(NSURL *leftFileURL, NSUInteger leftFileStartingSectorOffset,
													 NSURL *rightFileURL, NSUInteger rightFileStartingSectorOffset, 
													 NSUInteger sectorCount);

BOOL sectorInFilesMatches(NSURL *leftFileURL, NSUInteger leftFileSectorOffset,
						  NSURL *rightFileURL, NSUInteger rightFileSectorOffset);

// ========================================
// Calculate the MD5 digest for the audio portion of the specified file
// ========================================
NSString * calculateMD5DigestForURL(NSURL *fileURL);
NSString * calculateMD5DigestForURLRegion(NSURL *fileURL, NSUInteger startingSector, NSUInteger sectorCount);

// ========================================
// Calculate the SHA1 digest for the audio portion of the specified file
// ========================================
NSString * calculateSHA1DigestForURL(NSURL *fileURL);
NSString * calculateSHA1DigestForURLRegion(NSURL *fileURL, NSUInteger startingSector, NSUInteger sectorCount);

// ========================================
// Calculate the MD5 and SHA1 digests for the audio portion of the specified file
// The MD5 checksum (NSString *) will be object 0 in the returned array
// The SHA1 hash (NSString *) will be object 1 in the returned array
// ========================================
NSArray * calculateMD5AndSHA1DigestsForURL(NSURL *fileURL);
NSArray * calculateMD5AndSHA1DigestsForURLRegion(NSURL *fileURL, NSUInteger startingSector, NSUInteger sectorCount);
