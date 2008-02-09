/*
 *  Copyright (C) 2008 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import "iTunesQueryOperation.h"
#import "CompactDisc.h"
#import "SessionDescriptor.h"
#import "TrackDescriptor.h"
#import "iTunes.h"

@interface MusicDatabaseQueryOperation ()
@property (assign) NSError * error;
@property (assign) NSArray * queryResults;
@end

@implementation iTunesQueryOperation

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
		if(audioCDTracks.count != compactDisc.firstSession.tracks.count)
			continue;

		NSMutableDictionary *discInformation = [[NSMutableDictionary alloc] init];

		NSString *albumArtist = audioCDPlaylist.artist;
		if(albumArtist)
			[discInformation setObject:albumArtist forKey:kMetadataArtistKey];

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
