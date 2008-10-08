/*
 *  Copyright (C) 2008 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import "ReadISRCsSheetController.h"
#import "ISRCDetectionOperation.h"

#import "TrackDescriptor.h"
#import "TrackMetadata.h"

// ========================================
// Context objects for observeValueForKeyPath:ofObject:change:context:
// ========================================
static NSString * const kOperationQueueKVOContext		= @"org.sbooth.Rip.ReadISRCsSheetController.OperationQueue.KVOContext";

@interface ReadISRCsSheetController ()
@property (assign) NSOperationQueue * operationQueue;
@property (readonly) NSManagedObjectContext * managedObjectContext;
@end

@interface ReadISRCsSheetController (Callbacks)
- (void) didPresentErrorWithRecovery:(BOOL)didRecover contextInfo:(void *)contextInfo;
@end

@interface ReadISRCsSheetController (Private)
- (NSManagedObjectContext *) managedObjectContext;
@end

@implementation ReadISRCsSheetController

@synthesize disk = _disk;
@synthesize trackIDs = _trackIDs;
@synthesize operationQueue = _operationQueue;
@synthesize managedObjectContext = _managedObjectContext;

- (id) init
{
	if((self = [super initWithWindowNibName:@"ReadISRCsSheet"])) {
		self.operationQueue = [[NSOperationQueue alloc] init];
		[self.operationQueue setMaxConcurrentOperationCount:1];
	}
	return self;
}

- (void) observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
	if(kOperationQueueKVOContext == context) {
		if([keyPath isEqualToString:@"isExecuting"]) {
			ISRCDetectionOperation *operation = (ISRCDetectionOperation *)object;
			
			if([operation isExecuting]) {
				NSManagedObjectID *trackID = operation.trackID;
				
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
		}
		else if([keyPath isEqualToString:@"isCancelled"]) {
			ISRCDetectionOperation *operation = (ISRCDetectionOperation *)object;
			
			[operation removeObserver:self forKeyPath:@"isExecuting"];
			[operation removeObserver:self forKeyPath:@"isCancelled"];
			[operation removeObserver:self forKeyPath:@"isFinished"];

			if(operation.error)
				[self presentError:operation.error modalForWindow:self.window delegate:self didPresentSelector:@selector(didPresentErrorWithRecovery:contextInfo:) contextInfo:NULL];
		}
		else if([keyPath isEqualToString:@"isFinished"]) {
			ISRCDetectionOperation *operation = (ISRCDetectionOperation *)object;
			
			[operation removeObserver:self forKeyPath:@"isExecuting"];
			[operation removeObserver:self forKeyPath:@"isCancelled"];
			[operation removeObserver:self forKeyPath:@"isFinished"];

			if(operation.error)
				[self presentError:operation.error modalForWindow:self.window delegate:self didPresentSelector:@selector(didPresentErrorWithRecovery:contextInfo:) contextInfo:NULL];
			else if([operation isFinished] && 0 == [[self.operationQueue operations] count])
				[[NSApplication sharedApplication] endSheet:self.window returnCode:NSOKButton];
		}
	}
	else
		[super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
}

- (IBAction) readISRCs:(id)sender
{
	[_progressIndicator startAnimation:sender];

	for(NSManagedObjectID *objectID in self.trackIDs) {
		ISRCDetectionOperation *operation = [[ISRCDetectionOperation alloc] init];
		
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
	
#pragma unused(sender)
	
	[self.operationQueue cancelAllOperations];
	[[NSApplication sharedApplication] endSheet:self.window returnCode:NSCancelButton];
}

@end

@implementation ReadISRCsSheetController (Callbacks)

- (void) didPresentErrorWithRecovery:(BOOL)didRecover contextInfo:(void *)contextInfo
{
	
#pragma unused(contextInfo)

	if(0 == [[self.operationQueue operations] count])
		[[NSApplication sharedApplication] endSheet:self.window returnCode:(didRecover ? NSOKButton : NSCancelButton)];	
}

@end

@implementation ReadISRCsSheetController (Private)

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
