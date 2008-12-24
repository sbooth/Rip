/*
 *  Copyright (C) 2008 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import "DetectPregapsSheetController.h"
#import "PregapDetectionOperation.h"

#import "TrackDescriptor.h"
#import "TrackMetadata.h"

// ========================================
// Context objects for observeValueForKeyPath:ofObject:change:context:
// ========================================
static NSString * const kOperationQueueKVOContext		= @"org.sbooth.Rip.DetectPregapsSheetController.OperationQueue.KVOContext";

@interface DetectPregapsSheetController ()
@property (assign) NSOperationQueue * operationQueue;
@property (readonly) NSManagedObjectContext * managedObjectContext;
@end

@interface DetectPregapsSheetController (Callbacks)
- (void) didPresentErrorWithRecovery:(BOOL)didRecover contextInfo:(void *)contextInfo;
@end

@interface DetectPregapsSheetController (Private)
- (void) setStatusTextForTrackID:(NSManagedObjectID *)trackID;
- (void) operationDidReturn:(PregapDetectionOperation *)operation;
- (NSManagedObjectContext *) managedObjectContext;
@end

@implementation DetectPregapsSheetController

@synthesize disk = _disk;
@synthesize trackIDs = _trackIDs;
@synthesize operationQueue = _operationQueue;
@synthesize managedObjectContext = _managedObjectContext;

- (id) init
{
	if((self = [super initWithWindowNibName:@"DetectPregapsSheet"])) {
		self.operationQueue = [[NSOperationQueue alloc] init];
		[self.operationQueue setMaxConcurrentOperationCount:1];
	}
	return self;
}

- (void) observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
	if(kOperationQueueKVOContext == context) {
		PregapDetectionOperation *operation = (PregapDetectionOperation *)object;
		
		if([keyPath isEqualToString:@"isExecuting"]) {
			if([operation isExecuting]) {
				// KVO is thread-safe, but doesn't guarantee observeValueForKeyPath: will be called from the main thread
				if([NSThread isMainThread])
					[self setStatusTextForTrackID:operation.trackID];
				else
					[self performSelectorOnMainThread:@selector(setStatusTextForTrackID:) withObject:operation.trackID waitUntilDone:NO];
			}
		}
		else if([keyPath isEqualToString:@"isCancelled"] || [keyPath isEqualToString:@"isFinished"]) {
			[operation removeObserver:self forKeyPath:@"isExecuting"];
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

- (void) beginDetectPregapsSheetForWindow:(NSWindow *)window modalDelegate:(id)modalDelegate didEndSelector:(SEL)didEndSelector contextInfo:(void *)contextInfo
{
	NSParameterAssert(nil != window);
	
	[[NSApplication sharedApplication] beginSheet:self.window
								   modalForWindow:window
									modalDelegate:modalDelegate
								   didEndSelector:didEndSelector
									  contextInfo:contextInfo];
	
	[_progressIndicator startAnimation:self];
	
	for(NSManagedObjectID *objectID in self.trackIDs) {
		PregapDetectionOperation *operation = [[PregapDetectionOperation alloc] init];
		
		operation.disk = self.disk;
		operation.trackID = objectID;
		
		[operation addObserver:self forKeyPath:@"isExecuting" options:NSKeyValueObservingOptionNew context:kOperationQueueKVOContext];
		[operation addObserver:self forKeyPath:@"isCancelled" options:NSKeyValueObservingOptionNew context:kOperationQueueKVOContext];
		[operation addObserver:self forKeyPath:@"isFinished" options:NSKeyValueObservingOptionNew context:kOperationQueueKVOContext];
		
		[self.operationQueue addOperation:operation];
	}	
}

- (IBAction) cancel:(id)sender
{
	[_progressIndicator stopAnimation:sender];
	[self.operationQueue cancelAllOperations];
	
	[[NSApplication sharedApplication] endSheet:self.window returnCode:NSCancelButton];
	[self.window orderOut:sender];
}

@end

@implementation DetectPregapsSheetController (Callbacks)

- (void) didPresentErrorWithRecovery:(BOOL)didRecover contextInfo:(void *)contextInfo
{
	
#pragma unused(contextInfo)
	
	[[NSApplication sharedApplication] endSheet:self.window returnCode:(didRecover ? NSOKButton : NSCancelButton)];	
	[self.window orderOut:self];
}

@end

@implementation DetectPregapsSheetController (Private)

- (void) setStatusTextForTrackID:(NSManagedObjectID *)trackID
{
	NSParameterAssert(nil != trackID);
	
	// Fetch the TrackDescriptor object from the context and ensure it is the correct class
	NSManagedObject *managedObject = [self.managedObjectContext objectWithID:trackID];
	if(![managedObject isKindOfClass:[TrackDescriptor class]])
		return;
	
	TrackDescriptor *track = (TrackDescriptor *)managedObject;				
	
	NSString *trackDescription = nil;
	if(track.metadata.title)
		trackDescription = track.metadata.title;
	else
		trackDescription = [track.number stringValue];
	
	[_statusTextField setStringValue:trackDescription];
}

- (void) operationDidReturn:(PregapDetectionOperation *)operation
{
	NSParameterAssert(nil != operation);
	
	[_progressIndicator stopAnimation:self];
	
	if(operation.error)
		[self presentError:operation.error modalForWindow:self.window delegate:self didPresentSelector:@selector(didPresentErrorWithRecovery:contextInfo:) contextInfo:NULL];
	else if([operation isFinished] && 0 == [[self.operationQueue operations] count]) {
		[[NSApplication sharedApplication] endSheet:self.window returnCode:NSOKButton];
		[self.window orderOut:self];
	}
}

- (NSManagedObjectContext *) managedObjectContext
{
	// Create our own context for accessing the store
	if(!_managedObjectContext) {
		_managedObjectContext = [[NSManagedObjectContext alloc] init];
		[_managedObjectContext setPersistentStoreCoordinator:[[[NSApplication sharedApplication] delegate] persistentStoreCoordinator]];
	}
	
	return _managedObjectContext;
}

@end
