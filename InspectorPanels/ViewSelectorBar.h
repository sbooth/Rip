/*
 *  Copyright (C) 2009 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import <Cocoa/Cocoa.h>

@interface ViewSelectorBar : NSView
{
@private
	NSInteger _selectedIndex;
	NSInteger _pressedIndex;
	NSMutableArray *_items;
}

@property (assign) NSInteger selectedIndex;

- (void) addItemWithImage:(NSImage *)image tooltip:(NSString *)tooltip;

- (NSImage *) imageAtIndex:(NSInteger)itemIndex;
- (NSString *) tooltipAtIndex:(NSInteger)itemIndex;

@end
