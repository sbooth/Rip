/*
 *  Copyright (C) 2008 - 2009 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import "MusicDatabasePreferencesViewController.h"
#import "NSViewController+PreferencesViewControllerMethods.h"
#import "MusicDatabaseManager.h"
#import "MusicDatabaseInterface/MusicDatabaseInterface.h"

#define USE_ANIMATION 0
#define TRANSITION_ANIMATION_DURATION 0.125

@implementation MusicDatabasePreferencesViewController

- (id) init
{
	if((self = [super initWithNibName:@"MusicDatabasePreferencesView" bundle:nil]))
		self.title = NSLocalizedString(@"Metadata", @"The name of the music databases preference pane");
	
	return self;
}

- (void) awakeFromNib
{
	// Determine the default music database
	NSBundle *bundle = [[MusicDatabaseManager sharedMusicDatabaseManager] defaultMusicDatabase];	
	NSPredicate *predicate = [NSPredicate predicateWithFormat:@"musicDatabaseBundle == %@", bundle];
	NSArray *matchingBundles = [_musicDatabaseArrayController.arrangedObjects filteredArrayUsingPredicate:predicate];
	
	if(matchingBundles)
		[_musicDatabaseArrayController setSelectedObjects:matchingBundles];

	// Determine which music database bundle we are working with
	NSDictionary *musicDatabaseDictionary = [_musicDatabaseArrayController.selectedObjects lastObject];	
	NSBundle *musicDatabaseBundle = [musicDatabaseDictionary objectForKey:@"musicDatabaseBundle"];
	
	// If the bundle wasn't found, display an appropriate error
	if(!musicDatabaseBundle) {
		NSError *missingBundleError = [NSError errorWithDomain:NSCocoaErrorDomain code:ENOENT userInfo:nil];
		[[NSApplication sharedApplication] presentError:missingBundleError];
		return;
	}
	
	MusicDatabaseManager *musicDatabaseManager = [MusicDatabaseManager sharedMusicDatabaseManager];
	
	Class musicDatabaseClass = [musicDatabaseBundle principalClass];
	NSObject <MusicDatabaseInterface> *musicDatabaseInterface = [[musicDatabaseClass alloc] init];
	
	// The musicDatabase's view controller uses the representedObject property to hold the musicDatabase settings
	_musicDatabaseSettingsViewController = [musicDatabaseInterface configurationViewController];
	
	NSDictionary *musicDatabaseSettings = [musicDatabaseManager settingsForMusicDatabase:musicDatabaseBundle];
	[_musicDatabaseSettingsViewController setRepresentedObject:[musicDatabaseSettings mutableCopy]];
	
	// Adjust two view sizes to accomodate the musicDatabase's settings view:
	//  1. The frame belonging to self.view
	//  2. The frame belonging to _musicDatabaseSettingsView
	
	// Calculate the difference between the current and target musicDatabase settings view sizes
	NSRect currentMusicDatabaseSettingsViewFrame = [_musicDatabaseSettingsView frame];
	NSRect targetMusicDatabaseSettingsViewFrame = [_musicDatabaseSettingsViewController.view frame];
	
	// The frames of both views will be adjusted by the following dimensions
	CGFloat viewDeltaX = targetMusicDatabaseSettingsViewFrame.size.width - currentMusicDatabaseSettingsViewFrame.size.width;
	CGFloat viewDeltaY = targetMusicDatabaseSettingsViewFrame.size.height - currentMusicDatabaseSettingsViewFrame.size.height;
	
	NSRect newMusicDatabaseSettingsViewFrame = currentMusicDatabaseSettingsViewFrame;
	
	newMusicDatabaseSettingsViewFrame.size.width += viewDeltaX;
	newMusicDatabaseSettingsViewFrame.size.height += viewDeltaY;
	
	NSRect currentViewFrame = [self.view frame];
	NSRect newViewFrame = currentViewFrame;
	
	newViewFrame.size.width += viewDeltaX;
	newViewFrame.size.height += viewDeltaY;
	
	// Set the new sizes
	[self.view setFrame:newViewFrame];
	[_musicDatabaseSettingsView setFrame:newMusicDatabaseSettingsViewFrame];
	
	// Now that the sizes are correct, add the view controller's view to the view hierarchy
	[_musicDatabaseSettingsView addSubview:_musicDatabaseSettingsViewController.view];
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
	
	// If the bundle wasn't found, display an appropriate error
	if(!musicDatabaseBundle) {
		NSError *missingBundleError = [NSError errorWithDomain:NSCocoaErrorDomain code:ENOENT userInfo:nil];
		[[NSApplication sharedApplication] presentError:missingBundleError];
		return;
	}
	
	MusicDatabaseManager *musicDatabaseManager = [MusicDatabaseManager sharedMusicDatabaseManager];
	
	// Remove any musicDatabase settings subviews that are currently being displayed and save the settings
	if(_musicDatabaseSettingsViewController) {
		
#if USE_ANIMATION
		NSMutableDictionary *fadeOutAnimationDictionary = [NSMutableDictionary dictionary];
		
		[fadeOutAnimationDictionary setObject:_musicDatabaseSettingsViewController.view forKey:NSViewAnimationTargetKey];
        [fadeOutAnimationDictionary setObject:NSViewAnimationFadeOutEffect forKey:NSViewAnimationEffectKey];
		
		NSViewAnimation *fadeOutAnimation = [[NSViewAnimation alloc] initWithViewAnimations:[NSArray arrayWithObject:fadeOutAnimationDictionary]];
		
		[fadeOutAnimation setDuration:TRANSITION_ANIMATION_DURATION];
		[fadeOutAnimation setAnimationCurve:NSAnimationEaseIn];
		[fadeOutAnimation setAnimationBlockingMode:NSAnimationBlocking];
		
		[fadeOutAnimation startAnimation];
#endif
		
		[_musicDatabaseSettingsViewController.view removeFromSuperview];
		
		[self savePreferences:sender];
	}
	
	// The newly selected musicDatabase is now the default
	musicDatabaseManager.defaultMusicDatabase = musicDatabaseBundle;
	
	Class musicDatabaseClass = [musicDatabaseBundle principalClass];
	NSObject <MusicDatabaseInterface> *musicDatabaseInterface = [[musicDatabaseClass alloc] init];
	
	_musicDatabaseSettingsViewController = [musicDatabaseInterface configurationViewController];
	
	// Some musicDatabases may not allow user configuration
	if(!_musicDatabaseSettingsViewController) {
		NSLog(@"nil NSViewController subclasses aren't currently supported!");
	}
	
	// The musicDatabase's view controller uses the representedObject property to hold the musicDatabase settings
	NSDictionary *musicDatabaseSettings = [musicDatabaseManager settingsForMusicDatabase:musicDatabaseBundle];
	[_musicDatabaseSettingsViewController setRepresentedObject:[musicDatabaseSettings mutableCopy]];
	
	// Adjust three view sizes to accomodate the musicDatabase's settings view:
	//  1. The frame belonging to self.view
	//  2. The frame belonging to _musicDatabaseSettingsView
	//  3. The enclosing window's frame
	
	// Calculate the difference between the current and target musicDatabase settings view sizes
	NSRect currentMusicDatabaseSettingsViewFrame = [_musicDatabaseSettingsView frame];
	NSRect targetMusicDatabaseSettingsViewFrame = [_musicDatabaseSettingsViewController.view frame];
	
	// The frames of all views will be adjusted by the following dimensions
	CGFloat viewDeltaX = targetMusicDatabaseSettingsViewFrame.size.width - currentMusicDatabaseSettingsViewFrame.size.width;
	CGFloat viewDeltaY = targetMusicDatabaseSettingsViewFrame.size.height - currentMusicDatabaseSettingsViewFrame.size.height;
	
	// Calculate the new window and view sizes
	NSRect currentWindowFrame = [[[self view] window] frame];
	NSRect newWindowFrame = currentWindowFrame;
	
	newWindowFrame.origin.x -= viewDeltaX / 2;
	newWindowFrame.origin.y -= viewDeltaY;
	newWindowFrame.size.width += viewDeltaX;
	newWindowFrame.size.height += viewDeltaY;
	
	NSRect newMusicDatabaseSettingsViewFrame = currentMusicDatabaseSettingsViewFrame;
	
	newMusicDatabaseSettingsViewFrame.size.width += viewDeltaX;
	newMusicDatabaseSettingsViewFrame.size.height += viewDeltaY;
	
	NSRect currentViewFrame = [self.view frame];
	NSRect newViewFrame = currentViewFrame;
	
	newViewFrame.size.width += viewDeltaX;
	newViewFrame.size.height += viewDeltaY;
	
	// Set the new sizes
	[[[self view] window] setFrame:newWindowFrame display:YES animate:YES];
	[self.view setFrame:newViewFrame];
	[_musicDatabaseSettingsView setFrame:newMusicDatabaseSettingsViewFrame];
	
	// Now that the sizes are correct, add the view controller's view to the view hierarchy
	[_musicDatabaseSettingsView addSubview:_musicDatabaseSettingsViewController.view];
	
#if USE_ANIMATION
	NSMutableDictionary *fadeInAnimationDictionary = [NSMutableDictionary dictionary];
	
	[fadeInAnimationDictionary setObject:_musicDatabaseSettingsViewController.view forKey:NSViewAnimationTargetKey];	 
	[fadeInAnimationDictionary setObject:NSViewAnimationFadeInEffect forKey:NSViewAnimationEffectKey];
	
	NSViewAnimation *fadeInAnimation = [[NSViewAnimation alloc] initWithViewAnimations:[NSArray arrayWithObject:fadeInAnimationDictionary]];
	
	[fadeInAnimation setDuration:TRANSITION_ANIMATION_DURATION];
	[fadeInAnimation setAnimationCurve:NSAnimationEaseIn];
	
	[fadeInAnimation startAnimation];
#endif
}

@end

@implementation MusicDatabasePreferencesViewController (PreferencesViewControllerMethods)

- (IBAction) restoreDefaults:(id)sender
{
	
#pragma unused (sender)
	
	// Determine which musicDatabase bundle we are working with
	NSDictionary *musicDatabaseDictionary = [_musicDatabaseArrayController.selectedObjects lastObject];	
	NSBundle *musicDatabaseBundle = [musicDatabaseDictionary objectForKey:@"musicDatabaseBundle"];
	
	// If the bundle wasn't found, display an appropriate error
	if(!musicDatabaseBundle) {
		NSError *missingBundleError = [NSError errorWithDomain:NSCocoaErrorDomain code:ENOENT userInfo:nil];
		[[NSApplication sharedApplication] presentError:missingBundleError];
		return;
	}
	
	MusicDatabaseManager *musicDatabaseManager = [MusicDatabaseManager sharedMusicDatabaseManager];
	[musicDatabaseManager restoreDefaultSettingsForMusicDatabase:musicDatabaseBundle];
	
	NSDictionary *musicDatabaseSettings = [musicDatabaseManager settingsForMusicDatabase:musicDatabaseBundle];
	[_musicDatabaseSettingsViewController setRepresentedObject:[musicDatabaseSettings mutableCopy]];
}

- (IBAction) savePreferences:(id)sender
{
	
#pragma unused (sender)
	
	MusicDatabaseManager *musicDatabaseManager = [MusicDatabaseManager sharedMusicDatabaseManager];
	musicDatabaseManager.defaultMusicDatabaseSettings = _musicDatabaseSettingsViewController.representedObject;
	
	// Allow PlugIns to store data elsewhere besides user defaults
	if([_musicDatabaseSettingsViewController respondsToSelector:@selector(savePreferences:)])
		[_musicDatabaseSettingsViewController savePreferences:sender];
}

@end
