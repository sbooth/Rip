/*
 *  Copyright (C) 2008 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#pragma once

#import <Cocoa/Cocoa.h>

// ========================================
// Compare two files for differences
// ========================================
NSIndexSet * compareFilesForNonMatchingSectors(NSURL *leftFileURL, NSURL *rightFileURL, NSError **error);

NSIndexSet * compareFileRegionsForNonMatchingSectors(NSURL *leftFileURL, NSUInteger leftFileStartingSectorOffset,
													 NSURL *rightFileURL, NSUInteger rightFileStartingSectorOffset, 
													 NSUInteger sectorCount, 
													 NSError **error);

// ========================================
// Calculate the MD5 digest for the audio portion of the specified file
// ========================================
NSString * calculateMD5DigestForURL(NSURL *fileURL, NSError **error);

// ========================================
// Calculate the SHA1 digest for the audio portion of the specified file
// ========================================
NSString * calculateSHA1DigestForURL(NSURL *fileURL, NSError **error);

// ========================================
// Calculate the MD5 and SHA1 digests for the audio portion of the specified file
// The MD5 checksum (NSString *) will be object 0 in the returned array
// The SH1 hash (NSString *) will be object 1 in the returned array
// ========================================
NSArray * calculateMD5AndSHA1DigestsForURL(NSURL *fileURL, NSError **error);
