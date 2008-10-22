/*
 *  Copyright (C) 2008 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import <Cocoa/Cocoa.h>
#include <DiskArbitration/DiskArbitration.h>

// ========================================
// An NSWindowController subclass managing pregap detection
// ========================================
@interface DetectPregapsSheetController : NSWindowController
{
	IBOutlet NSProgressIndicator *_progressIndicator;
	IBOutlet NSTextField *_statusTextField;

@private
	__strong DADiskRef _disk;
	NSSet *_trackIDs;
	NSOperationQueue *_operationQueue;
	NSManagedObjectContext *_managedObjectContext;
}

// ========================================
// Properties affecting MCN reading
@property (assign) DADiskRef disk;
@property (copy) NSSet * trackIDs;

// ========================================
// Action Methods
- (IBAction) cancel:(id)sender;

// ========================================
// The meat & potatoes
- (void) beginDetectPregapsSheetForWindow:(NSWindow *)window modalDelegate:(id)modalDelegate didEndSelector:(SEL)didEndSelector contextInfo:(void *)contextInfo;

@end
