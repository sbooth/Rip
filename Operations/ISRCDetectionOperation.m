/*
 *  Copyright (C) 2008 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import "ISRCDetectionOperation.h"
#import "TrackDescriptor.h"
#import "TrackMetadata.h"
#import "Drive.h"

@interface ISRCDetectionOperation ()
@property (assign) NSError * error;
@end

@implementation ISRCDetectionOperation

@synthesize disk = _disk;
@synthesize trackID = _trackID;
@synthesize error = _error;

- (id) initWithDADiskRef:(DADiskRef)disk
{
	NSParameterAssert(NULL != disk);
	
	if((self = [super init]))
		self.disk = disk;
	return self;
}

- (void) main
{
	NSAssert(NULL != self.disk, @"self.disk may not be NULL");
	NSAssert(nil != self.trackID, @"self.trackID may not be nil");
	
	// Create our own context for accessing the store
	NSManagedObjectContext *managedObjectContext = [[NSManagedObjectContext alloc] init];
	[managedObjectContext setPersistentStoreCoordinator:[[[NSApplication sharedApplication] delegate] persistentStoreCoordinator]];
	
	// Fetch the TrackDescriptor object from the context and ensure it is the correct class
	NSManagedObject *managedObject = [managedObjectContext objectWithID:self.trackID];
	if(![managedObject isKindOfClass:[TrackDescriptor class]]) {
		self.error = [NSError errorWithDomain:NSCocoaErrorDomain code:2 userInfo:nil];
		return;
	}
	
	TrackDescriptor *track = (TrackDescriptor *)managedObject;

	// Open the CD media for reading
	Drive *drive = [[Drive alloc] initWithDADiskRef:self.disk];
	if(![drive openDevice]) {
		self.error = drive.error;
		return;
	}

	// Read the ISRC
	track.metadata.ISRC = [drive readISRC:track.number.unsignedIntegerValue];
	
	// Save the changes
	if(managedObjectContext.hasChanges) {
		NSError *error = nil;
		if(![managedObjectContext save:&error])
			self.error = error;
	}

	// Close the device
	if(![drive closeDevice])
		self.error = drive.error;
}

@end
