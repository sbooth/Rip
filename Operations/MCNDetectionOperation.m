/*
 *  Copyright (C) 2008 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import "MCNDetectionOperation.h"
#import "CompactDisc.h"
#import "AlbumMetadata.h"
#import "Drive.h"

@interface MCNDetectionOperation ()
@property (assign) NSError * error;
@end

@implementation MCNDetectionOperation

@synthesize disk = _disk;
@synthesize compactDiscID = _compactDiscID;
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
	NSAssert(nil != self.compactDiscID, @"self.compactDiscID may not be nil");
	
	// Create our own context for accessing the store
	NSManagedObjectContext *managedObjectContext = [[NSManagedObjectContext alloc] init];
	[managedObjectContext setPersistentStoreCoordinator:[[[NSApplication sharedApplication] delegate] persistentStoreCoordinator]];
	
	// Fetch the CompactDisc object from the context and ensure it is the correct class
	NSManagedObject *managedObject = [managedObjectContext objectWithID:self.compactDiscID];
	if(![managedObject isKindOfClass:[CompactDisc class]]) {
		self.error = [NSError errorWithDomain:NSCocoaErrorDomain code:2 userInfo:nil];
		return;
	}
	
	CompactDisc *disc = (CompactDisc *)managedObject;
	
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
