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

NSArray * compareFileRegionsForNonMatchingSectors(NSURL *leftFileURL, NSUInteger leftFileStartingSectorOffset,
												  NSURL *rightFileURL, NSUInteger rightFileStartingSectorOffset, 
												  NSUInteger sectorCount, 
												  NSError **error);
