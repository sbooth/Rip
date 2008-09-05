/*
 *  Copyright (C) 2008 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import <Cocoa/Cocoa.h>

// ========================================
// Constants
// ========================================
extern NSString * const		kMusicBrainzServiceName;

@interface MusicBrainzSettingsViewController : NSViewController
{
	IBOutlet NSTextField *_musicBrainzPasswordTextField;
}

@end
