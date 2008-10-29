/*
 *  Copyright (C) 2008 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import "AudioUtilities.h"

#include <AudioToolbox/ExtendedAudioFile.h>
#include <CommonCrypto/CommonDigest.h>

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
	
	// Ensure both files contain the same number of frames
	SInt64 totalFramesInLeftFile;
	dataSize = sizeof(totalFramesInLeftFile);
	status = ExtAudioFileGetProperty(leftFile, kExtAudioFileProperty_FileLengthFrames, &dataSize, &totalFramesInLeftFile);
	if(noErr != status) {
		if(error)
			*error = [NSError errorWithDomain:NSOSStatusErrorDomain code:status userInfo:nil];
		goto cleanup;
	}

	SInt64 totalFramesInRightFile;
	dataSize = sizeof(totalFramesInRightFile);
	status = ExtAudioFileGetProperty(rightFile, kExtAudioFileProperty_FileLengthFrames, &dataSize, &totalFramesInRightFile);
	if(noErr != status) {
		if(error)
			*error = [NSError errorWithDomain:NSOSStatusErrorDomain code:status userInfo:nil];
		goto cleanup;
	}

	if(totalFramesInLeftFile != totalFramesInRightFile) {
		if(error)
			*error = [NSError errorWithDomain:NSOSStatusErrorDomain code:paramErr userInfo:nil];
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

NSIndexSet * 
compareFileRegionsForNonMatchingSectors(NSURL *leftFileURL, 
										NSUInteger leftFileStartingSectorOffset,
										NSURL *rightFileURL, 
										NSUInteger rightFileStartingSectorOffset, 
										NSUInteger sectorCount, 
										NSError **error)
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
	
	// Ensure both files contain an adequate number of frames
	SInt64 totalFramesInLeftFile;
	dataSize = sizeof(totalFramesInLeftFile);
	status = ExtAudioFileGetProperty(leftFile, kExtAudioFileProperty_FileLengthFrames, &dataSize, &totalFramesInLeftFile);
	if(noErr != status) {
		if(error)
			*error = [NSError errorWithDomain:NSOSStatusErrorDomain code:status userInfo:nil];
		goto cleanup;
	}
	
	SInt64 totalFramesInRightFile;
	dataSize = sizeof(totalFramesInRightFile);
	status = ExtAudioFileGetProperty(rightFile, kExtAudioFileProperty_FileLengthFrames, &dataSize, &totalFramesInRightFile);
	if(noErr != status) {
		if(error)
			*error = [NSError errorWithDomain:NSOSStatusErrorDomain code:status userInfo:nil];
		goto cleanup;
	}
	
	if(((SInt64)leftFileStartingSectorOffset + sectorCount) > totalFramesInLeftFile || ((SInt64)rightFileStartingSectorOffset + sectorCount) > totalFramesInRightFile) {
		if(error)
			*error = [NSError errorWithDomain:NSOSStatusErrorDomain code:paramErr userInfo:nil];
		goto cleanup;
	}
	
	// For some reason seeking fails if the client data format is not set
	AudioStreamBasicDescription cddaDescription = getStreamDescriptionForCDDA();
	status = ExtAudioFileSetProperty(leftFile, kExtAudioFileProperty_ClientDataFormat, sizeof(cddaDescription), &cddaDescription);
	if(noErr != status) {
		if(error)
			*error = [NSError errorWithDomain:NSOSStatusErrorDomain code:status userInfo:nil];
		goto cleanup;
	}

	status = ExtAudioFileSetProperty(rightFile, kExtAudioFileProperty_ClientDataFormat, sizeof(cddaDescription), &cddaDescription);
	if(noErr != status) {
		if(error)
			*error = [NSError errorWithDomain:NSOSStatusErrorDomain code:status userInfo:nil];
		goto cleanup;
	}
	
	// Seek to the desired starting sectors
	status = ExtAudioFileSeek(leftFile, AUDIO_FRAMES_PER_CDDA_SECTOR * (SInt64)leftFileStartingSectorOffset);
	if(noErr != status) {
		if(error)
			*error = [NSError errorWithDomain:NSOSStatusErrorDomain code:status userInfo:nil];
		goto cleanup;
	}

	status = ExtAudioFileSeek(rightFile, AUDIO_FRAMES_PER_CDDA_SECTOR * (SInt64)rightFileStartingSectorOffset);
	if(noErr != status) {
		if(error)
			*error = [NSError errorWithDomain:NSOSStatusErrorDomain code:status userInfo:nil];
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
	while(sectorCount--) {
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

NSString * calculateMD5DigestForURL(NSURL *fileURL, NSError **error)
{
	NSArray *array = calculateMD5AndSHA1DigestsForURL(fileURL, error);
	return ((1 <= [array count]) ? [array objectAtIndex:0] : nil);
}

NSString * calculateSHA1DigestForURL(NSURL *fileURL, NSError **error)
{
	NSArray *array = calculateMD5AndSHA1DigestsForURL(fileURL, error);
	return ((2 <= [array count]) ? [array objectAtIndex:1] : nil);
}

NSArray * calculateMD5AndSHA1DigestsForURL(NSURL *fileURL, NSError **error)
{
	NSCParameterAssert(nil != fileURL);
	
	NSMutableArray *result = nil;
	
	// Initialize the MD5 and SHA1 checksums
	CC_MD5_CTX md5;
	CC_MD5_Init(&md5);
	
	CC_SHA1_CTX sha1;
	CC_SHA1_Init(&sha1);
	
	// Open the file for reading
	ExtAudioFileRef file = NULL;
	OSStatus status = ExtAudioFileOpenURL((CFURLRef)fileURL, &file);
	if(noErr != status) {
		if(error)
			*error = [NSError errorWithDomain:NSOSStatusErrorDomain code:status userInfo:nil];
		return nil;
	}
	
	// Verify the file contains CDDA audio
	AudioStreamBasicDescription fileFormat;
	UInt32 dataSize = sizeof(fileFormat);
	status = ExtAudioFileGetProperty(file, kExtAudioFileProperty_FileDataFormat, &dataSize, &fileFormat);
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
		
	// Set up extraction buffers
	int8_t buffer [kCDSectorSizeCDDA];
	AudioBufferList bufferList;
	bufferList.mNumberBuffers = 1;
	bufferList.mBuffers[0].mNumberChannels = fileFormat.mChannelsPerFrame;
	bufferList.mBuffers[0].mData = (void *)buffer;	
	
	// Iteratively process each CDDA sector in the file
	for(;;) {
		bufferList.mBuffers[0].mDataByteSize = kCDSectorSizeCDDA;
		
		UInt32 frameCount = AUDIO_FRAMES_PER_CDDA_SECTOR;
		status = ExtAudioFileRead(file, &frameCount, &bufferList);
		
		if(noErr != status)
			break;
		else if(AUDIO_FRAMES_PER_CDDA_SECTOR != frameCount)
			break;
		
		// Update the MD5 and SHA1 digests
		CC_MD5_Update(&md5, bufferList.mBuffers[0].mData, bufferList.mBuffers[0].mDataByteSize);
		CC_SHA1_Update(&sha1, bufferList.mBuffers[0].mData, bufferList.mBuffers[0].mDataByteSize);
	}
	
	// Complete the MD5 and SHA1 calculations and store the result
	result = [NSMutableArray array];
	
	unsigned char md5Digest [CC_MD5_DIGEST_LENGTH];
	CC_MD5_Final(md5Digest, &md5);
	
	unsigned char sha1Digest [CC_SHA1_DIGEST_LENGTH];
	CC_SHA1_Final(sha1Digest, &sha1);
	
	NSMutableString *tempString = [NSMutableString string];
	
	NSUInteger i;
	for(i = 0; i < CC_MD5_DIGEST_LENGTH; ++i)
		[tempString appendFormat:@"%02x", md5Digest[i]];
	[result addObject:[tempString copy]];
	
	tempString = [NSMutableString string];
	for(i = 0; i < CC_SHA1_DIGEST_LENGTH; ++i)
		[tempString appendFormat:@"%02x", sha1Digest[i]];
	[result addObject:[tempString copy]];

cleanup:
	status = ExtAudioFileDispose(file);
	if(noErr != status) {
		if(error)
			*error = [NSError errorWithDomain:NSOSStatusErrorDomain code:status userInfo:nil];
	}
	
	return [result copy];
}

