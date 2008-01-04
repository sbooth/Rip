/*
 *  Copyright (C) 2008 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import "FreeDB.h"
#import "CompactDisc.h"
#import "TrackDescriptor.h"

#include <cddb/cddb.h>

@interface FreeDB (Private)
- (cddb_disc_t *) buildDisc:(NSError **)error;
@end

@implementation FreeDB

- (BOOL) performQuery:(NSError **)error;
{
	// Remove all previous query results
	NSIndexSet *indexesToBeRemoved = [NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, self.queryResults.count)];
	[self willChange:NSKeyValueChangeRemoval valuesAtIndexes:indexesToBeRemoved forKey:@"queryResults"];
	[_queryResults removeAllObjects];
	[self didChange:NSKeyValueChangeRemoval valuesAtIndexes:indexesToBeRemoved forKey:@"queryResults"];

	// Convert the CompactDisc TOC to libcddb's format
	cddb_disc_t *disc = [self buildDisc:error];
	if(NULL == disc)
		return NO;

	BOOL result = YES;

	// Create a connection that will be used to communicate with FreeDB
	cddb_conn_t *conn = cddb_new();
	if(NULL == conn) {
		if(error)
			*error = [NSError errorWithDomain:NSPOSIXErrorDomain code:ENOMEM userInfo:nil];
		result = NO;
		goto cleanup;
	}
	
	// Determine the number of matching discs
	int matches = cddb_query(conn, disc);
	if(-1 == matches) {
		cddb_error_print(cddb_errno(conn));
		if(error)
			*error = [NSError errorWithDomain:NSPOSIXErrorDomain code:ENOMEM userInfo:nil];
		result = NO;
		goto cleanup;
	}

	// Iterate through each matching disc
	while(0 < matches) {
		
		// Read the disc details and build them into a more useful data structure
		int success = cddb_read(conn, disc);
		if(!success) {
			--matches;
			continue;
		}
		
		NSMutableDictionary *discInformation = [[NSMutableDictionary alloc] init];
		
		const char *genre = cddb_disc_get_genre(disc);
		if(genre)
			[discInformation setObject:[NSString stringWithUTF8String:genre] forKey:kMetadataGenreKey];
		
		unsigned int year = cddb_disc_get_year(disc);
		if(0 != year)
			[discInformation setObject:[[NSNumber numberWithInt:year] stringValue] forKey:kMetadataDateKey];

		const char *title = cddb_disc_get_title(disc);
		if(title)
			[discInformation setObject:[NSString stringWithUTF8String:title] forKey:kMetadataAlbumTitleKey];
		
		const char *artist = cddb_disc_get_artist(disc);
		if(artist)
			[discInformation setObject:[NSString stringWithUTF8String:artist] forKey:kMetadataAlbumArtistKey];

		const char *extData = cddb_disc_get_ext_data(disc);
		if(extData)
			[discInformation setObject:[NSString stringWithUTF8String:extData] forKey:kMetadataCommentKey];
		
		// Iterate through each track on the disc and store the information
		NSMutableArray *discTracks = [[NSMutableArray alloc] init];
		
		cddb_track_t *track = cddb_disc_get_track_first(disc);
		while(track) {
			NSMutableDictionary *trackInformation = [[NSMutableDictionary alloc] init];

			int number = cddb_track_get_number(track);
			if(0 != number)
				[trackInformation setObject:[NSNumber numberWithInt:number] forKey:kMetadataTrackNumberKey];
			
			artist = cddb_track_get_artist(track);
			if(artist)
				[trackInformation setObject:[NSString stringWithUTF8String:artist] forKey:kMetadataArtistKey];
			
			title = cddb_track_get_title(track);
			if(title)
				[trackInformation setObject:[NSString stringWithUTF8String:title] forKey:kMetadataTitleKey];
			
			extData = cddb_track_get_ext_data(track);
			if(extData)
				[trackInformation setObject:[NSString stringWithUTF8String:extData] forKey:kMetadataCommentKey];
			
			[discTracks addObject:trackInformation];
			
			// Get the next track from the disc
			track = cddb_disc_get_track_next(disc);
		}

		[discInformation setObject:discTracks forKey:kMusicDatabaseTracksKey];
		
		// Add the matching disc to the set of query results in a KVC-compliant manner
		NSIndexSet *insertionIndex = [NSIndexSet indexSetWithIndex:self.queryResults.count];
		[self willChange:NSKeyValueChangeInsertion valuesAtIndexes:insertionIndex forKey:@"queryResults"];
		[_queryResults addObject:discInformation];
		[self didChange:NSKeyValueChangeInsertion valuesAtIndexes:insertionIndex forKey:@"queryResults"];
		
		// Housekeeping
		matches--;
		if(0 < matches) {
			if(!cddb_query_next(conn, disc)) {
#if DEBUG
				NSLog(@"libcddb query index out of bounds");
#endif
				goto cleanup;
			}
		}
	}
	
cleanup:
	if(disc)
		cddb_disc_destroy(disc);

	if(conn)
		cddb_destroy(conn);
	
	return result;
}

@end

@implementation FreeDB (Private)

- (cddb_disc_t *) buildDisc:(NSError **)error
{
	NSAssert(nil != self.compactDisc, @"self.compactDisc may not be nil");

	// Allocate the memory for the cddb_disc_t object
	cddb_disc_t *disc = cddb_disc_new();
	if(NULL == disc) {
		if(error)
			*error = [NSError errorWithDomain:NSPOSIXErrorDomain code:ENOMEM userInfo:nil];
		return NULL;
	}
	
	// Convert the TOC from the CompactDisc object's format to that used by libcddb
	CDMSF lastSectorMSF = CDConvertLBAToMSF([self.compactDisc lastSectorForSession:1]);
	NSUInteger lengthInSeconds = (60 * lastSectorMSF.minute) + lastSectorMSF.second;
	
	cddb_disc_set_length(disc, lengthInSeconds);
	
	NSArray *firstSessionTracks = [self.compactDisc tracksForSession:1];
	for(TrackDescriptor *trackDescriptor in firstSessionTracks) {
		cddb_track_t *track = cddb_track_new();
		if(NULL == track) {
			if(error)
				*error = [NSError errorWithDomain:NSPOSIXErrorDomain code:ENOMEM userInfo:nil];
			cddb_disc_destroy(disc);
			return NULL;
		}
		
		cddb_track_set_frame_offset(track, trackDescriptor.firstSector);
		cddb_disc_add_track(disc, track);
	}
	
	return disc;
}

@end
