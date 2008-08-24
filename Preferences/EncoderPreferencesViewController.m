/*
 *  Copyright (C) 2008 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import "EncoderPreferencesViewController.h"
#import "EncoderSettingsSheetController.h"
#import "EncoderManager.h"
#import "EncoderInterface/EncoderInterface.h"

@implementation EncoderPreferencesViewController

- (id) init
{
	return [super initWithNibName:@"EncoderPreferencesView" bundle:nil];
}

- (void) awakeFromNib
{
	// Determine the default encoder
	NSString *bundleIdentifier = [[NSUserDefaults standardUserDefaults] stringForKey:@"defaultEncoder"];
	NSBundle *bundle = [NSBundle bundleWithIdentifier:bundleIdentifier];
	
	// Ensure it is the selected object
	NSPredicate *predicate = [NSPredicate predicateWithFormat:@"encoderBundle == %@", bundle];
	NSArray *matchingBundles = [_encoderArrayController.arrangedObjects filteredArrayUsingPredicate:predicate];
	
	if(matchingBundles)
		[_encoderArrayController setSelectedObjects:matchingBundles];	
}

- (NSArray *) availableEncoders
{
	EncoderManager *encoderManager = [EncoderManager sharedEncoderManager];
	
	NSMutableArray *encoders = [[NSMutableArray alloc] init];
	
	for(NSBundle *encoderBundle in encoderManager.availableEncoders) {
		
		NSMutableDictionary *encoderDictionary = [[NSMutableDictionary alloc] init];
		
		NSString *encoderName = [encoderBundle objectForInfoDictionaryKey:@"EncoderName"];
		NSString *encoderVersion = [encoderBundle objectForInfoDictionaryKey:@"EncoderVersion"];
		//		NSString *encoderIconName = [encoderBundle objectForInfoDictionaryKey:@"EncoderIcon"];
		//		NSImage *encoderIcon = [NSImage imageNamed:encoderIconName];
		
		[encoderDictionary setObject:encoderBundle forKey:@"encoderBundle"];
		
		if(encoderName)
			[encoderDictionary setObject:encoderName forKey:@"encoderName"];
		if(encoderVersion)
			[encoderDictionary setObject:encoderVersion forKey:@"encoderVersion"];
		//		if(encoderIcon)
		//			[encoderDictionary setObject:encoderIcon forKey:@"encoderIcon"];			
		
		[encoders addObject:encoderDictionary];
	}
	
	return encoders;
}

- (IBAction) selectDefaultEncoder:(id)sender
{
	
#pragma unused(sender)
	
	// Determine which encoder bundle we are working with
	NSDictionary *encoderDictionary = [_encoderArrayController.selectedObjects lastObject];	
	NSBundle *encoderBundle = [encoderDictionary objectForKey:@"encoderBundle"];
	NSString *bundleIdentifier = [encoderBundle bundleIdentifier];
	
	// Set this as the default encoder
	[[NSUserDefaults standardUserDefaults] setObject:bundleIdentifier forKey:@"defaultEncoder"];
	
	// If no settings are present for this encoder, store the defaults
	if(![[NSUserDefaults standardUserDefaults] dictionaryForKey:bundleIdentifier]) {
		// Instantiate the encoder interface
		id <EncoderInterface> encoderInterface = [[[encoderBundle principalClass] alloc] init];
		
		// Grab the encoder's settings dictionary
		[[NSUserDefaults standardUserDefaults] setObject:[encoderInterface defaultSettings] forKey:bundleIdentifier];
	}
}

- (IBAction) editEncoderSettings:(id)sender
{
	
#pragma unused(sender)
	
	// Determine which encoder bundle we are working with
	NSDictionary *encoderDictionary = [_encoderArrayController.selectedObjects lastObject];	
	NSBundle *encoderBundle = [encoderDictionary objectForKey:@"encoderBundle"];
	
	// Instantiate the encoder interface
	id <EncoderInterface> encoderInterface = [[[encoderBundle principalClass] alloc] init];
	
	// Grab the encoder's settings dictionary
	NSString *bundleIdentifier = [encoderBundle bundleIdentifier];
	NSDictionary *encoderSettings = [[NSUserDefaults standardUserDefaults] dictionaryForKey:bundleIdentifier];
	if(!encoderSettings)
		encoderSettings = [encoderInterface defaultSettings];
	
	// The encoder's view controller uses the representedObject property to hold the encoder settings
	NSViewController *encoderSettingsViewController = [encoderInterface configurationViewController];
	[encoderSettingsViewController setRepresentedObject:[encoderSettings mutableCopy]];
	
	// If there is nothing to configure, avoid showing an empty window
	if(!encoderSettingsViewController) {
		NSBeep();
		return;
	}
	
	// Create the sheet which will display the encoder settings and assign the encoder-specific view
	EncoderSettingsSheetController *encoderSettingsSheetController = [[EncoderSettingsSheetController alloc] init];
	encoderSettingsSheetController.settingsViewController = encoderSettingsViewController;
	
	// Show the sheet
	[[NSApplication sharedApplication] beginSheet:encoderSettingsSheetController.window
								   modalForWindow:[[self view] window]
									modalDelegate:self
								   didEndSelector:@selector(encoderSettingsSheetDidEnd:returnCode:contextInfo:)
									  contextInfo:encoderSettingsSheetController];
}

@end

@implementation EncoderPreferencesViewController (Callbacks)

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
	NSString *bundleIdentifier = [encoderBundle bundleIdentifier];
	
	// Replace only the relevant encoder's settings in the defaults
	[[NSUserDefaults standardUserDefaults] setObject:encoderSettings forKey:bundleIdentifier];
}

@end
