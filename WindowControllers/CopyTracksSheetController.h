/*
 *  Copyright (C) 2008 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import <Cocoa/Cocoa.h>
#include <DiskArbitration/DiskArbitration.h>

@class CompactDisc, DriveInformation, AccurateRipDiscRecord;

// ========================================
// An NSWindowController subclass for customizing the extraction
// of one or more tracks from a CD
// ========================================
@interface CopyTracksSheetController : NSWindowController
{
	IBOutlet NSProgressIndicator *_progressIndicator;
	IBOutlet NSTextField *_statusTextField;
	
@private
	__strong DADiskRef _disk;
	NSArray *_trackIDs;
	BOOL _extractAsImage;

	NSMapTable *_activeTimers;
	NSMutableArray *_extractionRecords;

	CompactDisc *_compactDisc;
	DriveInformation *_driveInformation;
	NSManagedObjectContext *_managedObjectContext;

	NSOperationQueue *_operationQueue;
	NSMutableArray *_tracksToBeExtracted;
	
	AccurateRipDiscRecord *_accurateRipPressingToMatch;
}

// ========================================
// Properties
// ========================================
@property (assign) DADiskRef disk;
@property (copy) NSArray * trackIDs;
@property (assign) BOOL extractAsImage;

@property (readonly) NSArray * extractionRecords;

@property (readonly, assign) CompactDisc * compactDisc;
@property (readonly, assign) DriveInformation * driveInformation;
@property (readonly, assign) NSManagedObjectContext * managedObjectContext;

@property (readonly) NSOperationQueue * operationQueue;

@property (readonly, assign) AccurateRipDiscRecord * accurateRipPressingToMatch;

// ========================================
// Action methods
// ========================================

- (IBAction) copyTracks:(id)sender;
- (IBAction) cancel:(id)sender;

@end
