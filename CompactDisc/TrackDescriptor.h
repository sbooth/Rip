/*
 *  $Id$
 *  Copyright (C) 2005 - 2007 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import <Cocoa/Cocoa.h>

// ========================================
// Utility class encapsulating useful information about
// a single track on a CDDA disk
// ========================================
@interface TrackDescriptor : NSObject <NSCopying>
{
	NSUInteger _session;
	NSUInteger _number;
	NSUInteger _firstSector;
	NSUInteger _channels;
	BOOL _preEmphasis;
	BOOL _copyPermitted;
	BOOL _dataTrack;
}

@property (assign) NSUInteger session;
@property (assign) NSUInteger number;
@property (assign) NSUInteger firstSector;
@property (assign) NSUInteger channels;
@property (assign) BOOL preEmphasis;
@property (assign) BOOL copyPermitted;
@property (assign) BOOL dataTrack;

@end
