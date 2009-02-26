/*
 *  Copyright (C) 2009 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import "WavPackSettingsViewController.h"
#import "WavPackEncoderInterface.h"

@implementation WavPackSettingsViewController

- (id) init
{
	return [super initWithNibName:@"WavPackSettings" bundle:[NSBundle bundleForClass:[WavPackEncoderInterface class]]];
}

@end
