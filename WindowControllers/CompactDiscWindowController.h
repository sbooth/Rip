/*
 *  Copyright (C) 2007 - 2008 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import <Cocoa/Cocoa.h>
#include <DiskArbitration/DiskArbitration.h>

@class CompactDisc, DriveInformation;

@interface CompactDiscWindowController : NSWindowController
{
	IBOutlet NSObjectController *_driveInformationController;
	IBOutlet NSObjectController *_compactDiscController;
	IBOutlet NSArrayController *_trackController;
	IBOutlet NSTableView *_trackTable;
	IBOutlet NSDrawer *_metadataDrawer;
	
@private
	__strong DADiskRef _disk;
	CompactDisc *_compactDisc;
	DriveInformation *_driveInformation;
	
	NSOperationQueue *_operationQueue;
	int _extractionMode; // eExtractionMode
}

// ========================================
// Properties useful for binding
// ========================================
@property (readonly) NSArrayController * trackController;
@property (readonly) NSObjectController * driveInformationController;

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

- (IBAction) toggleMetadataDrawer:(id)sender;

- (IBAction) determineDriveReadOffset:(id)sender;

- (IBAction) copySelectedTracks:(id)sender;
- (IBAction) copyImage:(id)sender;

- (IBAction) detectPregaps:(id)sender;

- (IBAction) readMCN:(id)sender;
- (IBAction) readISRCs:(id)sender;

- (IBAction) createCueSheet:(id)sender;

- (IBAction) queryDefaultMusicDatabase:(id)sender;
- (IBAction) queryMusicDatabase:(id)sender;

- (IBAction) queryAccurateRip:(id)sender;

- (IBAction) ejectDisc:(id)sender;

@end
