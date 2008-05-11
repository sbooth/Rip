/*
 *  Copyright (C) 2008 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import "PreferencesWindowController.h"
#import "EncoderSettingsSheetController.h"
#import "EncoderManager.h"
#import "EncoderInterface/EncoderInterface.h"

@implementation PreferencesWindowController

- (id) init
{
	return [super initWithWindowNibName:@"PreferencesWindow"];
}

- (NSArray *) availableEncoders
{
	if(nil == _em)
		_em = [[EncoderManager alloc] init];

	NSMutableArray *encoders = [[NSMutableArray alloc] init];

	for(NSBundle *encoderBundle in _em.availableEncoders) {

		NSMutableDictionary *encoderDictionary = [[NSMutableDictionary alloc] init];

		NSString *encoderName = [encoderBundle objectForInfoDictionaryKey:@"EncoderName"];
		NSString *encoderVersion = [encoderBundle objectForInfoDictionaryKey:@"EncoderVersion"];
		NSString *encoderIconName = [encoderBundle objectForInfoDictionaryKey:@"EncoderIcon"];
		NSImage *encoderIcon = [NSImage imageNamed:encoderIconName];

		[encoderDictionary setObject:encoderBundle forKey:@"encoderBundle"];

		if(encoderName)
			[encoderDictionary setObject:encoderName forKey:@"encoderName"];
		if(encoderVersion)
			[encoderDictionary setObject:encoderVersion forKey:@"encoderVersion"];
		if(encoderIcon)
			[encoderDictionary setObject:encoderIcon forKey:@"encoderIcon"];			

		[encoders addObject:encoderDictionary];
	}
	
	return encoders;
}

- (IBAction) editEncoderSettings:(id)sender
{
	
#pragma unused(sender)

	// Determine which encoder bundle we are working with
	NSDictionary *encoderDictionary = [_arrayController.selectedObjects lastObject];	
	NSBundle *encoderBundle = [encoderDictionary objectForKey:@"encoderBundle"];

	// Instantiate the encoder interface
	id <EncoderInterface> encoderInterface = [[[encoderBundle principalClass] alloc] init];

	// Grab the encoder's settings dictionary
	NSDictionary *allEncoderSettings = [[NSUserDefaults standardUserDefaults] dictionaryForKey:@"encoderSettings"];
	NSString *bundleIdentifier = [encoderBundle bundleIdentifier];
	NSDictionary *encoderSettings = [allEncoderSettings objectForKey:bundleIdentifier];
	if(!encoderSettings)
		encoderSettings = [encoderInterface defaultSettings];

	// The encoder's view controller uses the representedObject property to hold the encoder settings
	NSViewController *encoderSettingsViewController = [encoderInterface configurationViewController];
	[encoderSettingsViewController setRepresentedObject:encoderSettings];

	// Create the sheet which will display the encoder settings and assign the encoder-specific view
	EncoderSettingsSheetController *encoderSettingsSheetController = [[EncoderSettingsSheetController alloc] init];
	encoderSettingsSheetController.settingsViewController = encoderSettingsViewController;
	
	// Show the sheet
	[[NSApplication sharedApplication] beginSheet:encoderSettingsSheetController.window
								   modalForWindow:self.window
									modalDelegate:self
								   didEndSelector:@selector(encoderSettingsSheetDidEnd:returnCode:contextInfo:)
									  contextInfo:encoderSettingsSheetController];
}

@end

@implementation PreferencesWindowController (Private)

- (void) encoderSettingsSheetDidEnd:(NSWindow *)sheet returnCode:(int)returnCode contextInfo:(void *)contextInfo
{
	NSParameterAssert(nil != sheet);
	NSParameterAssert(NULL != contextInfo);
	
	[sheet orderOut:self];
	
	EncoderSettingsSheetController *encoderSettingsSheetController = (EncoderSettingsSheetController *)contextInfo;
	
	// Don't save settings if the cancel button was pressed
	if(NSCancelButton == returnCode)
		return;
	
	// Determine which encoder plug-in bundle the settings belong to
	NSDictionary *encoderSettings = encoderSettingsSheetController.settingsViewController.representedObject;
	NSBundle *encoderBundle = [NSBundle bundleForClass:[encoderSettingsSheetController.settingsViewController class]];
	
	// Replace only the relevant encoder's settings in the defaults
	NSMutableDictionary *allEncoderSettings = [[[NSUserDefaults standardUserDefaults] dictionaryForKey:@"encoderSettings"] mutableCopy];
	if(!allEncoderSettings)
		allEncoderSettings = [NSMutableDictionary dictionary];
	
	[allEncoderSettings setObject:encoderSettings forKey:[encoderBundle bundleIdentifier]];
	[[NSUserDefaults standardUserDefaults] setObject:allEncoderSettings forKey:@"encoderSettings"];
}

@end
