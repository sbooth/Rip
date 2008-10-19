/*
 *  Copyright (C) 2008 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import <Cocoa/Cocoa.h>
#include <DiskArbitration/DiskArbitration.h>

@class CompactDisc, DriveInformation, AccurateRipDiscRecord, ImageExtractionRecord;

// ========================================
// An NSWindowController subclass for customizing the extraction
// of one or more tracks from a CD
// ========================================
@interface CopyTracksSheetController : NSWindowController
{
	IBOutlet NSProgressIndicator *_progressIndicator;
	IBOutlet NSTextField *_statusTextField;
	IBOutlet NSTextField *_detailedStatusTextField;
	
@private
	__strong DADiskRef _disk;
	NSArray *_trackIDs;
	BOOL _extractAsImage;

	NSWindow *_sheetOwner;
	id _sheetModalDelegate;
	SEL _sheetDidEndSelector;
	void *_sheetContextInfo;
	
	CompactDisc *_compactDisc;
	DriveInformation *_driveInformation;
	NSManagedObjectContext *_managedObjectContext;

	NSMutableArray *_activeTimers;
	NSOperationQueue *_operationQueue;

	NSMutableArray *_tracksToBeExtracted;
	NSMutableArray *_tracksExtractedButNotVerified;
	NSMutableArray *_trackExtractionRecords;
	
	ImageExtractionRecord *_imageExtractionRecord;
	
	AccurateRipDiscRecord *_accurateRipPressingToMatch;
	NSInteger _accurateRipPressingOffset;
}

// ========================================
// Properties
@property (assign) DADiskRef disk;
@property (copy) NSArray * trackIDs;
@property (assign) BOOL extractAsImage;

@property (readonly, assign) AccurateRipDiscRecord * accurateRipPressingToMatch;

@property (readonly) NSArray * trackExtractionRecords;
@property (readonly) ImageExtractionRecord * imageExtractionRecord;

// ========================================
// The meat & potatoes
- (void) beginCopyTracksSheetForWindow:(NSWindow *)window modalDelegate:(id)modalDelegate didEndSelector:(SEL)didEndSelector contextInfo:(void *)contextInfo;

// ========================================
// Action methods
- (IBAction) cancel:(id)sender;

@end
