/*
 *  $Id$
 *  Copyright (C) 2005 - 2007 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import <Cocoa/Cocoa.h>

// ========================================
// Utility class encapsulating useful information about
// a single session on a CDDA disk
// ========================================
@interface SessionDescriptor : NSObject <NSCopying>
{
	NSUInteger _number;
	NSUInteger _firstTrack;
	NSUInteger _lastTrack;
	NSUInteger _leadOut;
}

@property (assign) NSUInteger number;
@property (assign) NSUInteger firstTrack;
@property (assign) NSUInteger lastTrack;
@property (assign) NSUInteger leadOut;

@end
