/*
 *  Copyright (C) 2009 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import <Cocoa/Cocoa.h>

// ========================================
// KVC key names for the metadata dictionaries
// ========================================
extern NSString * const		kMetadataTitleKey;
extern NSString * const		kMetadataArtistKey;
extern NSString * const		kMetadataGenreKey;
extern NSString * const		kMetadataComposerKey;
extern NSString * const		kMetadataReleaseDateKey;
extern NSString * const		kMetadataCompilationKey;
extern NSString * const		kMetadataTrackNumberKey;
extern NSString * const		kMetadataTrackTotalKey;
extern NSString * const		kMetadataDiscNumberKey;
extern NSString * const		kMetadataDiscTotalKey;
extern NSString * const		kMetadataLyricsKey;
extern NSString * const		kMetadataCommentKey;
extern NSString * const		kMetadataISRCKey;
extern NSString * const		kMetadataMCNKey;
extern NSString * const		kMetadataMusicBrainzIDKey;

extern NSString * const		kMetadataAdditionalMetadataKey;

extern NSString * const		kAlbumArtFrontCoverKey;

extern NSString * const		kTrackMetadataArrayKey;		// NSArray * of NSDictionary *

// ========================================
// A class encapsulating data about a compact disc passed to a MetadataSource
// ========================================
@interface MetadataSourceData : NSObject
{
@private
	NSData *_discTOC;					// Contains a CDTOC * as defined in <IOKit/storage/IOCDTypes.h>
	NSUInteger _freeDBDiscID;			// This disc's FreeDB disc ID
	NSString * _musicBrainzDiscID;		// This disc's MusicBrainz disc ID
	NSDictionary *_settings;			// A dictionary containing any settings configured by the user
	NSDictionary *_metadata;			// A dictionary containing the disc's metadata
}

// ========================================
// Properties
@property (copy) NSData * discTOC;
@property (assign) NSUInteger freeDBDiscID;
@property (copy) NSString * musicBrainzDiscID;
@property (copy) NSDictionary * settings;
@property (copy) NSDictionary * metadata;

@end
