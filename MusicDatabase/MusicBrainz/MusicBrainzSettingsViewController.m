/*
 *  Copyright (C) 2008 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import "MusicBrainzSettingsViewController.h"
#import "MusicBrainzDatabaseInterface.h"

@implementation MusicBrainzSettingsViewController

- (id) init
{
	return [super initWithNibName:@"MusicBrainzSettings" bundle:[NSBundle bundleForClass:[MusicBrainzDatabaseInterface class]]];
}

@end
