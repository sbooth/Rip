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

#import "NSIndexSet+SetMethods.h"

#include <AudioToolbox/AudioFile.h>

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

@property (readonly) NSArray * orderedTracks;
@property (readonly) NSArray * orderedTracksRemainingToBeExtracted;

@end

@interface CopyTracksSheetController (Callbacks)
- (void) didPresentErrorWithRecovery:(BOOL)didRecover contextInfo:(void *)contextInfo;
- (void) audioExtractionTimerFired:(NSTimer *)timer;
@end

@interface CopyTracksSheetController (SheetCallbacks)
- (void) showReadMCNSheetDidEnd:(NSWindow *)sheet returnCode:(int)returnCode contextInfo:(void *)contextInfo;
- (void) showReadISRCsSheetDidEnd:(NSWindow *)sheet returnCode:(int)returnCode contextInfo:(void *)contextInfo;
- (void) showDetectPregapsSheetDidEnd:(NSWindow *)sheet returnCode:(int)returnCode contextInfo:(void *)contextInfo;
@end

@interface CopyTracksSheetController (Private)
- (void) beginReadMCNSheet;
- (void) beginReadISRCsSheet;
- (void) beginDetectPregapsSheet;
- (void) performShowCopyTracksSheet;

- (void) startExtractingNextTrack;

- (void) extractWholeTrack:(TrackDescriptor *)track;
- (void) extractPartialTrack:(TrackDescriptor *)track sectorRange:(SectorRange *)sectorRange;
- (void) extractPartialTrack:(TrackDescriptor *)track sectorRange:(SectorRange *)sectorRange enforceMinimumReadSize:(BOOL)enforceMinimumReadSize;

- (void) extractSectors:(NSIndexSet *)sectorIndexes forTrack:(TrackDescriptor *)track coalesceRanges:(BOOL)coalesceRanges;

- (void) processExtractionOperation:(ExtractionOperation *)operation;
- (void) processExtractionOperationForWholeTrack:(ExtractionOperation *)operation;
- (void) processExtractionOperationForPartialTrack:(ExtractionOperation *)operation;

- (NSNumber *) calculateAccurateRipChecksumForExtractionOperation:(ExtractionOperation *)operation;
- (NSArray *) determinePossibleAccurateRipOffsetForTrack:(TrackDescriptor *)track URL:(NSURL *)URL;

- (TrackExtractionRecord *) createTrackExtractionRecordForOperation:(ExtractionOperation *)operation accurateRipChecksum:(NSNumber *)checksum;

- (BOOL) synthesizeTrack:(TrackDescriptor *)track toURL:(NSURL *)fileURL error:(NSError **)error;
@end

@implementation CopyTracksSheetController

@synthesize disk = _disk;
@synthesize trackIDs = _trackIDs;

@synthesize trackExtractionRecords = _trackExtractionRecords;

@synthesize compactDisc = _compactDisc;
@synthesize driveInformation = _driveInformation;
@synthesize managedObjectContext = _managedObjectContext;

@synthesize operationQueue = _operationQueue;

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
					
					// Determine if this operation represents a whole track extraction or a partial track extraction
					BOOL isWholeTrack = [operation.sectors containsSectorRange:track.sectorRange];

					// Check to see if this track has been extracted before
					ExtractionOperation *copyOperation = [_tracksExtractedButNotVerified objectForKey:[track objectID]];
					if(!isWholeTrack)
						[_detailedStatusTextField setStringValue:[NSString stringWithFormat:NSLocalizedString(@"Re-extracting sectors %u - %u", @""), operation.sectors.firstSector, operation.sectors.lastSector]];
					else if(copyOperation)
						[_detailedStatusTextField setStringValue:NSLocalizedString(@"Verifying audio", @"")];
					else
						[_detailedStatusTextField setStringValue:NSLocalizedString(@"Extracting audio", @"")];
				}
				else
					[_detailedStatusTextField setStringValue:NSLocalizedString(@"Unknown", @"")];
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

