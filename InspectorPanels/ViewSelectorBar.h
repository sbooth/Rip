/*
 *  Copyright (C) 2009 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import <Cocoa/Cocoa.h>

@class ViewSelectorBarItem;

@interface ViewSelectorBar : NSView
{
@private
	NSInteger _selectedIndex;
	NSInteger _pressedIndex;
	NSMutableArray *_items;
}

@property (assign) NSInteger selectedIndex;
@property (readonly) ViewSelectorBarItem * selectedItem;

- (void) addItem:(ViewSelectorBarItem *)item;

- (BOOL) selectItem:(ViewSelectorBarItem *)item;
- (BOOL) selectItemWithIdentifer:(NSString *)itemIdentifier;

- (ViewSelectorBarItem *) itemAtIndex:(NSInteger)itemIndex;
- (ViewSelectorBarItem *) itemWithIdentifier:(NSString *)itemIdentifier;

@end
