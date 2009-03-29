/*
 *  Copyright (C) 2008 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import "MusicBrainzQueryOperation.h"
#import "MusicBrainzSettingsViewController.h"

#include <Security/Security.h>

#include <musicbrainz3/webservice.h>
#include <musicbrainz3/query.h>
#include <musicbrainz3/model.h>
#include <musicbrainz3/utils.h>

@interface MusicDatabaseQueryOperation ()
@property (assign) NSArray * queryResults;
@property (copy) NSError * error;
@end

@implementation MusicBrainzQueryOperation

- (void) main
{
	NSAssert(nil != self.musicBrainzDiscID, @"self.musicBrainzDiscID may not be nil");
	
	// Set up the MusicBrainz web service
	MusicBrainz::WebService *ws = new MusicBrainz::WebService();
	if(NULL == ws) {
		self.error = [NSError errorWithDomain:NSPOSIXErrorDomain code:ENOMEM userInfo:nil];
		return;
	}
	
	// Set MB server and port
	if([self.settings objectForKey:@"musicBrainzServer"])
		ws->setHost([[self.settings objectForKey:@"musicBrainzServer"] UTF8String]);
	
	if([self.settings objectForKey:@"musicBrainzServerPort"])
		ws->setPort((const int)[[self.settings objectForKey:@"musicBrainzServerPort"] integerValue]);
	
	// Use authentication, if specified
	if([self.settings objectForKey:@"musicBrainzUsername"]) {
		NSString *username = [self.settings objectForKey:@"musicBrainzUsername"];
		
		ws->setUserName([username UTF8String]);

		// Use KeyChain for password storage
		SecKeychainItemRef keychainItemRef = NULL;
		void *passwordData = NULL;
		UInt32 passwordLength = 0;

		const char *serviceNameUTF8 = [kMusicBrainzServiceName UTF8String];
		const char *usernameUTF8 = [username UTF8String];
		
		// Search for the item in the keychain
		OSStatus status = SecKeychainFindGenericPassword(NULL,
														 strlen(serviceNameUTF8),
														 serviceNameUTF8,
														 strlen(usernameUTF8),
														 usernameUTF8,
														 &passwordLength,
														 &passwordData,
														 &keychainItemRef);
		if(noErr == status) {
			NSString *password = [[NSString alloc] initWithBytes:passwordData length:passwordLength encoding:NSUTF8StringEncoding];
			ws->setPassword([password UTF8String]);
		}
		else if(errSecItemNotFound == status)
			;
		else
			;
		
		// Clean up
		status = SecKeychainItemFreeContent(NULL, passwordData);
		if(noErr != status)
			;
		
		if(keychainItemRef)
			CFRelease(keychainItemRef);			
	}
	
	
	// Proxy setup
	if([[self.settings objectForKey:@"musicBrainzUseProxy"] boolValue]) {
		if([self.settings objectForKey:@"musicBrainzProxyServer"])
			ws->setProxyHost([[self.settings objectForKey:@"musicBrainzProxyServer"] UTF8String]);
		if([self.settings objectForKey:@"musicBrainzProxyServerPort"])
			ws->setProxyPort((const int)[[self.settings objectForKey:@"musicBrainzProxyServerPort"] integerValue]);

		if([self.settings objectForKey:@"musicBrainzProxyUsername"]) {
			ws->setProxyUserName([[self.settings objectForKey:@"musicBrainzProxyUsername"] UTF8String]);
			
			if([self.settings objectForKey:@"musicBrainzProxyPassword"])
				ws->setProxyPassword([[self.settings objectForKey:@"musicBrainzProxyPassword"] UTF8String]);
		}
	}		

	MusicBrainz::Query q(ws);
	MusicBrainz::ReleaseResultList results;

	try {
		std::string discID = [self.musicBrainzDiscID cStringUsingEncoding:NSASCIIStringEncoding];
		MusicBrainz::ReleaseFilter f = MusicBrainz::ReleaseFilter().discId(discID);
        results = q.getReleases(&f);
	}
	
	catch(/* const MusicBrainz::Exception &e */const std::exception &e) {

#if DEBUG
		NSLog(@"MusicBrainz error: %s", e.what());
#endif

		self.error = [NSError errorWithDomain:NSPOSIXErrorDomain code:ENOMEM userInfo:nil];
		return;
	}
	
	NSMutableArray *matchingReleases = [[NSMutableArray alloc] init];
	
	for(MusicBrainz::ReleaseResultList::iterator i = results.begin(); i != results.end(); i++) {
		MusicBrainz::ReleaseResult *result = *i;
		MusicBrainz::Release *release;
		
		try {
			MusicBrainz::ReleaseIncludes includes = MusicBrainz::ReleaseIncludes().tracks().artist().releaseEvents();
			release = q.getReleaseById(result->getRelease()->getId(), &includes);
		}
		
		catch(/* const MusicBrainz::Exception &e */const std::exception &e) {

#if DEBUG
			NSLog(@"MusicBrainz error: %s", e.what());
#endif

			continue;
		}
		
		NSMutableDictionary *releaseDictionary = [NSMutableDictionary dictionary];
		
		// ID
		if(!release->getId().empty()) {
			NSURL *albumURI = [NSURL URLWithString:[NSString stringWithCString:release->getId().c_str() encoding:NSUTF8StringEncoding]];
			[releaseDictionary setObject:[[albumURI path] lastPathComponent] forKey:kMetadataMusicBrainzIDKey];
		}
		
		// Title
		if(!release->getTitle().empty())
			[releaseDictionary setObject:[NSString stringWithCString:release->getTitle().c_str() encoding:NSUTF8StringEncoding] forKey:kMetadataAlbumTitleKey];
		
		// Artist
		if(NULL != release->getArtist() && !release->getArtist()->getName().empty())
			[releaseDictionary setObject:[NSString stringWithCString:release->getArtist()->getName().c_str() encoding:NSUTF8StringEncoding] forKey:kMetadataAlbumArtistKey];
		
		// Take a best guess on the release date
		if(1 == release->getNumReleaseEvents()) {
			MusicBrainz::ReleaseEvent *releaseEvent = release->getReleaseEvent(0);
			[releaseDictionary setObject:[NSString stringWithCString:releaseEvent->getDate().c_str() encoding:NSUTF8StringEncoding] forKey:kMetadataReleaseDateKey];
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
					[releaseDictionary setObject:[NSString stringWithCString:releaseEvent->getDate().c_str() encoding:NSUTF8StringEncoding] forKey:kMetadataReleaseDateKey];
			}
			
			// Nothing matched, just take the first one
			if(nil == [releaseDictionary valueForKey:kMetadataReleaseDateKey] && 0 < release->getNumReleaseEvents()) {
				MusicBrainz::ReleaseEvent *releaseEvent = release->getReleaseEvent(0);
				[releaseDictionary setObject:[NSString stringWithCString:releaseEvent->getDate().c_str() encoding:NSUTF8StringEncoding] forKey:kMetadataReleaseDateKey];
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
			if(!track->getId().empty()) {
				NSURL *trackURI = [NSURL URLWithString:[NSString stringWithCString:track->getId().c_str() encoding:NSUTF8StringEncoding]];
				[trackDictionary setObject:[[trackURI path] lastPathComponent] forKey:kMetadataMusicBrainzIDKey];
			}
			
			// Track title
			[trackDictionary setObject:[NSString stringWithCString:track->getTitle().c_str() encoding:NSUTF8StringEncoding] forKey:kMetadataTitleKey];
			
			// Ensure the track's artist is set if an artist was retrieved from MusicBrainz
			if(NULL != track->getArtist() && !track->getArtist()->getName().empty())
				[trackDictionary setObject:[NSString stringWithCString:track->getArtist()->getName().c_str() encoding:NSUTF8StringEncoding] forKey:kMetadataArtistKey];
			else if(NULL != release->getArtist() && !release->getArtist()->getName().empty())
				[trackDictionary setObject:[NSString stringWithCString:release->getArtist()->getName().c_str() encoding:NSUTF8StringEncoding] forKey:kMetadataArtistKey];

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
		[matchingReleases addObject:releaseDictionary];

		delete result;
	}
	
	// Set the query results
	self.queryResults = matchingReleases;
}

@end
