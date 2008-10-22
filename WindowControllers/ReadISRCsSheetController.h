/*
 *  Copyright (C) 2008 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import <Cocoa/Cocoa.h>
#include <DiskArbitration/DiskArbitration.h>

// ========================================
// An NSWindowController subclass managing ISRC reading
// ========================================
@interface ReadISRCsSheetController : NSWindowController
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
// The meat & potatoes
- (void) beginReadISRCsSheetForWindow:(NSWindow *)window modalDelegate:(id)modalDelegate didEndSelector:(SEL)didEndSelector contextInfo:(void *)contextInfo;

// ========================================
// Action Methods
- (IBAction) cancel:(id)sender;

@end
