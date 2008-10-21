/*
 *  Copyright (C) 2008 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import "AudioUtilities.h"

#include <AudioToolbox/ExtendedAudioFile.h>

#import "CDDAUtilities.h"

NSIndexSet *
compareFilesForNonMatchingSectors(NSURL *leftFileURL, NSURL *rightFileURL, NSError **error)
{
	NSCParameterAssert(nil != leftFileURL);
	NSCParameterAssert(nil != rightFileURL);
	
	NSMutableIndexSet *mismatchedSectors = nil;

	ExtAudioFileRef leftFile = NULL;
	ExtAudioFileRef rightFile = NULL;
	
	// Open the files for reading
	OSStatus status = ExtAudioFileOpenURL((CFURLRef)leftFileURL, &leftFile);
	if(noErr != status) {
		if(error)
			*error = [NSError errorWithDomain:NSOSStatusErrorDomain code:status userInfo:nil];
		return nil;
	}

	status = ExtAudioFileOpenURL((CFURLRef)rightFileURL, &rightFile);
	if(noErr != status) {
		if(error)
			*error = [NSError errorWithDomain:NSOSStatusErrorDomain code:status userInfo:nil];
		goto cleanup;
	}
	
	// Determine the files' type
	AudioStreamBasicDescription leftStreamDescription;
	UInt32 dataSize = (UInt32)sizeof(leftStreamDescription);
	status = ExtAudioFileGetProperty(leftFile, kExtAudioFileProperty_FileDataFormat, &dataSize, &leftStreamDescription);
	if(noErr != status) {
		if(error)
			*error = [NSError errorWithDomain:NSOSStatusErrorDomain code:status userInfo:nil];
		goto cleanup;
	}

	AudioStreamBasicDescription rightStreamDescription;
	dataSize = (UInt32)sizeof(rightStreamDescription);
	status = ExtAudioFileGetProperty(rightFile, kExtAudioFileProperty_FileDataFormat, &dataSize, &rightStreamDescription);
	if(noErr != status) {
		if(error)
			*error = [NSError errorWithDomain:NSOSStatusErrorDomain code:status userInfo:nil];
		goto cleanup;
	}

	// Make sure the files are the expected type (CDDA)
	if(!streamDescriptionIsCDDA(&leftStreamDescription) || !streamDescriptionIsCDDA(&rightStreamDescription)) {
		if(error)
			*error = [NSError errorWithDomain:NSPOSIXErrorDomain code:EINVAL userInfo:nil];
		goto cleanup;
	}
	
	// Set up the extraction buffers
	int8_t leftBuffer [kCDSectorSizeCDDA];
	int8_t rightBuffer [kCDSectorSizeCDDA];
	
	AudioBufferList leftAudioBuffer;
	leftAudioBuffer.mNumberBuffers = 1;
	leftAudioBuffer.mBuffers[0].mNumberChannels = leftStreamDescription.mChannelsPerFrame;
	leftAudioBuffer.mBuffers[0].mData = (void *)leftBuffer;
	leftAudioBuffer.mBuffers[0].mDataByteSize = kCDSectorSizeCDDA;

	AudioBufferList rightAudioBuffer;
	rightAudioBuffer.mNumberBuffers = 1;
	rightAudioBuffer.mBuffers[0].mNumberChannels = rightStreamDescription.mChannelsPerFrame;
	rightAudioBuffer.mBuffers[0].mData = (void *)rightBuffer;
	rightAudioBuffer.mBuffers[0].mDataByteSize = kCDSectorSizeCDDA;
	
	NSUInteger sectorCounter = 0;

	mismatchedSectors = [NSMutableIndexSet indexSet];
	
	// Iteratively read data from each file and compare it
	for(;;) {
		leftAudioBuffer.mBuffers[0].mDataByteSize = kCDSectorSizeCDDA;
		rightAudioBuffer.mBuffers[0].mDataByteSize = kCDSectorSizeCDDA;
		
		UInt32 leftFrameCount = AUDIO_FRAMES_PER_CDDA_SECTOR;
		UInt32 rightFrameCount = AUDIO_FRAMES_PER_CDDA_SECTOR;
		
		// Read a sector of input from each file
		status = ExtAudioFileRead(leftFile, &leftFrameCount, &leftAudioBuffer);
		if(noErr != status) {
			if(error)
				*error = [NSError errorWithDomain:NSOSStatusErrorDomain code:status userInfo:nil];
			goto cleanup;
		}

		status = ExtAudioFileRead(rightFile, &rightFrameCount, &rightAudioBuffer);
		if(noErr != status) {
			if(error)
				*error = [NSError errorWithDomain:NSOSStatusErrorDomain code:status userInfo:nil];
			goto cleanup;
		}
		
		// If no frames were returned, comparison is finished
		// If the same number of frames were not returned from each file, comparison is finished
		if(0 == leftFrameCount || 0 == rightFrameCount || leftFrameCount != rightFrameCount)
			break;
		
		// Compare the two sectors for differences
		if(!memcmp(leftAudioBuffer.mBuffers[0].mData, rightAudioBuffer.mBuffers[0].mData, kCDSectorSizeCDDA))
			[mismatchedSectors addIndex:sectorCounter];
		
		++sectorCounter;
	}
	
	// Cleanup
cleanup:
	if(leftFile) {
		status = ExtAudioFileDispose(leftFile);
		if(noErr != status) {
			if(error)
				*error = [NSError errorWithDomain:NSOSStatusErrorDomain code:status userInfo:nil];
		}
	}
	
	if(rightFile) {
		status = ExtAudioFileDispose(rightFile);
		if(noErr != status) {
			if(error)
				*error = [NSError errorWithDomain:NSOSStatusErrorDomain code:status userInfo:nil];
		}
	}

	return [mismatchedSectors copy];
}
