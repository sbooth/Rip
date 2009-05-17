/*
 *  Copyright (C) 2009 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import "ViewSelectorBar.h"
#import "ViewSelectorBarItem.h"

#define MARGIN_SIZE 2

// Cell states
enum {
	eCellNormalState = 0,
	eCellPressedState = 1,
	eCellSelectedState = 2
};

@interface ViewSelectorBar (Private)
- (void) drawGridLines;
- (void) drawBackground;
- (void) drawImageForCellAtIndex:(NSUInteger)index state:(NSInteger)state;
- (NSRect) frameRectForCellAtIndex:(NSUInteger)index;
@end

@implementation ViewSelectorBar

@synthesize selectedIndex = _selectedIndex;

- (id) initWithFrame:(NSRect)frameRect
{
	if((self = [super initWithFrame:frameRect])) {
		_items = [NSMutableArray array];
		_selectedIndex = -1;
		_pressedIndex = -1;
	}
	return self;
}

- (id) initWithCoder:(NSCoder *)decoder
{
	if((self = [super initWithCoder:decoder])) {
		_items = [NSMutableArray array];
		_selectedIndex = -1;
		_pressedIndex = -1;
	}
	return self;
}

- (void) drawRect:(NSRect)rect
{

#pragma unused(rect)
	
	// The background is a two-tone gradient in the bottom half of bounds
	[self drawBackground];
	
	// Draw the images
	NSUInteger itemCount = [_items count];
	NSUInteger itemIndex;
	for(itemIndex = 0; itemIndex < itemCount; ++itemIndex) {
		NSInteger state = 0;
		if(_selectedIndex == (NSInteger)itemIndex)
			state = eCellSelectedState;
		else if(_pressedIndex == (NSInteger)itemIndex)
			state = eCellPressedState;
		
		[self drawImageForCellAtIndex:itemIndex state:state];
	}

	// Draw the grid lines
	[self drawGridLines];
}

#pragma mark Mouse Methods

- (BOOL)acceptsFirstMouse:(NSEvent *)theEvent
{
	
#pragma unused(theEvent)

	return YES;
}

- (void) mouseDown:(NSEvent *)theEvent
{
	_pressedIndex = -1;

	NSPoint point = [self convertPoint:[theEvent locationInWindow] fromView:nil];

	NSUInteger itemCount = [_items count];
	NSUInteger itemIndex;
	for(itemIndex = 0; itemIndex < itemCount; ++itemIndex) {
		NSRect cellRect = [self frameRectForCellAtIndex:itemIndex];
		if(NSMouseInRect(point, cellRect, [self isFlipped])) {
			_pressedIndex = itemIndex;
			break;
		}
	}
		
	[self setNeedsDisplay:YES];
}

- (void) mouseDragged:(NSEvent *)theEvent
{
	_pressedIndex = -1;
	
	NSPoint point = [self convertPoint:[theEvent locationInWindow] fromView:nil];
	
	NSUInteger itemCount = [_items count];
	NSUInteger itemIndex;
	for(itemIndex = 0; itemIndex < itemCount; ++itemIndex) {
		NSRect cellRect = [self frameRectForCellAtIndex:itemIndex];
		if(NSMouseInRect(point, cellRect, [self isFlipped])) {
			_pressedIndex = itemIndex;
			break;
		}
	}
	
	[self setNeedsDisplay:YES];
}

- (void) mouseUp:(NSEvent *)theEvent
{

#pragma unused(theEvent)
	
	if(-1 != _pressedIndex && self.selectedIndex != _pressedIndex)
		self.selectedIndex = _pressedIndex;
	
	_pressedIndex = -1;
	[self setNeedsDisplay:YES];
}

#pragma mark Item Management

- (void) addItem:(ViewSelectorBarItem *)item
{
	NSParameterAssert(nil != item);
	
	[_items addObject:item];

	// Recalculate the tool tip rectangles
	[self removeAllToolTips];

	NSUInteger itemCount = [_items count];
	NSUInteger itemIndex;
	for(itemIndex = 0; itemIndex < itemCount; ++itemIndex) {
		NSRect cellRect = [self frameRectForCellAtIndex:itemIndex];
		ViewSelectorBarItem *itemInfo = [_items objectAtIndex:itemIndex];
		NSString *itemTooltip = [itemInfo tooltip];
		if(itemTooltip)
			[self addToolTipRect:cellRect owner:itemTooltip userData:NULL];
	}
	
	// Ensure an item is selected
	if(-1 == self.selectedIndex/* && itemCount*/)
		self.selectedIndex = 0;
}

- (void) setSelectedIndex:(NSInteger)selectedIndex
{
	NSParameterAssert(selectedIndex < (NSInteger)[_items count]);
	
	_selectedIndex = selectedIndex;
}

- (ViewSelectorBarItem *) selectedItem
{
	NSInteger selectedIndex = self.selectedIndex;
	if(-1 == selectedIndex)
		return nil;
	
	return [_items objectAtIndex:self.selectedIndex];
}

- (BOOL) selectItem:(ViewSelectorBarItem *)item
{
	NSParameterAssert(nil != item);

	for(ViewSelectorBarItem *currentItem in _items) {
		if(item == currentItem) {
			self.selectedIndex = [_items indexOfObject:currentItem];
			return YES;
		}
	}
	
	return NO;
}

