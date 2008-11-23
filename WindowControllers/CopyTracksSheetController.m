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

#import "ExtractedAudioFile.h"

#import "CDDAUtilities.h"
#import "FileUtilities.h"
#import "AudioUtilities.h"

#import "NSIndexSet+SetMethods.h"

#import "Logger.h"

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

@property (assign) NSUInteger retryCount;

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

- (void) removeTemporaryFiles;

- (void) startExtractingNextTrack;

- (void) extractWholeTrack:(TrackDescriptor *)track;
- (void) extractPartialTrack:(TrackDescriptor *)track sectorRange:(SectorRange *)sectorRange;
- (void) extractPartialTrack:(TrackDescriptor *)track sectorRange:(SectorRange *)sectorRange enforceMinimumReadSize:(BOOL)enforceMinimumReadSize;
- (void) extractPartialTrack:(TrackDescriptor *)track sectorRange:(SectorRange *)sectorRange enforceMinimumReadSize:(BOOL)enforceMinimumReadSize cushionSectors:(NSUInteger)cushionSectors;

- (void) extractSectors:(NSIndexSet *)sectorIndexes forTrack:(TrackDescriptor *)track coalesceRanges:(BOOL)coalesceRanges;

- (void) processExtractionOperation:(ExtractionOperation *)operation;
- (void) processExtractionOperation:(ExtractionOperation *)operation forWholeTrack:(TrackDescriptor *)track;
- (void) processExtractionOperation:(ExtractionOperation *)operation forPartialTrack:(TrackDescriptor *)track;

- (NSUInteger) calculateAccurateRipChecksumForTrack:(TrackDescriptor *)track extractionOperation:(ExtractionOperation *)operation;
- (NSUInteger) calculateAccurateRipChecksumForTrack:(TrackDescriptor *)track extractionOperation:(ExtractionOperation *)operation readOffsetAdjustment:(NSUInteger)readOffsetAdjustment;

- (NSArray *) determinePossibleAccurateRipOffsetForTrack:(TrackDescriptor *)track URL:(NSURL *)URL;
- (NSArray *) determinePossibleAccurateRipOffsetForTrack:(TrackDescriptor *)track URL:(NSURL *)URL startingSector:(NSUInteger)startingSector;

//- (TrackExtractionRecord *) createTrackExtractionRecordForTrack:(TrackDescriptor *)track extractionOperation:(ExtractionOperation *)operation;

- (BOOL) saveSectors:(NSIndexSet *)sectors fromOperation:(ExtractionOperation *)operation forTrack:(TrackDescriptor *)track;
- (BOOL) sendTrackToEncoder:(TrackDescriptor *)track extractionOperation:(ExtractionOperation *)operation accurateRipChecksum:(NSUInteger)accurateRipChecksum accurateRipConfidenceLevel:(NSNumber *)accurateRipConfidenceLevel error:(NSError **)error;
- (BOOL) sendTrackToEncoder:(TrackDescriptor *)track extractionOperation:(ExtractionOperation *)operation accurateRipChecksum:(NSUInteger)accurateRipChecksum accurateRipConfidenceLevel:(NSNumber *)accurateRipConfidenceLevel accurateRipAlternatePressingChecksum:(NSUInteger)accurateRipAlternatePressingChecksum accurateRipAlternatePressingOffset:(NSNumber *)accurateRipAlternatePressingOffset error:(NSError **)error;
@end

@implementation CopyTracksSheetController

@synthesize disk = _disk;
@synthesize trackIDs = _trackIDs;

@synthesize maxRetries = _maxRetries;
@synthesize requiredMatches = _requiredMatches;

@synthesize trackExtractionRecords = _trackExtractionRecords;
@synthesize failedTrackIDs = _failedTrackIDs;

@synthesize compactDisc = _compactDisc;
@synthesize driveInformation = _driveInformation;
@synthesize managedObjectContext = _managedObjectContext;

@synthesize operationQueue = _operationQueue;

