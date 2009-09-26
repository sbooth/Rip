/*
 *  Copyright (C) 2008 - 2009 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import "MusicBrainzSettingsViewController.h"
#import "MusicBrainzDatabaseInterface.h"

#include <Security/Security.h>

NSString * const	kMusicBrainzServiceName					= @"MusicBrainz";

@implementation MusicBrainzSettingsViewController

- (id) init
{
	return [super initWithNibName:@"MusicBrainzSettings" bundle:[NSBundle bundleWithIdentifier:@"org.sbooth.Rip.MusicDatabase.MusicBrainz"]];
}

- (void) awakeFromNib
{
	SecKeychainItemRef keychainItemRef = NULL;
	void *passwordData = NULL;
	UInt32 passwordLength = 0;

	NSString *username = [self.representedObject objectForKey:@"musicBrainzUsername"];
	
	// If no username is set, the password can't be retrieved
	if(!username)
		return;
	
	const char *serviceNameUTF8 = [kMusicBrainzServiceName UTF8String];
	const char *usernameUTF8 = [username UTF8String];
	
	// Search for the item in the keychain
	OSStatus status = SecKeychainFindGenericPassword(NULL,
													 (UInt32)strlen(serviceNameUTF8),
													 serviceNameUTF8,
													 (UInt32)strlen(usernameUTF8),
													 usernameUTF8,
													 &passwordLength,
													 &passwordData,
													 &keychainItemRef);
	if(noErr == status) {
		NSString *password = [[NSString alloc] initWithBytes:passwordData length:passwordLength encoding:NSUTF8StringEncoding];
		[_musicBrainzPasswordTextField setStringValue:password];
	}
	
	// Clean up
	/*status = */SecKeychainItemFreeContent(NULL, passwordData);
	
	if(keychainItemRef)
		CFRelease(keychainItemRef), keychainItemRef = NULL;
}

@end

@implementation MusicBrainzSettingsViewController (PreferencesViewControllerMethods)

- (IBAction) savePreferences:(id)sender
{
	
#pragma unused (sender)

	NSString *username = [self.representedObject objectForKey:@"musicBrainzUsername"];

	// If no username is set, the password can't be stored
	if(!username)
		return;
	
	NSString *password = [_musicBrainzPasswordTextField stringValue];

	const char *serviceNameUTF8 = [kMusicBrainzServiceName UTF8String];
	const char *usernameUTF8 = [username UTF8String];
	const char *passwordUTF8 = [password UTF8String];
	
	SecKeychainItemRef keychainItemRef = NULL;

	// Search for the item in the keychain
	OSStatus status = SecKeychainFindGenericPassword(NULL,
													 (UInt32)strlen(serviceNameUTF8),
													 serviceNameUTF8,
													 (UInt32)strlen(usernameUTF8),
													 usernameUTF8,
													 NULL,
													 NULL,
													 &keychainItemRef);
	
	// If the item wasn't found, store it
	if(errSecItemNotFound == status) {		
		/*status = */SecKeychainAddGenericPassword(NULL,
												   (UInt32)strlen(serviceNameUTF8),
												   serviceNameUTF8,
												   (UInt32)strlen(usernameUTF8),
												   usernameUTF8,
												   (UInt32)strlen(passwordUTF8), 
												   passwordUTF8, 
												   &keychainItemRef);
	}
	// Otherwise, update the password
	else if(noErr == status) {
		/*status = */SecKeychainItemModifyAttributesAndData(keychainItemRef,
															NULL,
															(UInt32)strlen(passwordUTF8), 
															passwordUTF8);
	}
	
	// Clean up
	if(keychainItemRef)
		CFRelease(keychainItemRef), keychainItemRef = NULL;
}

@end
