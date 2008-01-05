/*
 *  Copyright (C) 2008 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import "MusicBrainzDatabase.h"
#import "CompactDisc.h"

#include <musicbrainz3/webservice.h>
#include <musicbrainz3/query.h>
#include <musicbrainz3/model.h>
#include <musicbrainz3/utils.h>

@implementation MusicBrainzDatabase

- (BOOL) performQuery:(NSError **)error
{
	// Remove all previous query results
	NSIndexSet *indexesToBeRemoved = [NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, self.queryResults.count)];
	[self willChange:NSKeyValueChangeRemoval valuesAtIndexes:indexesToBeRemoved forKey:@"queryResults"];
	[_queryResults removeAllObjects];
	[self didChange:NSKeyValueChangeRemoval valuesAtIndexes:indexesToBeRemoved forKey:@"queryResults"];

	// Set up the MusicBrainz web service
	MusicBrainz::WebService *ws = new MusicBrainz::WebService();
	if(NULL == ws) {
		if(error)
			*error = [NSError errorWithDomain:NSPOSIXErrorDomain code:ENOMEM userInfo:nil];
		return NO;
	}
	
	// Set MB server and port
	if(nil != [[NSUserDefaults standardUserDefaults] stringForKey:@"musicBrainzServer"])
		ws->setHost([[[NSUserDefaults standardUserDefaults] stringForKey:@"musicBrainzServer"] cStringUsingEncoding:NSUTF8StringEncoding]);
	
	if(nil != [[NSUserDefaults standardUserDefaults] objectForKey:@"musicBrainzServerPort"])
		ws->setPort([[NSUserDefaults standardUserDefaults] integerForKey:@"musicBrainzServerPort"]);
	
	// Use authentication, if specified
	if(nil != [[NSUserDefaults standardUserDefaults] stringForKey:@"musicBrainzUsername"])
		ws->setUserName([[[NSUserDefaults standardUserDefaults] stringForKey:@"musicBrainzUsername"] cStringUsingEncoding:NSUTF8StringEncoding]);
	
	if(nil != [[NSUserDefaults standardUserDefaults] objectForKey:@"musicBrainzPassword"])
		ws->setPassword([[[NSUserDefaults standardUserDefaults] stringForKey:@"musicBrainzPassword"] cStringUsingEncoding:NSUTF8StringEncoding]);
	
	// Proxy setup
	if([[NSUserDefaults standardUserDefaults] boolForKey:@"musicBrainzUseProxy"]) {
		if(nil != [[NSUserDefaults standardUserDefaults] stringForKey:@"musicBrainzProxyServer"])
			ws->setProxyHost([[[NSUserDefaults standardUserDefaults] stringForKey:@"musicBrainzProxyServer"] cStringUsingEncoding:NSUTF8StringEncoding]);
		if(nil != [[NSUserDefaults standardUserDefaults] stringForKey:@"musicBrainzProxyServerPort"])
			ws->setProxyPort([[NSUserDefaults standardUserDefaults] integerForKey:@"musicBrainzProxyServerPort"]);
	}		

	MusicBrainz::Query q(ws);
	MusicBrainz::ReleaseResultList results;

	try {
		std::string discID = [self.compactDisc.musicBrainzDiscID cStringUsingEncoding:NSASCIIStringEncoding];
		MusicBrainz::ReleaseFilter f = MusicBrainz::ReleaseFilter().discId(discID);
        results = q.getReleases(&f);
	}
	
	catch(/* const MusicBrainz::Exception &e */const std::exception &e) {
#if DEBUG
		NSLog(@"MusicBrainz error: %s", e.what());
#endif
		if(error)
			*error = [NSError errorWithDomain:NSPOSIXErrorDomain code:ENOMEM userInfo:nil];
		return NO;
	}
	
	for(MusicBrainz::ReleaseResultList::iterator i = results.begin(); i != results.end(); i++) {
		MusicBrainz::ReleaseResult *result = *i;
		MusicBrainz::Release *release;
		
		try {
			MusicBrainz::ReleaseIncludes includes = MusicBrainz::ReleaseIncludes().tracks().artist().releaseEvents();
			release = q.getReleaseById(result->getRelease()->getId(), &includes);
		}
		
		catch(/* const MusicBrainz::Exception &e */const std::exception &e) {
#if DEBUG
			NSLog(@"Error: %s", e.what());
#endif
			continue;
		}
		
		NSMutableDictionary *releaseDictionary = [NSMutableDictionary dictionary];
		
		// ID
		if(!release->getId().empty())
			[releaseDictionary setObject:[NSString stringWithCString:release->getId().c_str() encoding:NSUTF8StringEncoding] forKey:kMetadataMusicBrainzIDKey];
		
		// Title
		if(!release->getTitle().empty())
			[releaseDictionary setObject:[NSString stringWithCString:release->getTitle().c_str() encoding:NSUTF8StringEncoding] forKey:kMetadataAlbumTitleKey];
		
		// Artist
		if(NULL != release->getArtist() && !release->getArtist()->getName().empty())
			[releaseDictionary setObject:[NSString stringWithCString:release->getArtist()->getName().c_str() encoding:NSUTF8StringEncoding] forKey:kMetadataAlbumArtistKey];
		
		// Take a best guess on the release date
		if(1 == release->getNumReleaseEvents()) {
			MusicBrainz::ReleaseEvent *releaseEvent = release->getReleaseEvent(0);
			[releaseDictionary setObject:[NSString stringWithCString:releaseEvent->getDate().c_str() encoding:NSUTF8StringEncoding] forKey:kMetadataDateKey];
		}
		else {
			NSString	*currentLocale		= [[NSUserDefaults standardUserDefaults] objectForKey:@"AppleLocale"];
			NSArray		*localeElements		= [currentLocale componentsSeparatedByString:@"_"];
//			NSString	*currentLanguage	= [localeElements objectAtIndex:0];
			NSString	*currentCountry		= [localeElements objectAtIndex:1];
			
			// Try to match based on the assumption that the disc is from the user's own locale
			for(NSInteger k = 0; k < release->getNumReleaseEvents(); ++k) {
				MusicBrainz::ReleaseEvent *releaseEvent = release->getReleaseEvent(k);
				NSString *releaseEventCountry = [NSString stringWithCString:releaseEvent->getCountry().c_str() encoding:NSASCIIStringEncoding];
				if(NSOrderedSame == [releaseEventCountry caseInsensitiveCompare:currentCountry])
					[releaseDictionary setObject:[NSString stringWithCString:releaseEvent->getDate().c_str() encoding:NSUTF8StringEncoding] forKey:kMetadataDateKey];
			}
			
			// Nothing matched, just take the first one
			if(nil == [releaseDictionary valueForKey:kMetadataDateKey] && 0 < release->getNumReleaseEvents()) {
				MusicBrainz::ReleaseEvent *releaseEvent = release->getReleaseEvent(0);
				[releaseDictionary setObject:[NSString stringWithCString:releaseEvent->getDate().c_str() encoding:NSUTF8StringEncoding] forKey:kMetadataDateKey];
			}
		}
		
		// Iterate through the tracks
		NSMutableArray *tracksDictionary = [NSMutableArray array];
		NSInteger trackno = 1;
		for(MusicBrainz::TrackList::iterator j = release->getTracks().begin(); j != release->getTracks().end(); j++) {
			MusicBrainz::Track *track = *j;
			NSMutableDictionary *trackDictionary = [NSMutableDictionary dictionary];
			
			// Number
			[trackDictionary setObject:[NSNumber numberWithInteger:trackno] forKey:kMetadataTrackNumberKey];
			
			// ID
			if(!track->getId().empty())
				[trackDictionary setObject:[NSString stringWithCString:track->getId().c_str() encoding:NSUTF8StringEncoding] forKey:kMetadataMusicBrainzIDKey];
			
			// Track title
			[trackDictionary setObject:[NSString stringWithCString:track->getTitle().c_str() encoding:NSUTF8StringEncoding] forKey:kMetadataTitleKey];
			
			// Track artist
			if(NULL != track->getArtist() && !track->getArtist()->getName().empty())
				[trackDictionary setObject:[NSString stringWithCString:track->getArtist()->getName().c_str() encoding:NSUTF8StringEncoding] forKey:kMetadataArtistKey];
			
			// Look for Composer relations
			MusicBrainz::RelationList relations = track->getRelations(MusicBrainz::Relation::TO_TRACK);
			
			for(MusicBrainz::RelationList::iterator k = relations.begin(); k != relations.end(); ++k) {
				MusicBrainz::Relation *relation = *k;
				
				if("Composer" == MusicBrainz::extractFragment(relation->getType())) {
					if(MusicBrainz::Relation::TO_ARTIST == relation->getTargetType()) {
						MusicBrainz::Artist *composer = NULL;
						
						try {
							composer = q.getArtistById(relation->getTargetId());
							if(NULL == composer)
								continue;
						}
						
						catch(/* const MusicBrainz::Exception &e */ const std::exception &e) {
							NSLog(@"MusicBrainz error: %s", e.what());
							continue;
						}
						
						[trackDictionary setObject:[NSString stringWithCString:composer->getName().c_str() encoding:NSUTF8StringEncoding] forKey:kMetadataComposerKey];
						
						delete composer;
					}
				}				
			}
			
			++trackno;
			
			[tracksDictionary addObject:trackDictionary];
			delete track;
		}
		
		[releaseDictionary setObject:tracksDictionary forKey:kMusicDatabaseTracksKey];

		// Add the matching disc to the set of query results in a KVC-compliant manner
		NSIndexSet *insertionIndex = [NSIndexSet indexSetWithIndex:self.queryResults.count];
		[self willChange:NSKeyValueChangeInsertion valuesAtIndexes:insertionIndex forKey:@"queryResults"];
		[_queryResults addObject:releaseDictionary];
		[self didChange:NSKeyValueChangeInsertion valuesAtIndexes:insertionIndex forKey:@"queryResults"];
		
		delete result;
	}
	
	return YES;
}

@end
