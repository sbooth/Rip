/*
 *  Copyright (C) 2008 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import "CopyTracksSheetController.h"

#import "CompactDisc.h"
#import "DriveInformation.h"

#import "SessionDescriptor.h"
#import "TrackDescriptor.h"
#import "AlbumMetadata.h"
#import "TrackMetadata.h"

#import "BitArray.h"
#import "SectorRange.h"
#import "ExtractionOperation.h"

#import "ReadOffsetCalculationOperation.h"

#import "TrackExtractionRecord.h"

#import "AccurateRipDiscRecord.h"
#import "AccurateRipTrackRecord.h"
#import "AccurateRipUtilities.h"

#import "ReadMCNSheetController.h"
#import "ReadISRCsSheetController.h"
#import "DetectPregapsSheetController.h"
#import "CalculateAccurateRipOffsetsSheetController.h"

#import "EncoderManager.h"

#import "SecondsFormatter.h"

#import "CDDAUtilities.h"
#import "FileUtilities.h"
#import "AudioUtilities.h"

// ========================================
// Context objects for observeValueForKeyPath:ofObject:change:context:
// ========================================
static NSString * const kAudioExtractionKVOContext		= @"org.sbooth.Rip.CopyTracksSheetController.ExtractAudioKVOContext";

// ========================================
// The number of sectors which will be scanned during offset verification
// ========================================
#define MAXIMUM_OFFSET_TO_CHECK_IN_SECTORS 2

// ========================================
// The minimum size (in bytes) of blocks to re-read from the disc
// ========================================
#define MINIMUM_DISC_READ_SIZE (2048 * 1024)

@interface CopyTracksSheetController ()
@property (assign) CompactDisc * compactDisc;
@property (assign) DriveInformation * driveInformation;
@property (assign) NSManagedObjectContext * managedObjectContext;

@property (assign) NSOperationQueue * operationQueue;

@property (assign) AccurateRipDiscRecord * accurateRipPressingToMatch;
@property (assign) NSInteger accurateRipPressingOffset;
@end

@interface CopyTracksSheetController (Callbacks)
- (void) didPresentErrorWithRecovery:(BOOL)didRecover contextInfo:(void *)contextInfo;
- (void) audioExtractionTimerFired:(NSTimer *)timer;
@end

@interface CopyTracksSheetController (SheetCallbacks)
- (void) showReadMCNSheetDidEnd:(NSWindow *)sheet returnCode:(int)returnCode contextInfo:(void *)contextInfo;
- (void) showReadISRCsSheetDidEnd:(NSWindow *)sheet returnCode:(int)returnCode contextInfo:(void *)contextInfo;
- (void) showDetectPregapsSheetDidEnd:(NSWindow *)sheet returnCode:(int)returnCode contextInfo:(void *)contextInfo;
- (void) showCalculateAccurateRipOffsetsSheetDidEnd:(NSWindow *)sheet returnCode:(int)returnCode contextInfo:(void *)contextInfo;
@end

@interface CopyTracksSheetController (Private)
- (void) beginReadMCNSheet;
- (void) beginReadISRCsSheet;
- (void) beginDetectPregapsSheet;
- (void) beginCalculateAccurateRipOffsetsSheet;
- (void) performShowCopyTracksSheet;

- (void) startExtractingNextTrack;

- (void) extractWholeTrack:(TrackDescriptor *)track;
- (void) extractPartialTrack:(TrackDescriptor *)track sectorRange:(SectorRange *)sectorRange;
- (void) extractPartialTrack:(TrackDescriptor *)track sectorRange:(SectorRange *)sectorRange enforceMinimumReadSize:(BOOL)enforceMinimumReadSize;

- (void) extractSectorIndexes:(NSIndexSet *)sectorIndexes inTrack:(TrackDescriptor *)track coalesceRanges:(BOOL)coalesceRanges;

- (void) processExtractionOperation:(ExtractionOperation *)operation;
- (void) processExtractionOperationForWholeTrack:(ExtractionOperation *)operation;
- (void) processExtractionOperationForPartialTrack:(ExtractionOperation *)operation;

- (NSNumber *) calculateAccurateRipChecksumForExtractionOperation:(ExtractionOperation *)operation;

- (TrackExtractionRecord *) createTrackExtractionRecordForOperation:(ExtractionOperation *)operation accurateRipChecksum:(NSNumber *)checksum;
@end

@implementation CopyTracksSheetController

@synthesize disk = _disk;
@synthesize trackIDs = _trackIDs;

@synthesize trackExtractionRecords = _trackExtractionRecords;

@synthesize compactDisc = _compactDisc;
@synthesize driveInformation = _driveInformation;
@synthesize managedObjectContext = _managedObjectContext;

@synthesize operationQueue = _operationQueue;

@synthesize accurateRipPressingToMatch = _accurateRipPressingToMatch;
@synthesize accurateRipPressingOffset = _accurateRipPressingOffset;

- (id) init
{
	if((self = [super initWithWindowNibName:@"CopyTracksSheet"])) {
		// Create our own context for accessing the store
		self.managedObjectContext = [[NSManagedObjectContext alloc] init];
		[self.managedObjectContext setPersistentStoreCoordinator:[[[NSApplication sharedApplication] delegate] persistentStoreCoordinator]];

		self.operationQueue = [[NSOperationQueue alloc] init];
		[self.operationQueue setMaxConcurrentOperationCount:1];
		
		_activeTimers = [NSMutableArray array];
	}
	return self;
}

- (void) finalize
{
	if(_disk)
		CFRelease(_disk), _disk = NULL;
	
	[super finalize];
}

- (void) awakeFromNib
{
}

- (void) observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
	if(kAudioExtractionKVOContext == context) {
		ExtractionOperation *operation = (ExtractionOperation *)object;
		
		if([keyPath isEqualToString:@"isExecuting"]) {
			if([operation isExecuting]) {
				// Schedule a timer which will update the UI while the operations runs
				NSTimer *timer = [NSTimer timerWithTimeInterval:0.3 target:self selector:@selector(audioExtractionTimerFired:) userInfo:operation repeats:YES];
				[[NSRunLoop mainRunLoop] addTimer:timer forMode:NSRunLoopCommonModes];
				[_activeTimers addObject:timer];
				
				if(operation.trackIDs) {
					NSManagedObjectID *trackID = operation.trackIDs.lastObject;
					
					// Fetch the TrackDescriptor object from the context and ensure it is the correct class
					NSManagedObject *managedObject = [self.managedObjectContext objectWithID:trackID];
					if(![managedObject isKindOfClass:[TrackDescriptor class]])
						return;
					
					TrackDescriptor *track = (TrackDescriptor *)managedObject;				
					
					// Create a user-friendly representation of the track being processed
					if(track.metadata.title)
						[_statusTextField setStringValue:track.metadata.title];
					else
						[_statusTextField setStringValue:[track.number stringValue]];
					
					// Check to see if this track has been extracted before
					ExtractionOperation *copyOperation = [_tracksExtractedButNotVerified objectForKey:[track objectID]];
					if(copyOperation)
						[_detailedStatusTextField setStringValue:NSLocalizedString(@"Extracting audio (verification phase)", @"")];
					else
						[_detailedStatusTextField setStringValue:NSLocalizedString(@"Extracting audio (copy phase)", @"")];
				}
				else {
					[_detailedStatusTextField setStringValue:NSLocalizedString(@"fnord", @"")];
				}
			}
		}
		else if([keyPath isEqualToString:@"isCancelled"] || [keyPath isEqualToString:@"isFinished"]) {
			[operation removeObserver:self forKeyPath:@"isExecuting"];
			[operation removeObserver:self forKeyPath:@"isCancelled"];
			[operation removeObserver:self forKeyPath:@"isFinished"];
			
			// Process the extracted audio
			[self processExtractionOperation:operation];

			// If no tracks are being processed and none remain to be extracted, we are finished			
			if(![[self.operationQueue operations] count] && ![_tracksToBeExtracted count]) {
				
				// Remove any active timers
				[_activeTimers makeObjectsPerformSelector:@selector(invalidate)];
				[_activeTimers removeAllObjects];
				
				self.disk = NULL;
				
				[[NSApplication sharedApplication] endSheet:self.window returnCode:NSOKButton];
				[self.window orderOut:self];
			}
		}
	}
	else
		[super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
}

- (void) setDisk:(DADiskRef)disk
{
	if(disk != _disk) {
		if(_disk)
			CFRelease(_disk), _disk = NULL;
		
		self.compactDisc = nil;
		self.driveInformation = nil;
		
		if(disk) {
			_disk = DADiskCopyWholeDisk(disk);
			
			self.compactDisc = [CompactDisc compactDiscWithDADiskRef:self.disk inManagedObjectContext:self.managedObjectContext];
			self.driveInformation = [DriveInformation driveInformationWithDADiskRef:self.disk inManagedObjectContext:self.managedObjectContext];
		}
	}
}

- (void) beginCopyTracksSheetForWindow:(NSWindow *)window modalDelegate:(id)modalDelegate didEndSelector:(SEL)didEndSelector contextInfo:(void *)contextInfo
{
	NSParameterAssert(nil != window);
	
	// Save the owning window's information
	_sheetOwner = window;
	_sheetModalDelegate = modalDelegate;
	_sheetDidEndSelector = didEndSelector;
	_sheetContextInfo = contextInfo;
	
	// Start the sheet cascade
	[self beginReadMCNSheet];
}

- (IBAction) cancel:(id)sender
{
	[self.operationQueue cancelAllOperations];

	// Remove any active timers
	[_activeTimers makeObjectsPerformSelector:@selector(invalidate)];
	[_activeTimers removeAllObjects];
	
	self.disk = NULL;
	
	[[NSApplication sharedApplication] endSheet:self.window returnCode:NSCancelButton];
	[self.window orderOut:sender];
}

@end

@implementation CopyTracksSheetController (Callbacks)

- (void) didPresentErrorWithRecovery:(BOOL)didRecover contextInfo:(void *)contextInfo
{
	
#pragma unused(contextInfo)
	
	// Remove any active timers
	[_activeTimers makeObjectsPerformSelector:@selector(invalidate)];
	[_activeTimers removeAllObjects];
	
	self.disk = NULL;

	[[NSApplication sharedApplication] endSheet:self.window returnCode:(didRecover ? NSOKButton : NSCancelButton)];	
	[self.window orderOut:self];
}

- (void) audioExtractionTimerFired:(NSTimer *)timer
{
	ExtractionOperation *operation = (ExtractionOperation *)[timer userInfo];
	
	if([operation isFinished] || [operation isCancelled]) {
		[_activeTimers removeObjectIdenticalTo:timer];
		[timer invalidate];
		return;
	}
	
	[_progressIndicator setDoubleValue:operation.fractionComplete];

//	NSTimeInterval secondsElapsed = [[NSDate date] timeIntervalSinceDate:operation.startTime];
//	NSTimeInterval estimatedTimeRemaining = (secondsElapsed / operation.fractionComplete) - secondsElapsed;
	
//	NSLog(@"C2 errors: %i", [operation.errorFlags countOfOnes]);
}

@end

@implementation CopyTracksSheetController (SheetCallbacks)

- (void) showReadMCNSheetDidEnd:(NSWindow *)sheet returnCode:(int)returnCode contextInfo:(void *)contextInfo
{
	NSParameterAssert(nil != sheet);
	
	[sheet orderOut:self];
	
	ReadMCNSheetController *sheetController = (ReadMCNSheetController *)contextInfo;
	sheetController = nil;
	
	if(NSCancelButton == returnCode) {
		[self cancel:self];
		return;
	}
	
	[self beginReadISRCsSheet];
}

- (void) showReadISRCsSheetDidEnd:(NSWindow *)sheet returnCode:(int)returnCode contextInfo:(void *)contextInfo
{
	NSParameterAssert(nil != sheet);
	
	[sheet orderOut:self];
	
	ReadISRCsSheetController *sheetController = (ReadISRCsSheetController *)contextInfo;
	sheetController = nil;
	
	if(NSCancelButton == returnCode) {
		[self cancel:self];
		return;
	}
	
	[self beginDetectPregapsSheet];
}

- (void) showDetectPregapsSheetDidEnd:(NSWindow *)sheet returnCode:(int)returnCode contextInfo:(void *)contextInfo
{
	NSParameterAssert(nil != sheet);
	
	[sheet orderOut:self];
	
	DetectPregapsSheetController *sheetController = (DetectPregapsSheetController *)contextInfo;
	sheetController = nil;

	if(NSCancelButton == returnCode) {
		[self cancel:self];
		return;
	}
	
	[self beginCalculateAccurateRipOffsetsSheet];
}

- (void) showCalculateAccurateRipOffsetsSheetDidEnd:(NSWindow *)sheet returnCode:(int)returnCode contextInfo:(void *)contextInfo
{
	NSParameterAssert(nil != sheet);
	NSParameterAssert(nil != contextInfo);
	
	[sheet orderOut:self];
	
	CalculateAccurateRipOffsetsSheetController *sheetController = (CalculateAccurateRipOffsetsSheetController *)contextInfo;

	if(NSCancelButton == returnCode) {
		sheetController = nil;
		[self cancel:self];
		return;
	}
	
	NSPredicate *zeroOffsetPredicate = [NSPredicate predicateWithFormat:@"%K == 0", kReadOffsetKey];
	NSArray *matchingPressingsWithZeroOffset = [sheetController.accurateRipOffsets filteredArrayUsingPredicate:zeroOffsetPredicate];
	if([matchingPressingsWithZeroOffset count]) {
		NSManagedObjectID *accurateRipTrackID = [[matchingPressingsWithZeroOffset lastObject] objectForKey:kAccurateRipTrackIDKey];
		
		// Fetch the AccurateRipTrackRecord object from the context and ensure it is the correct class
		NSManagedObject *managedObject = [self.managedObjectContext objectWithID:accurateRipTrackID];
		if(![managedObject isKindOfClass:[AccurateRipTrackRecord class]]) {
//			[self presentError:error modalForWindow:self.window delegate:self didPresentSelector:@selector(didPresentErrorWithRecovery:contextInfo:) contextInfo:NULL];
			return;
		}
		
		AccurateRipTrackRecord *accurateRipTrack = (AccurateRipTrackRecord *)managedObject;
		self.accurateRipPressingToMatch = accurateRipTrack.disc;
		self.accurateRipPressingOffset = 0;
	}
	else {
		NSLog(@"FIXME: USE ALTERNATE AR PRESSING");
		NSLog(@"Possibilities: %@", sheetController.accurateRipOffsets);
		
		self.accurateRipPressingOffset = 10;
	}

	sheetController = nil;
	
	[self performShowCopyTracksSheet];	
}

@end


@implementation CopyTracksSheetController (Private)

- (void) beginReadMCNSheet
{
	// Read the MCN for the disc, if not present
	if(!self.compactDisc.metadata.MCN) {
		ReadMCNSheetController *sheetController = [[ReadMCNSheetController alloc] init];
		
		sheetController.disk = self.disk;
		
		[sheetController beginReadMCNSheetForWindow:_sheetOwner
										modalDelegate:self 
									   didEndSelector:@selector(showReadMCNSheetDidEnd:returnCode:contextInfo:) 
										  contextInfo:sheetController];
	}
	else
		[self beginReadISRCsSheet];
}

- (void) beginReadISRCsSheet
{
	NSMutableArray *tracksWithoutISRCs = [NSMutableArray array];
	
	// Ensure ISRCs have been read for the selected tracks
	for(NSManagedObjectID *objectID in self.trackIDs) {
		
		// Fetch the TrackDescriptor object from the context and ensure it is the correct class
		NSManagedObject *managedObject = [self.managedObjectContext objectWithID:objectID];
		if(![managedObject isKindOfClass:[TrackDescriptor class]]) {
//			[self presentError:error modalForWindow:self.window delegate:self didPresentSelector:@selector(didPresentErrorWithRecovery:contextInfo:) contextInfo:NULL];
			continue;
		}
		
		TrackDescriptor *track = (TrackDescriptor *)managedObject;
		
		// Don't waste time re-reading a pre-existing ISRC
		if(!track.metadata.ISRC)
			[tracksWithoutISRCs addObject:track];
	}
	
	if([tracksWithoutISRCs count]) {
		ReadISRCsSheetController *sheetController = [[ReadISRCsSheetController alloc] init];
		
		sheetController.disk = self.disk;
		sheetController.trackIDs = [tracksWithoutISRCs valueForKey:@"objectID"];
		
		[sheetController beginReadISRCsSheetForWindow:_sheetOwner
										modalDelegate:self 
									   didEndSelector:@selector(showReadISRCsSheetDidEnd:returnCode:contextInfo:) 
										  contextInfo:sheetController];
	}
	else
		[self beginDetectPregapsSheet];
}

- (void) beginDetectPregapsSheet
{
	NSMutableArray *tracksWithoutPregaps = [NSMutableArray array];
	
	// Ensure pregaps have been read for the selected tracks
	for(NSManagedObjectID *objectID in self.trackIDs) {
		
		// Fetch the TrackDescriptor object from the context and ensure it is the correct class
		NSManagedObject *managedObject = [self.managedObjectContext objectWithID:objectID];
		if(![managedObject isKindOfClass:[TrackDescriptor class]]) {
//			[self presentError:error modalForWindow:self.window delegate:self didPresentSelector:@selector(didPresentErrorWithRecovery:contextInfo:) contextInfo:NULL];
			continue;
		}
		
		TrackDescriptor *track = (TrackDescriptor *)managedObject;
		
		// Grab pre-gaps
		if(!track.pregap)
			[tracksWithoutPregaps addObject:track];
	}
	
	if([tracksWithoutPregaps count]) {
		DetectPregapsSheetController *sheetController = [[DetectPregapsSheetController alloc] init];
		
		sheetController.disk = self.disk;
		sheetController.trackIDs = [tracksWithoutPregaps valueForKey:@"objectID"];
		
		[sheetController beginDetectPregapsSheetForWindow:_sheetOwner
											modalDelegate:self 
										   didEndSelector:@selector(showDetectPregapsSheetDidEnd:returnCode:contextInfo:) 
											  contextInfo:sheetController];
	}
	else
		[self beginCalculateAccurateRipOffsetsSheet];
}

- (void) beginCalculateAccurateRipOffsetsSheet
{
	if(self.compactDisc.accurateRipDiscs) {
		CalculateAccurateRipOffsetsSheetController *sheetController = [[CalculateAccurateRipOffsetsSheetController alloc] init];
	
		sheetController.disk = self.disk;
	
		[sheetController beginCalculateAccurateRipOffsetsSheetForWindow:_sheetOwner
														  modalDelegate:self 
														 didEndSelector:@selector(showCalculateAccurateRipOffsetsSheetDidEnd:returnCode:contextInfo:) 
															contextInfo:sheetController];
	}
	else
		[self performShowCopyTracksSheet];
}

- (void) performShowCopyTracksSheet
{
	// Show ourselves
	[[NSApplication sharedApplication] beginSheet:self.window
								   modalForWindow:_sheetOwner
									modalDelegate:_sheetModalDelegate
								   didEndSelector:_sheetDidEndSelector
									  contextInfo:_sheetContextInfo];

	// Copy the array containing the tracks to be extracted
	_tracksToBeExtracted = [self.trackIDs mutableCopy];
	_tracksExtractedButNotVerified = [NSMutableDictionary dictionary];
	_sectorIndexesNeedingVerification = [NSMutableDictionary dictionary];
	
	// Set up the extraction records
	_trackExtractionRecords = [NSMutableArray array];
	
	// Get started on the first one
	[self startExtractingNextTrack];
}

- (void) startExtractingNextTrack
{
	if(![_tracksToBeExtracted count])
		return;

	// Remove the last object
	NSManagedObjectID *objectID = [_tracksToBeExtracted lastObject];
	[_tracksToBeExtracted removeLastObject];
	
	// Fetch the TrackDescriptor object from the context and ensure it is the correct class
	NSManagedObject *managedObject = [self.managedObjectContext objectWithID:objectID];
	if(![managedObject isKindOfClass:[TrackDescriptor class]]) {
//		[self presentError:error modalForWindow:self.window delegate:self didPresentSelector:@selector(didPresentErrorWithRecovery:contextInfo:) contextInfo:NULL];
		return;
	}
	
	
	TrackDescriptor *track = (TrackDescriptor *)managedObject;

	[self extractWholeTrack:track];
}

- (void) extractWholeTrack:(TrackDescriptor *)track
{
	NSParameterAssert(nil != track);
	
	[self extractPartialTrack:track sectorRange:track.sectorRange];
}

- (void) extractPartialTrack:(TrackDescriptor *)track sectorRange:(SectorRange *)sectorRange
{
	NSParameterAssert(nil != track);
	NSParameterAssert(nil != sectorRange);
	
	[self extractPartialTrack:track sectorRange:sectorRange enforceMinimumReadSize:NO];	
}

- (void) extractPartialTrack:(TrackDescriptor *)track sectorRange:(SectorRange *)sectorRange enforceMinimumReadSize:(BOOL)enforceMinimumReadSize
{
	NSParameterAssert(nil != track);
	NSParameterAssert(nil != sectorRange);
	
	// Should a block of at least MINIMUM_DISC_READ_SIZE be read?
	if(enforceMinimumReadSize && MINIMUM_DISC_READ_SIZE > sectorRange.byteSize) {
		NSUInteger sizeIncrease = MINIMUM_DISC_READ_SIZE - sectorRange.byteSize;
		NSUInteger sectorOffset = ((sizeIncrease / 2)  / kCDSectorSizeCDDA) + 1;
		
		NSUInteger newFirstSector = sectorRange.firstSector;
		if(newFirstSector > sectorOffset)
			newFirstSector -= sectorOffset;
		NSUInteger newLastSector = sectorRange.lastSector + sectorOffset;
		
		sectorRange = [SectorRange sectorRangeWithFirstSector:newFirstSector lastSector:newLastSector];
	}
	
	// Audio extraction
	ExtractionOperation *extractionOperation = [[ExtractionOperation alloc] init];
	
	extractionOperation.disk = self.disk;
	extractionOperation.sectors = sectorRange;
	extractionOperation.allowedSectors = self.compactDisc.firstSession.sectorRange;
	extractionOperation.trackIDs = [NSArray arrayWithObject:[track objectID]];
	extractionOperation.readOffset = self.driveInformation.readOffset;
	extractionOperation.URL = temporaryURLWithExtension(@"wav");
	
	// Observe the operation's progress
	[extractionOperation addObserver:self forKeyPath:@"isExecuting" options:NSKeyValueObservingOptionNew context:kAudioExtractionKVOContext];
	[extractionOperation addObserver:self forKeyPath:@"isCancelled" options:NSKeyValueObservingOptionNew context:kAudioExtractionKVOContext];
	[extractionOperation addObserver:self forKeyPath:@"isFinished" options:NSKeyValueObservingOptionNew context:kAudioExtractionKVOContext];
	
	// Do it.  Do it.  Do it.
	[self.operationQueue addOperation:extractionOperation];
}

- (void) extractSectorIndexes:(NSIndexSet *)sectorIndexes inTrack:(TrackDescriptor *)track coalesceRanges:(BOOL)coalesceRanges
{
	NSParameterAssert(nil != track);
	NSParameterAssert(nil != sectorIndexes);

	NSUInteger trackFirstSector = track.firstSector.unsignedIntegerValue;
	
	// Coalesce the index set into ranges to minimize the number of disc accesses
	if(coalesceRanges) {
		NSUInteger firstIndex = NSNotFound;
		NSUInteger latestIndex = NSNotFound;
		NSUInteger sectorIndex = [sectorIndexes firstIndex];

		for(;;) {
			// Last sector
			if(NSNotFound == sectorIndex) {
				if(NSNotFound != firstIndex) {
					if(firstIndex == latestIndex)
						[self extractPartialTrack:track sectorRange:[SectorRange sectorRangeWithSector:(trackFirstSector + firstIndex)] enforceMinimumReadSize:YES];
					else
						[self extractPartialTrack:track sectorRange:[SectorRange sectorRangeWithFirstSector:(trackFirstSector + firstIndex) lastSector:(trackFirstSector + latestIndex)] enforceMinimumReadSize:YES];
				}
				
				break;
			}
			
			// Consolidate this sector into the current range
			if(latestIndex == (sectorIndex - 1))
				latestIndex = sectorIndex;
			// Store the previous range and start a new one
			else {
				if(NSNotFound != firstIndex) {
					if(firstIndex == latestIndex)
						[self extractPartialTrack:track sectorRange:[SectorRange sectorRangeWithSector:(trackFirstSector + firstIndex)] enforceMinimumReadSize:YES];
					else
						[self extractPartialTrack:track sectorRange:[SectorRange sectorRangeWithFirstSector:(trackFirstSector + firstIndex) lastSector:(trackFirstSector + latestIndex)] enforceMinimumReadSize:YES];
				}
				
				firstIndex = sectorIndex;
				latestIndex = sectorIndex;
			}
			
			sectorIndex = [sectorIndexes indexGreaterThanIndex:sectorIndex];
		}
	}
	else {
		NSUInteger sectorIndex = [sectorIndexes firstIndex];
		while(NSNotFound != sectorIndex) {
			[self extractPartialTrack:track sectorRange:[SectorRange sectorRangeWithSector:(trackFirstSector + sectorIndex)] enforceMinimumReadSize:YES];
			sectorIndex = [sectorIndexes indexGreaterThanIndex:sectorIndex];			
		}
		
	}	
}

- (void) processExtractionOperation:(ExtractionOperation *)operation
{
	NSParameterAssert(nil != operation);
	
	// Delete the output file if the operation was cancelled or did not succeed
	if(operation.error || operation.isCancelled) {
		if(operation.error)
			[self presentError:operation.error modalForWindow:self.window delegate:self didPresentSelector:@selector(didPresentErrorWithRecovery:contextInfo:) contextInfo:NULL];
		
		NSError *error = nil;
		if(![[NSFileManager defaultManager] removeItemAtPath:operation.URL.path error:&error])
			[self presentError:error modalForWindow:self.window delegate:self didPresentSelector:@selector(didPresentErrorWithRecovery:contextInfo:) contextInfo:NULL];

		return;
	}
	
#if DEBUG
	NSLog(@"Extraction to %@ finished, %u C2 errors.  MD5 = %@", operation.URL.path, operation.errorFlags.countOfOnes, operation.MD5);
#endif
	
	if(operation.trackIDs)
		[self processExtractionOperationForWholeTrack:operation];
	else
		[self processExtractionOperationForPartialTrack:operation];
}

- (void) processExtractionOperationForWholeTrack:(ExtractionOperation *)operation
{
	NSParameterAssert(nil != operation);
	NSParameterAssert(1 == [[operation trackIDs] count]);
	
	// Fetch the track this operation represents
	NSManagedObjectID *trackID = [operation.trackIDs lastObject];
	NSManagedObject *managedObject = [self.managedObjectContext objectWithID:trackID];
	if(![managedObject isKindOfClass:[TrackDescriptor class]])
		return;
	
	TrackDescriptor *track = (TrackDescriptor *)managedObject;			
	
	// Calculate the actual AccurateRip checksums of the extracted audio
	NSNumber *trackActualAccurateRipChecksum = [self calculateAccurateRipChecksumForExtractionOperation:operation];
	
	// If this disc was found in Accurate Rip, verify the track's checksum
	if(self.accurateRipPressingToMatch) {
		AccurateRipTrackRecord *accurateRipTrack = [self.accurateRipPressingToMatch trackNumber:track.number.unsignedIntegerValue];
			
		// If the track was accurately ripped, ship it off to the encoder
		if(accurateRipTrack && accurateRipTrack.checksum.unsignedIntegerValue == trackActualAccurateRipChecksum.unsignedIntegerValue) {
			// Create the extraction record
			TrackExtractionRecord *extractionRecord = [self createTrackExtractionRecordForOperation:operation accurateRipChecksum:trackActualAccurateRipChecksum];
			extractionRecord.accurateRipConfidenceLevel = accurateRipTrack.confidenceLevel;
			
			NSError *error = nil;
			if(![[EncoderManager sharedEncoderManager] encodeURL:operation.URL forTrackExtractionRecord:extractionRecord error:&error]) {
				[self.managedObjectContext deleteObject:extractionRecord];
				[self presentError:error modalForWindow:self.window delegate:self didPresentSelector:@selector(didPresentErrorWithRecovery:contextInfo:) contextInfo:NULL];
				return;
			}
			
			[_trackExtractionRecords addObject:extractionRecord];
			[self startExtractingNextTrack];
			
			return;
		}
		
		// If the checksum was not verified, fall through to handling below
	}
	
	// Re-rip portions of the track if any C2 error flags were returned
	if(operation.errorFlags.countOfOnes) {
		NSIndexSet *positionOfErrors = [operation.errorFlags indexSetForOnes];
		
		NSIndexSet *currentSectorsNeedingVerification = [_sectorIndexesNeedingVerification objectForKey:[track objectID]];
		if(currentSectorsNeedingVerification) {
			NSMutableIndexSet *newSectorsNeedingVerification = [currentSectorsNeedingVerification mutableCopy];
			[newSectorsNeedingVerification addIndexes:positionOfErrors];
			[_sectorIndexesNeedingVerification setObject:newSectorsNeedingVerification forKey:[track objectID]];
		}
		else
			[_sectorIndexesNeedingVerification setObject:positionOfErrors forKey:[track objectID]];

		[self extractSectorIndexes:positionOfErrors inTrack:track coalesceRanges:YES];
	}
	// No C2 errors were encountered
	else {
		[_detailedStatusTextField setStringValue:NSLocalizedString(@"Verifying copy integrity", @"")];

		// Check to see if this track has been extracted before
		ExtractionOperation *copyOperation = [_tracksExtractedButNotVerified objectForKey:[track objectID]];
		
		// The track is verified if a copy operation has already been performed
		// and the SHA1 hashes for the copy and this verification operation match
		if(copyOperation && [copyOperation.SHA1 isEqualToString:operation.SHA1]) {
			[_tracksExtractedButNotVerified removeObjectForKey:[track objectID]];

			// Remove the old temporary files
			NSError *error = nil;
			if(![[NSFileManager defaultManager] removeItemAtPath:copyOperation.URL.path error:&error])
				NSLog(@"Error removing temporary file: %@", error);
			
			// Ship the track off to the encoder
			TrackExtractionRecord *extractionRecord = [self createTrackExtractionRecordForOperation:operation accurateRipChecksum:trackActualAccurateRipChecksum];
			if(![[EncoderManager sharedEncoderManager] encodeURL:operation.URL forTrackExtractionRecord:extractionRecord error:&error]) {
				[self.managedObjectContext deleteObject:extractionRecord];
				[self presentError:error modalForWindow:self.window delegate:self didPresentSelector:@selector(didPresentErrorWithRecovery:contextInfo:) contextInfo:NULL];
				return;
			}
			
			[_trackExtractionRecords addObject:extractionRecord];
			[self startExtractingNextTrack];
		}
		// This track has been extracted before but the SHA1 hashes don't match
		// Determine where the differences are and re-extract those sections
		else if(copyOperation) {
#if DEBUG
			NSLog(@"Track extracted before but SHA1 hashes don't match.  No C2 errors.");
#endif
			
			NSError *error = nil;
			NSIndexSet *nonMatchingSectorIndexes = compareFilesForNonMatchingSectors(copyOperation.URL, operation.URL, &error);
			
			// Sanity check
			if(!nonMatchingSectorIndexes.count) {
				NSLog(@"Internal inconsistency: SHA1 hashes don't match but no sector-level differences found");
				return;
			}
			
			[_trackPartialExtractions addObject:operation];
			
			NSIndexSet *currentSectorsNeedingVerification = [_sectorIndexesNeedingVerification objectForKey:[track objectID]];
			if(currentSectorsNeedingVerification) {
				NSMutableIndexSet *newSectorsNeedingVerification = [currentSectorsNeedingVerification mutableCopy];
				[newSectorsNeedingVerification addIndexes:nonMatchingSectorIndexes];
				[_sectorIndexesNeedingVerification setObject:newSectorsNeedingVerification forKey:[track objectID]];
			}
			else
				[_sectorIndexesNeedingVerification setObject:nonMatchingSectorIndexes forKey:[track objectID]];
			
			[self extractSectorIndexes:nonMatchingSectorIndexes inTrack:track coalesceRanges:YES];
		}
		// This track has not been extracted before, so re-rip the entire track (verification)
		else {
			[_tracksExtractedButNotVerified setObject:operation forKey:[track objectID]];			
			[self extractWholeTrack:track];
		}
	}
}

- (void) processExtractionOperationForPartialTrack:(ExtractionOperation *)operation
{
	NSParameterAssert(nil != operation);
	
	// Determine the whole track copy operation corresponding to this operation
	ExtractionOperation *copyOperation = nil;
	for(ExtractionOperation *previousOperation in [_tracksExtractedButNotVerified allValues]) {
		if([previousOperation.sectors containsSectorRange:operation.sectors])
			copyOperation = previousOperation;
	}
	
	// Determine any partial extractions that overlap this sector range
	NSMutableArray *previousExtractions = [NSMutableArray array];
	for(ExtractionOperation *previousOperation in _trackPartialExtractions) {
		if([previousOperation.sectors intersectsSectorRange:operation.sectors])
			[previousExtractions addObject:previousOperation];
	}
	
	// Iterate through all the matching operations and check for two matches
}

- (NSNumber *) calculateAccurateRipChecksumForExtractionOperation:(ExtractionOperation *)operation
{
	NSParameterAssert(nil != operation);
	NSParameterAssert(1 == [[operation trackIDs] count]);
	
	[_detailedStatusTextField setStringValue:NSLocalizedString(@"Calculating AccurateRip checksums", @"")];
		
	NSManagedObjectID *trackID = operation.trackIDs.lastObject;
	NSManagedObject *managedObject = [self.managedObjectContext objectWithID:trackID];
	if(![managedObject isKindOfClass:[TrackDescriptor class]])
		return nil;
			
	TrackDescriptor *track = (TrackDescriptor *)managedObject;
	NSUInteger accurateRipChecksum = calculateAccurateRipChecksumForFile(operation.URL, 
																		 self.compactDisc.firstSession.firstTrack.number.unsignedIntegerValue == track.number.unsignedIntegerValue,
																		 self.compactDisc.firstSession.lastTrack.number.unsignedIntegerValue == track.number.unsignedIntegerValue);
	
	// Since Core Data only stores signed integers, cast the unsigned checksum to signed for storage
	return [NSNumber numberWithInt:(int32_t)accurateRipChecksum];
}

#if 0
- (NSDictionary *) calculateAccurateRipChecksumsForExtractionOperation:(ExtractionOperation *)operation
{
	NSParameterAssert(nil != operation);
	NSParameterAssert(1 == [[operation trackIDs] count]);
	
	// If trackIDs is set, the ExtractionOperation represents one or more whole tracks (and not an arbitrary range of sectors)
	// If this is the case, calculate the AccurateRip checksum(s) for the extracted tracks
	// This will allow tracks to be verified later if for some reason AccurateRip isn't available during ripping
	if(operation.trackIDs) {
		[_detailedStatusTextField setStringValue:NSLocalizedString(@"Calculating AccurateRip checksums", @"")];
		
		NSMutableDictionary *actualAccurateRipChecksums = [NSMutableDictionary dictionary];
		NSUInteger sectorOffset = 0;
		
		for(NSManagedObjectID *trackID in operation.trackIDs) {
			NSManagedObject *managedObject = [self.managedObjectContext objectWithID:trackID];
			if(![managedObject isKindOfClass:[TrackDescriptor class]])
				continue;
			
			TrackDescriptor *track = (TrackDescriptor *)managedObject;			
			SectorRange *trackSectorRange = track.sectorRange;
			
			// Since a file may contain multiple non-sequential tracks, there is not a 1:1 correspondence between
			// LBAs on the disc and sample frame offsets in the file.  Adjust for that here
			SectorRange *adjustedSectorRange = [SectorRange sectorRangeWithFirstSector:sectorOffset sectorCount:trackSectorRange.length];
			sectorOffset += trackSectorRange.length;
			
			NSUInteger accurateRipChecksum = calculateAccurateRipChecksumForFileRegion(operation.URL, 
																					   adjustedSectorRange.firstSector,
																					   adjustedSectorRange.lastSector,
																					   self.compactDisc.firstSession.firstTrack.number.unsignedIntegerValue == track.number.unsignedIntegerValue,
																					   self.compactDisc.firstSession.lastTrack.number.unsignedIntegerValue == track.number.unsignedIntegerValue);
			
			// Since Core Data only stores signed integers, cast the unsigned checksum to signed for storage
			[actualAccurateRipChecksums setObject:[NSNumber numberWithInt:(int32_t)accurateRipChecksum]
										   forKey:[track objectID]];			
		}
		
		return [actualAccurateRipChecksums copy];
	}
	else
		return nil;
}
#endif

- (TrackExtractionRecord *) createTrackExtractionRecordForOperation:(ExtractionOperation *)operation accurateRipChecksum:(NSNumber *)checksum
{
	NSParameterAssert(nil != operation);
	NSParameterAssert(1 == [[operation trackIDs] count]);
	
	// Fetch the track this operation represents
	NSManagedObjectID *trackID = [operation.trackIDs lastObject];
	NSManagedObject *managedObject = [self.managedObjectContext objectWithID:trackID];
	if(![managedObject isKindOfClass:[TrackDescriptor class]])
		return nil;
	
	TrackDescriptor *track = (TrackDescriptor *)managedObject;			

	TrackExtractionRecord *extractionRecord = [NSEntityDescription insertNewObjectForEntityForName:@"TrackExtractionRecord" 
																			inManagedObjectContext:self.managedObjectContext];
	
	extractionRecord.date = [NSDate date];
	extractionRecord.drive = self.driveInformation;
	extractionRecord.errorFlags = operation.errorFlags;
	extractionRecord.MD5 = operation.MD5;
	extractionRecord.SHA1 = operation.SHA1;
	extractionRecord.track = track;
	extractionRecord.accurateRipChecksum = checksum;
	
	return extractionRecord;
}

#if 0
- (BOOL) encodeTrack:(TrackDescriptor *)track error:(NSError **)error
{
	NSParameterAssert(nil != track);
	// Create the extraction record
	TrackExtractionRecord *extractionRecord = [self createTrackExtractionRecordForOperation:operation accurateRipChecksum:trackActualAccurateRipChecksum];
	[_trackExtractionRecords addObject:extractionRecord];
	
	if(![[EncoderManager sharedEncoderManager] encodeURL:operation.URL forTrackExtractionRecord:extractionRecord error:&error]) {
		[self.managedObjectContext deleteObject:extractionRecord];
		[self presentError:error modalForWindow:self.window delegate:self didPresentSelector:@selector(didPresentErrorWithRecovery:contextInfo:) contextInfo:NULL];
		return;
	}
	
}
#endif	

@end
