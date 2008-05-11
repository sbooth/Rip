/*
 *  Copyright (C) 2008 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import "FLACSettingsViewController.h"
#import "FLACEncoderInterface.h"

@implementation FLACSettingsViewController

- (id) init
{
	return [super initWithNibName:@"FLACSettings" bundle:[NSBundle bundleForClass:[FLACEncoderInterface class]]];
}

@end
