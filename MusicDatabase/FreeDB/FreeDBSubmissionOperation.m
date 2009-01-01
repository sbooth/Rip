/*
 *  Copyright (C) 2009 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import "FreeDBSubmissionOperation.h"
#import <IOKit/storage/IOCDTypes.h>

#include <cddb/cddb.h>

@interface MusicDatabaseSubmissionOperation ()
@property (copy) NSError * error;
@end

@interface FreeDBSubmissionOperation (Private)
- (cddb_disc_t *) buildDisc:(CDTOC *)toc;
@end

@implementation FreeDBSubmissionOperation

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
	
	// Proxy support
	if([[self.settings objectForKey:@"freeDBUseProxy"] boolValue]) {
		cddb_http_proxy_enable(conn);
		
		if([self.settings objectForKey:@"freeDBProxyServer"])
			cddb_set_http_proxy_server_name(conn, [[self.settings objectForKey:@"freeDBProxyServer"] UTF8String]);
		if([self.settings objectForKey:@"freeDBProxyServerPort"])
			cddb_set_http_proxy_server_port(conn, [[self.settings objectForKey:@"freeDBProxyServerPort"] intValue]);
		
		if([[self.settings objectForKey:@"freeDBUseProxyAuthentication"] boolValue]) {
			cddb_set_http_proxy_username(conn, [[self.settings objectForKey:@"freeDBProxyServerUsername"] UTF8String]);
			cddb_set_http_proxy_password(conn, [[self.settings objectForKey:@"freeDBProxyServerPassword"] UTF8String]);
		}
	}
	
	// Set ourselves as the cddb client
	NSBundle *myBundle = [NSBundle bundleForClass:[self class]];
	NSString *bundleIdentifier = [myBundle objectForInfoDictionaryKey:@"CFBundleIdentifier"];
	NSString *bundleVersion = [myBundle objectForInfoDictionaryKey:@"CFBundleVersion"];
	cddb_set_client(conn, [bundleIdentifier UTF8String], [bundleVersion UTF8String]);
	
	if([self.settings objectForKey:@"freeDBEMailAddress"])
		cddb_set_email_address(conn, [[self.settings objectForKey:@"freeDBEMailAddress"] UTF8String]);
	
	// Flesh out the disc's metadata
	if([self.metadata objectForKey:kMetadataAlbumTitleKey])
		cddb_disc_set_title(disc, [[self.metadata objectForKey:kMetadataAlbumTitleKey] UTF8String]);

	if([self.metadata objectForKey:kMetadataAlbumArtistKey])
		cddb_disc_set_artist(disc, [[self.metadata objectForKey:kMetadataAlbumArtistKey] UTF8String]);

	// Tracks in FreeDB only contain title and artist
	NSArray *tracks = [self.metadata objectForKey:kMusicDatabaseTracksKey];
	for(NSDictionary *trackMetadata in tracks) {
		NSNumber *trackNumber = [trackMetadata objectForKey:kMetadataTrackNumberKey];

		cddb_track_t *track = cddb_disc_get_track(disc, [trackNumber intValue]);
		if(NULL == track)
			continue;
		
		if([trackMetadata objectForKey:kMetadataTitleKey])
			cddb_track_set_title(track, [[trackMetadata objectForKey:kMetadataTitleKey] UTF8String]);

		if([trackMetadata objectForKey:kMetadataArtistKey])
			cddb_track_set_artist(track, [[trackMetadata objectForKey:kMetadataArtistKey] UTF8String]);
	}
	
	// TODO: Verify all required data is present
	
	// Submit the disc
	int success = cddb_write(conn, disc);
	if(!success) {
		cddb_error_print(cddb_errno(conn));
		self.error = [NSError errorWithDomain:NSPOSIXErrorDomain code:ENOMEM userInfo:nil];
		goto cleanup;
	}
	
cleanup:
	if(disc)
		cddb_disc_destroy(disc);
	
	if(conn)
		cddb_destroy(conn);
}

@end

@implementation FreeDBSubmissionOperation (Private)

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
		
		// Only the first session is used to create the FreeDB ID
		if(1 != desc->session)
			continue;
		
		// First track
		if(0xA0 == desc->point && 1 == desc->adr)
			firstTrackNumber = desc->p.minute;
		// Last track
		else if(0xA1 == desc->point && 1 == desc->adr)
			lastTrackNumber = desc->p.minute;
		// Lead-out
		else if(0xA2 == desc->point && 1 == desc->adr)
			leadOutMSF = desc->p;
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
