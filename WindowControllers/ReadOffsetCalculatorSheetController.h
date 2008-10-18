/*
 *  Copyright (C) 2008 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import <Cocoa/Cocoa.h>
#include <DiskArbitration/DiskArbitration.h>

@class CompactDisc, DriveInformation;

@interface ReadOffsetCalculatorSheetController : NSWindowController
{
	IBOutlet NSProgressIndicator *_progressIndicator;
	IBOutlet NSTextField *_statusTextField;
	
	IBOutlet NSTextField *_suggestedOffsetTextField;
	IBOutlet NSArrayController *_possibleOffsetsArrayController;
	
	IBOutlet NSButton *_possibleOffsetsViewDisclosureButton;
	IBOutlet NSView *_possibleOffsetsView;
	
@private
	__strong DADiskRef _disk;
	CompactDisc *_compactDisc;
	DriveInformation *_driveInformation;
	NSManagedObjectContext *_managedObjectContext;
	NSOperationQueue *_operationQueue;
	BOOL _possibleOffsetsShown;
}

// ========================================
// Properties
@property (assign) DADiskRef disk;

@property (readonly, assign) BOOL possibleOffsetsShown;

// ========================================
// The meat & potatoes
- (void) beginReadOffsetCalculatorSheetForWindow:(NSWindow *)window modalDelegate:(id)modalDelegate didEndSelector:(SEL)didEndSelector contextInfo:(void *)contextInfo;

// ========================================
// Action Methods
- (IBAction) acceptSuggestedOffset:(id)sender;
- (IBAction) cancel:(id)sender;

- (IBAction) togglePossibleOffsetsShown:(id)sender;
- (IBAction) useSelectedOffset:(id)sender;

@end
