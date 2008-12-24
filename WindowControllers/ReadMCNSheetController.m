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

@interface ReadMCNSheetController (Private)
- (void) operationDidReturn:(MCNDetectionOperation *)operation;
@end

@implementation ReadMCNSheetController

@synthesize disk = _disk;
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
		MCNDetectionOperation *operation = (MCNDetectionOperation *)object;
		
		if([keyPath isEqualToString:@"isCancelled"] || [keyPath isEqualToString:@"isFinished"]) {
			[operation removeObserver:self forKeyPath:@"isCancelled"];
			[operation removeObserver:self forKeyPath:@"isFinished"];
		
			// KVO is thread-safe, but doesn't guarantee observeValueForKeyPath: will be called from the main thread
			if([NSThread isMainThread])
				[self operationDidReturn:operation];
			else
				[self performSelectorOnMainThread:@selector(operationDidReturn:) withObject:operation waitUntilDone:NO];
		}
	}
	else
		[super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
}

- (void) beginReadMCNSheetForWindow:(NSWindow *)window modalDelegate:(id)modalDelegate didEndSelector:(SEL)didEndSelector contextInfo:(void *)contextInfo
{
	NSParameterAssert(nil != window);
	
	[[NSApplication sharedApplication] beginSheet:self.window
								   modalForWindow:window 
									modalDelegate:modalDelegate 
								   didEndSelector:didEndSelector 
									  contextInfo:contextInfo];
	
	[_progressIndicator startAnimation:self];
	
	MCNDetectionOperation *operation = [[MCNDetectionOperation alloc] init];
	
	operation.disk = self.disk;
	
	[operation addObserver:self forKeyPath:@"isFinished" options:NSKeyValueObservingOptionNew context:kOperationQueueKVOContext];
	[operation addObserver:self forKeyPath:@"isCancelled" options:NSKeyValueObservingOptionNew context:kOperationQueueKVOContext];

	[self.operationQueue addOperation:operation];
}

- (IBAction) cancel:(id)sender
{
	[_progressIndicator stopAnimation:sender];
	[self.operationQueue cancelAllOperations];
	
	[[NSApplication sharedApplication] endSheet:self.window returnCode:NSCancelButton];
	[self.window orderOut:sender];
}

@end

@implementation ReadMCNSheetController (Callbacks)

- (void) didPresentErrorWithRecovery:(BOOL)didRecover contextInfo:(void *)contextInfo
{

#pragma unused(contextInfo)
	
	[[NSApplication sharedApplication] endSheet:self.window returnCode:(didRecover ? NSOKButton : NSCancelButton)];	
	[self.window orderOut:self];
}

@end

@implementation ReadMCNSheetController (Private)

- (void) operationDidReturn:(MCNDetectionOperation *)operation
{
	NSParameterAssert(nil != operation);
	
	[_progressIndicator stopAnimation:self];
	
	if(operation.error)
		[self presentError:operation.error modalForWindow:self.window delegate:self didPresentSelector:@selector(didPresentErrorWithRecovery:contextInfo:) contextInfo:NULL];
	else if([operation isFinished]) {
		[[NSApplication sharedApplication] endSheet:self.window returnCode:NSOKButton];
		[self.window orderOut:self];
	}
}

@end
