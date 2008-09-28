/*
 *  Copyright (C) 2005 - 2007 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import <Cocoa/Cocoa.h>

@class SessionDescriptor, SectorRange;
@class TrackMetadata;

// ========================================
// This class encapsulates useful information about a single track on a CDDA disc
// and its associated metadata
// ========================================
@interface TrackDescriptor : NSManagedObject
{
}

// ========================================
// Core Data properties
@property (assign) NSNumber * channelsPerFrame;
@property (assign) NSNumber * digitalCopyPermitted;
@property (assign) NSNumber * firstSector;
@property (assign) NSNumber * hasPreEmphasis;
@property (assign) NSNumber * isDataTrack;
@property (assign) NSNumber * isSelected; // Transient
@property (assign) NSNumber * lastSector;
@property (assign) NSNumber * number;
@property (assign) NSNumber * pregap;

// ========================================
// Core Data relationships
@property (assign) TrackMetadata * metadata;
@property (assign) SessionDescriptor * session;

// ========================================
// Computed properties
@property (readonly) NSUInteger sectorCount;
@property (readonly) SectorRange * sectorRange;

@end