@synthesize retryCount = _retryCount;

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
				
				if(operation.trackID) {
					// Fetch the TrackDescriptor object from the context and ensure it is the correct class
					NSManagedObject *managedObject = [self.managedObjectContext objectWithID:operation.trackID];
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
					if(!isWholeTrack)
						[_detailedStatusTextField setStringValue:[NSString stringWithFormat:NSLocalizedString(@"Re-extracting sectors %u - %u", @""), operation.sectors.firstSector, operation.sectors.lastSector]];
					else if(_copyOperation)
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
			if(![[self.operationQueue operations] count] && ![_tracksRemaining count]) {
				
				// Post-process the encoded tracks, if required
				if([_encodingOperations count]) {
					NSError *error = nil;
					if(![[EncoderManager sharedEncoderManager] postProcessEncodingOperations:_encodingOperations error:&error])
						[self presentError:error modalForWindow:self.window delegate:self didPresentSelector:@selector(didPresentErrorWithRecovery:contextInfo:) contextInfo:NULL];
				}
				
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
	
	// Remove temporary files
	[self removeTemporaryFiles];	

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
	NSPredicate *trackPredicate  = [NSPredicate predicateWithFormat:@"self IN %@", [_tracksRemaining allObjects]];
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
	_tracksRemaining = [self.trackIDs mutableCopy];
	
	// Set up the extraction records
	_trackExtractionRecords = [NSMutableSet set];
	_failedTrackIDs = [NSMutableSet set];
	_encodingOperations =  [NSMutableArray array];
	
	// Get started on the first one
	[self startExtractingNextTrack];
}

- (void) removeTemporaryFiles
{
	NSError *error = nil;
	
	// Remove temporary files
	NSArray *temporaryURLS = [_partialExtractions valueForKey:@"URL"];
	for(NSURL *URL in temporaryURLS) {
		if(![[NSFileManager defaultManager] removeItemAtPath:[URL path] error:&error])
			[[Logger sharedLogger] logMessage:@"Error removing temporary file: %@", error];
	}

	if(_copyOperation && ![[NSFileManager defaultManager] removeItemAtPath:[_copyOperation.URL path] error:&error])
		[[Logger sharedLogger] logMessage:@"Error removing temporary file: %@", error];
	
	if(_verificationOperation && ![[NSFileManager defaultManager] removeItemAtPath:[_verificationOperation.URL path] error:&error])
		[[Logger sharedLogger] logMessage:@"Error removing temporary file: %@", error];
}

- (void) startExtractingNextTrack
{
	NSArray *tracks = self.orderedTracksRemainingToBeExtracted;

	if(![tracks count])
		return;
	
	TrackDescriptor *track = [tracks objectAtIndex:0];
	[_tracksRemaining removeObject:[track objectID]];
	
	[self removeTemporaryFiles];
	
	// Reset extraction state
	_synthesizedFile = nil;
	_copyOperation = nil;
	_verificationOperation = nil;
	_partialExtractions = [NSMutableArray array];
	_sectorsNeedingVerification = [NSMutableIndexSet indexSet];

	self.retryCount = 0;
	
	[[Logger sharedLogger] logMessageWithLevel:eLogMessageLevelDebug format:@"Beginning extraction for track %@", track.number];

	[self extractWholeTrack:track];
}

- (void) extractWholeTrack:(TrackDescriptor *)track
{
	[self extractPartialTrack:track sectorRange:track.sectorRange enforceMinimumReadSize:NO cushionSectors:MAXIMUM_OFFSET_TO_CHECK_IN_SECTORS];
}

- (void) extractPartialTrack:(TrackDescriptor *)track sectorRange:(SectorRange *)sectorRange
{
	[self extractPartialTrack:track sectorRange:sectorRange enforceMinimumReadSize:NO cushionSectors:0];
}

- (void) extractPartialTrack:(TrackDescriptor *)track sectorRange:(SectorRange *)sectorRange enforceMinimumReadSize:(BOOL)enforceMinimumReadSize
{
	[self extractPartialTrack:track sectorRange:sectorRange enforceMinimumReadSize:enforceMinimumReadSize cushionSectors:0];
}

- (void) extractPartialTrack:(TrackDescriptor *)track sectorRange:(SectorRange *)sectorRange enforceMinimumReadSize:(BOOL)enforceMinimumReadSize cushionSectors:(NSUInteger)cushionSectors
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
	extractionOperation.cushionSectors = cushionSectors;
	extractionOperation.trackID = [track objectID];
	extractionOperation.readOffset = self.driveInformation.readOffset;
	extractionOperation.URL = temporaryURLWithExtension(@"wav");
	extractionOperation.useC2 = [self.driveInformation.useC2 boolValue];

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
		if([[NSFileManager defaultManager] fileExistsAtPath:operation.URL.path] && ![[NSFileManager defaultManager] removeItemAtPath:operation.URL.path error:&error])
			[self presentError:error modalForWindow:self.window delegate:self didPresentSelector:@selector(didPresentErrorWithRecovery:contextInfo:) contextInfo:NULL];

		return;
	}
	
	if(operation.useC2) {
		[[Logger sharedLogger] logMessageWithLevel:eLogMessageLevelDebug format:@"Extracted sectors %u - %u to %@, %u C2 block errors.  MD5 = %@", operation.sectorsRead.firstSector, operation.sectorsRead.lastSector, [operation.URL.path lastPathComponent], operation.blockErrorFlags.count, operation.MD5];
		if([operation.blockErrorFlags count])
			[[Logger sharedLogger] logMessageWithLevel:eLogMessageLevelDebug format:@"C2 block errors for sectors %@", operation.blockErrorFlags];
	}
	else
		[[Logger sharedLogger] logMessageWithLevel:eLogMessageLevelDebug format:@"Extracted sectors %u - %u to %@.  MD5 = %@", operation.sectorsRead.firstSector, operation.sectorsRead.lastSector, [operation.URL.path lastPathComponent], operation.MD5];
	
	// Fetch the track this operation represents
	NSManagedObject *managedObject = [self.managedObjectContext objectWithID:operation.trackID];
	if(![managedObject isKindOfClass:[TrackDescriptor class]])
		return;

	TrackDescriptor *track = (TrackDescriptor *)managedObject;			

	// Determine if this operation represents a whole track extraction or a partial track extraction
	if([operation.sectors containsSectorRange:track.sectorRange])
		[self processExtractionOperation:operation forWholeTrack:track];
	else
		[self processExtractionOperation:operation forPartialTrack:track];
}

