/*
 *  Copyright (C) 2008 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import "AdvancedPreferencesViewController.h"
#import "ApplicationDelegate.h"

@implementation AdvancedPreferencesViewController

- (id) init
{
	if((self = [super initWithNibName:@"AdvancedPreferencesView" bundle:nil]))
		self.title = NSLocalizedString(@"Advanced", @"The name of the advanced preference pane");
	
	return self;
}

- (NSManagedObjectContext *) managedObjectContext
{
	return [(ApplicationDelegate *)[[NSApplication sharedApplication] delegate] managedObjectContext];
}

@end

@implementation AdvancedPreferencesViewController (PreferencesViewControllerMethods)

- (IBAction) savePreferences:(id)sender
{
	[(ApplicationDelegate *)[[NSApplication sharedApplication] delegate] saveAction:sender];
}

@end
