/*
 *  Copyright (C) 2007 - 2009 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import <Cocoa/Cocoa.h>
#import <DiskArbitration/DASession.h>

@interface ApplicationDelegate : NSObject
{
	IBOutlet NSWindowController *_inspectorPanelWindowController;
	IBOutlet NSWindowController *_metadataEditorPanelWindowController;
	
@private
	DASessionRef _diskArbitrationSession;
	NSPersistentStoreCoordinator *_persistentStoreCoordinator;
	NSManagedObjectModel *_managedObjectModel;
	NSManagedObjectContext *_managedObjectContext;
	NSPersistentStore *_primaryStore;
	NSPersistentStore *_inMemoryStore;
	NSFileHandle *_logFile;
}

// File and folder locations
@property (readonly) NSURL * applicationSupportFolderURL;
@property (readonly) NSURL * applicationLogFileURL;

// Core Data
@property (readonly, assign) NSPersistentStoreCoordinator * persistentStoreCoordinator;
@property (readonly, assign) NSPersistentStore * primaryStore;
@property (readonly, assign) NSPersistentStore * inMemoryStore;
@property (readonly, assign) NSManagedObjectModel * managedObjectModel;
@property (readonly, assign) NSManagedObjectContext * managedObjectContext;

// Save changes to the main NSManagedObjectContext
- (IBAction) saveAction:(id)sender;

@end
