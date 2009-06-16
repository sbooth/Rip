/*
 *  Copyright (C) 2008 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import "AudioUtilities.h"

#include <AudioToolbox/AudioFile.h>
#include <CommonCrypto/CommonDigest.h>

#import "CDDAUtilities.h"

NSIndexSet *
compareFilesForNonMatchingSectors(NSURL *leftFileURL, NSURL *rightFileURL)
{
	NSCParameterAssert(nil != leftFileURL);
	NSCParameterAssert(nil != rightFileURL);
	
	NSMutableIndexSet *mismatchedSectors = nil;

	AudioFileID leftFile = NULL;
	AudioFileID rightFile = NULL;
	
	// Open the files for reading
	OSStatus status = AudioFileOpenURL((CFURLRef)leftFileURL, fsRdPerm, kAudioFileWAVEType, &leftFile);
	if(noErr != status)
		return nil;

	status = AudioFileOpenURL((CFURLRef)rightFileURL, fsRdPerm, kAudioFileWAVEType, &rightFile);
	if(noErr != status)
		goto cleanup;
	
	// Determine the files' type
	AudioStreamBasicDescription leftStreamDescription;
	UInt32 dataSize = (UInt32)sizeof(leftStreamDescription);
	status = AudioFileGetProperty(leftFile, kAudioFilePropertyDataFormat, &dataSize, &leftStreamDescription);
	if(noErr != status)
		goto cleanup;

	AudioStreamBasicDescription rightStreamDescription;
	dataSize = (UInt32)sizeof(rightStreamDescription);
	status = AudioFileGetProperty(rightFile, kAudioFilePropertyDataFormat, &dataSize, &rightStreamDescription);
	if(noErr != status)
		goto cleanup;

	// Make sure the files are the expected type (CDDA)
	if(!streamDescriptionIsCDDA(&leftStreamDescription) || !streamDescriptionIsCDDA(&rightStreamDescription))
		goto cleanup;
	
	// Ensure both files contain the same number of frames
	UInt64 totalPacketsInLeftFile;
	dataSize = sizeof(totalPacketsInLeftFile);
	status = AudioFileGetProperty(leftFile, kAudioFilePropertyAudioDataPacketCount, &dataSize, &totalPacketsInLeftFile);
	if(noErr != status)
		goto cleanup;

	UInt64 totalPacketsInRightFile;
	dataSize = sizeof(totalPacketsInRightFile);
	status = AudioFileGetProperty(rightFile, kAudioFilePropertyAudioDataPacketCount, &dataSize, &totalPacketsInRightFile);
	if(noErr != status)
		goto cleanup;

	if(totalPacketsInLeftFile != totalPacketsInRightFile)
		goto cleanup;
	
	// Set up the extraction buffers
	int8_t leftBuffer [kCDSectorSizeCDDA];
	int8_t rightBuffer [kCDSectorSizeCDDA];
	
	NSUInteger sectorCounter = 0;

	mismatchedSectors = [NSMutableIndexSet indexSet];
	
	// Iteratively read data from each file and compare it
	for(;;) {
		UInt32 leftByteCount = kCDSectorSizeCDDA;
		UInt32 rightByteCount = kCDSectorSizeCDDA;
		
		UInt32 leftPacketCount = AUDIO_FRAMES_PER_CDDA_SECTOR;
		UInt32 rightPacketCount = AUDIO_FRAMES_PER_CDDA_SECTOR;
		
		SInt64 startingPacket = sectorCounter * AUDIO_FRAMES_PER_CDDA_SECTOR;
		
		// Read a sector of input from each file
		status = AudioFileReadPackets(leftFile, false, &leftByteCount, NULL, startingPacket, &leftPacketCount, leftBuffer);
		if(noErr != status)
			goto cleanup;

		status = AudioFileReadPackets(rightFile, false, &rightByteCount, NULL, startingPacket, &rightPacketCount, rightBuffer);
		if(noErr != status)
			goto cleanup;
		
		// If no frames were returned, comparison is finished
		// If the same number of frames were not returned from each file, comparison is finished
		if(0 == leftPacketCount || 0 == rightPacketCount || leftPacketCount != rightPacketCount)
			break;
		
		// Compare the two sectors for differences
		if(!memcmp(leftBuffer, rightBuffer, kCDSectorSizeCDDA))
			[mismatchedSectors addIndex:sectorCounter];
		
		++sectorCounter;
	}
	
	// Cleanup
cleanup:
	if(leftFile) {
		status = AudioFileClose(leftFile);
		if(noErr != status)
			;
	}
	
	if(rightFile) {
		status = AudioFileClose(rightFile);
		if(noErr != status)
			;
	}

	return [mismatchedSectors copy];
}

NSIndexSet * 
compareFileRegionsForNonMatchingSectors(NSURL *leftFileURL, 
										NSUInteger leftFileStartingSectorOffset,
										NSURL *rightFileURL, 
										NSUInteger rightFileStartingSectorOffset, 
										NSUInteger sectorCount)
{
	NSCParameterAssert(nil != leftFileURL);
	NSCParameterAssert(nil != rightFileURL);
	
	NSMutableIndexSet *mismatchedSectors = nil;
	
	AudioFileID leftFile = NULL;
	AudioFileID rightFile = NULL;
	
	// Open the files for reading
	OSStatus status = AudioFileOpenURL((CFURLRef)leftFileURL, fsRdPerm, kAudioFileWAVEType, &leftFile);
	if(noErr != status)
		return nil;
	
	status = AudioFileOpenURL((CFURLRef)rightFileURL, fsRdPerm, kAudioFileWAVEType, &rightFile);
	if(noErr != status)
		goto cleanup;
	
	// Determine the files' type
	AudioStreamBasicDescription leftStreamDescription;
	UInt32 dataSize = (UInt32)sizeof(leftStreamDescription);
	status = AudioFileGetProperty(leftFile, kAudioFilePropertyDataFormat, &dataSize, &leftStreamDescription);
	if(noErr != status)
		goto cleanup;
	
	AudioStreamBasicDescription rightStreamDescription;
	dataSize = (UInt32)sizeof(rightStreamDescription);
	status = AudioFileGetProperty(rightFile, kAudioFilePropertyDataFormat, &dataSize, &rightStreamDescription);
	if(noErr != status)
		goto cleanup;
	
	// Make sure the files are the expected type (CDDA)
	if(!streamDescriptionIsCDDA(&leftStreamDescription) || !streamDescriptionIsCDDA(&rightStreamDescription))
		goto cleanup;
	
	// Ensure both files contain an adequate number of frames
	UInt64 totalPacketsInLeftFile;
	dataSize = sizeof(totalPacketsInLeftFile);
	status = AudioFileGetProperty(leftFile, kAudioFilePropertyAudioDataPacketCount, &dataSize, &totalPacketsInLeftFile);
	if(noErr != status)
		goto cleanup;
	
	UInt64 totalPacketsInRightFile;
	dataSize = sizeof(totalPacketsInRightFile);
	status = AudioFileGetProperty(rightFile, kAudioFilePropertyAudioDataPacketCount, &dataSize, &totalPacketsInRightFile);
	if(noErr != status)
		goto cleanup;
	
	UInt64 packetsRequiredInLeftFile = ((UInt64)leftFileStartingSectorOffset + sectorCount) * AUDIO_FRAMES_PER_CDDA_SECTOR;
	UInt64 packetsRequiredInRightFile = ((UInt64)rightFileStartingSectorOffset + sectorCount) * AUDIO_FRAMES_PER_CDDA_SECTOR;
	
	if(packetsRequiredInLeftFile > totalPacketsInLeftFile || packetsRequiredInRightFile > totalPacketsInRightFile)
		goto cleanup;
		
	// Set up the extraction buffers
	int8_t leftBuffer [kCDSectorSizeCDDA];
	int8_t rightBuffer [kCDSectorSizeCDDA];
		
	NSUInteger sectorCounter = leftFileStartingSectorOffset;
	
	SInt64 leftStartingPacket = leftFileStartingSectorOffset * AUDIO_FRAMES_PER_CDDA_SECTOR;
	SInt64 rightStartingPacket = rightFileStartingSectorOffset * AUDIO_FRAMES_PER_CDDA_SECTOR;

	mismatchedSectors = [NSMutableIndexSet indexSet];
	
	// Iteratively read data from each file and compare it
	while(sectorCount--) {
		UInt32 leftByteCount = kCDSectorSizeCDDA;
		UInt32 rightByteCount = kCDSectorSizeCDDA;
		
		UInt32 leftPacketCount = AUDIO_FRAMES_PER_CDDA_SECTOR;
		UInt32 rightPacketCount = AUDIO_FRAMES_PER_CDDA_SECTOR;
		
		// Read a sector of input from each file
		status = AudioFileReadPackets(leftFile, false, &leftByteCount, NULL, leftStartingPacket, &leftPacketCount, leftBuffer);
		if(noErr != status)
			goto cleanup;
		
		status = AudioFileReadPackets(rightFile, false, &rightByteCount, NULL, rightStartingPacket, &rightPacketCount, rightBuffer);
		if(noErr != status)
			goto cleanup;
		
		// If no frames were returned, comparison is finished
		// If the same number of frames were not returned from each file, comparison is finished
		if(0 == leftPacketCount || 0 == rightPacketCount || leftPacketCount != rightPacketCount)
			break;
		
		// Compare the two sectors for differences
		if(!memcmp(leftBuffer, rightBuffer, kCDSectorSizeCDDA))
			[mismatchedSectors addIndex:sectorCounter];
		
		++sectorCounter;
		
		leftStartingPacket += leftPacketCount;
		rightStartingPacket += rightPacketCount;
	}
	
	// Cleanup
cleanup:
	if(leftFile) {
		status = AudioFileClose(leftFile);
		if(noErr != status)
			;
	}
	
	if(rightFile) {
		status = AudioFileClose(rightFile);
		if(noErr != status)
			;
	}
	
	return [mismatchedSectors copy];
}

BOOL 
sectorInFilesMatches(NSURL *leftFileURL, 
					 NSUInteger leftFileSectorOffset,
					 NSURL *rightFileURL, 
					 NSUInteger rightFileSectorOffset)
{
	NSIndexSet *mismatchedSectors = compareFileRegionsForNonMatchingSectors(leftFileURL, leftFileSectorOffset, 
																			rightFileURL, rightFileSectorOffset,
																			1);
	
	return (0 == [mismatchedSectors count]);
}

NSString * calculateMD5DigestForURL(NSURL *fileURL)
{
	NSArray *array = calculateMD5AndSHA1DigestsForURL(fileURL);
	return ((1 <= [array count]) ? [array objectAtIndex:0] : nil);
}

NSString * calculateMD5DigestForURLRegion(NSURL *fileURL, NSUInteger startingSector, NSUInteger sectorCount)
{
	NSArray *array = calculateMD5AndSHA1DigestsForURLRegion(fileURL, startingSector, sectorCount);
	return ((1 <= [array count]) ? [array objectAtIndex:0] : nil);
}

NSString * calculateSHA1DigestForURL(NSURL *fileURL)
{
	NSArray *array = calculateMD5AndSHA1DigestsForURL(fileURL);
	return ((2 <= [array count]) ? [array objectAtIndex:1] : nil);
}

NSString * calculateSHA1DigestForURLRegion(NSURL *fileURL, NSUInteger startingSector, NSUInteger sectorCount)
{
	NSArray *array = calculateMD5AndSHA1DigestsForURLRegion(fileURL, startingSector, sectorCount);
	return ((2 <= [array count]) ? [array objectAtIndex:1] : nil);
}

NSArray * calculateMD5AndSHA1DigestsForURL(NSURL *fileURL)
{
	return calculateMD5AndSHA1DigestsForURLRegion(fileURL, 0, NSUIntegerMax);
}

NSArray * calculateMD5AndSHA1DigestsForURLRegion(NSURL *fileURL, NSUInteger startingSector, NSUInteger sectorCount)
{
	NSCParameterAssert(nil != fileURL);
	
	NSMutableArray *result = nil;
	
	// Initialize the MD5 and SHA1 checksums
	CC_MD5_CTX md5;
	CC_MD5_Init(&md5);
	
	CC_SHA1_CTX sha1;
	CC_SHA1_Init(&sha1);
	
	// Open the file for reading
	AudioFileID file = NULL;
	OSStatus status = AudioFileOpenURL((CFURLRef)fileURL, fsRdPerm, kAudioFileWAVEType, &file);
	if(noErr != status)
		return nil;
	
	// Verify the file contains CDDA audio
	AudioStreamBasicDescription fileFormat;
	UInt32 dataSize = sizeof(fileFormat);
	status = AudioFileGetProperty(file, kAudioFilePropertyDataFormat, &dataSize, &fileFormat);
	if(noErr != status)
		goto cleanup;
	
	if(!streamDescriptionIsCDDA(&fileFormat))
		goto cleanup;
		
	// Set up extraction buffer
	int8_t buffer [kCDSectorSizeCDDA];
	
	SInt64 startingPacket = AUDIO_FRAMES_PER_CDDA_SECTOR * startingSector;
	NSUInteger sectorCounter = 0;
	
	// Iteratively process the specified CDDA sectors
	while(sectorCounter < sectorCount) {
		
		UInt32 byteCount = kCDSectorSizeCDDA;
		UInt32 packetCount = AUDIO_FRAMES_PER_CDDA_SECTOR;
		
		status = AudioFileReadPackets(file, false, &byteCount, NULL, startingPacket, &packetCount, buffer);
		if(noErr != status)
			goto cleanup;
		
		if(AUDIO_FRAMES_PER_CDDA_SECTOR != packetCount)
			break;
		
		// Update the MD5 and SHA1 digests
		CC_MD5_Update(&md5, buffer, byteCount);
		CC_SHA1_Update(&sha1, buffer, byteCount);
		
		// Housekeeping
		startingPacket += packetCount;
		++sectorCounter;
	}
	
	// Complete the MD5 and SHA1 calculations and store the result
	result = [NSMutableArray array];
	
	unsigned char md5Digest [CC_MD5_DIGEST_LENGTH];
	CC_MD5_Final(md5Digest, &md5);
	
	unsigned char sha1Digest [CC_SHA1_DIGEST_LENGTH];
	CC_SHA1_Final(sha1Digest, &sha1);
	
	NSMutableString *tempString = [NSMutableString string];
	
	for(NSUInteger i = 0; i < CC_MD5_DIGEST_LENGTH; ++i)
		[tempString appendFormat:@"%02x", md5Digest[i]];
	[result addObject:[tempString copy]];
	
	tempString = [NSMutableString string];
	for(NSUInteger i = 0; i < CC_SHA1_DIGEST_LENGTH; ++i)
		[tempString appendFormat:@"%02x", sha1Digest[i]];
	[result addObject:[tempString copy]];

cleanup:
	status = AudioFileClose(file);
	if(noErr != status)
		;
	
	return [result copy];
}
