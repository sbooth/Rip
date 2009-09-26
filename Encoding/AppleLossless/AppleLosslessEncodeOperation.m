/*
 *  Copyright (C) 2008 - 2009 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import "AppleLosslessEncodeOperation.h"
#import "NSImage+BitmapRepresentationMethods.h"

#include <mp4v2/mp4v2.h>

@implementation AppleLosslessEncodeOperation

// ========================================
// The amount of time to sleep while waiting for the NSTask to finish
// ========================================
#define SLEEP_TIME_INTERVAL ((NSTimeInterval)0.25)

- (void) main
{	
	// The superclass takes care of the encoding
	[super main];
		
	// Stop now if the operation was cancelled or any errors occurred
	if(self.isCancelled || self.error)
		return;

	// ========================================
	// TAGGING
	
	// Open the file for modification
	MP4FileHandle file = MP4Modify([[self.outputURL path] fileSystemRepresentation], MP4_DETAILS_ERROR, 0);
	if(MP4_INVALID_FILE_HANDLE == file) {
		self.error = [NSError errorWithDomain:NSPOSIXErrorDomain code:EIO userInfo:nil];
		return;
	}

	// Read the tags
	const MP4Tags *tags = MP4TagsAlloc();
	if(NULL == tags) {
		MP4Close(file);
		
		self.error = [NSError errorWithDomain:NSPOSIXErrorDomain code:ENOMEM userInfo:nil];
		return;
	}
	
	MP4TagsFetch(tags, file);
	
	// Metadata
	if([self.metadata objectForKey:kMetadataTitleKey])
		MP4TagsSetName(tags, [[self.metadata objectForKey:kMetadataTitleKey] UTF8String]);
	if([self.metadata objectForKey:kMetadataAlbumTitleKey])
		MP4TagsSetAlbum(tags, [[self.metadata objectForKey:kMetadataAlbumTitleKey] UTF8String]);
	if([self.metadata objectForKey:kMetadataArtistKey])
		MP4TagsSetArtist(tags, [[self.metadata objectForKey:kMetadataArtistKey] UTF8String]);
	if([self.metadata objectForKey:kMetadataAlbumArtistKey])
		MP4TagsSetAlbumArtist(tags, [[self.metadata objectForKey:kMetadataAlbumArtistKey] UTF8String]);
	if([self.metadata objectForKey:kMetadataGenreKey])
		MP4TagsSetGenre(tags, [[self.metadata objectForKey:kMetadataGenreKey] UTF8String]);
	if([self.metadata objectForKey:kMetadataComposerKey])
		MP4TagsSetComposer(tags, [[self.metadata objectForKey:kMetadataComposerKey] UTF8String]);
	if([self.metadata objectForKey:kMetadataReleaseDateKey])
		MP4TagsSetReleaseDate(tags, [[self.metadata objectForKey:kMetadataReleaseDateKey] UTF8String]);
	if([self.metadata objectForKey:kMetadataCompilationKey]) {
		uint8_t isCompilation = [[self.metadata objectForKey:kMetadataCompilationKey] boolValue];
		MP4TagsSetCompilation(tags, &isCompilation);
	}
	if([self.metadata objectForKey:kMetadataTrackNumberKey]) {
		MP4TagTrack trackInfo;
		
		trackInfo.index = [[self.metadata objectForKey:kMetadataTrackNumberKey] unsignedShortValue];
		if([self.metadata objectForKey:kMetadataTrackTotalKey])
			trackInfo.total = [[self.metadata objectForKey:kMetadataTrackTotalKey] unsignedShortValue];
		else
			trackInfo.total = 0;
		
		MP4TagsSetTrack(tags, &trackInfo);
	}
	if([self.metadata objectForKey:kMetadataDiscNumberKey]) {
		MP4TagDisk discInfo;
		
		discInfo.index = [[self.metadata objectForKey:kMetadataDiscNumberKey] unsignedShortValue];
		if([self.metadata objectForKey:kMetadataTrackTotalKey])
			discInfo.total = [[self.metadata objectForKey:kMetadataDiscTotalKey] unsignedShortValue];
		else
			discInfo.total = 0;
		
		MP4TagsSetDisk(tags, &discInfo);
	}			
	if([self.metadata objectForKey:kMetadataCommentKey])
		MP4TagsSetComments(tags, [[self.metadata objectForKey:kMetadataCommentKey] UTF8String]);
	
	if([self.metadata objectForKey:kAlbumArtFrontCoverKey]) {
		NSImage *frontCoverImage = [self.metadata objectForKey:kAlbumArtFrontCoverKey];
		NSData *frontCoverPNGData = [frontCoverImage PNGData];
		
		MP4TagArtwork artwork;
		
		artwork.data = (void *)[frontCoverPNGData bytes];
		artwork.size = (uint32_t)[frontCoverPNGData length];
		artwork.type = MP4_ART_PNG;

		MP4TagsAddArtwork(tags, &artwork);
	}
	
	// Application version
	NSString *appName = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleName"];
	NSString *shortVersionNumber = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
	NSString *versionNumber = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleVersion"];	

	MP4TagsSetEncodingTool(tags, [[NSString stringWithFormat:@"%@ %@ (%@)", appName, shortVersionNumber, versionNumber] UTF8String]);
	
	// Save our changes
	MP4TagsStore(tags, file);
	MP4Close(file);	
}

@end
