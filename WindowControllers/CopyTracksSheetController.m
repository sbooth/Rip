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

#import "ExtractionRecord.h"
#import "ExtractedTrackRecord.h"

#import "AccurateRipDiscRecord.h"
#import "AccurateRipTrackRecord.h"
#import "AccurateRipUtilities.h"

#import "ReadMCNSheetController.h"
#import "ReadISRCsSheetController.h"
#import "DetectPregapsSheetController.h"

#import "EncoderManager.h"

#import "CDDAUtilities.h"
#import "FileUtilities.h"

// ========================================
// Context objects for observeValueForKeyPath:ofObject:change:context:
// ========================================
static NSString * const kAudioExtractionKVOContext		= @"org.sbooth.Rip.CopyTracksSheetController.ExtractAudioKVOContext";
static NSString * const kOffsetVerificationKVOContext	= @"org.sbooth.Rip.CopyTracksSheetController.OffsetVerificationKVOContext";

// ========================================
// The number of sectors which will be scanned during offset verification
// ========================================
#define MAXIMUM_OFFSET_TO_CHECK_IN_SECTORS 2

@interface CopyTracksSheetController ()
@property (assign) CompactDisc * compactDisc;
@property (assign) DriveInformation * driveInformation;
@property (assign) NSManagedObjectContext * managedObjectContext;

@property (assign) NSOperationQueue * operationQueue;
@end

@interface CopyTracksSheetController (Callbacks)
- (void) didPresentErrorWithRecovery:(BOOL)didRecover contextInfo:(void *)contextInfo;
- (void) audioExtractionTimerFired:(NSTimer *)timer;
- (void) offsetVerificationTimerFired:(NSTimer *)timer;
@end

@interface CopyTracksSheetController (Private)
- (BOOL) readMCNIfRequired;
- (BOOL) readISRCsIfRequired;
- (BOOL) detectPregapsIfRequired;

- (void) performCopyTracks;
- (void) startExtractingNextTrack;

- (void) processExtractionOperation:(ExtractionOperation *)operation;
- (void) processExtractionOperation:(ExtractionOperation *)operation withOffsetVerificationOperation:(ReadOffsetCalculationOperation *)offsetVerificationOperation;

- (ExtractionRecord *) createExtractionRecordForOperation:(ExtractionOperation *)operation accurateRipChecksums:(NSDictionary *)checksums;
@end

@implementation CopyTracksSheetController

@synthesize disk = _disk;
@synthesize trackIDs = _trackIDs;
@synthesize extractAsImage = _extractAsImage;

