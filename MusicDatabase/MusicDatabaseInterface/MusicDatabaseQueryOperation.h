/*
 *  Copyright (C) 2008 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import <Cocoa/Cocoa.h>

// ========================================
// KVC key names for the metadata dictionaries
// ========================================
extern NSString * const		kMetadataTitleKey;
extern NSString * const		kMetadataAlbumTitleKey;
extern NSString * const		kMetadataArtistKey;
extern NSString * const		kMetadataAlbumArtistKey;
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

// ========================================
// KVC key names for the query results
// ========================================
extern NSString * const		kMusicDatabaseTracksKey;		// NSArray * of NSDictionary *

// ========================================
// NSOperation subclass providing a generic interface to an online music database
// such as FreeDB or MusicBrainz
// The results from the query are stored as an array; each array item represents a match
// from the database and will contain dictionaries with entries for the keys above
// If queryResults is nil, an error occurred and error will be set
// If queryResults is empty, no matches were found
// ========================================
@interface MusicDatabaseQueryOperation : NSOperation
{
@protected
	NSData *_discTOC;					// Contains a CDTOC * as defined in <IOKit/storage/IOCDTypes.h>
	NSNumber * _freeDBDiscID;			// This disc's FreeDB disc ID
	NSString * _musicBrainzDiscID;		// This disc's MusicBrainz disc ID
	NSDictionary *_settings;			// A dictionary containing any settings configured by the user
	NSArray *_queryResults;
	NSError *_error;
}

// ========================================
// Properties
@property (assign) NSData * discTOC;
@property (assign) NSNumber * freeDBDiscID;
@property (assign) NSString * musicBrainzDiscID;
@property (copy) NSDictionary * settings;
@property (readonly, assign) NSArray * queryResults;
@property (readonly, assign) NSError * error;

@end
