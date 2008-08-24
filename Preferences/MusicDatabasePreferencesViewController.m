/*
 *  Copyright (C) 2008 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import "MusicDatabasePreferencesViewController.h"
#import "MusicDatabaseManager.h"
#import "MusicDatabaseInterface/MusicDatabaseInterface.h"
#import "EncoderSettingsSheetController.h"

@implementation MusicDatabasePreferencesViewController

- (id) init
{
	return [super initWithNibName:@"MusicDatabasePreferencesView" bundle:nil];
}

- (void) awakeFromNib
{
	// Determine the default music database
	NSBundle *bundle = [[MusicDatabaseManager sharedMusicDatabaseManager] defaultMusicDatabase];	
	NSPredicate *predicate = [NSPredicate predicateWithFormat:@"musicDatabaseBundle == %@", bundle];
	NSArray *matchingBundles = [_musicDatabaseArrayController.arrangedObjects filteredArrayUsingPredicate:predicate];
	
	if(matchingBundles)
		[_musicDatabaseArrayController setSelectedObjects:matchingBundles];
}

- (NSArray *) availableMusicDatabases
{
	MusicDatabaseManager *musicDatabaseManager = [MusicDatabaseManager sharedMusicDatabaseManager];
	
	NSMutableArray *musicDatabases = [[NSMutableArray alloc] init];
	
	for(NSBundle *musicDatabaseBundle in musicDatabaseManager.availableMusicDatabases) {
		
		NSMutableDictionary *musicDatabaseDictionary = [[NSMutableDictionary alloc] init];
		
		NSString *musicDatabaseName = [musicDatabaseBundle objectForInfoDictionaryKey:@"MusicDatabaseName"];
		//		NSString *musicDatabaseIconName = [musicDatabaseBundle objectForInfoDictionaryKey:@"MusicDatabaseIcon"];
		//		NSImage *musicDatabaseIcon = [NSImage imageNamed:musicDatabaseIconName];
		
		[musicDatabaseDictionary setObject:musicDatabaseBundle forKey:@"musicDatabaseBundle"];
		
		if(musicDatabaseName)
			[musicDatabaseDictionary setObject:musicDatabaseName forKey:@"musicDatabaseName"];
		//		if(musicDatabaseIcon)
		//			[musicDatabaseDictionary setObject:musicDatabaseIcon forKey:@"musicDatabaseIcon"];			
		
		[musicDatabases addObject:musicDatabaseDictionary];
	}
	
	return musicDatabases;
}

- (IBAction) selectDefaultMusicDatabase:(id)sender
{
	
#pragma unused(sender)
	
	// Determine which music database bundle we are working with
	NSDictionary *musicDatabaseDictionary = [_musicDatabaseArrayController.selectedObjects lastObject];	
	NSBundle *musicDatabaseBundle = [musicDatabaseDictionary objectForKey:@"musicDatabaseBundle"];
	
	MusicDatabaseManager *musicDatabaseManager = [MusicDatabaseManager sharedMusicDatabaseManager];
	musicDatabaseManager.defaultMusicDatabase = musicDatabaseBundle;	
}

- (IBAction) editMusicDatabaseSettings:(id)sender
{
	
#pragma unused(sender)
	
	// Determine which music database bundle we are working with
	NSDictionary *musicDatabaseDictionary = [_musicDatabaseArrayController.selectedObjects lastObject];	
	NSBundle *musicDatabaseBundle = [musicDatabaseDictionary objectForKey:@"musicDatabaseBundle"];
	
	// Instantiate the music database interface
	id <MusicDatabaseInterface> musicDatabaseInterface = [[[musicDatabaseBundle principalClass] alloc] init];
	
	// Grab the music database's settings dictionary
	NSDictionary *musicDatabaseSettings = [[MusicDatabaseManager sharedMusicDatabaseManager] settingsForMusicDatabase:musicDatabaseBundle];
	
	// The music database's view controller uses the representedObject property to hold the music database settings
	NSViewController *musicDatabaseSettingsViewController = [musicDatabaseInterface configurationViewController];
	[musicDatabaseSettingsViewController setRepresentedObject:[musicDatabaseSettings mutableCopy]];
	
	// If there is nothing to configure, avoid showing an empty window
	if(!musicDatabaseSettingsViewController) {
		NSBeep();
		return;
	}
	
	// Create the sheet which will display the encoder settings and assign the encoder-specific view
	EncoderSettingsSheetController *musicDatabaseSettingsSheetController = [[EncoderSettingsSheetController alloc] init];
	musicDatabaseSettingsSheetController.settingsViewController = musicDatabaseSettingsViewController;
	
	// Show the sheet
	[[NSApplication sharedApplication] beginSheet:musicDatabaseSettingsSheetController.window
								   modalForWindow:[[self view] window]
									modalDelegate:self
								   didEndSelector:@selector(encoderSettingsSheetDidEnd:returnCode:contextInfo:)
									  contextInfo:musicDatabaseSettingsSheetController];
}

@end

@implementation MusicDatabasePreferencesViewController (Callbacks)

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
