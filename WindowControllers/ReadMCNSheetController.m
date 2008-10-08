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

- (void) observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
	if(kOperationQueueKVOContext == context) {
		if([keyPath isEqualToString:@"isCancelled"]) {
			MCNDetectionOperation *operation = (MCNDetectionOperation *)object;
			
			[operation removeObserver:self forKeyPath:@"isCancelled"];
			[operation removeObserver:self forKeyPath:@"isFinished"];
			
			[_progressIndicator unbind:@"animate"];
			
			if(operation.error)
				[self presentError:operation.error modalForWindow:self.window delegate:self didPresentSelector:@selector(didPresentErrorWithRecovery:contextInfo:) contextInfo:NULL];
		}
		else if([keyPath isEqualToString:@"isFinished"]) {
			MCNDetectionOperation *operation = (MCNDetectionOperation *)object;

			[operation removeObserver:self forKeyPath:@"isCancelled"];
			[operation removeObserver:self forKeyPath:@"isFinished"];

			[_progressIndicator unbind:@"animate"];
			
			if(operation.error)
				[self presentError:operation.error modalForWindow:self.window delegate:self didPresentSelector:@selector(didPresentErrorWithRecovery:contextInfo:) contextInfo:NULL];
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
	
	[operation addObserver:self forKeyPath:@"isFinished" options:NSKeyValueObservingOptionNew context:kOperationQueueKVOContext];
	[operation addObserver:self forKeyPath:@"isCancelled" options:NSKeyValueObservingOptionNew context:kOperationQueueKVOContext];

	[_progressIndicator bind:@"animate" toObject:operation withKeyPath:@"isExecuting" options:nil];
	
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
