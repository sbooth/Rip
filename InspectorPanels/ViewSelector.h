/*
 *  Copyright (C) 2009 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import <Cocoa/Cocoa.h>

#define VIEW_SELECTOR_BAR_HEIGHT 25

@class ViewSelectorBar;

@interface ViewSelector : NSView
{
@private
	NSSize _initialWindowSize;
	ViewSelectorBar *_selectorBar;
	NSView *_bodyView;
}

- (ViewSelectorBar *) selectorBar;

@end