@synthesize extractionRecords = _extractionRecords;

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
				// Schedule a timer which will update the UI
				NSTimer *timer = [NSTimer timerWithTimeInterval:0.5 target:self selector:@selector(audioExtractionTimerFired:) userInfo:operation repeats:YES];
				[[NSRunLoop mainRunLoop] addTimer:timer forMode:NSRunLoopCommonModes];
				
				NSString *trackDescription = nil;
				NSArray *trackIDs = operation.trackIDs;
				
				if(1 == [trackIDs count]) {
					NSManagedObjectID *trackID = [trackIDs lastObject];
					
					// Fetch the TrackDescriptor object from the context and ensure it is the correct class
					NSManagedObject *managedObject = [self.managedObjectContext objectWithID:trackID];
					if(![managedObject isKindOfClass:[TrackDescriptor class]])
						return;
					
					TrackDescriptor *track = (TrackDescriptor *)managedObject;				
					
					if(track.metadata.title)
						trackDescription = track.metadata.title;
					else
						trackDescription = [track.number stringValue];
				}
				else {
					
				}
				
				[_statusTextField setStringValue:trackDescription];
			}
		}
		else if([keyPath isEqualToString:@"isCancelled"] || [keyPath isEqualToString:@"isFinished"]) {
			[operation removeObserver:self forKeyPath:@"isExecuting"];
			[operation removeObserver:self forKeyPath:@"isCancelled"];
			[operation removeObserver:self forKeyPath:@"isFinished"];

			// If this disc wasn't found in AccurateRip, handle the extracted audio now
			if(!self.compactDisc.accurateRipDiscs) {
				[self processExtractionOperation:operation];

				// If no tracks are being processed and none remain to be extracted, we are finished			
				if(![[self.operationQueue operations] count] && ![_tracksToBeExtracted count])
					[[NSApplication sharedApplication] endSheet:self.window returnCode:NSOKButton];
			}
		}
	}
	else if(kOffsetVerificationKVOContext == context) {
		ReadOffsetCalculationOperation *operation = (ReadOffsetCalculationOperation *)object;
		
		if([keyPath isEqualToString:@"isExecuting"]) {
			if([operation isExecuting]) {
				// Schedule a timer which will update the UI
				NSTimer *timer = [NSTimer timerWithTimeInterval:0.5 target:self selector:@selector(offsetVerificationTimerFired:) userInfo:operation repeats:YES];
				[[NSRunLoop mainRunLoop] addTimer:timer forMode:NSRunLoopCommonModes];
				
				[_statusTextField setStringValue:@"Verifying the offset of the extracted audio"];
			}
		}
		else if([keyPath isEqualToString:@"isCancelled"] || [keyPath isEqualToString:@"isFinished"]) {
			[operation removeObserver:self forKeyPath:@"isExecuting"];
			[operation removeObserver:self forKeyPath:@"isCancelled"];
			[operation removeObserver:self forKeyPath:@"isFinished"];
			
			// Use AccurateRip to verify the results
			ExtractionOperation *extractionOperation = [[operation dependencies] lastObject];
			[self processExtractionOperation:extractionOperation withOffsetVerificationOperation:operation];
			
			// If no tracks are being processed and none remain to be extracted, we are finished			
			if(![[self.operationQueue operations] count] && ![_tracksToBeExtracted count])
				[[NSApplication sharedApplication] endSheet:self.window returnCode:NSOKButton];			
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

- (IBAction) copyTracks:(id)sender
{
	
#pragma unused(sender)
	
	BOOL needMCN = [self readMCNIfRequired];
	if(needMCN)
		return;
	
	BOOL needISRCs = [self readISRCsIfRequired];
	if(needISRCs)
		return;
	
	BOOL needPregaps = [self detectPregapsIfRequired];
	if(needPregaps)
		return;

	[self performCopyTracks];
}

- (IBAction) ok:(id)sender
{
	
#pragma unused(sender)
	
	if([self.operationQueue.operations count]) {
		NSBeep();
		return;
	}
	
	self.disk = NULL;

	[[NSApplication sharedApplication] endSheet:self.window returnCode:NSOKButton];
}

- (IBAction) cancel:(id)sender
{
	
#pragma unused(sender)
	
	[self.operationQueue cancelAllOperations];

	self.disk = NULL;

	[[NSApplication sharedApplication] endSheet:self.window returnCode:NSCancelButton];
}

@end

@implementation CopyTracksSheetController (Callbacks)

- (void) didPresentErrorWithRecovery:(BOOL)didRecover contextInfo:(void *)contextInfo
{
	
#pragma unused(contextInfo)
	
	[[NSApplication sharedApplication] endSheet:self.window returnCode:(didRecover ? NSOKButton : NSCancelButton)];	
}

- (void) audioExtractionTimerFired:(NSTimer *)timer
{
	ExtractionOperation *operation = (ExtractionOperation *)[timer userInfo];
	
	if([operation isFinished] || [operation isCancelled]) {
		[timer invalidate];
		return;
	}
	
	[_progressIndicator setDoubleValue:operation.fractionComplete];
	//	NSLog(@"C2 errors: %i", [operation.errorFlags countOfOnes]);
}

- (void) offsetVerificationTimerFired:(NSTimer *)timer
{
	ReadOffsetCalculationOperation *operation = (ReadOffsetCalculationOperation *)[timer userInfo];
	
	if([operation isFinished] || [operation isCancelled]) {
		[timer invalidate];
		return;
	}
	
	[_progressIndicator setDoubleValue:operation.fractionComplete];
	//	NSLog(@"C2 errors: %i", [operation.errorFlags countOfOnes]);
}

@end

@implementation CopyTracksSheetController (SheetCallbacks)

- (void) showReadMCNSheetDidEnd:(NSWindow *)sheet returnCode:(int)returnCode contextInfo:(void *)contextInfo
{
	
#pragma unused(contextInfo)
	
	NSParameterAssert(nil != sheet);
	
	[sheet orderOut:self];
	
	if(NSCancelButton == returnCode) {
		[self cancel:self];
		return;
	}
	
	BOOL needISRCs = [self readISRCsIfRequired];
	if(needISRCs)
		return;
	
	BOOL needPregaps = [self detectPregapsIfRequired];
	if(needPregaps)
		return;	
}

- (void) showReadISRCsSheetDidEnd:(NSWindow *)sheet returnCode:(int)returnCode contextInfo:(void *)contextInfo
{
	
#pragma unused(contextInfo)
	
	NSParameterAssert(nil != sheet);
	
	[sheet orderOut:self];
	
	if(NSCancelButton == returnCode) {
		[self cancel:self];
		return;
	}
	
	BOOL needPregaps = [self detectPregapsIfRequired];
	if(needPregaps)
		return;
	
	[self performCopyTracks];
}

- (void) showDetectPregapsSheetDidEnd:(NSWindow *)sheet returnCode:(int)returnCode contextInfo:(void *)contextInfo
{
	
#pragma unused(contextInfo)
	
	NSParameterAssert(nil != sheet);
	
	[sheet orderOut:self];
	
	if(NSCancelButton == returnCode) {
		[self cancel:self];
		return;
	}
	
	[self performCopyTracks];
}

@end


@implementation CopyTracksSheetController (Private)

- (BOOL) readMCNIfRequired
{
	// Read the MCN for the disc, if not present
	if(!self.compactDisc.metadata.MCN) {
		ReadMCNSheetController *sheetController = [[ReadMCNSheetController alloc] init];
		
		sheetController.disk = self.disk;
		sheetController.compactDiscID = self.compactDisc.objectID;
		
		[[NSApplication sharedApplication] beginSheet:sheetController.window 
									   modalForWindow:self.window
										modalDelegate:self 
									   didEndSelector:@selector(showReadMCNSheetDidEnd:returnCode:contextInfo:) 
										  contextInfo:sheetController];
		
		[sheetController readMCN:self];
		
		return YES;
	}
	else
		return NO;
}

- (BOOL) readISRCsIfRequired
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
		
		[[NSApplication sharedApplication] beginSheet:sheetController.window 
									   modalForWindow:self.window
										modalDelegate:self 
									   didEndSelector:@selector(showReadISRCsSheetDidEnd:returnCode:contextInfo:) 
										  contextInfo:sheetController];
		
		[sheetController readISRCs:self];
		
		return YES;
	}
	else
		return NO;
}

