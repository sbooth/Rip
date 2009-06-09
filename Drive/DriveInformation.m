/*
 *  Copyright (C) 2005 - 2009 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import "DriveInformation.h"
#import "DiskUtilities.h"

#include <IOKit/storage/IOStorageDeviceCharacteristics.h>

#include <IOKit/storage/IOCDMedia.h>
#include <IOKit/storage/IOCDTypes.h>

#include <IOKit/scsi/SCSITaskLib.h>
#include <IOKit/scsi/IOSCSIMultimediaCommandsDevice.h>

#include <IOKit/usb/USB.h>

@interface DriveInformation ()
@property (assign) NSDictionary * deviceProperties;
@end

@interface DriveInformation (Private)
- (id) valueInDeviceCharacteristicsDictionaryForKey:(NSString *)key;
- (id) valueInProtocolCharacteristicsDictionaryForKey:(NSString *)key;
@end

@implementation DriveInformation

// ========================================
// Creation
+ (id) driveInformationWithDADiskRef:(DADiskRef)disk inManagedObjectContext:(NSManagedObjectContext *)managedObjectContext
{
	NSParameterAssert(NULL != disk);
	NSParameterAssert(nil != managedObjectContext);
	
	NSString *deviceIdentifier = getDeviceIdentifierForDADiskRef(disk);
	if(!deviceIdentifier)
		return nil;
	
	NSEntityDescription *entityDescription = [NSEntityDescription entityForName:@"DriveInformation"
														 inManagedObjectContext:managedObjectContext];
	NSFetchRequest *fetchRequest = [[NSFetchRequest alloc] init];
	
	[fetchRequest setEntity:entityDescription];
	[fetchRequest setFetchLimit:1];
	
	NSPredicate *fetchPredicate = [NSPredicate predicateWithFormat:@"deviceIdentifier == %@", deviceIdentifier];
	[fetchRequest setPredicate:fetchPredicate];
	
	NSError *error = nil;
	NSArray *matchingDrives = [managedObjectContext executeFetchRequest:fetchRequest error:&error];
	if(!matchingDrives) {
		// Deal with error...
		return nil;
	}
	
	DriveInformation *driveInformation = nil;
	if(0 == matchingDrives.count) {
		driveInformation = [NSEntityDescription insertNewObjectForEntityForName:@"DriveInformation"
														 inManagedObjectContext:managedObjectContext];
		
		driveInformation.deviceIdentifier = deviceIdentifier;
	}
	else
		driveInformation = matchingDrives.lastObject;
	
	// Extract the device properties
	driveInformation.deviceProperties = getDevicePropertiesForDADiskRef(disk);
	
	return driveInformation;
}

// ========================================
// Core Data properties
@dynamic deviceIdentifier;
@dynamic readOffset;
@dynamic useC2;

// ========================================
// Core Data relationships
@dynamic extractedImages;
@dynamic extractedTracks;

// ========================================
// Other properties
@synthesize deviceProperties = _deviceProperties;

// Device Characteristics
- (NSString *) vendorName
{
	return [self valueInDeviceCharacteristicsDictionaryForKey:@ kIOPropertyVendorNameKey];
}

- (NSString *) productName
{
	return [self valueInDeviceCharacteristicsDictionaryForKey:@ kIOPropertyProductNameKey];
}

- (NSString *) productRevisionLevel
{
	return [self valueInDeviceCharacteristicsDictionaryForKey:@ kIOPropertyProductRevisionLevelKey];
}

- (NSData *) productSerialNumber
{
	return [self valueInDeviceCharacteristicsDictionaryForKey:@ kIOPropertyProductSerialNumberKey];
}

- (NSNumber *) supportedCDFeatures
{
	return [self valueInDeviceCharacteristicsDictionaryForKey:@ kIOPropertySupportedCDFeaturesKey];
}

- (NSNumber *) hasAccurateStream
{
	NSNumber *supportedCDFeatures = self.supportedCDFeatures;
	if(supportedCDFeatures)
		return [NSNumber numberWithBool:(0 != (kCDFeaturesCDDAStreamAccurateMask & [supportedCDFeatures integerValue]))];
	else
		return nil;
}

// Protocol Characteristics
- (NSString *) physicalInterconnectType
{
	NSString *physicalInterconnectType = [self valueInProtocolCharacteristicsDictionaryForKey:@ kIOPropertyPhysicalInterconnectTypeKey];
	
	if(physicalInterconnectType) {
		if([physicalInterconnectType isEqualToString:@ kIOPropertyPhysicalInterconnectTypeATA])
			return NSLocalizedString(@"ATA", @"kIOPropertyPhysicalInterconnectTypeATA");
		else if([physicalInterconnectType isEqualToString:@ kIOPropertyPhysicalInterconnectTypeSerialATA])
			return NSLocalizedString(@"Serial ATA", @"kIOPropertyPhysicalInterconnectTypeSerialATA");
		else if([physicalInterconnectType isEqualToString:@ kIOPropertyPhysicalInterconnectTypeSerialAttachedSCSI])
			return NSLocalizedString(@"SAS", @"kIOPropertyPhysicalInterconnectTypeSerialAttachedSCSI");
		else if([physicalInterconnectType isEqualToString:@ kIOPropertyPhysicalInterconnectTypeATAPI])
			return NSLocalizedString(@"ATAPI", @"kIOPropertyPhysicalInterconnectTypeATAPI");
		else if([physicalInterconnectType isEqualToString:@ kIOPropertyPhysicalInterconnectTypeUSB])
			return NSLocalizedString(@"USB", @"kIOPropertyPhysicalInterconnectTypeUSB");
		else if([physicalInterconnectType isEqualToString:@ kIOPropertyPhysicalInterconnectTypeFireWire])
			return NSLocalizedString(@"FireWire", @"kIOPropertyPhysicalInterconnectTypeFireWire");
		else if([physicalInterconnectType isEqualToString:@ kIOPropertyPhysicalInterconnectTypeSCSIParallel])
			return NSLocalizedString(@"SCSI Parallel Interface", @"kIOPropertyPhysicalInterconnectTypeSCSIParallel");
		else if([physicalInterconnectType isEqualToString:@ kIOPropertyPhysicalInterconnectTypeFibreChannel])
			return NSLocalizedString(@"Fibre Channel Interface", @"kIOPropertyPhysicalInterconnectTypeFibreChannel");
		else if([physicalInterconnectType isEqualToString:@ kIOPropertyPhysicalInterconnectTypeVirtual])
			return NSLocalizedString(@"Virtual Interface", @"kIOPropertyPhysicalInterconnectTypeVirtual");
		else
			return physicalInterconnectType;
	}
	else
		return nil;
	
}

- (NSString *) physicalInterconnectLocation
{
	NSString *physicalInterconnectLocation = [self valueInProtocolCharacteristicsDictionaryForKey:@ kIOPropertyPhysicalInterconnectLocationKey];
	
	if(physicalInterconnectLocation) {
		if([physicalInterconnectLocation isEqualToString:@ kIOPropertyInternalKey])
			return NSLocalizedString(@"Internal", @"kIOPropertyInternalKey");
		else if([physicalInterconnectLocation isEqualToString:@ kIOPropertyExternalKey])
			return NSLocalizedString(@"External", @"kIOPropertyExternalKey");
		else if([physicalInterconnectLocation isEqualToString:@ kIOPropertyInternalExternalKey])
			return NSLocalizedString(@"Internal/External", @"kIOPropertyInternalExternalKey");
		else if([physicalInterconnectLocation isEqualToString:@ kIOPropertyInterconnectFileKey])
			return NSLocalizedString(@"File", @"kIOPropertyInterconnectFileKey");
		else if([physicalInterconnectLocation isEqualToString:@ kIOPropertyInterconnectRAMKey])
			return NSLocalizedString(@"RAM", @"kIOPropertyInterconnectRAMKey");
		else
			return physicalInterconnectLocation;
	}
	else
		return nil;
}

@end

@implementation DriveInformation (Private)

- (id) valueInDeviceCharacteristicsDictionaryForKey:(NSString *)key
{
	NSParameterAssert(nil != key);
	
	NSDictionary *deviceCharacteristics = [self.deviceProperties objectForKey:@ kIOPropertyDeviceCharacteristicsKey];	
	return [deviceCharacteristics objectForKey:key];
}

- (id) valueInProtocolCharacteristicsDictionaryForKey:(NSString *)key;
{
	NSParameterAssert(nil != key);
	
	NSDictionary *protocolCharacteristics = [self.deviceProperties objectForKey:@ kIOPropertyProtocolCharacteristicsKey];	
	return [protocolCharacteristics objectForKey:key];
}

@end
