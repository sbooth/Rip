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
@private
	DADiskRef _disk;
	NSArray *_tracksIDs;
	NSOperationQueue *_operationQueue;
}

// ========================================
// Properties affecting MCN reading
@property (assign) DADiskRef disk;
@property (assign) NSArray * trackIDs;

// ========================================
// Action Methods
- (IBAction) detectPregaps:(id)sender;

//- (IBAction) ok:(id)sender;
- (IBAction) cancel:(id)sender;

@end
