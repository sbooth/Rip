/*
 *  Copyright (C) 2008 - 2009 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import <Cocoa/Cocoa.h>

@interface GeneralPreferencesViewController : NSViewController
{
	IBOutlet NSComboBox *_customOutputFileNamingComboBox;
	IBOutlet NSPopUpButton *_customOutputFileFormatSpecifierPopUpButton;
}

- (IBAction) insertCustomOutputFileNamingFormatSpecifier:(id)sender;
- (IBAction) saveCustomOutputFileNamingFormat:(id)sender;

@end