- (void) processExtractionOperation:(ExtractionOperation *)operation forWholeTrack:(TrackDescriptor *)track
{
	NSParameterAssert(nil != operation);
	NSParameterAssert(nil != track);

	// Calculate the actual AccurateRip checksum of the extracted audio
	NSUInteger trackActualAccurateRipChecksum = [self calculateAccurateRipChecksumForTrack:track extractionOperation:operation];

	// Determine the possible AccurateRip offsets for the extracted audio, if any
	NSArray *possibleAccurateRipOffsets = [self determinePossibleAccurateRipOffsetForTrack:track URL:operation.URL startingSector:operation.cushionSectors];

	// Determine which pressings (if any) are the primary ones (offset checksum matches with a zero read offset)
	NSPredicate *zeroOffsetPredicate = [NSPredicate predicateWithFormat:@"%K == 0", kReadOffsetKey];
	NSArray *matchingPressingsWithZeroOffset = [possibleAccurateRipOffsets filteredArrayUsingPredicate:zeroOffsetPredicate];
	
	// Iterate through each pressing and compare the track's AccurateRip checksums
	if([matchingPressingsWithZeroOffset count]) {

		for(NSDictionary *matchingPressingInfo in matchingPressingsWithZeroOffset) {
			NSManagedObjectID *accurateRipTrackID = [matchingPressingInfo objectForKey:kAccurateRipTrackIDKey];

			// Fetch the AccurateRipTrackRecord object from the context and ensure it is the correct class
			NSManagedObject *managedObject = [self.managedObjectContext objectWithID:accurateRipTrackID];
			if(![managedObject isKindOfClass:[AccurateRipTrackRecord class]])
				continue;
			
			AccurateRipTrackRecord *accurateRipTrack = (AccurateRipTrackRecord *)managedObject;

			// If the track was accurately ripped, ship it off to the encoder
			if([accurateRipTrack.checksum unsignedIntegerValue] == trackActualAccurateRipChecksum) {
				NSError *error = nil;
				if([self sendTrackToEncoder:track extractionOperation:operation accurateRipChecksum:trackActualAccurateRipChecksum accurateRipConfidenceLevel:accurateRipTrack.confidenceLevel error:&error])
					[self startExtractingNextTrack];
				else
					[self presentError:error modalForWindow:self.window delegate:self didPresentSelector:@selector(didPresentErrorWithRecovery:contextInfo:) contextInfo:NULL];
				
				return;
			}
			
			// If the checksum was not verified, fall through to handling below
		}
	}
	else if([possibleAccurateRipOffsets count]) {
		[[Logger sharedLogger] logMessageWithLevel:eLogMessageLevelDebug format:@"Using alternate AccurateRip pressing"];
		
		for(NSDictionary *alternatePressingInfo in possibleAccurateRipOffsets) {
			NSManagedObjectID *accurateRipTrackID = [alternatePressingInfo objectForKey:kAccurateRipTrackIDKey];
			
			// Fetch the AccurateRipTrackRecord object from the context and ensure it is the correct class
			NSManagedObject *managedObject = [self.managedObjectContext objectWithID:accurateRipTrackID];
			if(![managedObject isKindOfClass:[AccurateRipTrackRecord class]])
				continue;
			
			AccurateRipTrackRecord *accurateRipTrack = (AccurateRipTrackRecord *)managedObject;

			// Calculate the AccurateRip checksum for the alternate pressing
			NSNumber *alternatePressingOffset = [alternatePressingInfo objectForKey:kReadOffsetKey];
			NSUInteger trackAlternateAccurateRipChecksum = [self calculateAccurateRipChecksumForTrack:track extractionOperation:operation readOffsetAdjustment:[alternatePressingOffset unsignedIntegerValue]];
						
			// If the track was accurately ripped, ship it off to the encoder
			if([accurateRipTrack.checksum unsignedIntegerValue] == trackAlternateAccurateRipChecksum) {
				NSError *error = nil;
				if([self sendTrackToEncoder:track extractionOperation:operation accurateRipChecksum:trackActualAccurateRipChecksum accurateRipConfidenceLevel:accurateRipTrack.confidenceLevel accurateRipAlternatePressingChecksum:trackAlternateAccurateRipChecksum accurateRipAlternatePressingOffset:alternatePressingOffset error:&error])
					[self startExtractingNextTrack];
				else
					[self presentError:error modalForWindow:self.window delegate:self didPresentSelector:@selector(didPresentErrorWithRecovery:contextInfo:) contextInfo:NULL];
				
				return;
			}
		}
	}

	// Re-rip only portions of the track if any C2 block error flags were returned
	if(operation.useC2 && operation.blockErrorFlags.count) {
		NSIndexSet *positionOfErrors = operation.blockErrorFlags;

		// Determine which sectors have no C2 errors
		SectorRange *trackSectorRange = track.sectorRange;
		NSMutableIndexSet *sectorsWithNoErrors = [NSMutableIndexSet indexSetWithIndexesInRange:NSMakeRange(trackSectorRange.firstSector, trackSectorRange.length)];
		[sectorsWithNoErrors removeIndexes:positionOfErrors];
		
		// Save the sectors from this operation with no C2 errors
		[self saveSectors:sectorsWithNoErrors fromOperation:operation forTrack:track];

		// Mark the bad sectors
		[_sectorsNeedingVerification addIndexes:positionOfErrors];

		[self extractSectors:positionOfErrors forTrack:track coalesceRanges:YES];
	}
	// No C2 errors were encountered or C2 is disabled
	else {
		[_detailedStatusTextField setStringValue:NSLocalizedString(@"Verifying copy integrity", @"")];

		// The track is verified if a copy operation has already been performed
		// and the SHA1 hashes for the copy and this verification operation match
		if(_copyOperation && [_copyOperation.SHA1 isEqualToString:operation.SHA1]) {
			// Remove the old temporary files
			NSError *error = nil;
			if(![[NSFileManager defaultManager] removeItemAtPath:_copyOperation.URL.path error:&error])
				[[Logger sharedLogger] logMessage:@"Error removing temporary file: %@", error];
			
			if([self sendTrackToEncoder:track extractionOperation:operation accurateRipChecksum:trackActualAccurateRipChecksum accurateRipConfidenceLevel:nil error:&error])
				[self startExtractingNextTrack];
			else
				[self presentError:error modalForWindow:self.window delegate:self didPresentSelector:@selector(didPresentErrorWithRecovery:contextInfo:) contextInfo:NULL];
		}
		// This track has been extracted before but the SHA1 hashes don't match
		// Determine where the differences are and re-extract those sectors
		else if(_copyOperation) {
			[[Logger sharedLogger] logMessageWithLevel:eLogMessageLevelDebug format:@"Track extracted before but SHA1 hashes don't match."];
			
			NSIndexSet *nonMatchingSectorIndexes = compareFilesForNonMatchingSectors(_copyOperation.URL, operation.URL);
			
			// Sanity check
			if(!nonMatchingSectorIndexes.count) {
				[[Logger sharedLogger] logMessage:@"Internal inconsistency: SHA1 hashes don't match but no sector-level differences found"];
				return;
			}

			// Convert from sector indexes to sector numbers
			NSMutableIndexSet *nonMatchingSectors = [nonMatchingSectorIndexes mutableCopy];
			[nonMatchingSectors shiftIndexesStartingAtIndex:[nonMatchingSectorIndexes firstIndex] by:_copyOperation.sectors.firstSector];
			
			// Determine which sectors did match
			SectorRange *trackSectorRange = track.sectorRange;
			NSMutableIndexSet *matchingSectors = [NSMutableIndexSet indexSetWithIndexesInRange:NSMakeRange(trackSectorRange.firstSector, trackSectorRange.length)];
			[matchingSectors removeIndexes:nonMatchingSectors];
			
			// A track containing sectors from multiple extraction operations will be synthesized
			// Start with the sectors from this operation that matched the copy operation
			if([matchingSectors count])
				[self saveSectors:matchingSectors fromOperation:operation forTrack:track];

			[[Logger sharedLogger] logMessageWithLevel:eLogMessageLevelDebug format:@"Sectors with differences: %@", nonMatchingSectors];

			[_sectorsNeedingVerification addIndexes:nonMatchingSectors];
			
			[self extractSectors:nonMatchingSectors forTrack:track coalesceRanges:YES];
		}
		// This track has not been extracted before, so re-rip the entire track (verification)
		else
			[self extractWholeTrack:track];
	}
	
	if(!_copyOperation)
		_copyOperation = operation;
	else if(!_verificationOperation)
		_verificationOperation = operation;
	else
		NSLog(@"ERROR: Extra copy operation performed (no support for ultra passes)");
}

