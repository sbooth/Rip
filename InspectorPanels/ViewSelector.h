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
	NSMutableArray *_views;
}

- (void) addItemWithView:(NSView *)view image:(NSImage *)image tooltip:(NSString *)tooltip;

- (ViewSelectorBar *) selectorBar;

@end
