/*
 *  Copyright (C) 2008 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import "FreeDBSettingsViewController.h"
#import "FreeDBDatabaseInterface.h"

@implementation FreeDBSettingsViewController

- (id) init
{
	return [super initWithNibName:@"FreeDBSettings" bundle:[NSBundle bundleForClass:[FreeDBDatabaseInterface class]]];
}

@end
