/*
 *  Copyright (C) 2008 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import "FreeDBQueryOperation.h"
#import <IOKit/storage/IOCDTypes.h>

#include <cddb/cddb.h>

@interface MusicDatabaseQueryOperation ()
@property (assign) NSArray * queryResults;
@property (assign) NSError * error;
@end

@interface FreeDBQueryOperation (Private)
- (cddb_disc_t *) buildDisc:(CDTOC *)toc;
@end

@implementation FreeDBQueryOperation

- (void) main
{
	NSAssert(nil != self.discTOC, @"self.discTOC may not be nil");

	// Convert the disc's TOC to libcddb's format
	cddb_disc_t *disc = [self buildDisc:(CDTOC *)[self.discTOC bytes]];
	if(NULL == disc)
		return;

	// Create a connection that will be used to communicate with FreeDB
	cddb_conn_t *conn = cddb_new();
	if(NULL == conn) {
		self.error = [NSError errorWithDomain:NSPOSIXErrorDomain code:ENOMEM userInfo:nil];
		goto cleanup;
	}
	
	// Determine the number of matching discs
	int matches = cddb_query(conn, disc);
	if(-1 == matches) {
		cddb_error_print(cddb_errno(conn));
		self.error = [NSError errorWithDomain:NSPOSIXErrorDomain code:ENOMEM userInfo:nil];
		goto cleanup;
	}

	NSMutableArray *matchingDiscs = [[NSMutableArray alloc] init];

	// Iterate through each matching disc
	while(0 < matches) {
		
		// Read the disc details and build them into a more useful data structure
		int success = cddb_read(conn, disc);
		if(!success) {
			--matches;
			continue;
		}
		
		NSMutableDictionary *discInformation = [[NSMutableDictionary alloc] init];
		
		// Genre is set in FreeDB on a per-album basis, but treated on a per-track basis here
		const char *genre = cddb_disc_get_genre(disc);

		unsigned int year = cddb_disc_get_year(disc);
		if(0 != year)
			[discInformation setObject:[[NSNumber numberWithInt:year] stringValue] forKey:kMetadataReleaseDateKey];

		const char *albumTitle = cddb_disc_get_title(disc);
		if(albumTitle)
			[discInformation setObject:[NSString stringWithUTF8String:albumTitle] forKey:kMetadataAlbumTitleKey];
		
		const char *albumArtist = cddb_disc_get_artist(disc);
		if(albumArtist)
			[discInformation setObject:[NSString stringWithUTF8String:albumArtist] forKey:kMetadataAlbumArtistKey];

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
			
			if(genre)
				[trackInformation setObject:[NSString stringWithUTF8String:genre] forKey:kMetadataGenreKey];

			// Ensure the track's artist is set if an artist was retrieved from FreeDB
			const char *artist = cddb_track_get_artist(track);
			if(artist)
				[trackInformation setObject:[NSString stringWithUTF8String:artist] forKey:kMetadataArtistKey];
			else if(albumArtist)
				[trackInformation setObject:[NSString stringWithUTF8String:albumArtist] forKey:kMetadataArtistKey];
			
			const char *title = cddb_track_get_title(track);
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
		[matchingDiscs addObject:discInformation];
		
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

	// Set the query results
	self.queryResults = matchingDiscs;
	
cleanup:
	if(disc)
		cddb_disc_destroy(disc);

	if(conn)
		cddb_destroy(conn);
}

@end

@implementation FreeDBQueryOperation (Private)

- (cddb_disc_t *) buildDisc:(CDTOC *)toc
{
	NSParameterAssert(NULL != toc);

	// Allocate the memory for the cddb_disc_t object
	cddb_disc_t *disc = cddb_disc_new();
	if(NULL == disc) {
		self.error = [NSError errorWithDomain:NSPOSIXErrorDomain code:ENOMEM userInfo:nil];
		return NULL;
	}
	
	// Convert the TOC from the CDTOC format to that used by libcddb
	NSUInteger firstTrackNumber = 0, lastTrackNumber = 0;
	CDMSF leadOutMSF = { 0, 0, 0 };
	
	// Iterate through each descriptor in the first session and extract the information we need
	NSUInteger numDescriptors = CDTOCGetDescriptorCount(toc);
	NSUInteger i;
	for(i = 0; i < numDescriptors; ++i) {
		CDTOCDescriptor *desc = &toc->descriptors[i];
		
		// First track
		if(0xA0 == desc->point && 1 == desc->adr) {
			if(1 == desc->session)
				firstTrackNumber = desc->p.minute;
		}
		// Last track
		else if(0xA1 == desc->point && 1 == desc->adr) {
			if(1 == desc->session)
				lastTrackNumber = desc->p.minute;
		}
		// Lead-out
		else if(0xA2 == desc->point && 1 == desc->adr) {
			if(1 == desc->session)
				leadOutMSF = desc->p;
		}
	}
	
	NSUInteger trackNumber;
	for(trackNumber = firstTrackNumber; trackNumber <= lastTrackNumber; ++trackNumber) {
		CDMSF msf = CDConvertTrackNumberToMSF(trackNumber, toc);
		cddb_track_t *track = cddb_track_new();
		if(NULL == track) {
			self.error = [NSError errorWithDomain:NSPOSIXErrorDomain code:ENOMEM userInfo:nil];
			cddb_disc_destroy(disc);
			return NULL;
		}
		
		cddb_track_set_frame_offset(track, CDConvertMSFToLBA(msf));
		cddb_disc_add_track(disc, track);
	}
	
	CDMSF firstTrackMSF = CDConvertTrackNumberToMSF(firstTrackNumber, toc);
	NSInteger discLengthInSeconds = ((leadOutMSF.minute * 60) + leadOutMSF.second) - ((firstTrackMSF.minute * 60) + firstTrackMSF.second);

	cddb_disc_set_length(disc, (unsigned int)discLengthInSeconds);
	
	return disc;
}

@end
