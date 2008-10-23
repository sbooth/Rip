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
//
// The general extraction strategy looks like:
//  - Extract the entire track (copy)
//  - Compare
// ========================================
@interface CopyTracksSheetController : NSWindowController
{
	IBOutlet NSProgressIndicator *_progressIndicator;
	IBOutlet NSTextField *_statusTextField;
	IBOutlet NSTextField *_detailedStatusTextField;
	
@private
	__strong DADiskRef _disk;
	NSSet *_trackIDs;

	NSWindow *_sheetOwner;
	id _sheetModalDelegate;
	SEL _sheetDidEndSelector;
	void *_sheetContextInfo;
	
	CompactDisc *_compactDisc;
	DriveInformation *_driveInformation;
	NSManagedObjectContext *_managedObjectContext;

	NSMutableArray *_activeTimers;
	NSOperationQueue *_operationQueue;

	NSMutableSet *_tracksToBeExtracted;
	NSMutableDictionary *_tracksExtractedButNotVerified;
	NSMutableDictionary *_sectorIndexesNeedingVerification;
	NSMutableArray *_trackPartialExtractions;

	NSMutableArray *_trackExtractionRecords;
}

// ========================================
// Properties
@property (assign) DADiskRef disk;
@property (copy) NSSet * trackIDs;

@property (readonly) NSArray * trackExtractionRecords;

// ========================================
// The meat & potatoes
- (void) beginCopyTracksSheetForWindow:(NSWindow *)window modalDelegate:(id)modalDelegate didEndSelector:(SEL)didEndSelector contextInfo:(void *)contextInfo;

// ========================================
// Action methods
- (IBAction) cancel:(id)sender;

@end
