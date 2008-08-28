/*
 *  Copyright (C) 2008 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import "GeneralPreferencesViewController.h"

@implementation GeneralPreferencesViewController

- (id) init
{
	if((self = [super initWithNibName:@"GeneralPreferencesView" bundle:nil]))
		self.title = NSLocalizedString(@"General", @"The name of the general preference pane");
	
	return self;
}

@end