- (BOOL) selectItemWithIdentifer:(NSString *)itemIdentifier
{
	NSParameterAssert(nil != itemIdentifier);
	
	for(ViewSelectorBarItem *item in _items) {
		if([[item identifier] isEqualToString:itemIdentifier]) {
			self.selectedIndex = [_items indexOfObject:item];
			return YES;
		}
	}
	
	return NO;
}

- (ViewSelectorBarItem *) itemAtIndex:(NSInteger)itemIndex
{
	NSParameterAssert(0 <= itemIndex && itemIndex < [_items count]);
	
	return [_items objectAtIndex:itemIndex];
}

- (ViewSelectorBarItem *) itemWithIdentifier:(NSString *)itemIdentifier
{
	NSParameterAssert(nil != itemIdentifier);
	
	for(ViewSelectorBarItem *item in _items) {
		if([[item identifier] isEqualToString:itemIdentifier])
			return item;
	}
	
	return nil;
}

@end

@implementation ViewSelectorBar (Private)

- (void) drawGridLines
{
	NSRect bounds = [self bounds];
	
	NSUInteger itemCount = [_items count];

	CGFloat cellWidth = bounds.size.width / itemCount;
	CGFloat cellHeight = bounds.size.height;
	
	NSColor *highlightColor = [NSColor colorWithCalibratedWhite:0.53f alpha:1.f];
	[highlightColor set];
	
	// Draw the bottom border
	NSRect bottomBorderRect = bounds;
	bottomBorderRect.size.height = 1;
	
	if([self needsToDrawRect:bottomBorderRect])
		[NSBezierPath fillRect:bottomBorderRect];
	
	// Since lines are drawn between cells, one cell has no separator
	if(1 >= itemCount)
		return;
	
	NSUInteger currentIndex;
	for(currentIndex = 1; currentIndex < itemCount; ++currentIndex) {
		NSRect cellBorderRect;
		
		cellBorderRect.size.height = cellHeight;
		cellBorderRect.size.width = 1;
		
		cellBorderRect.origin.x = currentIndex * cellWidth;
		cellBorderRect.origin.y = 1;
		
		if([self needsToDrawRect:cellBorderRect])
			[NSBezierPath fillRect:cellBorderRect];
	}
}

- (void) drawBackground
{
	NSColor *topColor = [NSColor colorWithCalibratedWhite:0.84f alpha:1.f];
	NSColor *bottomColor = [NSColor /*windowBackgroundColor*/colorWithCalibratedWhite:0.9f alpha:1.f];
	
	NSGradient *gradient = [[NSGradient alloc] initWithStartingColor:topColor endingColor:bottomColor];
	
	NSRect bounds = [self bounds];
	
	NSRect topRect, bottomRect;
	NSDivideRect(bounds, &bottomRect, &topRect, bounds.size.height / 2, NSMinYEdge);
	
	[[NSColor windowBackgroundColor] set];
	
	if([self needsToDrawRect:topRect])
		[NSBezierPath fillRect:topRect];
	
	if([self needsToDrawRect:bottomRect])
		[gradient drawInRect:bottomRect angle:270];
}

- (void) drawImageForCellAtIndex:(NSUInteger)cellIndex state:(NSInteger)state
{
	NSRect cellFrame = [self frameRectForCellAtIndex:cellIndex];
	
	// Avoid unnecessary drawing
	if(![self needsToDrawRect:cellFrame])
		return;

	// Shade the selected cell
	if(eCellSelectedState == state) {
		// FIXME: Not quite the same color as IB
//		NSColor *highlightColor = [NSColor colorWithCalibratedRed:0.81f green:0.84f blue:0.87f alpha:0.5f];
		NSColor *highlightColor = [NSColor selectedControlColor];
		highlightColor = [[NSColor selectedControlColor] colorWithAlphaComponent:0.55f];
		
		[highlightColor set];
		[NSBezierPath fillRect:cellFrame];
	}
	else if(eCellPressedState == state) {
		// FIXME: Not quite the same color as IB
//		NSColor *pressedColor = [NSColor colorWithCalibratedWhite:0.75f alpha:0.5f];
		NSColor *pressedColor = [NSColor colorWithCalibratedWhite:0.f alpha:0.07f];
		
		[pressedColor set];
		[NSBezierPath fillRect:cellFrame];
	}
	
	// Inset the rect so the image has the proper margins
	cellFrame = NSInsetRect(cellFrame, MARGIN_SIZE, MARGIN_SIZE);
	
	// Draw the image, centered in the rect
	NSImage *image = [[_items objectAtIndex:cellIndex] image];
	NSSize imageSize = [image size];
	
	NSPoint centerPoint = cellFrame.origin;
	
	centerPoint.x += (cellFrame.size.width - imageSize.width) / 2;
	centerPoint.y += (cellFrame.size.height - imageSize.height) / 2;
	
	[image drawAtPoint:centerPoint fromRect:NSZeroRect operation:NSCompositeSourceOver fraction:1.f];
}

- (NSRect) frameRectForCellAtIndex:(NSUInteger)cellIndex
{
	NSRect bounds = [self bounds];
	
	CGFloat cellWidth = bounds.size.width / [_items count];
	CGFloat cellHeight = bounds.size.height;
	
	NSRect cellFrame;
	
	cellFrame.size.width = cellWidth;
	cellFrame.size.height = cellHeight;
	
	cellFrame.origin.y = 0;
	cellFrame.origin.x = cellWidth * cellIndex;
	
	cellFrame = NSIntegralRect(cellFrame);
	
	return cellFrame;
}

@end
