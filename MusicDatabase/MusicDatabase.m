/*
 *  Copyright (C) 2008 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import "MusicDatabase.h"
#import "CompactDisc.h"

// ========================================
// KVC key names for the metadata dictionaries
// ========================================
NSString * const	kMetadataTitleKey						= @"title";
NSString * const	kMetadataAlbumTitleKey					= @"albumTitle";
NSString * const	kMetadataArtistKey						= @"artist";
NSString * const	kMetadataAlbumArtistKey					= @"albumArtist";
NSString * const	kMetadataGenreKey						= @"genre";
NSString * const	kMetadataComposerKey					= @"composer";
NSString * const	kMetadataDateKey						= @"date";
NSString * const	kMetadataCompilationKey					= @"compilation";
NSString * const	kMetadataTrackNumberKey					= @"trackNumber";
NSString * const	kMetadataTrackTotalKey					= @"trackTotal";
NSString * const	kMetadataDiscNumberKey					= @"discNumber";
NSString * const	kMetadataDiscTotalKey					= @"discTotal";
NSString * const	kMetadataCommentKey						= @"comment";
NSString * const	kMetadataISRCKey						= @"isrc";
NSString * const	kMetadataMCNKey							= @"mcn";
NSString * const	kMetadataBPMKey							= @"bpm";
NSString * const	kMetadataMusicDNSPUIDKey				= @"musicDNSPUID";
NSString * const	kMetadataMusicBrainzIDKey				= @"musicBrainzID";

// ========================================
// KVC key names for the query results
// ========================================
NSString * const	kMusicDatabaseTracksKey					= @"tracks";

@implementation MusicDatabase

@synthesize compactDisc = _compactDisc;
@synthesize queryResults = _queryResults;

- (id) init
{
	if((self = [super init]))
		_queryResults = [[NSMutableArray alloc] init];
	return self;
}

- (BOOL) performQuery:(NSError **)error;
{

#pragma unused(error)
	
	return YES;
}

#pragma mark KVC Accessors for queryResults

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
