/*
 *  Copyright (C) 2008 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import "iTunesDatabase.h"
#import "CompactDisc.h"
#import "SessionDescriptor.h"
#import "TrackDescriptor.h"
#import "iTunes.h"

@implementation iTunesDatabase

- (BOOL) performQuery:(NSError **)error
{
	// Remove all previous query results
	NSIndexSet *indexesToBeRemoved = [NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, self.queryResults.count)];
	[self willChange:NSKeyValueChangeRemoval valuesAtIndexes:indexesToBeRemoved forKey:@"queryResults"];
	[_queryResults removeAllObjects];
	[self didChange:NSKeyValueChangeRemoval valuesAtIndexes:indexesToBeRemoved forKey:@"queryResults"];

	// Create the scripting bridge application object for iTunes
	iTunesApplication *iTunes = [SBApplication applicationWithBundleIdentifier:@"com.apple.iTunes"];
	iTunes.delegate = self;

	// iTunes isn't installed !?
	if(nil == iTunes) {
		*error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSNotFound userInfo:nil];
		return NO;
	}

	// Launch iTunes if it isn't running
	if(!iTunes.isRunning)
		[iTunes run];
	
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
		if(audioCDTracks.count != self.compactDisc.firstSession.tracks.count)
			continue;

		NSMutableDictionary *discInformation = [[NSMutableDictionary alloc] init];

		NSString *albumArtist = audioCDPlaylist.artist;
		if(albumArtist)
			[discInformation setObject:albumArtist forKey:kMetadataAlbumArtistKey];

		NSString *albumComposer = audioCDPlaylist.composer;
		if(albumComposer)
			[discInformation setObject:albumComposer forKey:kMetadataComposerKey];

		NSInteger albumYear = audioCDPlaylist.year;
		if(albumYear)
			[discInformation setObject:[NSString stringWithFormat:@"%i", albumYear] forKey:kMetadataDateKey];
		
		NSInteger discNumber = audioCDPlaylist.discNumber;
		if(discNumber)
			[discInformation setObject:[NSNumber numberWithInteger:discNumber] forKey:kMetadataDiscNumberKey];

		NSInteger discCount = audioCDPlaylist.discCount;
		if(discCount)
			[discInformation setObject:[NSNumber numberWithInteger:discCount] forKey:kMetadataDiscTotalKey];

		NSString *albumGenre = audioCDPlaylist.genre;
		if(albumGenre)
			[discInformation setObject:albumGenre forKey:kMetadataGenreKey];
		
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
			
			NSString *composer = audioCDTrack.composer;
			if(composer)
				[trackInformation setObject:composer forKey:kMetadataComposerKey];
			
			NSInteger year = audioCDTrack.year;
			if(year)
				[trackInformation setObject:[NSString stringWithFormat:@"%i", year] forKey:kMetadataDateKey];
			
			NSInteger trackNumber = audioCDTrack.trackNumber;
			if(trackNumber)
				[trackInformation setObject:[NSNumber numberWithInteger:trackNumber] forKey:kMetadataTrackNumberKey];
			
			NSInteger trackCount = audioCDTrack.trackCount;
			if(trackCount)
				[trackInformation setObject:[NSNumber numberWithInteger:trackCount] forKey:kMetadataTrackTotalKey];

			NSString *genre = audioCDTrack.genre;
			if(genre)
				[trackInformation setObject:genre forKey:kMetadataGenreKey];
			
			NSString *lyrics = audioCDTrack.lyrics;
			if(lyrics)
				[trackInformation setObject:lyrics forKey:kMetadataLyricsKey];
			
			NSString *title = audioCDTrack.name;
			if(title)
				[trackInformation setObject:title forKey:kMetadataTitleKey];
			
			[discTracks addObject:trackInformation];
		}
		
		[discInformation setObject:discTracks forKey:kMusicDatabaseTracksKey];
		
		// Add the matching disc to the set of query results in a KVC-compliant manner
		NSIndexSet *insertionIndex = [NSIndexSet indexSetWithIndex:self.queryResults.count];
		[self willChange:NSKeyValueChangeInsertion valuesAtIndexes:insertionIndex forKey:@"queryResults"];
		[_queryResults addObject:discInformation];
		[self didChange:NSKeyValueChangeInsertion valuesAtIndexes:insertionIndex forKey:@"queryResults"];		
	}

	return YES;
}

- (void) eventDidFail:(const AppleEvent *)event withError:(NSError *)error
{
	
#pragma unused(event)
#pragma unused(error)
	
}

@end
