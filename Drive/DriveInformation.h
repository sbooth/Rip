/*
 *  Copyright (C) 2005 - 2007 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import <Cocoa/Cocoa.h>
#include <DiskArbitration/DiskArbitration.h>

// ========================================
// This class represents the information available about an IOKit
// device that can read IOCDMedia, along with the read offset
// stored for the device.
// ========================================
@interface DriveInformation : NSObject <NSCopying>
{
	DADiskRef _disk;
	NSDictionary *_deviceProperties;
}

@property (readonly, assign) DADiskRef disk;
@property (readonly, copy) NSDictionary * deviceProperties;

@property (readonly) NSData * deviceIdentifier;
@property (copy) NSNumber * readOffset;

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

- (id) initWithDADiskRef:(DADiskRef)disk;

@end
