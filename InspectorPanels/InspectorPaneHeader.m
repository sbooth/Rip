/*
 *  Copyright (C) 2009 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import "InspectorPaneHeader.h"
#import "InspectorPane.h"

#define DISCLOSURE_BUTTON_SIZE 13

@interface InspectorPaneHeader (Private)
- (void) createDisclosureButtonAndLabel;
#if USE_ALTERNATE_APPEARANCE
- (void) drawBorders;
- (void) drawBackground;
#endif
@end

@implementation InspectorPaneHeader

- (id) initWithFrame:(NSRect)frameRect
{
	if((self = [super initWithFrame:frameRect]))
		[self createDisclosureButtonAndLabel];
	return self;
}

- (BOOL) mouseDownCanMoveWindow
{
	return NO;
}

- (BOOL) acceptsFirstMouse:(NSEvent *)theEvent
{

#pragma unused(theEvent)

	return YES;
}

- (void) drawRect:(NSRect)rect
{
#if USE_ALTERNATE_APPEARANCE
	[self drawBackground];
	[self drawBorders];

	if(_pressed) {
		NSColor *pressedColor = [NSColor colorWithCalibratedWhite:0.75f alpha:0.5f];
		
		[pressedColor set];
		[NSBezierPath fillRect:rect];
	}
	else if(NSOnState == [_disclosureButton state]) {
		// FIXME: Not quite the same color as IB
		NSColor *highlightColor = [NSColor colorWithCalibratedRed:0.81f green:0.84f blue:0.87f alpha:0.5f];
		highlightColor = [[NSColor selectedControlColor] colorWithAlphaComponent:0.55f];
		
		[highlightColor set];
		[NSBezierPath fillRect:rect];
	}
#else
	NSColor *startColor = [NSColor colorWithCalibratedWhite:0.880f alpha:1.f];
	NSColor *endColor = [NSColor colorWithCalibratedWhite:0.773f alpha:1.f];
	NSGradient *gradient = [[NSGradient alloc] initWithStartingColor:startColor endingColor:endColor];
	
	NSColor *topBorderColorAbove = [NSColor colorWithCalibratedWhite:0.659f alpha:1.f];
	NSColor *topBorderColorBelow = [NSColor colorWithCalibratedWhite:0.925f alpha:1.f];
	NSColor *bottomBorderColor = [NSColor colorWithCalibratedWhite:0.612f alpha:1.f];
	
	[gradient drawInRect:rect angle:270];
	
	NSRect bottomBorderRect = [self bounds];
	bottomBorderRect.size.height = 1;
	bottomBorderRect.origin.y = 0;
	
	if([self needsToDrawRect:bottomBorderRect]) {
		[bottomBorderColor setFill];
		[NSBezierPath fillRect:bottomBorderRect];
	}
	
	NSRect topBorderRect = [self bounds];
	topBorderRect.size.height = 1;
	topBorderRect.origin.y = [self bounds].size.height - 1;

	if([self needsToDrawRect:topBorderRect]) {
		[topBorderColorAbove setFill];
		[NSBezierPath fillRect:topBorderRect];
	}
	
	NSRect topBorderAboveRect = [self bounds];
	topBorderAboveRect.size.height = 1;
	topBorderAboveRect.origin.y -= 1;
	
	if([self needsToDrawRect:topBorderAboveRect]) {
		[topBorderColorBelow setFill];
		[NSBezierPath fillRect:topBorderAboveRect];
	}
	
	[[NSColor colorWithCalibratedWhite:0.f alpha:0.03f] setFill];
	[NSBezierPath fillRect:rect];
	
	if(_pressed) {
		[[NSColor colorWithCalibratedWhite:0.f alpha:0.07f] setFill];
		[NSBezierPath fillRect:rect];
	}
#endif
}

- (void) mouseDown:(NSEvent *)theEvent
{

#pragma unused(theEvent)

	_pressed = YES;
	[self setNeedsDisplay:YES];
}

- (void) mouseDragged:(NSEvent *)theEvent
{
	NSPoint point = [self convertPoint:[theEvent locationInWindow] fromView:nil];
	_pressed = NSMouseInRect(point, [self bounds], [self isFlipped]);
	
	[self setNeedsDisplay:YES];
}

- (void) mouseUp:(NSEvent *)theEvent
{
	if(_pressed)
		[_disclosureButton performClick:theEvent];
	
	_pressed = NO;
	[self setNeedsDisplay:YES];
}

- (void) viewDidMoveToSuperview
{
	[_disclosureButton setTarget:[self superview]];
	[_disclosureButton setAction:@selector(toggleCollapsed:)];	
}

- (NSString *) title
{
	return [_titleTextField stringValue];	
}

- (void) setTitle:(NSString *)title
{
	[_titleTextField setStringValue:title];	
}

- (NSButton *) disclosureButton
{
	return _disclosureButton;
}

- (NSTextField *) titleTextField
{
	return _titleTextField;
}

@end

@implementation InspectorPaneHeader (Private)

- (void) createDisclosureButtonAndLabel
{
	NSRect boundsRect = [self bounds];
	
	NSRect buttonRect = NSMakeRect(3, 2, DISCLOSURE_BUTTON_SIZE, DISCLOSURE_BUTTON_SIZE);
	NSRect labelRect = NSMakeRect(16, 1, boundsRect.size.width - DISCLOSURE_BUTTON_SIZE - 4, 14);
		
	_disclosureButton = [[NSButton alloc] initWithFrame:buttonRect];
	
	[_disclosureButton setButtonType:NSPushOnPushOffButton];
	[_disclosureButton setBezelStyle:NSDisclosureBezelStyle];
	[_disclosureButton setTitle:@""];
	
	[_disclosureButton setTarget:[self superview]];
	[_disclosureButton setAction:@selector(toggleCollapsed:)];
	
	_titleTextField = [[NSTextField alloc] initWithFrame:labelRect];
	
	[_titleTextField setAutoresizingMask:(NSViewMinXMargin | NSViewMaxYMargin | NSViewWidthSizable)];
	[_titleTextField setEditable:NO];
	[_titleTextField setFont:[NSFont systemFontOfSize:11]];
	[_titleTextField setBordered:NO];
	[_titleTextField setDrawsBackground:NO];
	
	[self addSubview:_disclosureButton];
	[self addSubview:_titleTextField];
}

#if USE_ALTERNATE_APPEARANCE
- (void) drawBorders
{
	NSRect bounds = [self bounds];
	
	NSColor *highlightColor = [NSColor colorWithCalibratedWhite:0.53f alpha:1.f];
	[highlightColor set];
	
	// Draw the top border
	NSRect topBorderRect = bounds;
	topBorderRect.origin.y = bounds.size.height - 1;
	topBorderRect.size.height = 1;
	
	if([self needsToDrawRect:topBorderRect])
		[NSBezierPath fillRect:topBorderRect];	

	// Draw the bottom border
	NSRect bottomBorderRect = bounds;
	bottomBorderRect.size.height = 1;
	
	if([self needsToDrawRect:bottomBorderRect])
		[NSBezierPath fillRect:bottomBorderRect];	
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
#endif

@end
