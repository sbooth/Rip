/*
 *  Copyright (C) 2009 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import "ReplayGainUtilities.h"
#import "CDDAUtilities.h"
#import <AudioToolbox/AudioFile.h>

// ========================================
// Local definitions
// ========================================
#define BUFFER_LENGTH			4096

BOOL addReplayGainDataForTrack(struct replaygain_t *rg, NSURL *fileURL)
{
	NSCParameterAssert(NULL != rg);
	NSCParameterAssert(nil != fileURL);
	NSCParameterAssert([fileURL isFileURL]);
	
	// Buffer setup
	int16_t buffer [BUFFER_LENGTH];
	float leftRGBuffer [BUFFER_LENGTH / CDDA_CHANNELS_PER_FRAME];
	float rightRGBuffer [BUFFER_LENGTH / CDDA_CHANNELS_PER_FRAME];
	
#if DEBUG
	clock_t track_start = clock();
#endif
		
	// Open the file for reading
	AudioFileID fileID = NULL;
	OSStatus status = AudioFileOpenURL((CFURLRef)fileURL, fsRdPerm, kAudioFileWAVEType, &fileID);
	if(noErr != status)
		return NO;
	
	// Determine the file's type
	AudioStreamBasicDescription streamDescription;
	UInt32 dataSize = (UInt32)sizeof(streamDescription);
	status = AudioFileGetProperty(fileID, kAudioFilePropertyDataFormat, &dataSize, &streamDescription);
	if(noErr != status) {
		/*status = */AudioFileClose(fileID);
		return NO;
	}
	
	// Make sure the file is the expected type (CDDA)
	if(!streamDescriptionIsCDDA(&streamDescription)) {
		/*status = */AudioFileClose(fileID);
		return NO;
	}

	SInt64 startingPacket = 0;
	UInt32 packetCount = 0;
	UInt32 byteCount = 0;
	
	// Process the file
	for(;;) {
		
		// Read some audio
		packetCount = BUFFER_LENGTH / CDDA_CHANNELS_PER_FRAME;
		status = AudioFileReadPackets(fileID, FALSE, &byteCount, NULL, startingPacket, &packetCount, buffer);
		if(noErr != status) {
			/*status = */AudioFileClose(fileID);
			return NO;
		}
		
		// EOF condition is noErr with 0 packets returned
		if(0 == packetCount)
			break;
		
		// Deinterleave the samples
		UInt32 packetIndex;
		for(packetIndex = 0; packetIndex < packetCount; ++packetIndex) {
			int16_t leftSample = buffer[CDDA_CHANNELS_PER_FRAME * packetIndex];
			int16_t rightSample = buffer[CDDA_CHANNELS_PER_FRAME * packetIndex + 1];
			
			leftRGBuffer[packetIndex] = leftSample;
			rightRGBuffer[packetIndex] = rightSample;			
		}
		
		// Submit the data to the RG analysis engine
		int result = replaygain_analysis_analyze_samples(rg, leftRGBuffer, rightRGBuffer, packetCount, CDDA_CHANNELS_PER_FRAME);
		if(GAIN_ANALYSIS_OK != result) {
			AudioFileClose(fileID);
			return NO;
		}
		
		// Housekeeping
		startingPacket += packetCount;
	}
	
#if DEBUG
	clock_t track_end = clock();
	NSLog(@"Calculated replay gain for %@ in %f seconds\n", [[fileURL path] lastPathComponent], (track_end - track_start) / (double)CLOCKS_PER_SEC);
#endif
	
	AudioFileClose(fileID);

	return YES;
}
