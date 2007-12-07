/*
 *  $Id$
 *  Copyright (C) 2005 - 2007 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import <Cocoa/Cocoa.h>

#include <DiskArbitration/DiskArbitration.h>
#include <IOKit/storage/IOCDTypes.h>

@class SectorRange, SessionDescriptor, TrackDescriptor;

// ========================================
// This class simplifies access to CDTOC information
// ========================================
@interface CompactDisc : NSObject <NSCopying>
{
	NSMutableArray *_sessions;
	NSMutableArray *_tracks;
	
	NSUInteger _firstSession;
	NSUInteger _lastSession;
}

@property (readonly) NSInteger freeDBID;
@property (readonly, assign) NSUInteger firstSession;
@property (readonly, assign) NSUInteger lastSession;
@property (readonly) NSArray * sessions;
@property (readonly) NSArray * tracks;

// ========================================
// Create a CompactDisc with the specified CDTOC
- (id) initWithDADiskRef:(DADiskRef)disk;
- (id) initWithCDTOC:(CDTOC *)toc;

// ========================================
// Disc session information
- (SessionDescriptor *) sessionNumber:(NSUInteger)number;

- (NSUInteger) firstTrackForSession:(NSUInteger)session;
- (NSUInteger) lastTrackForSession:(NSUInteger)session;

// ========================================
// Session sector information
- (NSUInteger) firstSectorForSession:(NSUInteger)session;
- (NSUInteger) lastSectorForSession:(NSUInteger)session;

- (NSUInteger) leadOutForSession:(NSUInteger)session;

- (NSUInteger) sessionContainingSector:(NSUInteger)sector;
- (NSUInteger) sessionContainingSectorRange:(SectorRange *)sectorRange;

// ========================================
// Disc track information
- (TrackDescriptor *) trackNumber:(NSUInteger)number;
- (NSArray *) tracksForSession:(NSUInteger)session;

// ========================================
// Track sector information
- (NSUInteger) firstSectorForTrack:(NSUInteger)number;
- (NSUInteger) lastSectorForTrack:(NSUInteger)number;

@end
