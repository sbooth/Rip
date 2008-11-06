/*
 *  Copyright (C) 2005 - 2008 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import <Cocoa/Cocoa.h>
#include <DiskArbitration/DiskArbitration.h>

@class ImageExtractionRecord, TrackExtractionRecord;

// ========================================
// This class represents the information available about an IOKit device that can read IOCDMedia, 
// along with the read offset stored for the device.
// ========================================
@interface DriveInformation : NSManagedObject
{	
@private
	NSDictionary *_deviceProperties;
}

// ========================================
// Creation
+ (id) driveInformationWithDADiskRef:(DADiskRef)disk inManagedObjectContext:(NSManagedObjectContext *)managedObjectContext;

// ========================================
// Core Data properties
@property (assign) NSString * deviceIdentifier;
@property (assign) NSNumber * readOffset;
@property (assign) NSNumber * useC2;

// ========================================
// Core Data relationships
@property (assign) NSSet * extractedImages;
@property (assign) NSSet * extractedTracks;

// ========================================
// Other properties
@property (readonly, assign) NSDictionary * deviceProperties;

// ========================================
// Device Characteristics
@property (readonly) NSString * vendorName;
@property (readonly) NSString * productName;
@property (readonly) NSString * productRevisionLevel;
@property (readonly) NSData * productSerialNumber;
@property (readonly) NSNumber * supportedCDFeatures;
@property (readonly) NSNumber * hasAccurateStream;

// ========================================
// Protocol Characteristics
@property (readonly) NSString * physicalInterconnectType;
@property (readonly) NSString * physicalInterconnectLocation;

@end

// ========================================
// KVC accesors
@interface DriveInformation (CoreDataGeneratedAccessors)
- (void) addExtractedImagesObject:(ImageExtractionRecord *)value;
- (void) removeExtractedImagesObject:(ImageExtractionRecord *)value;
- (void) addExtractedImages:(NSSet *)value;
- (void) removeExtractedImages:(NSSet *)value;

- (void) addExtractedTracksObject:(TrackExtractionRecord *)value;
- (void) removeExtractedTracksObject:(TrackExtractionRecord *)value;
- (void) addExtractedTracks:(NSSet *)value;
- (void) removeExtractedTracks:(NSSet *)value;
@end
