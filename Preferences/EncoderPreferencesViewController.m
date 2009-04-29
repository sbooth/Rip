/*
 *  Copyright (C) 2008 - 2009 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import "EncoderPreferencesViewController.h"
#import "NSViewController+PreferencesViewControllerMethods.h"
#import "EncoderManager.h"
#import "EncoderInterface/EncoderInterface.h"

#define TRANSITION_ANIMATION_DURATION 0.15

@implementation EncoderPreferencesViewController

- (id) init
{
	if((self = [super initWithNibName:@"EncoderPreferencesView" bundle:nil]))
		self.title = NSLocalizedString(@"Encoders", @"The name of the encoders preference pane");
	
	return self;
}

- (void) awakeFromNib
{
	// Determine the default encoder
	NSBundle *bundle = [[EncoderManager sharedEncoderManager] defaultEncoder];	
	NSPredicate *predicate = [NSPredicate predicateWithFormat:@"encoderBundle == %@", bundle];
	NSArray *matchingBundles = [_encoderArrayController.arrangedObjects filteredArrayUsingPredicate:predicate];
	
	if(matchingBundles)
		[_encoderArrayController setSelectedObjects:matchingBundles];
	
	// Determine which encoder bundle we are working with
	NSDictionary *encoderDictionary = [_encoderArrayController.selectedObjects lastObject];	
	NSBundle *encoderBundle = [encoderDictionary objectForKey:@"encoderBundle"];
	
	// If the bundle wasn't found, display an appropriate error
	if(!encoderBundle) {
		NSError *missingBundleError = [NSError errorWithDomain:NSCocoaErrorDomain code:ENOENT userInfo:nil];
		[[NSApplication sharedApplication] presentError:missingBundleError];
		return;
	}
	
	EncoderManager *encoderManager = [EncoderManager sharedEncoderManager];
	
	Class encoderClass = [encoderBundle principalClass];
	NSObject <EncoderInterface> *encoderInterface = [[encoderClass alloc] init];
	
	// The encoder's view controller uses the representedObject property to hold the encoder settings
	_encoderSettingsViewController = [encoderInterface configurationViewController];
	
	NSDictionary *encoderSettings = [encoderManager settingsForEncoder:encoderBundle];
	[_encoderSettingsViewController setRepresentedObject:[encoderSettings mutableCopy]];
	
	// Adjust two view sizes to accomodate the encoder's settings view:
	//  1. The frame belonging to [self view]
	//  2. The frame belonging to _encoderSettingsView
	
	// Calculate the difference between the current and target encoder settings view sizes
	NSRect currentEncoderSettingsViewFrame = [_encoderSettingsView frame];
	NSRect targetEncoderSettingsViewFrame = [[_encoderSettingsViewController view] frame];
	
	// The frames of both views will be adjusted by the following dimensions
	CGFloat viewDeltaX = targetEncoderSettingsViewFrame.size.width - currentEncoderSettingsViewFrame.size.width;
	CGFloat viewDeltaY = targetEncoderSettingsViewFrame.size.height - currentEncoderSettingsViewFrame.size.height;
	
	NSRect newEncoderSettingsViewFrame = currentEncoderSettingsViewFrame;
	
	newEncoderSettingsViewFrame.size.width += viewDeltaX;
	newEncoderSettingsViewFrame.size.height += viewDeltaY;
	
	NSRect currentViewFrame = [[self view] frame];
	NSRect newViewFrame = currentViewFrame;
	
	newViewFrame.size.width += viewDeltaX;
	newViewFrame.size.height += viewDeltaY;
	
	// Set the new sizes
	[[self view] setFrame:newViewFrame];
	[_encoderSettingsView setFrame:newEncoderSettingsViewFrame];
	
	// Now that the sizes are correct, add the view controller's view to the view hierarchy
	[_encoderSettingsView addSubview:[_encoderSettingsViewController view]];
}

- (NSArray *) availableEncoders
{
	EncoderManager *encoderManager = [EncoderManager sharedEncoderManager];
	
	NSMutableArray *encoders = [[NSMutableArray alloc] init];
	
	for(NSBundle *encoderBundle in encoderManager.availableEncoders) {
		
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

- (IBAction) selectDefaultEncoder:(id)sender
{
	
#pragma unused(sender)
		
	// Determine which encoder bundle we are working with
	NSDictionary *encoderDictionary = [_encoderArrayController.selectedObjects lastObject];	
	NSBundle *encoderBundle = [encoderDictionary objectForKey:@"encoderBundle"];
	
	// If the bundle wasn't found, display an appropriate error
	if(!encoderBundle) {
		NSError *missingBundleError = [NSError errorWithDomain:NSCocoaErrorDomain code:ENOENT userInfo:nil];
		[[NSApplication sharedApplication] presentError:missingBundleError];
		return;
	}

	EncoderManager *encoderManager = [EncoderManager sharedEncoderManager];
	
	// Remove any encoder settings subviews that are currently being displayed and save the settings
	if(_encoderSettingsViewController) {

#if USE_ANIMATION
		NSDictionary *fadeOutAnimationDictionary = [NSDictionary dictionaryWithObjectsAndKeys:
													[_encoderSettingsViewController view], NSViewAnimationTargetKey,
													NSViewAnimationFadeOutEffect, NSViewAnimationEffectKey,
													nil];
		
		NSViewAnimation *fadeOutAnimation = [[NSViewAnimation alloc] initWithViewAnimations:[NSArray arrayWithObject:fadeOutAnimationDictionary]];
		
		[fadeOutAnimation setDuration:TRANSITION_ANIMATION_DURATION];
		[fadeOutAnimation setAnimationCurve:NSAnimationEaseIn];
		[fadeOutAnimation setAnimationBlockingMode:NSAnimationBlocking];
		
		[fadeOutAnimation startAnimation];
		
		[[_encoderSettingsViewController view] removeFromSuperviewWithoutNeedingDisplay];
#else
		[[_encoderSettingsViewController view] removeFromSuperview];
#endif
				
		[self savePreferences:sender];
	}

	// The newly selected encoder is now the default
	encoderManager.defaultEncoder = encoderBundle;
	
	Class encoderClass = [encoderBundle principalClass];
	NSObject <EncoderInterface> *encoderInterface = [[encoderClass alloc] init];

	_encoderSettingsViewController = [encoderInterface configurationViewController];

	// Some encoders may not allow user configuration
	if(!_encoderSettingsViewController) {
		NSLog(@"nil NSViewController subclasses aren't currently supported!");
	}

	// The encoder's view controller uses the representedObject property to hold the encoder settings
	NSDictionary *encoderSettings = [encoderManager settingsForEncoder:encoderBundle];
	[_encoderSettingsViewController setRepresentedObject:[encoderSettings mutableCopy]];

	// Adjust three view sizes to accomodate the encoder's settings view:
	//  1. The frame belonging to [self view]
	//  2. The frame belonging to _encoderSettingsView
	//  3. The enclosing window's frame
	
	// Calculate the difference between the current and target encoder settings view sizes
	NSRect currentEncoderSettingsViewFrame = [_encoderSettingsView frame];
	NSRect targetEncoderSettingsViewFrame = [[_encoderSettingsViewController view] frame];

	// The frames of all views will be adjusted by the following dimensions
	CGFloat viewDeltaX = targetEncoderSettingsViewFrame.size.width - currentEncoderSettingsViewFrame.size.width;
	CGFloat viewDeltaY = targetEncoderSettingsViewFrame.size.height - currentEncoderSettingsViewFrame.size.height;
	
	// Calculate the new window and view sizes
	NSRect currentWindowFrame = [[[self view] window] frame];
	NSRect newWindowFrame = currentWindowFrame;
	
	newWindowFrame.origin.x -= viewDeltaX / 2;
	newWindowFrame.origin.y -= viewDeltaY;
	newWindowFrame.size.width += viewDeltaX;
	newWindowFrame.size.height += viewDeltaY;

	NSRect newEncoderSettingsViewFrame = currentEncoderSettingsViewFrame;

	newEncoderSettingsViewFrame.size.width += viewDeltaX;
	newEncoderSettingsViewFrame.size.height += viewDeltaY;

	NSRect currentViewFrame = [[self view] frame];
	NSRect newViewFrame = currentViewFrame;
	
	newViewFrame.size.width += viewDeltaX;
	newViewFrame.size.height += viewDeltaY;

	// Set the new sizes
	[[[self view] window] setFrame:newWindowFrame display:YES animate:YES];
	[[self view] setFrame:newViewFrame];
	[_encoderSettingsView setFrame:newEncoderSettingsViewFrame];
		
	// Now that the sizes are correct, add the view controller's view to the view hierarchy
	[_encoderSettingsView addSubview:[_encoderSettingsViewController view]];

#if USE_ANIMATION
	NSDictionary *fadeInAnimationDictionary = [NSDictionary dictionaryWithObjectsAndKeys:
											   [_encoderSettingsViewController view], NSViewAnimationTargetKey,
											   NSViewAnimationFadeInEffect, NSViewAnimationEffectKey,
											   nil];

	NSViewAnimation *fadeInAnimation = [[NSViewAnimation alloc] initWithViewAnimations:[NSArray arrayWithObject:fadeInAnimationDictionary]];

	[fadeInAnimation setDuration:TRANSITION_ANIMATION_DURATION];
	[fadeInAnimation setAnimationCurve:NSAnimationEaseOut];
	[fadeInAnimation setAnimationBlockingMode:NSAnimationBlocking];

	[fadeInAnimation startAnimation];
#endif
}

@end

@implementation EncoderPreferencesViewController (PreferencesViewControllerMethods)

- (IBAction) restoreDefaults:(id)sender
{
	
#pragma unused (sender)
	
	// Determine which encoder bundle we are working with
	NSDictionary *encoderDictionary = [_encoderArrayController.selectedObjects lastObject];	
	NSBundle *encoderBundle = [encoderDictionary objectForKey:@"encoderBundle"];
	
	// If the bundle wasn't found, display an appropriate error
	if(!encoderBundle) {
		NSError *missingBundleError = [NSError errorWithDomain:NSCocoaErrorDomain code:ENOENT userInfo:nil];
		[[NSApplication sharedApplication] presentError:missingBundleError];
		return;
	}
	
	EncoderManager *encoderManager = [EncoderManager sharedEncoderManager];
	[encoderManager restoreDefaultSettingsForEncoder:encoderBundle];

	NSDictionary *encoderSettings = [encoderManager settingsForEncoder:encoderBundle];
	[_encoderSettingsViewController setRepresentedObject:[encoderSettings mutableCopy]];
}

- (IBAction) savePreferences:(id)sender
{

#pragma unused (sender)

	EncoderManager *encoderManager = [EncoderManager sharedEncoderManager];
	encoderManager.defaultEncoderSettings = _encoderSettingsViewController.representedObject;	
}

@end
