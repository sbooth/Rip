/*
 *  Copyright (C) 2007 - 2008 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import <Cocoa/Cocoa.h>
#import <DiskArbitration/DASession.h>
	
@interface ApplicationDelegate : NSObject
{
	DASessionRef _diskArbitrationSession;
	NSPersistentStoreCoordinator *_persistentStoreCoordinator;
	NSManagedObjectModel *_managedObjectModel;
	NSManagedObjectContext *_managedObjectContext;
}

@property (readonly) NSURL * applicationSupportFolderURL;
@property (readonly) NSURL * applicationLogFileURL;
@property (readonly, assign) NSPersistentStoreCoordinator * persistentStoreCoordinator;
@property (readonly, assign) NSManagedObjectModel * managedObjectModel;
@property (readonly, assign) NSManagedObjectContext * managedObjectContext;

- (IBAction) saveAction:(id)sender;

@end
