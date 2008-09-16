/*
 *  Copyright (C) 2008 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import "WAVESettingsViewController.h"
#import "WAVEEncoderInterface.h"

@implementation WAVESettingsViewController

- (id) init
{
	return [super initWithNibName:@"WAVESettings" bundle:[NSBundle bundleForClass:[WAVEEncoderInterface class]]];
}

@end
