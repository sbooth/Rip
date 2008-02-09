/*
 *  Copyright (C) 2008 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import "FreeDBQueryOperation.h"
#import "CompactDisc.h"
#import "SessionDescriptor.h"
#import "TrackDescriptor.h"

#include <cddb/cddb.h>

@interface MusicDatabaseQueryOperation ()
@property (assign) NSError * error;
@property (assign) NSArray * queryResults;
@end

@interface FreeDBQueryOperation (Private)
- (cddb_disc_t *) buildDisc:(CompactDisc *)compactDisc;
@end

@implementation FreeDBQueryOperation

- (void) main
{
	NSAssert(nil != self.compactDiscID, @"self.compactDiscID may not be nil");

	// Create our own context for accessing the store
	NSManagedObjectContext *managedObjectContext = [[NSManagedObjectContext alloc] init];
	[managedObjectContext setPersistentStoreCoordinator:[[[NSApplication sharedApplication] delegate] persistentStoreCoordinator]];
	
	// Fetch the CompactDisc object from the context and ensure it is the correct class
	NSManagedObject *managedObject = [managedObjectContext objectWithID:self.compactDiscID];
	if(![managedObject isKindOfClass:[CompactDisc class]]) {
		self.error = [NSError errorWithDomain:NSCocoaErrorDomain code:2 userInfo:nil];
		return;
	}
	
	CompactDisc *compactDisc = (CompactDisc *)managedObject;

	// Convert the CompactDisc TOC to libcddb's format
	cddb_disc_t *disc = [self buildDisc:compactDisc];
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

- (cddb_disc_t *) buildDisc:(CompactDisc *)compactDisc
{
	NSParameterAssert(nil != compactDisc);

	// Allocate the memory for the cddb_disc_t object
	cddb_disc_t *disc = cddb_disc_new();
	if(NULL == disc) {
		self.error = [NSError errorWithDomain:NSPOSIXErrorDomain code:ENOMEM userInfo:nil];
		return NULL;
	}
	
	// Convert the TOC from the CompactDisc object's format to that used by libcddb
	CDMSF lastSectorMSF = CDConvertLBAToMSF(compactDisc.firstSession.leadOut.unsignedIntegerValue - 1);
	NSUInteger lengthInSeconds = (60 * lastSectorMSF.minute) + lastSectorMSF.second;
	
	cddb_disc_set_length(disc, lengthInSeconds);
	
	NSArray *firstSessionTracks = compactDisc.firstSession.orderedTracks;
	for(TrackDescriptor *trackDescriptor in firstSessionTracks) {
		cddb_track_t *track = cddb_track_new();
		if(NULL == track) {
			self.error = [NSError errorWithDomain:NSPOSIXErrorDomain code:ENOMEM userInfo:nil];
			cddb_disc_destroy(disc);
			return NULL;
		}
		
		cddb_track_set_frame_offset(track, trackDescriptor.firstSector.intValue);
		cddb_disc_add_track(disc, track);
	}
	
	return disc;
}

@end
