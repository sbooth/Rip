/*
 *  Copyright (C) 2008 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import <Cocoa/Cocoa.h>
#include <DiskArbitration/DiskArbitration.h>

@class CompactDisc, DriveInformation;

// ========================================
// An NSWindowController subclass managing MCN reading
// ========================================
@interface CalculateAccurateRipOffsetsSheetController : NSWindowController
{
	IBOutlet NSProgressIndicator *_progressIndicator;
	IBOutlet NSTextField *_statusTextField;
	
@private
	__strong DADiskRef _disk;
	CompactDisc *_compactDisc;
	DriveInformation *_driveInformation;
	NSManagedObjectContext *_managedObjectContext;
	NSOperationQueue *_operationQueue;
	NSArray *_accurateRipOffsets;
}

// ========================================
// Properties affecting offset reading
@property (assign) DADiskRef disk;

// ========================================
// Other Properties
@property (readonly, copy) NSArray * accurateRipOffsets;

// ========================================
// Action Methods
- (IBAction) cancel:(id)sender;

// ========================================
// The meat & potatoes
- (void) beginCalculateAccurateRipOffsetsSheetForWindow:(NSWindow *)window modalDelegate:(id)modalDelegate didEndSelector:(SEL)didEndSelector contextInfo:(void *)contextInfo;

@end
