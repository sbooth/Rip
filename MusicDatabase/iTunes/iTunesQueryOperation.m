/*
 *  Copyright (C) 2008 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import "iTunesQueryOperation.h"
#import "iTunes.h"
#import <IOKit/storage/IOCDTypes.h>

@interface MusicDatabaseQueryOperation ()
@property (assign) NSArray * queryResults;
@property (assign) NSError * error;
@end

@implementation iTunesQueryOperation

- (void) main
{
	NSAssert(nil != self.discTOC, @"self.discTOC may not be nil");

	// Process the CDTOC into a more friendly format
	CDTOC *toc = (CDTOC *)[self.discTOC bytes];
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
	
	// Create the scripting bridge application object for iTunes
	iTunesApplication *iTunes = [SBApplication applicationWithBundleIdentifier:@"com.apple.iTunes"];
	iTunes.delegate = self;

	// iTunes isn't installed !?
	if(nil == iTunes) {
		self.error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSNotFound userInfo:nil];
		return;
	}

	// Launch iTunes if it isn't running
	if(!iTunes.isRunning)
		[iTunes run];
	
	NSMutableArray *matchingDiscs = [[NSMutableArray alloc] init];
	
	// Get all the audio CDs iTunes knows about

	// For some reason the following predicate isn't working
//	NSPredicate *audioCDPredicate = [NSPredicate predicateWithFormat:@"kind == %i", iTunesESrcAudioCD];
//	SBElementArray *iTunesAudioCDs = (SBElementArray *)[iTunes.sources filteredArrayUsingPredicate:audioCDPredicate];

	for(iTunesSource *source in iTunes.sources) {
		
		// Skip non-CD sources
		if(iTunesESrcAudioCD != source.kind)
			continue;
		
		SBElementArray *audioCDPlaylists = source.audioCDPlaylists;
		if(nil == audioCDPlaylists)
			continue;
		
		iTunesAudioCDPlaylist *audioCDPlaylist = [audioCDPlaylists objectAtIndex:0];
		SBElementArray *audioCDTracks = audioCDPlaylist.audioCDTracks;
	
		// Only discs with the same number of tracks are considered matches
		if(audioCDTracks.count != lastTrackNumber)
			continue;

		NSMutableDictionary *discInformation = [[NSMutableDictionary alloc] init];

		NSString *albumArtist = audioCDPlaylist.artist;
		if(albumArtist)
			[discInformation setObject:albumArtist forKey:kMetadataAlbumArtistKey];

		NSString *albumComposer = audioCDPlaylist.composer;

		NSInteger albumYear = audioCDPlaylist.year;
		if(albumYear)
			[discInformation setObject:[NSString stringWithFormat:@"%i", albumYear] forKey:kMetadataReleaseDateKey];
		
		NSInteger discNumber = audioCDPlaylist.discNumber;
		if(discNumber)
			[discInformation setObject:[NSNumber numberWithInteger:discNumber] forKey:kMetadataDiscNumberKey];

		NSInteger discCount = audioCDPlaylist.discCount;
		if(discCount)
			[discInformation setObject:[NSNumber numberWithInteger:discCount] forKey:kMetadataDiscTotalKey];

		NSString *albumGenre = audioCDPlaylist.genre;
		
		if(audioCDPlaylist.compilation)
			[discInformation setObject:[NSNumber numberWithBool:YES] forKey:kMetadataCompilationKey];
		
		NSString *albumTitle = audioCDPlaylist.name;
		if(albumTitle)
			[discInformation setObject:albumTitle forKey:kMetadataAlbumTitleKey];
				
		// Iterate through each track on the disc and store the information
		NSMutableArray *discTracks = [[NSMutableArray alloc] init];

		for(iTunesAudioCDTrack *audioCDTrack in audioCDTracks) {
			NSMutableDictionary *trackInformation = [[NSMutableDictionary alloc] init];

			NSString *artist = audioCDTrack.artist;
			if(artist)
				[trackInformation setObject:artist forKey:kMetadataArtistKey];
			else if(albumArtist)
				[trackInformation setObject:albumArtist forKey:kMetadataArtistKey];
			
			NSString *composer = audioCDTrack.composer;
			if(composer)
				[trackInformation setObject:composer forKey:kMetadataComposerKey];
			else if(albumComposer)
				[trackInformation setObject:albumComposer forKey:kMetadataComposerKey];
			
			NSInteger year = audioCDTrack.year;
			if(year)
				[trackInformation setObject:[NSString stringWithFormat:@"%i", year] forKey:kMetadataReleaseDateKey];
			
			NSInteger trackNumber = audioCDTrack.trackNumber;
			if(trackNumber)
				[trackInformation setObject:[NSNumber numberWithInteger:trackNumber] forKey:kMetadataTrackNumberKey];
			
			NSInteger trackCount = audioCDTrack.trackCount;
			if(trackCount)
				[trackInformation setObject:[NSNumber numberWithInteger:trackCount] forKey:kMetadataTrackTotalKey];

			NSString *genre = audioCDTrack.genre;
			if(genre)
				[trackInformation setObject:genre forKey:kMetadataGenreKey];
			else if(albumGenre)
				[trackInformation setObject:albumGenre forKey:kMetadataGenreKey];
			
			NSString *lyrics = audioCDTrack.lyrics;
			if(lyrics)
				[trackInformation setObject:lyrics forKey:kMetadataLyricsKey];
			
			NSString *title = audioCDTrack.name;
			if(title)
				[trackInformation setObject:title forKey:kMetadataTitleKey];
			
			[discTracks addObject:trackInformation];
		}
		
		[discInformation setObject:discTracks forKey:kMusicDatabaseTracksKey];
		[matchingDiscs addObject:discInformation];
	}

	// Set the query results
	self.queryResults = matchingDiscs;
}

- (void) eventDidFail:(const AppleEvent *)event withError:(NSError *)error
{
	
#pragma unused(event)

	self.error = error;
}

@end
