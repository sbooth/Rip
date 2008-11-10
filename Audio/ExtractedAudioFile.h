/*
 *  Copyright (C) 2008 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import <Cocoa/Cocoa.h>
#import <AudioToolbox/AudioFile.h>

// ========================================
// A class representing a WAVE file containing CD-DA audio
// that presents read/write access to that audio as CD-DA sectors
// An object of this class should not be created directly using alloc/init,
// but using the provided class methods
// ========================================
@interface ExtractedAudioFile : NSObject
{
@private
	NSURL *_URL;
	AudioFileID _file;
	NSString *_cachedMD5;
	NSString *_cachedSHA1;
}

// ========================================
// Creation
// ========================================
+ (id) createFileAtURL:(NSURL *)URL error:(NSError **)error;
+ (id) openFileForReadingAtURL:(NSURL *)URL error:(NSError **)error;
+ (id) openFileForReadingAndWritingAtURL:(NSURL *)URL error:(NSError **)error;

// ========================================
// Properties
// ========================================
@property (readonly, copy) NSURL * URL;
@property (readonly) NSString * MD5;
@property (readonly) NSString * SHA1;

@property (readonly) NSUInteger sectorsInFile;

- (BOOL) closeFile;

// ========================================
// Reading
// ========================================
- (NSData *) audioDataForSector:(NSUInteger)sector error:(NSError **)error;
- (NSData *) audioDataForSectors:(NSRange)sectors error:(NSError **)error;

// ========================================
// Writing
// ========================================
- (BOOL) setAudioData:(NSData *)data forSector:(NSUInteger)sector error:(NSError **)error;
- (BOOL) setAudioData:(NSData *)data forSectors:(NSRange)sectors error:(NSError **)error;

@end
