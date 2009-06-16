/*
 *  Copyright (C) 2008 - 2009 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

// Access to AccurateRip is regulated, see http://www.accuraterip.com/3rdparty-access.htm for details

#import "DriveOffsetQueryOperation.h"
#import "DiskUtilities.h"
#import "Logger.h"

#include <SystemConfiguration/SCNetwork.h>
#include <IOKit/storage/IOStorageDeviceCharacteristics.h>

@interface DriveOffsetQueryOperation ()
@property (copy) NSNumber * readOffset;
@property (copy) NSError *error;
@end

@implementation DriveOffsetQueryOperation

// ========================================
// Properties
@synthesize disk = _disk;
@synthesize readOffset = _readOffset;
@synthesize error = _error;

- (void) main
{
	NSAssert(NULL != self.disk, @"self.disk may not be NULL");
	
	// Before doing anything, verify we can access the AccurateRip web site
	SCNetworkConnectionFlags flags;
	if(SCNetworkCheckReachabilityByName("www.accuraterip.com", &flags)) {
		if(!(kSCNetworkFlagsReachable & flags && !(kSCNetworkFlagsConnectionRequired & flags))) {
			NSMutableDictionary *errorDictionary = [NSMutableDictionary dictionary];
			[errorDictionary setObject:[NSURL URLWithString:@"www.accuraterip.com"] forKey:NSErrorFailingURLStringKey];
			
			self.error = [NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorCannotConnectToHost userInfo:errorDictionary];
			return;
		}
	}

	// Fetch the drive's information
	NSDictionary *deviceProperties = getDevicePropertiesForDADiskRef(self.disk);
	if(!deviceProperties) {
		self.error = [NSError errorWithDomain:NSCocoaErrorDomain code:52 userInfo:nil];
		return;
	}
	
	NSDictionary *deviceCharacteristics = [deviceProperties objectForKey:@ kIOPropertyDeviceCharacteristicsKey];

	NSString *vendorName = [deviceCharacteristics objectForKey:@ kIOPropertyVendorNameKey];
	NSString *productName = [deviceCharacteristics objectForKey:@ kIOPropertyProductNameKey];

	// Build the URL
	NSURL *accurateRipOffsetsDBURL = [NSURL URLWithString:@"http://www.accuraterip.com/accuraterip/DriveOffsets.bin"];
	
	[[Logger sharedLogger] logMessageWithLevel:eLogMessageLevelDebug format:@"Querying %@", accurateRipOffsetsDBURL];
	
	// Create a request for the URL with a 2 minute timeout
	NSURLRequest *request = [NSURLRequest requestWithURL:accurateRipOffsetsDBURL
											 cachePolicy:NSURLRequestUseProtocolCachePolicy
										 timeoutInterval:120.0];
	
	NSHTTPURLResponse *accurateRipOffsetsDBResponse = nil;
	NSError *error = nil;
	NSData *accurateRipOffsetsDBResponseData = [NSURLConnection sendSynchronousRequest:request 
															returningResponse:&accurateRipOffsetsDBResponse 
																		error:&error];
	if(!accurateRipOffsetsDBResponseData) {
		self.error = error;
		return;
	}
	
	// Was the AccurateRip drive database found?
	if(404 == [accurateRipOffsetsDBResponse statusCode]) {
		NSMutableDictionary *errorDictionary = [NSMutableDictionary dictionary];
		[errorDictionary setObject:accurateRipOffsetsDBURL forKey:NSErrorFailingURLStringKey];
		
		self.error = [NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorResourceUnavailable userInfo:errorDictionary];
		return;
	}

	// An entry in the file consists of 0x45 bytes:
	//  - 2 bytes for the drive's read offset (int16_t)
	//  - 0x21 bytes for the drive's name and manufacturer, separated by " - "
	//  - 0x22 bytes of miscellaneous data (?? unknown format and purpose)
	const NSUInteger driveRecordSize = 0x45;
	NSUInteger numberOfDriveRecords = [accurateRipOffsetsDBResponseData length] / driveRecordSize;

	[[Logger sharedLogger] logMessageWithLevel:eLogMessageLevelDebug format:@"Retrieved %ld drive records", numberOfDriveRecords];

	// Iterate through each drive record and attempt to find a match
	NSUInteger driveRecordOffset = 0;
	for(NSUInteger driveRecordIndex = 0; driveRecordIndex < numberOfDriveRecords; ++driveRecordIndex) {
		int16_t readOffset = 0;
		[accurateRipOffsetsDBResponseData getBytes:&readOffset range:NSMakeRange(driveRecordOffset, 2)];
		readOffset = OSSwapLittleToHostInt16(readOffset);

		char *name [0x21];
		memset(name, 0, 0x21);
		[accurateRipOffsetsDBResponseData getBytes:&name range:NSMakeRange(driveRecordOffset + 2, 0x21)];

		NSString *nameString = [NSString stringWithCString:(const char *)name encoding:NSASCIIStringEncoding];
		
//		char *misc [0x22];
//		memset(misc, 0, 0x22);
//		[accurateRipOffsetsDBResponseData getBytes:&misc range:NSMakeRange(driveRecordOffset + 2 + 0x21, 0x22)];
		
//		NSString *miscString = [NSString stringWithCString:(const char *)misc encoding:NSASCIIStringEncoding];
		
		NSString *vendorAndProduct = [NSString stringWithFormat:@"%@ - %@", vendorName, productName];
		if([vendorAndProduct isEqualToString:nameString]) {
			self.readOffset = [NSNumber numberWithShort:readOffset];
			[[Logger sharedLogger] logMessageWithLevel:eLogMessageLevelDebug format:@"Drive read offset is%hi", readOffset];
			return;
		}

		driveRecordOffset += driveRecordSize;
	}
}

@end
