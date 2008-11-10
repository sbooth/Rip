/*
 *  Copyright (C) 2008 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import "ExtractedAudioFile.h"

#include <CommonCrypto/CommonDigest.h>
#include <IOKit/storage/IOCDTypes.h>

#import "CDDAUtilities.h"

@interface ExtractedAudioFile ()
@property (copy) NSURL * URL;
@property (copy) NSString * cachedMD5;
@property (copy) NSString * cachedSHA1;
@end

@interface ExtractedAudioFile (Private)
- (BOOL) createFile:(NSError **)error;
- (BOOL) openFileForReading:(NSError **)error;
- (BOOL) openFileForReadingAndWriting:(NSError **)error;
- (void) calculateMD5AndSHA1Digests;
@end

@implementation ExtractedAudioFile

// ========================================
// Creation
// ========================================
+ (id) createFileAtURL:(NSURL *)URL error:(NSError **)error
{
	NSParameterAssert(nil != URL);
	NSParameterAssert([URL isFileURL]);
	
	ExtractedAudioFile *file = [[ExtractedAudioFile alloc] init];
	
	file.URL = URL;
	
	return ([file createFile:error] ? file : nil);	
}

+ (id) openFileForReadingAtURL:(NSURL *)URL error:(NSError **)error
{
	NSParameterAssert(nil != URL);
	NSParameterAssert([URL isFileURL]);
	
	ExtractedAudioFile *file = [[ExtractedAudioFile alloc] init];
	
	file.URL = URL;
	
	return ([file openFileForReading:error] ? file : nil);	
}

+ (id) openFileForReadingAndWritingAtURL:(NSURL *)URL error:(NSError **)error
{
	NSParameterAssert(nil != URL);
	NSParameterAssert([URL isFileURL]);
	
	ExtractedAudioFile *file = [[ExtractedAudioFile alloc] init];
	
	file.URL = URL;
	
	return ([file openFileForReadingAndWriting:error] ? file : nil);	
}

// ========================================
// Properties
// ========================================
@synthesize URL = _URL;
@synthesize cachedMD5 = _cachedMD5;
@synthesize cachedSHA1 = _cachedSHA1;

- (void) finalize
{
	[self closeFile];
	
	[super finalize];
}

- (BOOL) closeFile
{
	if(_file) {
		OSStatus status = AudioFileClose(_file);
		_file = NULL;
		if(noErr != status) {
#if DEBUG
			NSLog(@"AudioFileClose failed");
#endif
			return NO;
		}
	}
	return YES;
}

// ========================================
// Digests
// ========================================
- (NSString *) MD5
{
	if(!self.cachedMD5)
		[self calculateMD5AndSHA1Digests];
	return self.cachedMD5;
}

- (NSString *) SHA1
{
	if(!self.cachedSHA1)
		[self calculateMD5AndSHA1Digests];
	return self.cachedSHA1;
}

- (NSUInteger) sectorsInFile
{
	UInt64 totalPackets = 0;
	UInt32 dataSize = sizeof(totalPackets);
	OSStatus status = AudioFileGetProperty(_file, kAudioFilePropertyAudioDataPacketCount, &dataSize, &totalPackets);
	if(noErr != status)
		return 0;
	
	return (NSUInteger)(totalPackets / AUDIO_FRAMES_PER_CDDA_SECTOR);
}

// ========================================
// Reading
// ========================================
- (NSData *) audioDataForSector:(NSUInteger)sector error:(NSError **)error
{
	return [self audioDataForSectors:NSMakeRange(sector, 1) error:error];
}

- (NSData *) audioDataForSectors:(NSRange)sectors error:(NSError **)error
{
	int8_t *buffer = calloc(sectors.length, kCDSectorSizeCDDA);
	UInt32 byteCount = kCDSectorSizeCDDA * sectors.length;		
	UInt32 packetCount = AUDIO_FRAMES_PER_CDDA_SECTOR * sectors.length;
	SInt64 startingPacket = AUDIO_FRAMES_PER_CDDA_SECTOR * sectors.location;
	
	// Read the requested sectors
	OSStatus status = AudioFileReadPackets(_file, false, &byteCount, NULL, startingPacket, &packetCount, buffer);
	if(noErr != status) {
		free(buffer);
		if(error)
			*error = [NSError errorWithDomain:NSOSStatusErrorDomain code:status userInfo:nil];
		return nil;
	}
	
	if((kCDSectorSizeCDDA * sectors.length) != byteCount) {
		free(buffer);
		return nil;
	}
	
	// The returned NSData takes ownership of buffer
	return [NSData dataWithBytesNoCopy:buffer length:byteCount freeWhenDone:YES];
}

// ========================================
// Writing
// ========================================
- (BOOL) setAudioData:(NSData *)data forSector:(NSUInteger)sector error:(NSError **)error
{
	return [self setAudioData:data forSectors:NSMakeRange(sector, 1) error:error];
}

- (BOOL) setAudioData:(NSData *)data forSectors:(NSRange)sectors error:(NSError **)error
{
	NSParameterAssert(nil != data);
	NSParameterAssert([data length] >= (kCDSectorSizeCDDA * sectors.length));

	const int8_t *buffer = [data bytes];
	UInt32 byteCount = kCDSectorSizeCDDA * sectors.length;		
	UInt32 packetCount = AUDIO_FRAMES_PER_CDDA_SECTOR * sectors.length;
	SInt64 startingPacket = AUDIO_FRAMES_PER_CDDA_SECTOR * sectors.location;
	
	// Write the requested sectors
	OSStatus status = AudioFileWritePackets(_file, false, byteCount, NULL, startingPacket, &packetCount, buffer);
	if(noErr != status) {
		if(error)
			*error = [NSError errorWithDomain:NSOSStatusErrorDomain code:status userInfo:nil];
		return NO;
	}
	
	if((kCDSectorSizeCDDA * sectors.length) != byteCount)
		return NO;
	
	// Invalidate our cached digests
	self.cachedMD5 = nil;
	self.cachedSHA1 = nil;
	
	return YES;	
}

@end

@implementation ExtractedAudioFile (Private)

- (BOOL) createFile:(NSError **)error
{
	// Set up the ASBD for CDDA audio
	AudioStreamBasicDescription cddaASBD = getStreamDescriptionForCDDA();
	
	// Create and open the output file, overwriting if it exists
	OSStatus status = AudioFileCreateWithURL((CFURLRef)self.URL, kAudioFileWAVEType, &cddaASBD, kAudioFileFlags_EraseFile, &_file);
	if(noErr != status) {
		if(error)
			*error = [NSError errorWithDomain:NSOSStatusErrorDomain code:status userInfo:nil];
		return NO;
	}
	
	return YES;
}

- (BOOL) openFileForReading:(NSError **)error
{
	// Open the input file for reading
	OSStatus status = AudioFileOpenURL((CFURLRef)self.URL, fsRdPerm, kAudioFileWAVEType, &_file);
	if(noErr != status) {
		if(error)
			*error = [NSError errorWithDomain:NSOSStatusErrorDomain code:status userInfo:nil];
		return NO;
	}

	// Determine the file's type
	AudioStreamBasicDescription streamDescription;
	UInt32 dataSize = (UInt32)sizeof(streamDescription);
	status = AudioFileGetProperty(_file, kAudioFilePropertyDataFormat, &dataSize, &streamDescription);
	if(noErr != status) {
		/*status = */AudioFileClose(_file);
		if(error)
			*error = [NSError errorWithDomain:NSOSStatusErrorDomain code:status userInfo:nil];
		return NO;
	}
	
	// Make sure the file is the expected type (CDDA)
	if(!streamDescriptionIsCDDA(&streamDescription)) {
		/*status = */AudioFileClose(_file);
		if(error)
			*error = [NSError errorWithDomain:NSOSStatusErrorDomain code:status userInfo:nil];
		return NO;
	}
		
	return YES;
}