- (void) processExtractionOperation:(ExtractionOperation *)operation forPartialTrack:(TrackDescriptor *)track;
{
	NSParameterAssert(nil != operation);
	NSParameterAssert(nil != track);
	
	// Which sectors need to be verified?
	if(![_sectorsNeedingVerification count])
		return;
	
	[[Logger sharedLogger] logMessageWithLevel:eLogMessageLevelDebug format:@"Sectors needing verification: %@", _sectorsNeedingVerification];

	// Only check sectors that are contained in this extraction operation
	NSIndexSet *operationSectors = [NSIndexSet indexSetWithIndexesInRange:NSMakeRange([operation.sectors firstSector], [operation.sectors length])];
	NSIndexSet *sectorsToCheck = [_sectorsNeedingVerification intersectedIndexSet:operationSectors];
	
	// Check for sectors with existing errors that were resolved by this operation
	// A sector's error is resolved if it matches the same sector from a previous extraction self.requiredMatches times (with no C2 errors if enabled)
	NSUInteger sectorIndex = [sectorsToCheck firstIndex];
	while(NSNotFound != sectorIndex) {
		
		// Iterate through all the matching operations and check each sector for matches
		NSUInteger matchCount = 0;
		for(ExtractionOperation *previousOperation in _partialExtractions) {
			
			// Skip this operation if it doesn't contain the sector or if a C2 error was reported for the sector
			if(![previousOperation.sectors containsSector:sectorIndex] || (previousOperation.useC2 && [previousOperation.blockErrorFlags containsIndex:sectorIndex]))
				continue;
			
			if(sectorInFilesMatches(operation.URL, [operation.sectors indexForSector:sectorIndex], previousOperation.URL, [previousOperation.sectors indexForSector:sectorIndex])) {
				++matchCount;

				// Save the sector from this operation if the required number of matches were made
				if(matchCount >= self.requiredMatches) {
					[[Logger sharedLogger] logMessageWithLevel:eLogMessageLevelDebug format:@"Sector %ld verified", sectorIndex];
					[_sectorsNeedingVerification removeIndex:sectorIndex];
					
					[self saveSectors:[NSIndexSet indexSetWithIndex:sectorIndex] fromOperation:operation forTrack:track];
					
					break;
				}
			}
		}	
		
		sectorIndex = [sectorsToCheck indexGreaterThanIndex:sectorIndex];
	}
	
	// Save this extraction operation
	[_partialExtractions addObject:operation];
	
	// If all sectors are verified, encode the track if it is verified by AccurateRip
	if(![_sectorsNeedingVerification count]) {
		[[Logger sharedLogger] logMessage:@"Track has no errors"];
		
		// Any operations in progress are no longer needed
		[self.operationQueue cancelAllOperations];
		
		// Finish the file synthesis
		NSURL *fileURL = _synthesizedFile.URL;
		NSString *MD5 = _synthesizedFile.MD5;
		NSString *SHA1 = _synthesizedFile.SHA1;
		
		[_synthesizedFile closeFile];
		_synthesizedFile = nil;
		
		// Calculate the AccurateRip checksum
		NSUInteger accurateRipChecksum = calculateAccurateRipChecksumForFile(fileURL,
																			 [self.compactDisc.firstSession.firstTrack.number isEqualToNumber:track.number],
																			 [self.compactDisc.firstSession.lastTrack.number isEqualToNumber:track.number]);

		// Determine the possible AccurateRip offsets for the extracted audio, if any
		NSArray *possibleAccurateRipOffsets = [self determinePossibleAccurateRipOffsetForTrack:track URL:fileURL];

		// Determine which pressings (if any) are the primary ones (offset checksum matches with a zero read offset)
		NSPredicate *zeroOffsetPredicate = [NSPredicate predicateWithFormat:@"%K == 0", kReadOffsetKey];
		NSArray *matchingPressingsWithZeroOffset = [possibleAccurateRipOffsets filteredArrayUsingPredicate:zeroOffsetPredicate];
		
		// Iterate through each pressing and compare the track's AccurateRip checksums
		if([matchingPressingsWithZeroOffset count]) {

			for(NSDictionary *matchingPressingInfo in matchingPressingsWithZeroOffset) {
				NSManagedObjectID *accurateRipTrackID = [matchingPressingInfo objectForKey:kAccurateRipTrackIDKey];
				
				// Fetch the AccurateRipTrackRecord object from the context and ensure it is the correct class
				NSManagedObject *managedObject = [self.managedObjectContext objectWithID:accurateRipTrackID];
				if(![managedObject isKindOfClass:[AccurateRipTrackRecord class]])
					continue;
				
				AccurateRipTrackRecord *accurateRipTrack = (AccurateRipTrackRecord *)managedObject;
		
				[[Logger sharedLogger] logMessageWithLevel:eLogMessageLevelDebug format:@"Track AR checksum = %.8lx, checking against %.8lx", accurateRipChecksum, accurateRipTrack.checksum.unsignedIntegerValue];
				
				// If the track was accurately ripped, ship it off to the encoder
				if([accurateRipTrack.checksum unsignedIntegerValue] == accurateRipChecksum) {					
					// Create the extraction record
					TrackExtractionRecord *extractionRecord = [NSEntityDescription insertNewObjectForEntityForName:@"TrackExtractionRecord" 
																							inManagedObjectContext:self.managedObjectContext];
					
					extractionRecord.date = [NSDate date];
					extractionRecord.drive = self.driveInformation;
//					extractionRecord.blockErrorFlags = operation.blockErrorFlags;
					extractionRecord.MD5 = MD5;
					extractionRecord.SHA1 = SHA1;
					extractionRecord.track = track;
					extractionRecord.accurateRipChecksum = [NSNumber numberWithUnsignedInteger:accurateRipChecksum];
					extractionRecord.accurateRipConfidenceLevel = accurateRipTrack.confidenceLevel;

					NSError *error = nil;
					EncodingOperation *encodingOperation = nil;
					if(![[EncoderManager sharedEncoderManager] encodeURL:fileURL forTrackExtractionRecord:extractionRecord encodingOperation:&encodingOperation delayPostProcessing:YES error:&error]) {
						[self.managedObjectContext deleteObject:extractionRecord];
						[self presentError:error modalForWindow:self.window delegate:self didPresentSelector:@selector(didPresentErrorWithRecovery:contextInfo:) contextInfo:NULL];
						return;
					}
					
					[_trackExtractionRecords addObject:extractionRecord];
					[_encodingOperations addObject:encodingOperation];

					[self startExtractingNextTrack];
					
					return;
				}
				
				// If the checksum was not verified, fall through to handling below
			}
		}
		else if([possibleAccurateRipOffsets count]) {
			[[Logger sharedLogger] logMessage:@"Using alternate AccurateRip pressing"];
			
			for(NSDictionary *alternatePressingInfo in possibleAccurateRipOffsets) {
				NSManagedObjectID *accurateRipTrackID = [alternatePressingInfo objectForKey:kAccurateRipTrackIDKey];
				
				// Fetch the AccurateRipTrackRecord object from the context and ensure it is the correct class
				NSManagedObject *managedObject = [self.managedObjectContext objectWithID:accurateRipTrackID];
				if(![managedObject isKindOfClass:[AccurateRipTrackRecord class]])
					continue;
				
				AccurateRipTrackRecord *accurateRipTrack = (AccurateRipTrackRecord *)managedObject;
				
				// Calculate the AccurateRip checksum for the alternate pressing
				NSNumber *alternatePressingOffset = [alternatePressingInfo objectForKey:kReadOffsetKey];
				NSUInteger trackAlternateAccurateRipChecksum = [self calculateAccurateRipChecksumForTrack:track extractionOperation:operation readOffsetAdjustment:[alternatePressingOffset unsignedIntegerValue]];
				
				[[Logger sharedLogger] logMessageWithLevel:eLogMessageLevelDebug format:@"Track alternate pressing AR checksum = %.8lx, checking against %.8lx", trackAlternateAccurateRipChecksum, accurateRipTrack.checksum.unsignedIntegerValue];

				// If the track was accurately ripped, ship it off to the encoder
				if([accurateRipTrack.checksum unsignedIntegerValue] == trackAlternateAccurateRipChecksum) {
					// Create the extraction record
					TrackExtractionRecord *extractionRecord = [NSEntityDescription insertNewObjectForEntityForName:@"TrackExtractionRecord" 
																							inManagedObjectContext:self.managedObjectContext];
					
					extractionRecord.date = [NSDate date];
					extractionRecord.drive = self.driveInformation;
//					extractionRecord.blockErrorFlags = operation.blockErrorFlags;
					extractionRecord.MD5 = MD5;
					extractionRecord.SHA1 = SHA1;
					extractionRecord.track = track;
					extractionRecord.accurateRipChecksum = [NSNumber numberWithUnsignedInteger:accurateRipChecksum];
					extractionRecord.accurateRipConfidenceLevel = accurateRipTrack.confidenceLevel;

					extractionRecord.accurateRipAlternatePressingChecksum = [NSNumber numberWithUnsignedInteger:trackAlternateAccurateRipChecksum];
					extractionRecord.accurateRipAlternatePressingOffset = alternatePressingOffset;
					
					NSError *error = nil;
					EncodingOperation *encodingOperation = nil;
					if(![[EncoderManager sharedEncoderManager] encodeURL:fileURL forTrackExtractionRecord:extractionRecord encodingOperation:&encodingOperation delayPostProcessing:YES error:&error]) {
						[self.managedObjectContext deleteObject:extractionRecord];
						[self presentError:error modalForWindow:self.window delegate:self didPresentSelector:@selector(didPresentErrorWithRecovery:contextInfo:) contextInfo:NULL];
						return;
					}
					
					[_trackExtractionRecords addObject:extractionRecord];
					[_encodingOperations addObject:encodingOperation];

					[self startExtractingNextTrack];
					
					return;
				}
			}
		}

		[[Logger sharedLogger] logMessageWithLevel:eLogMessageLevelDebug format:@"Track still has errors after synthesis"];

		// Retry the track if the maximum retry count hasn't been exceeded
		if(self.retryCount <= self.maxRetries) {
			++_retryCount;
			
			// Remove temporary files
			[self removeTemporaryFiles];
			
			// Reset extraction state
			_synthesizedFile = nil;
			_copyOperation = nil;
			_verificationOperation = nil;
			_partialExtractions = [NSMutableArray array];
			_sectorsNeedingVerification = [NSMutableIndexSet indexSet];
			
			[self extractWholeTrack:track];
		}
		else {
			[[Logger sharedLogger] logMessage:@"Extraction failed for track %@: maximum retry count exceeded", track.number];
			
			[_failedTrackIDs addObject:[track objectID]];
			
			[self startExtractingNextTrack];
		}
	}
	else
		[self extractSectors:_sectorsNeedingVerification forTrack:track coalesceRanges:YES];
}

