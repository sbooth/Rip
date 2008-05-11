/*
 *  Copyright (C) 2008 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import "EncoderSettingsSheetController.h"

@implementation EncoderSettingsSheetController

@synthesize settingsViewController = _settingsViewController;

- (id) init
{
	return [super initWithWindowNibName:@"EncoderSettingsSheet"];
}

- (void) awakeFromNib
{
	// Adjust the window and view's frame size to match the encoder's view size
	
	// Calculate the difference between the current and target encoder settings view sizes
	NSRect currentViewFrame = [_settingsView frame];
	NSRect targetViewFrame = [self.settingsViewController.view frame];
	
	CGFloat viewDeltaX = targetViewFrame.size.width - currentViewFrame.size.width;
	CGFloat viewDeltaY = targetViewFrame.size.height - currentViewFrame.size.height;
	
	// Calculate the new window and view sizes
	NSRect currentWindowFrame = [self.window frame];
	NSRect newWindowFrame = currentWindowFrame;

	newWindowFrame.size.width += viewDeltaX;
	newWindowFrame.size.height += viewDeltaY;

	NSRect newViewFrame = currentViewFrame;
	
	newViewFrame.size.width += viewDeltaX;
	newViewFrame.size.height += viewDeltaY;

	// Set the new sizes
	[self.window setFrame:newWindowFrame display:NO];
	[_settingsView setFrame:newViewFrame];
	
	// Now that the sizes are correct, add the view controller's view to the view hierarchy
	[_settingsView addSubview:self.settingsViewController.view];
}

- (IBAction) ok:(id)sender
{
	
#pragma unused(sender)
	
	[[NSApplication sharedApplication] endSheet:self.window returnCode:NSOKButton];	
}

- (IBAction) cancel:(id)sender
{
	
#pragma unused(sender)
	
	[[NSApplication sharedApplication] endSheet:self.window returnCode:NSCancelButton];	
}

@end
