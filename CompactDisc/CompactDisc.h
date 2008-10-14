/*
 *  Copyright (C) 2005 - 2007 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import <Cocoa/Cocoa.h>

#include <DiskArbitration/DiskArbitration.h>
#include <IOKit/storage/IOCDTypes.h>

@class SessionDescriptor, TrackDescriptor, SectorRange, AccurateRipDiscRecord, AlbumMetadata, ExtractionRecord;

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
@property (assign) NSNumber * freeDBDiscID;

// ========================================
// Core Data relationships
@property (assign) NSSet * accurateRipDiscs;
@property (assign) AlbumMetadata * metadata;
@property (assign) NSSet * sessions;
@property (assign) NSSet * extractionRecords;

// ========================================
// Other properties
@property (readonly) NSArray * orderedSessions;
@property (readonly) SessionDescriptor * firstSession;
@property (readonly) SessionDescriptor * lastSession;

// ========================================
// Computed properties
@property (readonly) NSString * musicBrainzDiscID;
@property (readonly) NSUInteger accurateRipID1;
@property (readonly) NSUInteger accurateRipID2;

// ========================================

- (SessionDescriptor *) sessionNumber:(NSUInteger)number;
- (TrackDescriptor *) trackNumber:(NSUInteger)number;

@end

@interface CompactDisc (CoreDataGeneratedAccessors)
- (void) addSessionsObject:(SessionDescriptor *)value;
- (void) removeSessionsObject:(SessionDescriptor *)value;
- (void) addSessions:(NSSet *)value;
- (void) removeSessions:(NSSet *)value;

- (void) addAccurateRipDiscsObject:(AccurateRipDiscRecord *)value;
- (void) removeAccurateRipDiscsObject:(AccurateRipDiscRecord *)value;
- (void) addAccurateRipDiscs:(NSSet *)value;
- (void) removeAccurateRipDiscs:(NSSet *)value;

- (void) addExtractionRecordsObject:(ExtractionRecord *)value;
- (void) removeExtractionRecordsObject:(ExtractionRecord *)value;
- (void) addExtractionRecords:(NSSet *)value;
- (void) removeExtractionRecords:(NSSet *)value;
@end
