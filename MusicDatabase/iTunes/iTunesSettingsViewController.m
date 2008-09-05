/*
 *  Copyright (C) 2008 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import "iTunesSettingsViewController.h"
#import "iTunesDatabaseInterface.h"

@implementation iTunesSettingsViewController

- (id) init
{
	return [super initWithNibName:@"iTunesSettings" bundle:[NSBundle bundleForClass:[iTunesDatabaseInterface class]]];
}

@end