- (NSArray *) orderedTracks
{
	// Fetch the tracks to be extracted and sort them by track number
	NSPredicate *trackPredicate  = [NSPredicate predicateWithFormat:@"self IN %@", [self.trackIDs allObjects]];
	NSSortDescriptor *trackNumberSortDescriptor = [[NSSortDescriptor alloc] initWithKey:@"number" ascending:YES];
	NSEntityDescription *trackEntityDescription = [NSEntityDescription entityForName:@"TrackDescriptor" inManagedObjectContext:self.managedObjectContext];
	
	NSFetchRequest *trackFetchRequest = [[NSFetchRequest alloc] init];
	
	[trackFetchRequest setEntity:trackEntityDescription];
	[trackFetchRequest setPredicate:trackPredicate];
	[trackFetchRequest setSortDescriptors:[NSArray arrayWithObject:trackNumberSortDescriptor]];
	
	NSError *error = nil;
	NSArray *tracks = [self.managedObjectContext executeFetchRequest:trackFetchRequest error:&error];
	if(!tracks) {
		[self presentError:error modalForWindow:self.window delegate:self didPresentSelector:@selector(didPresentErrorWithRecovery:contextInfo:) contextInfo:NULL];
		return nil;
	}
	
	return tracks;
}

- (NSArray *) orderedTracksRemainingToBeExtracted
{
	// Fetch the tracks to be extracted and sort them by track number
	NSPredicate *trackPredicate  = [NSPredicate predicateWithFormat:@"self IN %@", [_tracksToBeExtracted allObjects]];
	NSSortDescriptor *trackNumberSortDescriptor = [[NSSortDescriptor alloc] initWithKey:@"number" ascending:YES];
	NSEntityDescription *trackEntityDescription = [NSEntityDescription entityForName:@"TrackDescriptor" inManagedObjectContext:self.managedObjectContext];
	
	NSFetchRequest *trackFetchRequest = [[NSFetchRequest alloc] init];
	
	[trackFetchRequest setEntity:trackEntityDescription];
	[trackFetchRequest setPredicate:trackPredicate];
	[trackFetchRequest setSortDescriptors:[NSArray arrayWithObject:trackNumberSortDescriptor]];
	
	NSError *error = nil;
	NSArray *tracks = [self.managedObjectContext executeFetchRequest:trackFetchRequest error:&error];
	if(!tracks) {
		[self presentError:error modalForWindow:self.window delegate:self didPresentSelector:@selector(didPresentErrorWithRecovery:contextInfo:) contextInfo:NULL];
		return nil;
	}
	
	return tracks;
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
	for(TrackDescriptor *track in self.orderedTracks) {
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
	for(TrackDescriptor *track in self.orderedTracks) {
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
	_trackPartialExtractions = [NSMutableArray array];
	_sectorsNeedingVerification = [NSMutableDictionary dictionary];
	
	// Set up the extraction records
	_trackExtractionRecords = [NSMutableArray array];
	
	// Get started on the first one
	[self startExtractingNextTrack];
}

- (void) startExtractingNextTrack
{
	NSArray *tracks = self.orderedTracksRemainingToBeExtracted;

	if(![tracks count])
		return;
	
	TrackDescriptor *track = [tracks objectAtIndex:0];
	[_tracksToBeExtracted removeObject:[track objectID]];
	
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

- (void) extractSectors:(NSIndexSet *)sectorIndexes forTrack:(TrackDescriptor *)track coalesceRanges:(BOOL)coalesceRanges
{
	NSParameterAssert(nil != track);
	NSParameterAssert(nil != sectorIndexes);

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
						[self extractPartialTrack:track sectorRange:[SectorRange sectorRangeWithSector:firstIndex] enforceMinimumReadSize:YES];
					else
						[self extractPartialTrack:track sectorRange:[SectorRange sectorRangeWithFirstSector:firstIndex lastSector:latestIndex] enforceMinimumReadSize:YES];
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
						[self extractPartialTrack:track sectorRange:[SectorRange sectorRangeWithSector:firstIndex] enforceMinimumReadSize:YES];
					else
						[self extractPartialTrack:track sectorRange:[SectorRange sectorRangeWithFirstSector:firstIndex lastSector:latestIndex] enforceMinimumReadSize:YES];
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
			[self extractPartialTrack:track sectorRange:[SectorRange sectorRangeWithSector:sectorIndex] enforceMinimumReadSize:YES];
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
	NSLog(@"Extracted sectors %u - %u to %@, %u C2 block errors.  MD5 = %@", operation.sectorsRead.firstSector, operation.sectorsRead.lastSector, [operation.URL.path lastPathComponent], operation.blockErrorFlags.count, operation.MD5);
	if([operation.blockErrorFlags count])
		NSLog(@"C2 block errors for sectors %@", operation.blockErrorFlags);
#endif
	
	// Fetch the track this operation represents
	NSManagedObjectID *trackID = [operation.trackIDs lastObject];
	NSManagedObject *managedObject = [self.managedObjectContext objectWithID:trackID];
	if(![managedObject isKindOfClass:[TrackDescriptor class]])
		return;

	TrackDescriptor *track = (TrackDescriptor *)managedObject;			

	// Determine if this operation represents a whole track extraction or a partial track extraction
	if([operation.sectors containsSectorRange:track.sectorRange])
		[self processExtractionOperationForWholeTrack:operation];
	else
		[self processExtractionOperationForPartialTrack:operation];
}

- (void) processExtractionOperationForWholeTrack:(ExtractionOperation *)operation
{
	NSParameterAssert(nil != operation);
	
	// Fetch the track this operation represents
	NSManagedObjectID *trackID = [operation.trackIDs lastObject];
	NSManagedObject *managedObject = [self.managedObjectContext objectWithID:trackID];
	if(![managedObject isKindOfClass:[TrackDescriptor class]])
		return;
	
	TrackDescriptor *track = (TrackDescriptor *)managedObject;			
	
	// Calculate the actual AccurateRip checksum of the extracted audio
	NSNumber *trackActualAccurateRipChecksum = [self calculateAccurateRipChecksumForExtractionOperation:operation];

	// Determine the possible AccurateRip offsets for the extracted audio, if any
	NSArray *possibleAccurateRipOffsets = [self determinePossibleAccurateRipOffsetForTrack:track URL:operation.URL];

	// Determine which pressings (if any) are the primary ones (offset checksum matches with a zero read offset)
	NSPredicate *zeroOffsetPredicate = [NSPredicate predicateWithFormat:@"%K == 0", kReadOffsetKey];
	NSArray *matchingPressingsWithZeroOffset = [possibleAccurateRipOffsets filteredArrayUsingPredicate:zeroOffsetPredicate];
	
	// Iterate through each pressing and compare the track's AccurateRip checksums
	if([matchingPressingsWithZeroOffset count]) {

		for(NSDictionary *matchingPressingInfo in matchingPressingsWithZeroOffset) {
			NSManagedObjectID *accurateRipTrackID = [matchingPressingInfo objectForKey:kAccurateRipTrackIDKey];

			// Fetch the AccurateRipTrackRecord object from the context and ensure it is the correct class
			managedObject = [self.managedObjectContext objectWithID:accurateRipTrackID];
			if(![managedObject isKindOfClass:[AccurateRipTrackRecord class]])
				continue;
			
			AccurateRipTrackRecord *accurateRipTrack = (AccurateRipTrackRecord *)managedObject;

			// If the track was accurately ripped, ship it off to the encoder
			if([accurateRipTrack.checksum isEqualToNumber:trackActualAccurateRipChecksum]) {
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
	}
	else if([possibleAccurateRipOffsets count]) {
		NSLog(@"FIXME: USE ALTERNATE ACCURATERIP PRESSING");
	}
	
	// Re-rip portions of the track if any C2 error flags were returned
	if(operation.blockErrorFlags.count) {
		NSIndexSet *positionOfErrors = [operation.blockErrorFlags copy];

		NSIndexSet *currentSectorsNeedingVerification = [_sectorsNeedingVerification objectForKey:[track objectID]];
		if(currentSectorsNeedingVerification) {
			NSMutableIndexSet *newSectorsNeedingVerification = [currentSectorsNeedingVerification mutableCopy];
			[newSectorsNeedingVerification addIndexes:positionOfErrors];
			[_sectorsNeedingVerification setObject:newSectorsNeedingVerification forKey:[track objectID]];
		}
		else
			[_sectorsNeedingVerification setObject:positionOfErrors forKey:[track objectID]];

		[_trackPartialExtractions addObject:operation];
		
		[self extractSectors:positionOfErrors forTrack:track coalesceRanges:YES];
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
			
			NSIndexSet *currentSectorsNeedingVerification = [_sectorsNeedingVerification objectForKey:[track objectID]];
			if(currentSectorsNeedingVerification) {
				NSMutableIndexSet *newSectorsNeedingVerification = [currentSectorsNeedingVerification mutableCopy];
				[newSectorsNeedingVerification addIndexes:nonMatchingSectorIndexes];
				[_sectorsNeedingVerification setObject:newSectorsNeedingVerification forKey:[track objectID]];
			}
			else
				[_sectorsNeedingVerification setObject:nonMatchingSectorIndexes forKey:[track objectID]];
			
			[self extractSectors:nonMatchingSectorIndexes forTrack:track coalesceRanges:YES];
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
	
	// Fetch the track this operation represents a portion of
	NSManagedObjectID *trackID = [operation.trackIDs lastObject];
	NSManagedObject *managedObject = [self.managedObjectContext objectWithID:trackID];
	if(![managedObject isKindOfClass:[TrackDescriptor class]])
		return;
	
	TrackDescriptor *track = (TrackDescriptor *)managedObject;			
	NSIndexSet *sectorsNeedingVerification = [_sectorsNeedingVerification objectForKey:[track objectID]];
	
	if(!sectorsNeedingVerification)
		return;
	
	// Check for resolved C2 errors
	NSMutableIndexSet *verifiedSectors = [NSMutableIndexSet indexSet];
	NSUInteger sectorIndex = [sectorsNeedingVerification firstIndex];
	while(NSNotFound != sectorIndex) {
		
		if([operation.sectorsRead containsSector:sectorIndex] && ![operation.blockErrorFlags containsIndex:sectorIndex])
			[verifiedSectors addIndex:sectorIndex];
		
		sectorIndex = [sectorsNeedingVerification indexGreaterThanIndex:sectorIndex];
	}

#if DEBUG
	if([verifiedSectors count])
		NSLog(@"Resolved C2 block errors for sectors %@", verifiedSectors);
#endif

	// If this operation resolved any C2 errors, save it
	if([verifiedSectors count])
		[_trackPartialExtractions addObject:operation];

	// Update the list of sectors needing verification
	NSMutableIndexSet *updatedSectorsNeedingVerification = [sectorsNeedingVerification mutableCopy];
	[updatedSectorsNeedingVerification removeIndexes:verifiedSectors];

	if([updatedSectorsNeedingVerification count])
		[_sectorsNeedingVerification setObject:updatedSectorsNeedingVerification forKey:[track objectID]];
	else
		[_sectorsNeedingVerification removeObjectForKey:[track objectID]];
	
	// All sectors verified, synthesize the track and encode
	if(![updatedSectorsNeedingVerification count]) {

#if DEBUG
		NSLog(@"Track has no C2 errors");
#endif
		
		// Any operations in progress are no longer needed
		[self.operationQueue cancelAllOperations];

		NSURL *fileURL = temporaryURLWithExtension(@"wav");

		NSError *error = nil;
		if(![self synthesizeTrack:track toURL:fileURL error:&error])
			[self presentError:error modalForWindow:self.window delegate:self didPresentSelector:@selector(didPresentErrorWithRecovery:contextInfo:) contextInfo:NULL];
		
		// Calculate the digests and AccurateRip checksum
		NSArray *digests = calculateMD5AndSHA1DigestsForURL(fileURL, &error);
		NSUInteger accurateRipChecksum = calculateAccurateRipChecksumForFile(fileURL,
																			 [self.compactDisc.firstSession.firstTrack.number isEqualToNumber:track.number],
																			 [self.compactDisc.firstSession.lastTrack.number isEqualToNumber:track.number]);

		// Determine the possible AccurateRip offsets for the extracted audio, if any
		NSArray *possibleAccurateRipOffsets = [self determinePossibleAccurateRipOffsetForTrack:track URL:fileURL];

#if DEBUG
		NSLog(@"possibleAccurateRipOffsets: %@", possibleAccurateRipOffsets);
#endif
		
		// Determine which pressings (if any) are the primary ones (offset checksum matches with a zero read offset)
		NSPredicate *zeroOffsetPredicate = [NSPredicate predicateWithFormat:@"%K == 0", kReadOffsetKey];
		NSArray *matchingPressingsWithZeroOffset = [possibleAccurateRipOffsets filteredArrayUsingPredicate:zeroOffsetPredicate];
		
		// Iterate through each pressing and compare the track's AccurateRip checksums
		if([matchingPressingsWithZeroOffset count]) {

			for(NSDictionary *matchingPressingInfo in matchingPressingsWithZeroOffset) {
				NSManagedObjectID *accurateRipTrackID = [matchingPressingInfo objectForKey:kAccurateRipTrackIDKey];
				
				// Fetch the AccurateRipTrackRecord object from the context and ensure it is the correct class
				managedObject = [self.managedObjectContext objectWithID:accurateRipTrackID];
				if(![managedObject isKindOfClass:[AccurateRipTrackRecord class]])
					continue;
				
				AccurateRipTrackRecord *accurateRipTrack = (AccurateRipTrackRecord *)managedObject;
				
				// If the track was accurately ripped, ship it off to the encoder
				if([accurateRipTrack.checksum isEqualToNumber:[NSNumber numberWithUnsignedInteger:accurateRipChecksum]]) {
					// Create the extraction record
					TrackExtractionRecord *extractionRecord = [NSEntityDescription insertNewObjectForEntityForName:@"TrackExtractionRecord" 
																							inManagedObjectContext:self.managedObjectContext];
					
					extractionRecord.date = [NSDate date];
					extractionRecord.drive = self.driveInformation;
//					extractionRecord.blockErrorFlags = operation.blockErrorFlags;
					extractionRecord.MD5 = [digests objectAtIndex:0];
					extractionRecord.SHA1 = [digests objectAtIndex:1];
					extractionRecord.track = track;
					extractionRecord.accurateRipChecksum = [NSNumber numberWithUnsignedInteger:accurateRipChecksum];
					extractionRecord.accurateRipConfidenceLevel = accurateRipTrack.confidenceLevel;
					
					if(![[EncoderManager sharedEncoderManager] encodeURL:fileURL forTrackExtractionRecord:extractionRecord error:&error]) {
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
		}
		else if([possibleAccurateRipOffsets count]) {
			NSLog(@"FIXME: USE ALTERNATE ACCURATERIP PRESSING");
		}		
		
		
		
		
		
		
		
		
		
		
		
		return;
	}
	
	return;

	// Determine the whole track copy operation corresponding to this operation
	ExtractionOperation *copyOperation = [_tracksExtractedButNotVerified objectForKey:[track objectID]];
	if(copyOperation) {
#if 0
		// Check for resolved C2 errors from the original copy
		NSUInteger sectorIndex = [copyOperation.blockErrorFlags firstIndex];
		while(NSNotFound != sectorIndex) {
			
			if(![operation.blockErrorFlags containsIndex:sectorIndex]) {
				NSLog(@"C2 block error for sector %u resolved", sectorIndex);
				[currentSectorsNeedingVerification removeIndex:sectorIndex];
			}
			
			sectorIndex = [copyOperation.blockErrorFlags indexGreaterThanIndex:sectorIndex];
		}
#endif
	}
	
	
	// Determine any partial track extractions that overlap this sector range
	NSMutableArray *previousExtractions = [NSMutableArray array];
	for(ExtractionOperation *previousOperation in _trackPartialExtractions) {
		if([previousOperation.sectors intersectsSectorRange:operation.sectors])
			[previousExtractions addObject:previousOperation];
	}
	

	// If sectors with (multiple) C2 errors still remain, attempt to match 2 extractions
	if([updatedSectorsNeedingVerification count]) {
#if 0
		NSUInteger firstSector = (copyOperation.sectors.firstSector > operation.sectors.firstSector ? copyOperation.sectors.firstSector : operation.sectors.firstSector);
		NSUInteger lastSector = (copyOperation.sectors.lastSector < operation.sectors.lastSector ? copyOperation.sectors.lastSector : operation.sectors.lastSector);
		
		NSError *error = nil;
		NSIndexSet *mismatchedSectors = compareFileRegionsForNonMatchingSectors(operation.URL,
																				[operation.sectors indexForSector:firstSector],
																				copyOperation.URL,
																				[copyOperation.sectors indexForSector:firstSector],
																				lastSector - firstSector,
																				&error);
		
		NSLog(@"rerip mismatched sectors: %@", mismatchedSectors);

		
		// Iterate through all the matching operations and check each sector for two matches
		for(ExtractionOperation *previousOperation in previousExtractions) {
			firstSector = (previousOperation.sectors.firstSector > operation.sectors.firstSector ? previousOperation.sectors.firstSector : operation.sectors.firstSector);
			lastSector = (previousOperation.sectors.lastSector < operation.sectors.lastSector ? previousOperation.sectors.lastSector : operation.sectors.lastSector);
			
			error = nil;
			mismatchedSectors = compareFileRegionsForNonMatchingSectors(operation.URL,
																					[operation.sectors indexForSector:firstSector],
																					previousOperation.URL,
																					[previousOperation.sectors indexForSector:firstSector],
																					lastSector - firstSector + 1,
																					&error);
			
			NSLog(@"rerip mismatched sectors: %@", mismatchedSectors);
		}
#endif

		[_sectorsNeedingVerification setObject:updatedSectorsNeedingVerification forKey:[track objectID]];
	}	
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
																		 [self.compactDisc.firstSession.firstTrack.number isEqualToNumber:track.number],
																		 [self.compactDisc.firstSession.lastTrack.number isEqualToNumber:track.number]);
	
	// Since Core Data only stores signed integers, cast the unsigned checksum to signed for storage
	return [NSNumber numberWithInt:(int32_t)accurateRipChecksum];
}

- (NSArray *) determinePossibleAccurateRipOffsetForTrack:(TrackDescriptor *)track URL:(NSURL *)URL
{
	NSParameterAssert(nil != track);
	NSParameterAssert(nil != URL);
	
	// Scan the extracted file and determine possible AccurateRip offsets
	ReadOffsetCalculationOperation *operation = [[ReadOffsetCalculationOperation alloc ] init];
	
	operation.URL = URL;
	operation.trackID = [track objectID];
	operation.sixSecondPointSector = 6 * CDDA_SECTORS_PER_SECOND;
	operation.maximumOffsetToCheck = (MAXIMUM_OFFSET_TO_CHECK_IN_SECTORS * AUDIO_FRAMES_PER_CDDA_SECTOR);
	
	// Wait for the operation to be ready
	while(![operation isReady])
		[NSThread sleepForTimeInterval:0.25];
	
	// Run the operation in standalone mode
	[_detailedStatusTextField setStringValue:NSLocalizedString(@"Calculating AccurateRip offsets", @"")];
	[operation start];
	
	if(operation.error) {
//		[self presentError:operation.error modalForWindow:self.window delegate:self didPresentSelector:@selector(didPresentErrorWithRecovery:contextInfo:) contextInfo:NULL];
		return nil;
	}
	
	return operation.possibleReadOffsets;
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
																					   [self.compactDisc.firstSession.firstTrack.number isEqualToNumber:track.number],
																					   [self.compactDisc.firstSession.lastTrack.number isEqualToNumber:track.number]);
			
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
	extractionRecord.blockErrorFlags = operation.blockErrorFlags;
	extractionRecord.MD5 = operation.MD5;
	extractionRecord.SHA1 = operation.SHA1;
	extractionRecord.track = track;
	extractionRecord.accurateRipChecksum = checksum;
	
	return extractionRecord;
}

// Create a new output file containing the audio data with no C2 errors
- (BOOL) synthesizeTrack:(TrackDescriptor *)track toURL:(NSURL *)fileURL error:(NSError **)error
{
	NSParameterAssert(nil != track);
	NSParameterAssert(nil != fileURL);

	BOOL result = NO;
	
	// Determine the extraction operations for this track
	NSPredicate *trackIDPredicate = [NSPredicate predicateWithFormat:@"%@ IN trackIDs", [track objectID]];
	NSArray *matchingOperations = [_trackPartialExtractions filteredArrayUsingPredicate:trackIDPredicate];

#if DEBUG
	NSLog(@"matchingOperations: %@",matchingOperations);
#endif
	
	if(![matchingOperations count]) {
		if(error)
			*error = [NSError errorWithDomain:NSOSStatusErrorDomain code:paramErr userInfo:nil];
		return NO;
	}
	
	[_detailedStatusTextField setStringValue:NSLocalizedString(@"Creating temporary output file", @"")];

	// Set up the ASBD for CDDA audio
	const AudioStreamBasicDescription cddaASBD = getStreamDescriptionForCDDA();
	
	// Create and open the output file, overwriting if it exists
	AudioFileID outputFile = NULL;
	OSStatus status = AudioFileCreateWithURL((CFURLRef)fileURL, kAudioFileWAVEType, &cddaASBD, kAudioFileFlags_EraseFile, &outputFile);
	if(noErr != status) {
		if(error)
			*error = [NSError errorWithDomain:NSOSStatusErrorDomain code:status userInfo:nil];
		return NO;
	}
	
	// Track the sectors needed
	SectorRange *trackSectorRange = track.sectorRange;
	NSUInteger trackFirstSector = trackSectorRange.firstSector;
	NSMutableIndexSet *sectorsNeeded = [NSMutableIndexSet indexSetWithIndexesInRange:NSMakeRange(trackSectorRange.firstSector, trackSectorRange.length)];
	
#if DEBUG
	NSLog(@"sectorsNeeded: %@", sectorsNeeded);
#endif
	
	for(ExtractionOperation *operation in matchingOperations) {

		// Determine the error-free sectors in this input fragment
		SectorRange *inputFragmentSectors = operation.sectors;
		NSUInteger inputFileFirstSector = inputFragmentSectors.firstSector;
		NSIndexSet *inputSectors = [NSIndexSet indexSetWithIndexesInRange:NSMakeRange(inputFragmentSectors.firstSector, inputFragmentSectors.length)];
		NSMutableIndexSet *validInputSectors = [inputSectors mutableCopy];
		if(operation.blockErrorFlags)
			[validInputSectors removeIndexes:operation.blockErrorFlags];
		
		// Determine if any of the error-free sectors in the input file are needed
		NSIndexSet *sectorsToCopy = [sectorsNeeded intersectedIndexSet:validInputSectors];
		if(![sectorsToCopy count])
			continue;
		
#if DEBUG
		NSLog(@"sectorsToCopy: %@", sectorsToCopy);
#endif
		
		// Open the operation's output file to use as input
		AudioFileID inputFile = NULL;
		status = AudioFileOpenURL((CFURLRef)operation.URL, fsRdPerm, kAudioFileWAVEType, &inputFile);
		if(noErr != status) {
			if(error)
				*error = [NSError errorWithDomain:NSOSStatusErrorDomain code:status userInfo:nil];
			goto cleanup;
		}
		
		// Verify the file contains CDDA audio
		AudioStreamBasicDescription fileFormat;
		UInt32 dataSize = sizeof(fileFormat);
		status = AudioFileGetProperty(inputFile, kAudioFilePropertyDataFormat, &dataSize, &fileFormat);
		if(noErr != status) {
			if(error)
				*error = [NSError errorWithDomain:NSOSStatusErrorDomain code:status userInfo:nil];
			goto cleanup;
		}
		
		if(!streamDescriptionIsCDDA(&fileFormat)) {
			if(error)
				*error = [NSError errorWithDomain:NSOSStatusErrorDomain code:paramErr userInfo:nil];
			goto cleanup;
		}
		
		// The extraction buffer for one sector
		int8_t buffer [kCDSectorSizeCDDA];
		UInt32 packetCount, bytesRead;
		SInt64 startingPacketNumberInInputFile, startingPacketNumberInOutputFile;
		
		// Iteratively process each desired CDDA sector in the file
		NSUInteger sectorNumber = [sectorsToCopy firstIndex];
		while(NSNotFound != sectorNumber) {

			// Since this is lpcm audio, packets === frames and no packet descriptions are required
			
			startingPacketNumberInInputFile = (sectorNumber - inputFileFirstSector) * AUDIO_FRAMES_PER_CDDA_SECTOR;
			startingPacketNumberInOutputFile = (sectorNumber - trackFirstSector) * AUDIO_FRAMES_PER_CDDA_SECTOR;

			packetCount = AUDIO_FRAMES_PER_CDDA_SECTOR;
			bytesRead = 0;
			
			status = AudioFileReadPackets(inputFile, false, &bytesRead, NULL, startingPacketNumberInInputFile, &packetCount, buffer);
			
			if(noErr != status)
				break;
			else if(kCDSectorSizeCDDA != bytesRead)
				break;


			// Write the data to the output file at the appropriate location
			status = AudioFileWritePackets(outputFile, false, bytesRead, NULL, startingPacketNumberInOutputFile, &packetCount, buffer);
			if(noErr != status)
				break;
			else if(AUDIO_FRAMES_PER_CDDA_SECTOR != packetCount)
				break;

			sectorNumber = [sectorsToCopy indexGreaterThanIndex:sectorNumber];
		}

		// Close the input file
		status = AudioFileClose(inputFile);
		if(noErr != status) {
			if(error)
				*error = [NSError errorWithDomain:NSOSStatusErrorDomain code:status userInfo:nil];
			goto cleanup;
		}
		
		[sectorsNeeded removeIndexes:sectorsToCopy];
	}

	result = YES;
	
	cleanup:

	// Close the output file
	if(outputFile) {
		status = AudioFileClose(outputFile);
		if(noErr != status) {
			if(error)
				*error = [NSError errorWithDomain:NSOSStatusErrorDomain code:status userInfo:nil];
		}
	}
	
	return result;
}

@end
