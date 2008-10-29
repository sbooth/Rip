/*
 *  Copyright (C) 2005 - 2008 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import <Cocoa/Cocoa.h>

#include <DiskArbitration/DiskArbitration.h>
#include <IOKit/storage/IOCDTypes.h>

@class SessionDescriptor, TrackDescriptor, SectorRange, AccurateRipDiscRecord, AlbumMetadata, ImageExtractionRecord;

// ========================================
// This class simplifies access to a CDDA disc
// ========================================
@interface CompactDisc : NSManagedObject
{
}

// ========================================
// Creation
+ (id) compactDiscWithDADiskRef:(DADiskRef)disk inManagedObjectContext:(NSManagedObjectContext *)managedObjectContext;
+ (id) compactDiscWithCDTOC:(NSData *)tocData inManagedObjectContext:(NSManagedObjectContext *)managedObjectContext;

// ========================================
// Core Data properties
@property (assign) NSData * discTOC;
@property (assign) NSString * musicBrainzDiscID;

// ========================================
// Core Data relationships
@property (assign) NSSet * accurateRipDiscs;
@property (assign) NSSet * extractedImages;
@property (assign) AlbumMetadata * metadata;
@property (assign) NSSet * sessions;

// ========================================
// Other properties
@property (readonly) NSArray * orderedSessions;
@property (readonly) SessionDescriptor * firstSession;
@property (readonly) SessionDescriptor * lastSession;

// ========================================
// Computed properties
@property (readonly) NSUInteger freeDBDiscID;
@property (readonly) NSUInteger accurateRipID1;
@property (readonly) NSUInteger accurateRipID2;

// ========================================

- (SessionDescriptor *) sessionNumber:(NSUInteger)number;
- (TrackDescriptor *) trackNumber:(NSUInteger)number;

@end

// ========================================
// KVC accessors
@interface CompactDisc (CoreDataGeneratedAccessors)
- (void) addSessionsObject:(SessionDescriptor *)value;
- (void) removeSessionsObject:(SessionDescriptor *)value;
- (void) addSessions:(NSSet *)value;
- (void) removeSessions:(NSSet *)value;

- (void) addAccurateRipDiscsObject:(AccurateRipDiscRecord *)value;
- (void) removeAccurateRipDiscsObject:(AccurateRipDiscRecord *)value;
- (void) addAccurateRipDiscs:(NSSet *)value;
- (void) removeAccurateRipDiscs:(NSSet *)value;

- (void) addExtractedImagesObject:(ImageExtractionRecord *)value;
- (void) removeExtractedImagesObject:(ImageExtractionRecord *)value;
- (void) addExtractedImages:(NSSet *)value;
- (void) removeExtractedImages:(NSSet *)value;

@end
