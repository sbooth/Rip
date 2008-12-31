/*
 *  Copyright (C) 2008 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import "MusicDatabaseQueryOperation.h"

// ========================================
// KVC key names for the metadata dictionaries
// ========================================
NSString * const	kMetadataTitleKey						= @"title";
NSString * const	kMetadataAlbumTitleKey					= @"albumTitle";
NSString * const	kMetadataArtistKey						= @"artist";
NSString * const	kMetadataAlbumArtistKey					= @"albumArtist";
NSString * const	kMetadataGenreKey						= @"genre";
NSString * const	kMetadataComposerKey					= @"composer";
NSString * const	kMetadataReleaseDateKey					= @"date";
NSString * const	kMetadataCompilationKey					= @"compilation";
NSString * const	kMetadataTrackNumberKey					= @"trackNumber";
NSString * const	kMetadataTrackTotalKey					= @"trackTotal";
NSString * const	kMetadataDiscNumberKey					= @"discNumber";
NSString * const	kMetadataDiscTotalKey					= @"discTotal";
NSString * const	kMetadataLyricsKey						= @"lyrics";
NSString * const	kMetadataCommentKey						= @"comment";
NSString * const	kMetadataISRCKey						= @"ISRC";
NSString * const	kMetadataMCNKey							= @"MCN";
NSString * const	kMetadataMusicBrainzIDKey				= @"MusicBrainzID";
NSString * const	kAlbumArtFrontCoverKey					= @"albumArtFrontCover";

// ========================================
// KVC key names for the query results
// ========================================
NSString * const	kMusicDatabaseTracksKey					= @"tracks";

@interface MusicDatabaseQueryOperation ()
@property (assign) NSArray * queryResults;
@property (copy) NSError * error;
@end

@implementation MusicDatabaseQueryOperation

// ========================================
// Properties
@synthesize discTOC = _discTOC;
@synthesize freeDBDiscID = _freeDBDiscID;
@synthesize musicBrainzDiscID = _musicBrainzDiscID;
@synthesize settings = _settings;
@synthesize queryResults = _queryResults;
@synthesize error = _error;

// ========================================
// KVC Accessors for queryResults
- (NSUInteger) countOfQueryResults
{
	return [_queryResults count];
}

- (id) objectInQueryResultsAtIndex:(NSUInteger)index
{
	return [_queryResults objectAtIndex:index];
}

- (void) getQueryResults:(id *)buffer range:(NSRange)range
{
	[_queryResults getObjects:buffer range:range];
}

@end
