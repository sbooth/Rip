/*
 *  Copyright (C) 2008 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import <Cocoa/Cocoa.h>
#include <DiskArbitration/DiskArbitration.h>

@class CompactDisc, DriveInformation;

// ========================================
// An NSWindowController subclass for customizing the extraction
// of one or more tracks from a CD
// ========================================
@interface CopyTracksSheetController : NSWindowController
{
	IBOutlet NSProgressIndicator *_progressIndicator;
	IBOutlet NSTextField *_statusTextField;
	
@private
	DADiskRef _disk;
	NSArray *_trackIDs;
	
	CompactDisc *_compactDisc;
	DriveInformation *_driveInformation;
	NSManagedObjectContext *_managedObjectContext;

	NSOperationQueue *_operationQueue;
	NSMutableArray *_tracksToBeExtracted;
	NSMutableArray *_tracksSuccessfullyExtracted;
//	NSMutableArray *_tracksToCopy;
}

// ========================================
// Properties
// ========================================
@property (assign) DADiskRef disk;
@property (assign) NSArray * trackIDs;

@property (readonly, assign) CompactDisc * compactDisc;
@property (readonly, assign) DriveInformation * driveInformation;
@property (readonly, assign) NSManagedObjectContext * managedObjectContext;

@property (readonly) NSOperationQueue * operationQueue;

// ========================================
// Action methods
// ========================================

- (IBAction) copyTracks:(id)sender;
- (IBAction) cancel:(id)sender;

@end