- (BOOL) detectPregapsIfRequired
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
		
		[[NSApplication sharedApplication] beginSheet:sheetController.window 
									   modalForWindow:self.window
										modalDelegate:self 
									   didEndSelector:@selector(showDetectPregapsSheetDidEnd:returnCode:contextInfo:) 
										  contextInfo:sheetController];
		
		[sheetController detectPregaps:self];
		
		return YES;
	}
	else
		return NO;
}

- (void) performCopyTracks
{
	// Copy the array containing the tracks to be extracted
	_tracksToBeExtracted = [self.trackIDs mutableCopy];
	
	// Set up the extraction records
	_extractionRecords = [NSMutableArray array];
	
	// Get started on the first one
	if([_tracksToBeExtracted count])
		[self startExtractingNextTrack];
}

- (void) startExtractingNextTrack
{
	NSParameterAssert(1 <= [_tracksToBeExtracted count]);
	
	if(self.extractAsImage)
		NSLog(@"FIXME: EXTRACT IMAGE NOT INDIVIDUAL TRACKS");
	
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
	
	// Audio extraction
	ExtractionOperation *extractionOperation = [[ExtractionOperation alloc] init];
	
	extractionOperation.disk = self.disk;
	extractionOperation.sectors = track.sectorRange;
	extractionOperation.allowedSectors = self.compactDisc.firstSession.sectorRange;
	extractionOperation.trackIDs = [NSArray arrayWithObject:track.objectID];
	extractionOperation.readOffset = self.driveInformation.readOffset;
	extractionOperation.URL = temporaryURLWithExtension(@"wav");
	
	// Observe the operation's progress
	[extractionOperation addObserver:self forKeyPath:@"isExecuting" options:NSKeyValueObservingOptionNew context:kAudioExtractionKVOContext];
	[extractionOperation addObserver:self forKeyPath:@"isCancelled" options:NSKeyValueObservingOptionNew context:kAudioExtractionKVOContext];
	[extractionOperation addObserver:self forKeyPath:@"isFinished" options:NSKeyValueObservingOptionNew context:kAudioExtractionKVOContext];

	// Do it.  Do it.  Do it.
	[self.operationQueue addOperation:extractionOperation];

	// Offset verification is only applicable if the disc was found in AccurateRip
	if(self.compactDisc.accurateRipDiscs) {
		// AccurateRip offset checksums start at six seconds into the file
		NSUInteger sixSecondPointSector = (6 * CDDA_SECTORS_PER_SECOND);
		
		ReadOffsetCalculationOperation *offsetCalculationOperation = [[ReadOffsetCalculationOperation alloc] init];
		
		offsetCalculationOperation.URL = extractionOperation.URL;
		offsetCalculationOperation.trackDescriptorID = track.objectID;
		offsetCalculationOperation.sixSecondPointSector = sixSecondPointSector;
		offsetCalculationOperation.maximumOffsetToCheck = (MAXIMUM_OFFSET_TO_CHECK_IN_SECTORS * AUDIO_FRAMES_PER_CDDA_SECTOR);
		
		// Set up operation dependencies
		[offsetCalculationOperation addDependency:extractionOperation];

		// Observe the operation's progress
		[offsetCalculationOperation addObserver:self forKeyPath:@"isExecuting" options:NSKeyValueObservingOptionNew context:kOffsetVerificationKVOContext];
		[offsetCalculationOperation addObserver:self forKeyPath:@"isCancelled" options:NSKeyValueObservingOptionNew context:kOffsetVerificationKVOContext];
		[offsetCalculationOperation addObserver:self forKeyPath:@"isFinished" options:NSKeyValueObservingOptionNew context:kOffsetVerificationKVOContext];

		[self.operationQueue addOperation:offsetCalculationOperation];
	}
}

