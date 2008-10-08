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
	DADiskRef _disk;
	NSManagedObjectID *_compactDiscID;
	NSOperationQueue *_operationQueue;
}

// ========================================
// Properties affecting MCN reading
@property (assign) DADiskRef disk;
@property (assign) NSManagedObjectID * compactDiscID;

// ========================================
// Action Methods
- (IBAction) readMCN:(id)sender;
- (IBAction) cancel:(id)sender;

@end
