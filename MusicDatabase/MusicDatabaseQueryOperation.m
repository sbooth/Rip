/*
 *  Copyright (C) 2008 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import "MusicDatabaseQueryOperation.h"
#import "FreeDBQueryOperation.h"
#import "MusicBrainzQueryOperation.h"
#import "iTunesQueryOperation.h"

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
NSString * const	kMetadataLyricsKey						= @"lyrics";
NSString * const	kMetadataCommentKey						= @"comment";
NSString * const	kMetadataISRCKey						= @"ISRC";
NSString * const	kMetadataMCNKey							= @"MCN";
NSString * const	kMetadataMusicBrainzIDKey				= @"MusicBrainzID";

// ========================================
// KVC key names for the query results
// ========================================
NSString * const	kMusicDatabaseTracksKey					= @"tracks";

@interface MusicDatabaseQueryOperation ()
@property (assign) NSError * error;
@property (assign) NSArray * queryResults;
@end

@implementation MusicDatabaseQueryOperation

// ========================================
// Convenience functions for creating known subclasses
+ (id) defaultMusicDatabaseQueryOperation
{
//	NSInteger foo = [[NSUserDefaults standardUserDefaults] integerForKey:@""];
	
	return [[FreeDBQueryOperation alloc] init];
}

+ (id) FreeDBQueryOperation
{
	return [[FreeDBQueryOperation alloc] init];
}

+ (id) MusicBrainzQueryOperation
{
	return [[MusicBrainzQueryOperation alloc] init];	
}

+ (id) iTunesQueryOperation
{
	return [[iTunesQueryOperation alloc] init];
}

// ========================================
// Properties
@synthesize compactDiscID = _compactDiscID;
@synthesize error = _error;
@synthesize queryResults = _queryResults;

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
