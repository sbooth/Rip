/*
 *  Copyright (C) 2008 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import "FreeDBSettingsViewController.h"
#import "FreeDBDatabaseInterface.h"

#include <Security/Security.h>
#include <cddb/cddb.h>

NSString * const	kFreeDBServiceName						= @"FreeDB";

@implementation FreeDBSettingsViewController

- (id) init
{
	return [super initWithNibName:@"FreeDBSettings" bundle:[NSBundle bundleForClass:[FreeDBDatabaseInterface class]]];
}

- (void) awakeFromNib
{
	SecKeychainItemRef keychainItemRef = NULL;
	void *passwordData = NULL;
	UInt32 passwordLength = 0;
	
	NSString *username = [self.representedObject objectForKey:@"freeDBUsername"];
	
	// If no username is set, the password can't be retrieved
	if(!username)
		return;
	
	const char *serviceNameUTF8 = [kFreeDBServiceName UTF8String];
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
		[_freeDBPasswordTextField setStringValue:password];
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

@end

@implementation FreeDBSettingsViewController (PreferencesViewControllerMethods)

- (IBAction) savePreferences:(id)sender
{
	
#pragma unused (sender)
	
	NSString *username = [self.representedObject objectForKey:@"freeDBUsername"];
	
	// If no username is set, the password can't be stored
	if(!username)
		return;
	
	NSString *password = [_freeDBPasswordTextField stringValue];
	
	const char *serviceNameUTF8 = [kFreeDBServiceName UTF8String];
	const char *usernameUTF8 = [username UTF8String];
	const char *passwordUTF8 = [password UTF8String];
	
	SecKeychainItemRef keychainItemRef = NULL;
	
	// Search for the item in the keychain
	OSStatus status = SecKeychainFindGenericPassword(NULL,
													 strlen(serviceNameUTF8),
													 serviceNameUTF8,
													 strlen(usernameUTF8),
													 usernameUTF8,
													 NULL,
													 NULL,
													 &keychainItemRef);
	
	// If the item wasn't found, store it
	if(errSecItemNotFound == status) {		
		status = SecKeychainAddGenericPassword(NULL,
											   strlen(serviceNameUTF8),
											   serviceNameUTF8,
											   strlen(usernameUTF8),
											   usernameUTF8,
											   strlen(passwordUTF8), 
											   passwordUTF8, 
											   &keychainItemRef);
		if(noErr != status)
			;
	}
	// Otherwise, update the password
	else if(noErr == status) {
		status = SecKeychainItemModifyAttributesAndData(keychainItemRef,
														NULL,
														strlen(passwordUTF8), 
														passwordUTF8);
	}
	else {
		
	}
	
	// Clean up
	if(keychainItemRef)
		CFRelease(keychainItemRef);
}

@end