- (NSUInteger) calculateAccurateRipChecksumForTrack:(TrackDescriptor *)track extractionOperation:(ExtractionOperation *)operation
{
	return [self calculateAccurateRipChecksumForTrack:track extractionOperation:operation readOffsetAdjustment:0];
}

- (NSUInteger) calculateAccurateRipChecksumForTrack:(TrackDescriptor *)track extractionOperation:(ExtractionOperation *)operation readOffsetAdjustment:(NSUInteger)readOffsetAdjustment
{
	NSParameterAssert(nil != track);
	NSParameterAssert(nil != operation);
	
	[_detailedStatusTextField setStringValue:NSLocalizedString(@"Calculating AccurateRip checksum", @"")];
	
	return calculateAccurateRipChecksumForFileRegionUsingOffset(operation.URL, 
																operation.cushionSectors,
																operation.cushionSectors + operation.sectors.length - 1,
																[self.compactDisc.firstSession.firstTrack.number isEqualToNumber:track.number],
																[self.compactDisc.firstSession.lastTrack.number isEqualToNumber:track.number],
																readOffsetAdjustment);
}
	
	
- (NSArray *) determinePossibleAccurateRipOffsetForTrack:(TrackDescriptor *)track URL:(NSURL *)URL
{
	return [self determinePossibleAccurateRipOffsetForTrack:track URL:URL startingSector:0];
}

