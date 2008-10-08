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
	DADiskRef _disk;
	NSArray *_trackIDs;
	NSOperationQueue *_operationQueue;
	NSManagedObjectContext *_managedObjectContext;
}

// ========================================
// Properties affecting MCN reading
@property (assign) DADiskRef disk;
@property (assign) NSArray * trackIDs;

// ========================================
// Action Methods
- (IBAction) detectPregaps:(id)sender;
- (IBAction) cancel:(id)sender;

@end
