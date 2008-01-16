/*
 *  Copyright (C) 2005 - 2008 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import "DriveInformation.h"

#include <IOKit/storage/IOStorageDeviceCharacteristics.h>

#include <IOKit/storage/IOCDMedia.h>
#include <IOKit/storage/IOCDTypes.h>

#include <IOKit/scsi/SCSITaskLib.h>
#include <IOKit/scsi/IOSCSIMultimediaCommandsDevice.h>

#include <IOKit/usb/USB.h>

// ========================================
// Utility function that extracts the device identifier from a DADiskRef
// ========================================
static NSString * getDeviceIdentifierForDADiskRef(DADiskRef disk)
{
	NSCParameterAssert(NULL != disk);
	
	CFDictionaryRef description = DADiskCopyDescription(disk);
	
	// For USB devices, use kUSBDevicePropertyLocationID (A CFNumber) as the identifier
	// For all other devices, such as ATAPI, use the IOPath as the identifier

	NSString *deviceIdentifier = nil;
	
	// Extract the IOPath for the device containing this DADiskRef
	CFStringRef ioPath = CFDictionaryGetValue(description, kDADiskDescriptionDevicePathKey);
	if(ioPath)
		deviceIdentifier = [NSString stringWithString:(NSString *)ioPath];	
	else
		NSLog(@"No value for kDADiskDescriptionDevicePathKey in DADiskRef description");

	CFRelease(description);

	return deviceIdentifier;
}

// ========================================
// Utility function that extracts the device properties for a drive via a DADiskRef
// ========================================
static NSDictionary * getDevicePropertiesForDADiskRef(DADiskRef disk)
{
	NSCParameterAssert(NULL != disk);
	
	CFDictionaryRef description = DADiskCopyDescription(disk);
	
	// Extract the IOPath for the device containing this DADiskRef
	CFStringRef ioPath = CFDictionaryGetValue(description, kDADiskDescriptionDevicePathKey);
	if(NULL == ioPath) {
		NSLog(@"No value for kDADiskDescriptionDevicePathKey in DADiskRef description");
		
		CFRelease(description);
		
		return nil;
	}
	
	// Create a dictionary which will match the IOPath to an io_service_t object
	CFMutableDictionaryRef matchDictionary = CFDictionaryCreateMutable(kCFAllocatorDefault, 0, &kCFCopyStringDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
	if(NULL == matchDictionary) {
		NSLog(@"Unable to create a CFMutableDictionaryRef for kIOPathMatchKey matching");
		
		CFRelease(description);
		
		return nil;
	}
	
	CFDictionarySetValue(matchDictionary, CFSTR(kIOPathMatchKey), ioPath);
	
	// Obtain the matching device's io_service_t object
	// IOServiceGetMatchingService will consume one reference to matchDictionary
	io_service_t service = IOServiceGetMatchingService(kIOMasterPortDefault, matchDictionary);
	if(IO_OBJECT_NULL == service) {
		NSLog(@"No matching io_service_t found for IOPath %@", ioPath);
		
		CFRelease(description);
		
		return nil;
	}
	
	// Query the device's properties
	CFMutableDictionaryRef deviceProperties = NULL;
	IOReturn err = IORegistryEntryCreateCFProperties(service, &deviceProperties, kCFAllocatorDefault, 0);
	if(kIOReturnSuccess != err) {
		NSLog(@"Unable to get properties for device (IORegistryEntryCreateCFProperties returned 0x%.8x)", err);
		
		CFRelease(description);
		IOObjectRelease(service);
		
		return nil;
	}
	
	NSDictionary *devicePropertiesDictionary = [NSDictionary dictionaryWithDictionary:(NSDictionary *)deviceProperties];
	
	// Clean up
	CFRelease(deviceProperties);
	IOObjectRelease(service);
	CFRelease(description);
	
	return devicePropertiesDictionary;
}

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
+ (id) driveInformationWithDADiskRef:(DADiskRef)disk
{
	NSParameterAssert(NULL != disk);
	
	NSString *deviceIdentifier = getDeviceIdentifierForDADiskRef(disk);
	if(nil == deviceIdentifier)
		return nil;
	
	NSManagedObjectContext *managedObjectContext = [[[NSApplication sharedApplication] delegate] managedObjectContext];
	NSEntityDescription *entityDescription = [NSEntityDescription entityForName:@"DriveInformation"
														 inManagedObjectContext:managedObjectContext];
	NSFetchRequest *fetchRequest = [[NSFetchRequest alloc] init];
	
	[fetchRequest setEntity:entityDescription];
	[fetchRequest setFetchLimit:1];
	
	NSPredicate *fetchPredicate = [NSPredicate predicateWithFormat:@"deviceIdentifier == %@", deviceIdentifier];
	[fetchRequest setPredicate:fetchPredicate];
	
	NSError *error = nil;
	NSArray *matchingDrives = [managedObjectContext executeFetchRequest:fetchRequest error:&error];
	if(nil == matchingDrives) {
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
			return NSLocalizedStringFromTable(@"ATA", @"Drive", @"kIOPropertyPhysicalInterconnectTypeATA");
		else if([physicalInterconnectType isEqualToString:@ kIOPropertyPhysicalInterconnectTypeSerialATA])
			return NSLocalizedStringFromTable(@"Serial ATA", @"Drive", @"kIOPropertyPhysicalInterconnectTypeSerialATA");
		else if([physicalInterconnectType isEqualToString:@ kIOPropertyPhysicalInterconnectTypeSerialAttachedSCSI])
			return NSLocalizedStringFromTable(@"SAS", @"Drive", @"kIOPropertyPhysicalInterconnectTypeSerialAttachedSCSI");
		else if([physicalInterconnectType isEqualToString:@ kIOPropertyPhysicalInterconnectTypeATAPI])
			return NSLocalizedStringFromTable(@"ATAPI", @"Drive", @"kIOPropertyPhysicalInterconnectTypeATAPI");
		else if([physicalInterconnectType isEqualToString:@ kIOPropertyPhysicalInterconnectTypeUSB])
			return NSLocalizedStringFromTable(@"USB", @"Drive", @"kIOPropertyPhysicalInterconnectTypeUSB");
		else if([physicalInterconnectType isEqualToString:@ kIOPropertyPhysicalInterconnectTypeFireWire])
			return NSLocalizedStringFromTable(@"FireWire", @"Drive", @"kIOPropertyPhysicalInterconnectTypeFireWire");
		else if([physicalInterconnectType isEqualToString:@ kIOPropertyPhysicalInterconnectTypeSCSIParallel])
			return NSLocalizedStringFromTable(@"SCSI Parallel Interface", @"Drive", @"kIOPropertyPhysicalInterconnectTypeSCSIParallel");
		else if([physicalInterconnectType isEqualToString:@ kIOPropertyPhysicalInterconnectTypeFibreChannel])
			return NSLocalizedStringFromTable(@"Fibre Channel Interface", @"Drive", @"kIOPropertyPhysicalInterconnectTypeFibreChannel");
		else if([physicalInterconnectType isEqualToString:@ kIOPropertyPhysicalInterconnectTypeVirtual])
			return NSLocalizedStringFromTable(@"Virtual Interface", @"Drive", @"kIOPropertyPhysicalInterconnectTypeVirtual");
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
			return NSLocalizedStringFromTable(@"Internal", @"Drive", @"kIOPropertyInternalKey");
		else if([physicalInterconnectLocation isEqualToString:@ kIOPropertyExternalKey])
			return NSLocalizedStringFromTable(@"External", @"Drive", @"kIOPropertyExternalKey");
		else if([physicalInterconnectLocation isEqualToString:@ kIOPropertyInternalExternalKey])
			return NSLocalizedStringFromTable(@"Internal/External", @"Drive", @"kIOPropertyInternalExternalKey");
		else if([physicalInterconnectLocation isEqualToString:@ kIOPropertyInterconnectFileKey])
			return NSLocalizedStringFromTable(@"File", @"Drive", @"kIOPropertyInterconnectFileKey");
		else if([physicalInterconnectLocation isEqualToString:@ kIOPropertyInterconnectRAMKey])
			return NSLocalizedStringFromTable(@"RAM", @"Drive", @"kIOPropertyInterconnectRAMKey");
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
