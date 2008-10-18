/*
 *  Copyright (C) 2008 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import <Cocoa/Cocoa.h>
#include <DiskArbitration/DiskArbitration.h>

// ========================================
// An NSWindowController subclass managing MCN reading
// ========================================
@interface ReadMCNSheetController : NSWindowController
{
	IBOutlet NSProgressIndicator *_progressIndicator;

@private
	__strong DADiskRef _disk;
	NSOperationQueue *_operationQueue;
}

// ========================================
// Properties affecting MCN reading
@property (assign) DADiskRef disk;

// ========================================
// The meat & potatoes
- (void) beginReadMCNSheetForWindow:(NSWindow *)window modalDelegate:(id)modalDelegate didEndSelector:(SEL)didEndSelector contextInfo:(void *)contextInfo;

// ========================================
// Action Methods
- (IBAction) cancel:(id)sender;

@end
