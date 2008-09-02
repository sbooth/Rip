/*
 *  Copyright (C) 2008 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import "AppleLosslessSettingsViewController.h"
#import "AppleLosslessEncoderInterface.h"

@implementation AppleLosslessSettingsViewController

- (id) init
{
	return [super initWithNibName:@"AppleLosslessSettings" bundle:[NSBundle bundleForClass:[AppleLosslessEncoderInterface class]]];
}

@end
