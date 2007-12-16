/*
 *  Copyright (C) 2005 - 2007 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import "DriveInformation.h"

#include <IOKit/storage/IOStorageDeviceCharacteristics.h>

#include <IOKit/storage/IOCDMedia.h>
#include <IOKit/storage/IOCDTypes.h>

#include <IOKit/scsi/SCSITaskLib.h>
#include <IOKit/scsi/IOSCSIMultimediaCommandsDevice.h>

NSString * const	kConfiguredDrivesDefaultsKey			= @"Configured Drives";

@interface DriveInformation ()
@property (assign) DADiskRef disk;
@property (copy) NSDictionary * deviceProperties;
@end

@interface DriveInformation (Private)
- (id) valueInDeviceCharacteristicsDictionaryForKey:(NSString *)key;
- (id) valueInProtocolCharacteristicsDictionaryForKey:(NSString *)key;
@end

@implementation DriveInformation

@synthesize disk = _disk;
@synthesize deviceProperties = _deviceProperties;

- (id) initWithDADiskRef:(DADiskRef)disk
{
	NSParameterAssert(NULL != disk);
	
	if((self = [super init])) {
		self.disk = disk;
		
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
		
		self.deviceProperties = [NSDictionary dictionaryWithDictionary:(NSDictionary *)deviceProperties];
		
		// Clean up
		CFRelease(deviceProperties);
		IOObjectRelease(service);
		CFRelease(description);
	}
	
	return self;
}

- (id) copyWithZone:(NSZone *)zone
{
	DriveInformation *copy = [[[self class] allocWithZone:zone] init];
	
	copy.disk = self.disk;
	copy.deviceProperties = self.deviceProperties;

	return copy;
}

- (NSString *) deviceIdentifier
{
	CFDictionaryRef description = DADiskCopyDescription(self.disk);
	
	// Extract the IOPath for the device containing this DADiskRef
	CFStringRef ioPath = CFDictionaryGetValue(description, kDADiskDescriptionDevicePathKey);
	if(NULL == ioPath) {
		NSLog(@"No value for kDADiskDescriptionDevicePathKey in DADiskRef description");
		
		CFRelease(description);
		
		return nil;
	}
	
	return [NSString stringWithString:(NSString *)ioPath];
}

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

- (NSNumber *) readOffset
{
	NSDictionary *configuredDrives = [[NSUserDefaults standardUserDefaults] dictionaryForKey:kConfiguredDrivesDefaultsKey];
	NSString *deviceIdentifier = self.deviceIdentifier;
	
	if(nil == configuredDrives || nil == deviceIdentifier)
		return nil;
	
	return [configuredDrives objectForKey:deviceIdentifier];
}

- (void) setReadOffset:(NSNumber *)readOffset
{
	NSString *deviceIdentifier = self.deviceIdentifier;
	
	if(nil == deviceIdentifier)
		return;

	NSMutableDictionary *configuredDrives = [NSMutableDictionary dictionary];
	[configuredDrives addEntriesFromDictionary:[[NSUserDefaults standardUserDefaults] dictionaryForKey:kConfiguredDrivesDefaultsKey]];
	
	[configuredDrives removeObjectForKey:deviceIdentifier];
	
	if(readOffset)
		[configuredDrives setObject:readOffset forKey:deviceIdentifier];
	
	[[NSUserDefaults standardUserDefaults] setObject:configuredDrives forKey:kConfiguredDrivesDefaultsKey];
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
