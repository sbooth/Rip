/*
 *  Copyright (C) 2005 - 2009 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import "DiskUtilities.h"

// ========================================
// Utility function that extracts the device identifier from a DADiskRef
// ========================================
NSString * getDeviceIdentifierForDADiskRef(DADiskRef disk)
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
NSDictionary * getDevicePropertiesForDADiskRef(DADiskRef disk)
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
