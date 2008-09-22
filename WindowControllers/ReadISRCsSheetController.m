/*
 *  Copyright (C) 2008 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import "ReadISRCsSheetController.h"
#import "ISRCDetectionOperation.h"

// ========================================
// Context objects for observeValueForKeyPath:ofObject:change:context:
// ========================================
static NSString * const kOperationQueueKVOContext		= @"org.sbooth.Rip.ReadISRCsSheetController.OperationQueue.KVOContext";

@interface ReadISRCsSheetController ()
@property (assign) NSOperationQueue * operationQueue;
@end

@interface ReadISRCsSheetController (Callbacks)
- (void) didPresentErrorWithRecovery:(BOOL)didRecover contextInfo:(void *)contextInfo;
@end

@implementation ReadISRCsSheetController

@synthesize disk = _disk;
@synthesize trackIDs = _tracksIDs;
@synthesize operationQueue = _operationQueue;

- (id) init
{
	if((self = [super initWithWindowNibName:@"ReadISRCsSheet"])) {
		self.operationQueue = [[NSOperationQueue alloc] init];
		[self.operationQueue setMaxConcurrentOperationCount:1];
	}
	return self;
}

- (void) awakeFromNib
{
}

- (void) observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
	if(kOperationQueueKVOContext == context) {
		if([keyPath isEqualToString:@"isFinished"]) {			
			NSOperation *operation = (NSOperation *)object;
			[operation removeObserver:self forKeyPath:@"isFinished"];

			NSError *error = [operation valueForKey:@"error"];
			if(error)
				[self presentError:error modalForWindow:self.window delegate:self didPresentSelector:@selector(didPresentErrorWithRecovery:contextInfo:) contextInfo:NULL];
			else if([operation isFinished] && !self.operationQueue.operations.count)
				[[NSApplication sharedApplication] endSheet:self.window returnCode:NSOKButton];
		}
	}
	else
		[super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
}

- (IBAction) readISRCs:(id)sender
{
	
#pragma unused(sender)
	
	for(NSManagedObjectID *objectID in self.trackIDs) {
		ISRCDetectionOperation *operation = [[ISRCDetectionOperation alloc] init];
		
		operation.disk = self.disk;
		operation.trackID = objectID;
		
		[operation addObserver:self forKeyPath:@"isFinished" options:0 context:kOperationQueueKVOContext];
		
		[self.operationQueue addOperation:operation];
	}	
}

- (IBAction) cancel:(id)sender
{
	
#pragma unused(sender)
	
	[self.operationQueue cancelAllOperations];
	
	[[NSApplication sharedApplication] endSheet:self.window returnCode:NSCancelButton];
}

@end

@implementation ReadISRCsSheetController (Callbacks)

- (void) didPresentErrorWithRecovery:(BOOL)didRecover contextInfo:(void *)contextInfo
{
	
#pragma unused(contextInfo)
	
	[[NSApplication sharedApplication] endSheet:self.window returnCode:(didRecover ? NSOKButton : NSCancelButton)];	
}

@end
