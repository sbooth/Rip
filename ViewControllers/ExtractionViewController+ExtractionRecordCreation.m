/*
 *  Copyright (C) 2008 - 2009 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import "ExtractionViewController+ExtractionRecordCreation.h"

#import "FileUtilities.h"
#import "AudioUtilities.h"
#import "CDDAUtilities.h"

#import "ExtractedAudioFile.h"

#import "SectorRange.h"

#import "CompactDisc.h"
#import "SessionDescriptor.h"
#import "TrackDescriptor.h"
#import "TrackMetadata.h"
#import "ExtractionOperation.h"
#import "TrackExtractionRecord.h"
#import "ImageExtractionRecord.h"

#import "ReplayGainUtilities.h"
#import "AccurateRipUtilities.h"

#import "Logger.h"

#include <AudioToolbox/AudioFile.h>

@implementation ExtractionViewController (ExtractionRecordCreation)

- (NSURL *) prependAndAppendSilenceForTrackURL:(NSURL *)fileURL error:(NSError **)error
{
	NSParameterAssert(nil != fileURL);
	
	// Nothing to do
	if(!_sectorsOfSilenceToPrepend && !_sectorsOfSilenceToAppend)
		return fileURL;
	
	[_detailedStatusTextField setStringValue:NSLocalizedString(@"Creating output file", @"")];	
	
	// Create the output file
	NSURL *outputURL = temporaryURLWithExtension(@"wav");
	if(!createCDDAFileAtURL(outputURL, error))
		return nil;
	
	// Prepend the silence
	if(_sectorsOfSilenceToPrepend) {
		ExtractedAudioFile *audioFile = [ExtractedAudioFile openFileForReadingAndWritingAtURL:outputURL error:error];
		if(!audioFile)
			return nil;
		
		int8_t *silence = NSAllocateCollectable(kCDSectorSizeCDDA * _sectorsOfSilenceToPrepend, 0);
		memset(silence, 0, kCDSectorSizeCDDA * _sectorsOfSilenceToPrepend);
		
		// Write the silence
		NSUInteger sectorsWritten = [audioFile setAudio:silence forSectors:NSMakeRange(0, _sectorsOfSilenceToPrepend) error:error];
		
		// Clean up
		[audioFile closeFile];
		silence = NULL;
		
		if(sectorsWritten != _sectorsOfSilenceToPrepend)
			return nil;
	}
	
	// Copy the audio
	if(!copyAllSectorsFromURLToURL(fileURL, outputURL, _sectorsOfSilenceToPrepend)) {
		if(error)
			*error = [NSError errorWithDomain:NSPOSIXErrorDomain code:EIO userInfo:nil];
		return nil;
	}
	
	// Append the silence
	if(_sectorsOfSilenceToAppend) {
		ExtractedAudioFile *audioFile = [ExtractedAudioFile openFileForReadingAndWritingAtURL:outputURL error:error];
		if(!audioFile)
			return nil;
		
		int8_t *silence = NSAllocateCollectable(kCDSectorSizeCDDA * _sectorsOfSilenceToAppend, 0);
		memset(silence, 0, kCDSectorSizeCDDA * _sectorsOfSilenceToAppend);
		
		// Write the silence
		NSUInteger sectorsWritten = [audioFile setAudio:silence forSectors:NSMakeRange(_sectorsOfSilenceToPrepend + _sectorsToExtract.length, _sectorsOfSilenceToAppend) error:error];
		
		// Clean up
		[audioFile closeFile];
		silence = NULL;
		
		if(sectorsWritten != _sectorsOfSilenceToAppend)
			return nil;
	}
	
	return outputURL;
}

- (NSURL *) generateOutputFileForURL:(NSURL *)inputURL containsSilence:(BOOL)containsSilence error:(NSError **)error
{
	NSParameterAssert(nil != inputURL);
	
	[_detailedStatusTextField setStringValue:NSLocalizedString(@"Creating output file", @"")];	
	
	NSURL *URL = inputURL;
	
	// Strip off the cushion sectors before encoding
	if(MAXIMUM_OFFSET_TO_CHECK_IN_SECTORS) {

		// Create the output file
		NSURL *outputURL = temporaryURLWithExtension(@"wav");
		if(!createCDDAFileAtURL(outputURL, error))
			return nil;
		
		// The inputURL may have silence prepended or appended for Accurate Rip calculations
		// If it does, that silence needs to be skipped
		NSUInteger sectorsToSkip = MAXIMUM_OFFSET_TO_CHECK_IN_SECTORS - (containsSilence ? 0 : _sectorsOfSilenceToPrepend);
		
		if(!copySectorsFromURLToURL(inputURL, NSMakeRange(sectorsToSkip, _currentTrack.sectorCount), outputURL, 0)) {
			if(error)
				*error = [NSError errorWithDomain:NSPOSIXErrorDomain code:EIO userInfo:nil];
			return nil;
		}
		
		URL = outputURL;
	}
	
	return URL;
}

- (TrackExtractionRecord *) createTrackExtractionRecordForFileURL:(NSURL *)fileURL
{
	NSParameterAssert(nil != fileURL);
	
	NSUInteger accurateRipChecksum = calculateAccurateRipChecksumForFile(fileURL,											
																		 [self.compactDisc.firstSession.firstTrack.number isEqualToNumber:_currentTrack.number],
																		 [self.compactDisc.firstSession.lastTrack.number isEqualToNumber:_currentTrack.number]);
	
	return [self createTrackExtractionRecordForFileURL:fileURL
								   accurateRipChecksum:accurateRipChecksum 
							accurateRipConfidenceLevel:nil];
}

- (TrackExtractionRecord *) createTrackExtractionRecordForFileURL:(NSURL *)fileURL
											accurateRipChecksum:(NSUInteger)accurateRipChecksum
									 accurateRipConfidenceLevel:(NSNumber *)accurateRipConfidenceLevel
{
	return [self createTrackExtractionRecordForFileURL:fileURL
									 blockErrorFlags:nil
								 accurateRipChecksum:accurateRipChecksum
						  accurateRipConfidenceLevel:accurateRipConfidenceLevel
				accurateRipAlternatePressingChecksum:0
				  accurateRipAlternatePressingOffset:nil];
}

- (TrackExtractionRecord *) createTrackExtractionRecordForFileURL:(NSURL *)fileURL
											accurateRipChecksum:(NSUInteger)accurateRipChecksum
									 accurateRipConfidenceLevel:(NSNumber *)accurateRipConfidenceLevel
						   accurateRipAlternatePressingChecksum:(NSUInteger)accurateRipAlternatePressingChecksum
							 accurateRipAlternatePressingOffset:(NSNumber *)accurateRipAlternatePressingOffset
{
	return [self createTrackExtractionRecordForFileURL:fileURL
									 blockErrorFlags:nil
								 accurateRipChecksum:accurateRipChecksum
						  accurateRipConfidenceLevel:accurateRipConfidenceLevel
				accurateRipAlternatePressingChecksum:accurateRipAlternatePressingChecksum
				  accurateRipAlternatePressingOffset:accurateRipAlternatePressingOffset];
}

- (TrackExtractionRecord *) createTrackExtractionRecordForFileURL:(NSURL *)fileURL
												blockErrorFlags:(NSIndexSet *)blockErrorFlags
											accurateRipChecksum:(NSUInteger)accurateRipChecksum
									 accurateRipConfidenceLevel:(NSNumber *)accurateRipConfidenceLevel
						   accurateRipAlternatePressingChecksum:(NSUInteger)accurateRipAlternatePressingChecksum
							 accurateRipAlternatePressingOffset:(NSNumber *)accurateRipAlternatePressingOffset
{
	NSParameterAssert(nil != fileURL);

	// Calculate the MD5 and SHA1 digests
	NSArray *digests = calculateMD5AndSHA1DigestsForURL(fileURL);
	if(!digests)
		return nil;

	// Create the extraction record
	TrackExtractionRecord *extractionRecord = [NSEntityDescription insertNewObjectForEntityForName:@"TrackExtractionRecord" 
																			inManagedObjectContext:self.managedObjectContext];
	
	extractionRecord.date = [NSDate date];
	extractionRecord.drive = self.driveInformation;
	extractionRecord.inputURL = fileURL;
	extractionRecord.MD5 = [digests objectAtIndex:0];
	extractionRecord.SHA1 = [digests objectAtIndex:1];
	extractionRecord.track = _currentTrack;
	
	if(blockErrorFlags)
		extractionRecord.blockErrorFlags = blockErrorFlags;
	
	if(accurateRipChecksum)
		extractionRecord.accurateRipChecksum = [NSNumber numberWithUnsignedInteger:accurateRipChecksum];
	if(accurateRipConfidenceLevel)
		extractionRecord.accurateRipConfidenceLevel = accurateRipConfidenceLevel;
	
	if(accurateRipAlternatePressingChecksum)
		extractionRecord.accurateRipAlternatePressingChecksum = [NSNumber numberWithUnsignedInteger:accurateRipAlternatePressingChecksum];
	if(accurateRipAlternatePressingOffset)
		extractionRecord.accurateRipAlternatePressingOffset = accurateRipAlternatePressingOffset;
	
	return extractionRecord;
}

- (void) addTrackExtractionRecord:(TrackExtractionRecord *)extractionRecord
{
	NSParameterAssert(nil != extractionRecord);
	
	// Calculate the track's replay gain
	if(addReplayGainDataForTrack(&_rg, extractionRecord.inputURL)) {
		extractionRecord.track.metadata.replayGain = [NSNumber numberWithFloat:replaygain_analysis_get_title_gain(&_rg)];
		extractionRecord.track.metadata.peak = [NSNumber numberWithFloat:replaygain_analysis_get_title_peak(&_rg)];
	}
	else
		[[Logger sharedLogger] logMessageWithLevel:eLogMessageLevelDebug format:@"Unable to calculate replay gain"];
	
	[_trackExtractionRecords addObject:extractionRecord];
	[_tracksTable reloadData];
}

- (ImageExtractionRecord *) createImageExtractionRecord
{
	[_statusTextField setStringValue:NSLocalizedString(@"Creating image file", @"")];
	[_detailedStatusTextField setStringValue:@""];
	
	NSURL *imageFileURL = temporaryURLWithExtension(@"wav");
	
	// Set up the ASBD for CDDA audio
	AudioStreamBasicDescription cddaASBD = getStreamDescriptionForCDDA();
	
	// Create the output file
	AudioFileID file = NULL;
	OSStatus status = AudioFileCreateWithURL((CFURLRef)imageFileURL, kAudioFileWAVEType, &cddaASBD, kAudioFileFlags_EraseFile, &file);
	if(noErr != status)
		return nil;
	
	status = AudioFileClose(file);
	if(noErr != status)
		return nil;

	// Sort the extracted tracks
	NSSortDescriptor *trackNumberSortDescriptor = [[NSSortDescriptor alloc] initWithKey:@"track.number" ascending:YES];
	NSArray *sortedTrackExtractionRecords = [[_trackExtractionRecords allObjects] sortedArrayUsingDescriptors:[NSArray arrayWithObject:trackNumberSortDescriptor]];
		
	// Loop over all the extracted tracks and concatenate them together
	NSUInteger imageSectorNumber = 0;
	for(TrackExtractionRecord *trackExtractionRecord in sortedTrackExtractionRecords) {
		if(!copyAllSectorsFromURLToURL(trackExtractionRecord.inputURL, imageFileURL, imageSectorNumber))
			return nil;
		
		// Housekeeping
		imageSectorNumber += trackExtractionRecord.track.sectorCount;
	}
	
	// Calculate the audio checksums
	NSArray *digests = calculateMD5AndSHA1DigestsForURL(imageFileURL);
	if(!digests)
		return nil;
	
	// Create the extraction record
	ImageExtractionRecord *extractionRecord = [NSEntityDescription insertNewObjectForEntityForName:@"ImageExtractionRecord" 
																			inManagedObjectContext:self.managedObjectContext];
	
	extractionRecord.date = [NSDate date];
	extractionRecord.disc = self.compactDisc;
	extractionRecord.drive = self.driveInformation;
	extractionRecord.inputURL = imageFileURL;
	extractionRecord.MD5 = [digests objectAtIndex:0];
	extractionRecord.SHA1 = [digests objectAtIndex:1];
	
	[extractionRecord addTracks:_trackExtractionRecords];
	
	return extractionRecord;
}

@end