- (BOOL) openFileForReadingAndWriting:(NSError **)error
{
	// Open the input file for reading and writing
	OSStatus status = AudioFileOpenURL((CFURLRef)self.URL, fsRdWrPerm, kAudioFileWAVEType, &_file);
	if(noErr != status) {
		if(error)
			*error = [NSError errorWithDomain:NSOSStatusErrorDomain code:status userInfo:nil];
		return NO;
	}
	
	// Determine the file's type
	AudioStreamBasicDescription streamDescription;
	UInt32 dataSize = (UInt32)sizeof(streamDescription);
	status = AudioFileGetProperty(_file, kAudioFilePropertyDataFormat, &dataSize, &streamDescription);
	if(noErr != status) {
		/*status = */AudioFileClose(_file);
		if(error)
			*error = [NSError errorWithDomain:NSOSStatusErrorDomain code:status userInfo:nil];
		return NO;
	}
	
	// Make sure the file is the expected type (CDDA)
	if(!streamDescriptionIsCDDA(&streamDescription)) {
		/*status = */AudioFileClose(_file);
		if(error)
			*error = [NSError errorWithDomain:NSOSStatusErrorDomain code:status userInfo:nil];
		return NO;
	}
	
	return YES;
}

- (void) calculateMD5AndSHA1Digests
{
	// Initialize the MD5 and SHA1 checksums
	CC_MD5_CTX md5;
	CC_MD5_Init(&md5);
	
	CC_SHA1_CTX sha1;
	CC_SHA1_Init(&sha1);
	
	// Set up extraction buffer
	int8_t buffer [kCDSectorSizeCDDA];
	SInt64 startingPacket = 0;
	
	// Iteratively process each CDDA sector in the file
	for(;;) {
		
		UInt32 byteCount = kCDSectorSizeCDDA;
		UInt32 packetCount = AUDIO_FRAMES_PER_CDDA_SECTOR;
		
		OSStatus status = AudioFileReadPackets(_file, false, &byteCount, NULL, startingPacket, &packetCount, buffer);
		if(noErr != status)
			return;
		
		if(AUDIO_FRAMES_PER_CDDA_SECTOR != packetCount)
			break;
		
		// Update the MD5 and SHA1 digests
		CC_MD5_Update(&md5, buffer, byteCount);
		CC_SHA1_Update(&sha1, buffer, byteCount);
		
		// Housekeeping
		startingPacket += packetCount;
	}
	
	// Complete the MD5 and SHA1 calculations and store the result
	unsigned char md5Digest [CC_MD5_DIGEST_LENGTH];
	CC_MD5_Final(md5Digest, &md5);
	
	unsigned char sha1Digest [CC_SHA1_DIGEST_LENGTH];
	CC_SHA1_Final(sha1Digest, &sha1);
	
	NSMutableString *tempString = [NSMutableString string];
	
	NSUInteger i;
	for(i = 0; i < CC_MD5_DIGEST_LENGTH; ++i)
		[tempString appendFormat:@"%02x", md5Digest[i]];
	self.cachedMD5 = tempString;
	
	tempString = [NSMutableString string];
	for(i = 0; i < CC_SHA1_DIGEST_LENGTH; ++i)
		[tempString appendFormat:@"%02x", sha1Digest[i]];
	self.cachedSHA1 = tempString;	
}

@end
