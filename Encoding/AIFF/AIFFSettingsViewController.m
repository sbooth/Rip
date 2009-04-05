/*
 *  Copyright (C) 2008 - 2009 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import "AIFFSettingsViewController.h"
#import "AIFFEncoderInterface.h"

@implementation AIFFSettingsViewController

- (id) init
{
	return [super initWithNibName:@"AIFFSettings" bundle:[NSBundle bundleForClass:[AIFFEncoderInterface class]]];
}

@end