- (NSArray *) determinePossibleAccurateRipOffsetForTrack:(TrackDescriptor *)track URL:(NSURL *)URL startingSector:(NSUInteger)startingSector;
{
	NSParameterAssert(nil != track);
	NSParameterAssert(nil != URL);
	
	// Scan the extracted file and determine possible AccurateRip offsets
	ReadOffsetCalculationOperation *operation = [[ReadOffsetCalculationOperation alloc ] init];
	
	operation.URL = URL;
	operation.trackID = [track objectID];
	operation.sixSecondPointSector = (6 * CDDA_SECTORS_PER_SECOND) + startingSector;
	operation.maximumOffsetToCheck = (MAXIMUM_OFFSET_TO_CHECK_IN_SECTORS * AUDIO_FRAMES_PER_CDDA_SECTOR);
	
	// Wait for the operation to be ready
	while(![operation isReady])
		[NSThread sleepForTimeInterval:0.25];
	
	// Run the operation in standalone mode
	[_detailedStatusTextField setStringValue:NSLocalizedString(@"Calculating AccurateRip offsets", @"")];
	[operation start];
	
	if(operation.error) {
		[[Logger sharedLogger] logMessageWithLevel:eLogMessageLevelDebug format:@"Error calculating possible AccurateRip offsets: %@", operation.error];
		return nil;
	}
	
	return operation.possibleReadOffsets;
}

