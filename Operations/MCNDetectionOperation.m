/*
 *  Copyright (C) 2008 - 2009 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import "MCNDetectionOperation.h"
#import "CompactDisc.h"
#import "AlbumMetadata.h"
#import "Drive.h"
#import "ApplicationDelegate.h"

@interface MCNDetectionOperation ()
@property (copy) NSError * error;
@end

@implementation MCNDetectionOperation

@synthesize disk = _disk;
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
	
	// Create our own context for accessing the store
	NSManagedObjectContext *managedObjectContext = [[NSManagedObjectContext alloc] init];
	[managedObjectContext setPersistentStoreCoordinator:[(ApplicationDelegate *)[[NSApplication sharedApplication] delegate] persistentStoreCoordinator]];

	// Fetch the compact disc object
	CompactDisc *disc = [CompactDisc compactDiscWithDADiskRef:self.disk inManagedObjectContext:managedObjectContext];
	
	// Open the CD media for reading
	Drive *drive = [[Drive alloc] initWithDADiskRef:self.disk];
	if(![drive openDevice]) {
		self.error = drive.error;
		return;
	}
	
	// Read the MCN
	disc.metadata.MCN = [drive readMCN];
	
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
