/*
 *  Copyright (C) 2008 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import "ReadMCNSheetController.h"
#import "MCNDetectionOperation.h"

// ========================================
// Context objects for observeValueForKeyPath:ofObject:change:context:
// ========================================
static NSString * const kOperationQueueKVOContext		= @"org.sbooth.Rip.ReadMCNSheetController.OperationQueue.KVOContext";

@interface ReadMCNSheetController ()
@property (assign) NSOperationQueue * operationQueue;
@end

@interface ReadMCNSheetController (Callbacks)
- (void) didPresentErrorWithRecovery:(BOOL)didRecover contextInfo:(void *)contextInfo;
@end

@implementation ReadMCNSheetController

@synthesize disk = _disk;
@synthesize compactDiscID = _compactDiscID;
@synthesize operationQueue = _operationQueue;

- (id) init
{
	if((self = [super initWithWindowNibName:@"ReadMCNSheet"])) {
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
			else if([operation isFinished])
				[[NSApplication sharedApplication] endSheet:self.window returnCode:NSOKButton];
		}
	}
	else
		[super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
}

- (IBAction) readMCN:(id)sender
{
	
#pragma unused(sender)
	
	MCNDetectionOperation *operation = [[MCNDetectionOperation alloc] init];
	
	operation.disk = self.disk;
	operation.compactDiscID = self.compactDiscID;
	
	[operation addObserver:self forKeyPath:@"isFinished" options:0 context:kOperationQueueKVOContext];

	[self.operationQueue addOperation:operation];
}

- (IBAction) cancel:(id)sender
{
	
#pragma unused(sender)
	
	[self.operationQueue cancelAllOperations];
	
	[[NSApplication sharedApplication] endSheet:self.window returnCode:NSCancelButton];
}

@end

@implementation ReadMCNSheetController (Callbacks)

- (void) didPresentErrorWithRecovery:(BOOL)didRecover contextInfo:(void *)contextInfo
{
	
#pragma unused(contextInfo)
	
	[[NSApplication sharedApplication] endSheet:self.window returnCode:(didRecover ? NSOKButton : NSCancelButton)];	
}

@end
