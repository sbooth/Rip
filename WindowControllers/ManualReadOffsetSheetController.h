/*
 *  Copyright (C) 2008 - 2009 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import <Cocoa/Cocoa.h>
#include <DiskArbitration/DiskArbitration.h>

@class DriveInformation;

// ========================================
// An NSWindowController subclass managing MCN reading
// ========================================
@interface ManualReadOffsetSheetController : NSWindowController
{
@private
	__strong DADiskRef _disk;
	DriveInformation *_driveInformation;
	NSManagedObjectContext *_managedObjectContext;
}

// ========================================
// The disk contained in the drive
@property (assign) DADiskRef disk;

// ========================================
// The meat & potatoes
- (void) beginManualReadOffsetSheetForWindow:(NSWindow *)window modalDelegate:(id)modalDelegate didEndSelector:(SEL)didEndSelector contextInfo:(void *)contextInfo;

// ========================================
// Action Methods
- (IBAction) setReadOffset:(id)sender;
- (IBAction) cancel:(id)sender;

@end