#if 0
- (BOOL) interpolateC2ErrorsForTrack:(TrackDescriptor *)track withOperation:(ExtractionOperation *)operation error:(NSError **)error
{
	NSParameterAssert(nil != operation);
	
	BOOL result = NO;
	
	NSURL *fileURL = temporaryURLWithExtension(@"wav");
	
	// Copy the file sector by sector, interpolating single sector C2 errors

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
	SInt64 startingPacketNumber;
	
	// Iteratively process each desired CDDA sector in the file
	NSUInteger sectorNumber = trackFirstSector;
	for(;;) {
		
		// Since this is lpcm audio, packets === frames and no packet descriptions are required
		
		startingPacketNumber = (sectorNumber - trackFirstSector) * AUDIO_FRAMES_PER_CDDA_SECTOR;
		
		packetCount = AUDIO_FRAMES_PER_CDDA_SECTOR;
		bytesRead = 0;
		
		status = AudioFileReadPackets(inputFile, false, &bytesRead, NULL, startingPacketNumber, &packetCount, buffer);
		
		if(noErr != status)
			break;
		else if(kCDSectorSizeCDDA != bytesRead || AUDIO_FRAMES_PER_CDDA_SECTOR != packetCount)
			break;
		
		// Attempt to fixup any C2 errors
		if([operation.blockErrorFlags containsIndex:sectorNumber]) {
			NSData *errorFlags = [operation.errorFlags objectForKey:[NSNumber numberWithUnsignedInteger:sectorNumber]];
			
			const uint8_t *rawErrorFlags = [errorFlags bytes];
			
			// errorFlags contains 294 bytes, 1 bit for each byte in the sector
			// attempt a linear interpolation on any missing samples
			BitArray *ba = [[BitArray alloc] initWithBits:rawErrorFlags bitCount:kCDSectorSizeCDDA];
			NSIndexSet *bytesWithErrors = [ba indexSetForOnes];

			NSUInteger byteIndex = [bytesWithErrors firstIndex];
			while(NSNotFound != byteIndex) {
				
				// Is this a single byte error?
				if(byteIndex && ((kCDSectorSizeCDDA - 2) > byteIndex) && ![ba valueAtIndex:(byteIndex - 1)] && ![ba valueAtIndex:(byteIndex + 1)]) {
					NSLog(@"interpolating single byte error at index: %ld", byteIndex);
					
					int16_t avgValue = ((int16_t)buffer[byteIndex - 1] + (int16_t)buffer[byteIndex + 1]) / 2;
					buffer[byteIndex] = avgValue;
				}

				byteIndex = [bytesWithErrors indexGreaterThanIndex:byteIndex];
			}			
		}
		
		// Write the data to the output file at the appropriate location
		status = AudioFileWritePackets(outputFile, false, bytesRead, NULL, startingPacketNumber, &packetCount, buffer);
		if(noErr != status)
			break;
		else if(AUDIO_FRAMES_PER_CDDA_SECTOR != packetCount)
			break;
		
		++sectorNumber;
	}
	
	// Close the input file
	status = AudioFileClose(inputFile);
	if(noErr != status) {
		if(error)
			*error = [NSError errorWithDomain:NSOSStatusErrorDomain code:status userInfo:nil];
		goto cleanup;
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
#endif

- (BOOL) saveSectors:(NSIndexSet *)sectors fromOperation:(ExtractionOperation *)operation forTrack:(TrackDescriptor *)track
{
	NSParameterAssert(nil != sectors);
	NSParameterAssert(nil != operation);
	NSParameterAssert(nil != track);
	
	// Open the source file for reading
	NSError *error = nil;
	ExtractedAudioFile *inputFile = [ExtractedAudioFile openFileForReadingAtURL:operation.URL error:&error];
	if(!inputFile) {
		[self presentError:error modalForWindow:self.window delegate:self didPresentSelector:@selector(didPresentErrorWithRecovery:contextInfo:) contextInfo:NULL];
		return NO;
	}
	
	// Create the output file if it doesn't exist
	if(!_synthesizedFile) {
		_synthesizedFile = [ExtractedAudioFile createFileAtURL:temporaryURLWithExtension(@"wav") error:&error];
		if(!_synthesizedFile) {
			[inputFile closeFile];
			[self presentError:error modalForWindow:self.window delegate:self didPresentSelector:@selector(didPresentErrorWithRecovery:contextInfo:) contextInfo:NULL];
			return NO;
		}
	}
	
	// Convert the absolute sector numbers to indexes within the extracted audio
	NSUInteger trackFirstSector = track.sectorRange.firstSector;
	NSUInteger firstSectorInInputFile = operation.sectors.firstSector;
	NSUInteger inputFileCushionSectors = operation.cushionSectors;
	
	// Copy and save the specified sectors, combining ranges to minimize reads
	NSUInteger firstIndex = NSNotFound;
	NSUInteger latestIndex = NSNotFound;
	NSUInteger sectorIndex = [sectors firstIndex];
	
	for(;;) {
		// Last sector
		if(NSNotFound == sectorIndex) {
			if(NSNotFound != firstIndex) {
				if(firstIndex == latestIndex) {
					NSData *sectorData = [inputFile audioDataForSector:(firstIndex - firstSectorInInputFile + inputFileCushionSectors) error:&error];
					[_synthesizedFile setAudioData:sectorData forSector:(firstIndex - trackFirstSector) error:&error];
				}
				else {
					NSUInteger sectorCount = latestIndex - firstIndex + 1;
					NSData *sectorsData = [inputFile audioDataForSectors:NSMakeRange(firstIndex - firstSectorInInputFile + inputFileCushionSectors, sectorCount) error:&error];
					[_synthesizedFile setAudioData:sectorsData forSectors:NSMakeRange(firstIndex - trackFirstSector, sectorCount) error:&error];
				}
			}
			
			break;
		}
		
		// Consolidate this sector into the current range
		if(latestIndex == (sectorIndex - 1))
			latestIndex = sectorIndex;
		// Store the previous range and start a new one
		else {
			if(NSNotFound != firstIndex) {
				if(firstIndex == latestIndex) {
					NSData *sectorData = [inputFile audioDataForSector:(firstIndex - firstSectorInInputFile + inputFileCushionSectors) error:&error];
					[_synthesizedFile setAudioData:sectorData forSector:(firstIndex - trackFirstSector) error:&error];
				}
				else {
					NSUInteger sectorCount = latestIndex - firstIndex + 1;
					NSData *sectorsData = [inputFile audioDataForSectors:NSMakeRange(firstIndex - firstSectorInInputFile + inputFileCushionSectors, sectorCount) error:&error];
					[_synthesizedFile setAudioData:sectorsData forSectors:NSMakeRange(firstIndex - trackFirstSector, sectorCount) error:&error];
				}
			}
			
			firstIndex = sectorIndex;
			latestIndex = sectorIndex;
		}
		
		sectorIndex = [sectors indexGreaterThanIndex:sectorIndex];
	}
	
	[inputFile closeFile];
	
	return YES;
}

- (BOOL) sendTrackToEncoder:(TrackDescriptor *)track extractionOperation:(ExtractionOperation *)operation accurateRipChecksum:(NSUInteger)accurateRipChecksum accurateRipConfidenceLevel:(NSNumber *)accurateRipConfidenceLevel error:(NSError **)error
{
	return [self sendTrackToEncoder:track extractionOperation:operation accurateRipChecksum:accurateRipChecksum accurateRipConfidenceLevel:accurateRipConfidenceLevel accurateRipAlternatePressingChecksum:0 accurateRipAlternatePressingOffset:nil error:error];
}

- (BOOL) sendTrackToEncoder:(TrackDescriptor *)track extractionOperation:(ExtractionOperation *)operation accurateRipChecksum:(NSUInteger)accurateRipChecksum accurateRipConfidenceLevel:(NSNumber *)accurateRipConfidenceLevel accurateRipAlternatePressingChecksum:(NSUInteger)accurateRipAlternatePressingChecksum accurateRipAlternatePressingOffset:(NSNumber *)accurateRipAlternatePressingOffset error:(NSError **)error
{
	NSParameterAssert(nil != track);
	NSParameterAssert(nil != operation);
	
	NSURL *URLToEncode = operation.URL;
	
	// Strip off the cushion sectors before encoding, if present
	if(operation.cushionSectors) {
		[_detailedStatusTextField setStringValue:NSLocalizedString(@"Creating output file", @"")];
		
		ExtractedAudioFile *inputFile = [ExtractedAudioFile openFileForReadingAtURL:operation.URL error:error];
		if(!inputFile)
			return NO;
		
		ExtractedAudioFile *outputFile = [ExtractedAudioFile createFileAtURL:temporaryURLWithExtension(@"wav") error:error];
		if(!outputFile) {
			[inputFile closeFile];
			return NO;
		}
		
		NSUInteger startingSector = operation.cushionSectors;
		NSUInteger sectorCount = operation.sectors.length;
		NSUInteger sectorCounter = 0;
		
		while(sectorCounter < sectorCount) {
			NSData *audioData = [inputFile audioDataForSector:startingSector error:error];
			if(!audioData) {
				[inputFile closeFile];
				[outputFile closeFile];
				return NO;
			}
			
			if(![outputFile setAudioData:audioData forSector:sectorCounter error:error]) {
				[inputFile closeFile];
				[outputFile closeFile];
				return NO;
			}
			
			++sectorCounter;
			++startingSector;
		}
		
		// Sanity check to ensure the correct sectors were removed and all sectors were copied
		if(![operation.MD5 isEqualToString:outputFile.MD5] || ![operation.SHA1 isEqualToString:outputFile.SHA1]) {
			[[Logger sharedLogger] logMessage:@"Internal inconsistency: MD5 or SHA1 for extracted and synthesized audio don't match"];

			[inputFile closeFile];
			[outputFile closeFile];
			
			if(error)
				*error = [NSError errorWithDomain:NSCocoaErrorDomain code:42 userInfo:nil];
			return NO;
		}
		
		URLToEncode = outputFile.URL;

		[inputFile closeFile];
		[outputFile closeFile];
	}
	
	// Create the extraction record
	TrackExtractionRecord *extractionRecord = [NSEntityDescription insertNewObjectForEntityForName:@"TrackExtractionRecord" 
																			inManagedObjectContext:self.managedObjectContext];
	
	extractionRecord.date = [NSDate date];
	extractionRecord.drive = self.driveInformation;
	extractionRecord.blockErrorFlags = operation.blockErrorFlags;
	extractionRecord.MD5 = operation.MD5;
	extractionRecord.SHA1 = operation.SHA1;
	extractionRecord.track = track;

	if(accurateRipChecksum)
		extractionRecord.accurateRipChecksum = [NSNumber numberWithUnsignedInteger:accurateRipChecksum];
	if(accurateRipConfidenceLevel)
		extractionRecord.accurateRipConfidenceLevel = accurateRipConfidenceLevel;
	
	if(accurateRipAlternatePressingChecksum)
		extractionRecord.accurateRipAlternatePressingChecksum = [NSNumber numberWithUnsignedInteger:accurateRipAlternatePressingChecksum];
	if(accurateRipAlternatePressingOffset)
		extractionRecord.accurateRipAlternatePressingOffset = accurateRipAlternatePressingOffset;
	
	EncodingOperation *encodingOperation = nil;
	if(![[EncoderManager sharedEncoderManager] encodeURL:URLToEncode forTrackExtractionRecord:extractionRecord encodingOperation:&encodingOperation delayPostProcessing:YES error:error]) {
		[self.managedObjectContext deleteObject:extractionRecord];
		return NO;
	}
	
	[_trackExtractionRecords addObject:extractionRecord];
	[_encodingOperations addObject:encodingOperation];
	
	return YES;
}

@end