- (void) processExtractionOperation:(ExtractionOperation *)operation
{
	[self processExtractionOperation:operation withOffsetVerificationOperation:nil];
}

- (void) processExtractionOperation:(ExtractionOperation *)operation withOffsetVerificationOperation:(ReadOffsetCalculationOperation *)offsetVerificationOperation
{
	NSParameterAssert(nil != operation);
	
	// Delete the output file if the operation was cancelled or did not succeed
	if(operation.error || operation.isCancelled) {
		if(operation.error)
			[self presentError:operation.error modalForWindow:self.window delegate:nil didPresentSelector:NULL contextInfo:NULL];
		
		NSError *error = nil;
		if(![[NSFileManager defaultManager] removeItemAtPath:operation.URL.path error:&error])
			[self presentError:error modalForWindow:self.window delegate:nil didPresentSelector:NULL contextInfo:NULL];
		return;
	}
	
#if DEBUG
	NSLog(@"Extraction to %@ finished, %u C2 errors.  MD5 = %@", operation.URL.path, operation.errorFlags.countOfOnes, operation.MD5);
#endif
	
	// Create a dictionary to hold the actual checksums of the extracted audio
	NSMutableDictionary *actualAccurateRipChecksums = nil;
	NSMutableDictionary *accurateRipTracksUsed = nil;
	
	// If trackIDs is set, the ExtractionOperation represents one or more whole tracks (and not an arbitrary range of sectors)
	// If this is the case, calculate the AccurateRip checksum(s) for the extracted tracks
	if(operation.trackIDs) {
		NSUInteger sectorOffset = 0;
		actualAccurateRipChecksums = [NSMutableDictionary dictionary];
		
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
										   forKey:track.objectID];			
		}
	}
	
	// If this disc was found in Accurate Rip, verify the checksum(s) if whole tracks were extracted
	if(self.compactDisc.accurateRipDiscs && operation.trackIDs) {
		BOOL allTracksWereAccuratelyExtracted = YES;
		accurateRipTracksUsed = [NSMutableArray array];
		
		for(NSManagedObjectID *trackID in operation.trackIDs) {
			NSManagedObject *managedObject = [self.managedObjectContext objectWithID:trackID];
			if(![managedObject isKindOfClass:[TrackDescriptor class]])
				continue;
			
			TrackDescriptor *track = (TrackDescriptor *)managedObject;			
			
			// A disc may have multiple pressings in AccurateRip; try to use the one that matches
			// the configured read offset for the drive
			AccurateRipDiscRecord *accurateRipPressingToUse = nil;
			
			if(offsetVerificationOperation) {
				NSPredicate *zeroOffsetPredicate = [NSPredicate predicateWithFormat:@"%K == 0", kReadOffsetKey];
				NSArray *matchingPressingsWithZeroOffset = [offsetVerificationOperation.possibleReadOffsets filteredArrayUsingPredicate:zeroOffsetPredicate];
				if([matchingPressingsWithZeroOffset count]) {
					NSManagedObjectID *accurateRipTrackID = [[matchingPressingsWithZeroOffset lastObject] objectForKey:kAccurateRipTrackIDKey];
					
					// Fetch the AccurateRipTrackRecord object from the context and ensure it is the correct class
					managedObject = [self.managedObjectContext objectWithID:accurateRipTrackID];
					if(![managedObject isKindOfClass:[AccurateRipTrackRecord class]]) {
//						[self presentError:error modalForWindow:self.window delegate:self didPresentSelector:@selector(didPresentErrorWithRecovery:contextInfo:) contextInfo:NULL];
						return;
					}
					
					AccurateRipTrackRecord *accurateRipTrack = (AccurateRipTrackRecord *)managedObject;
					accurateRipPressingToUse = accurateRipTrack.disc;
				}
			}
			
			if(!accurateRipPressingToUse) {
				NSLog(@"USE ALTERNATE AR PRESSING !!!");
				return;
			}
			
			AccurateRipTrackRecord *accurateRipTrack = [accurateRipPressingToUse trackNumber:track.number.unsignedIntegerValue];
			NSNumber *trackActualAccurateRipChecksum = [actualAccurateRipChecksums objectForKey:track.objectID];
			
			if(accurateRipTrack && accurateRipTrack.checksum.unsignedIntegerValue == trackActualAccurateRipChecksum.unsignedIntegerValue) {
				[accurateRipTracksUsed setObject:accurateRipTrack forKey:track.objectID];
#if DEBUG
				NSLog(@"Track %@ accurately ripped, confidence %@", track.number, accurateRipTrack.confidenceLevel);
#endif
			}
			else {
				allTracksWereAccuratelyExtracted = NO;				
#if DEBUG
				NSLog(@"AccurateRip checksums don't match.  Expected %x, got %x", accurateRipTrack.checksum.unsignedIntegerValue, trackActualAccurateRipChecksum.unsignedIntegerValue);
#endif
			}
		}
		
		// If all tracks were accurately ripped, ship the tracks/image off to the encoder
		if(allTracksWereAccuratelyExtracted) {
			ExtractionRecord *extractionRecord = [self createExtractionRecordForOperation:operation accurateRipChecksums:actualAccurateRipChecksums];
			[[EncoderManager sharedEncoderManager] encodeURL:operation.URL extractionRecord:extractionRecord error:NULL];
			
			[self.extractionRecords addObject:extractionRecord];
		}
	}
	// Re-rip the tracks if any C2 error flags were returned
	else if(operation.errorFlags.countOfOnes) {
		
	}
	// No C2 errors, pass the track to the encoder
	else {
		ExtractionRecord *extractionRecord = [self createExtractionRecordForOperation:operation accurateRipChecksums:actualAccurateRipChecksums];
		[[EncoderManager sharedEncoderManager] encodeURL:operation.URL extractionRecord:extractionRecord error:NULL];
		
		[self.extractionRecords addObject:extractionRecord];
	}	
}

