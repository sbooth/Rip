/*
 *  Copyright (C) 2007 - 2008 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import <Cocoa/Cocoa.h>
#include <DiskArbitration/DiskArbitration.h>

@class CompactDisc, DriveInformation;

@interface CompactDiscWindowController : NSWindowController
{
	IBOutlet NSArrayController *_trackController;
	IBOutlet NSObjectController *_driveInformationController;
	IBOutlet NSTableView *_trackTable;
	
@private
	DADiskRef _disk;
	CompactDisc *_compactDisc;
	DriveInformation *_driveInformation;
	
	NSOperationQueue *_compactDiscOperationQueue;
	NSOperationQueue *_networkOperationQueue;
	
	// State for the current extraction session
	NSSet *_tracksToBeExtracted;
	NSSet *_tracksAccuratelyExtracted;
	NSArray *_tracksNotAccuratelyExtracted;
}

@property (readonly) NSArrayController * trackController;
@property (readonly) NSObjectController * driveInformationController;
@property (readonly) NSOperationQueue * compactDiscOperationQueue;
@property (readonly) NSOperationQueue * networkOperationQueue;

// ========================================
// Properties
// ========================================
@property (assign) DADiskRef disk;
@property (readonly, assign) CompactDisc * compactDisc;
@property (readonly, assign) DriveInformation * driveInformation;

// ========================================
// Action Methods
// ========================================
- (IBAction) selectAllTracks:(id)sender;
- (IBAction) deselectAllTracks:(id)sender;

- (IBAction) copySelectedTracks:(id)sender;
- (IBAction) copyImage:(id)sender;

- (IBAction) detectPreGaps:(id)sender;

- (IBAction) readMCN:(id)sender;
- (IBAction) readISRCs:(id)sender;

- (IBAction) createCueSheet:(id)sender;

- (IBAction) editTags:(id)sender;

- (IBAction) queryDefaultMusicDatabase:(id)sender;

- (IBAction) queryAccurateRip:(id)sender;

- (IBAction) ejectDisc:(id)sender;

@end
