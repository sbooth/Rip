/*
 *  Copyright (C) 2008 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import "AdvancedPreferencesViewController.h"

@implementation AdvancedPreferencesViewController

- (id) init
{
	if((self = [super initWithNibName:@"AdvancedPreferencesView" bundle:nil]))
		self.title = NSLocalizedString(@"Advanced", @"The name of the advanced preference pane");
	
	return self;
}

- (NSManagedObjectContext *) managedObjectContext
{
	return [[[NSApplication sharedApplication] delegate] managedObjectContext];
}

@end

@implementation AdvancedPreferencesViewController (PreferencesViewControllerMethods)

- (IBAction) savePreferences:(id)sender
{
	[[[NSApplication sharedApplication] delegate] saveAction:sender];
}

@end