- (ExtractionRecord *) createExtractionRecordForOperation:(ExtractionOperation *)operation accurateRipChecksums:(NSDictionary *)checksums
{
	NSParameterAssert(nil != operation);
	
	ExtractionRecord *extractionRecord = [NSEntityDescription insertNewObjectForEntityForName:@"ExtractionRecord" 
																	   inManagedObjectContext:self.managedObjectContext];
	
	extractionRecord.disc = self.compactDisc;
	extractionRecord.date = [NSDate date];
	extractionRecord.drive = self.driveInformation;
	extractionRecord.errorFlags = operation.errorFlags;
	extractionRecord.MD5 = operation.MD5;
	extractionRecord.SHA1 = operation.SHA1;
	
	if(operation.trackIDs) {		
		for(NSManagedObjectID *trackID in operation.trackIDs) {
			NSManagedObject *managedObject = [self.managedObjectContext objectWithID:trackID];
			if(![managedObject isKindOfClass:[TrackDescriptor class]])
				continue;
			
			TrackDescriptor *track = (TrackDescriptor *)managedObject;			
			
			ExtractedTrackRecord *extractedTrackRecord = [NSEntityDescription insertNewObjectForEntityForName:@"ExtractedTrackRecord" 
																					   inManagedObjectContext:self.managedObjectContext];
			
			extractedTrackRecord.track = track;		
			extractedTrackRecord.accurateRipChecksum = [checksums objectForKey:track.objectID];
//			extractedTrackRecord.accurateRipTrackRecord = [tracks objectForKey:track.objectID];
			
			[extractionRecord addTracksObject:extractedTrackRecord];
		}
	}
	
	return extractionRecord;
}

@end
