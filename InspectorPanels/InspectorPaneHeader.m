/*
 *  Copyright (C) 2009 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import "InspectorPaneHeader.h"
#import "InspectorPane.h"

#define DISCLOSURE_BUTTON_SIZE 13

@interface InspectorPaneHeader (Private)
- (void) createDisclosureButtonAndLabel;
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
	NSColor *startColor = [NSColor colorWithCalibratedWhite:0.880f alpha:1.f];
	NSColor *endColor = [NSColor colorWithCalibratedWhite:0.773f alpha:1.f];
	NSGradient *gradient = [[NSGradient alloc] initWithStartingColor:startColor endingColor:endColor];
	
	NSColor *topBorderColorAbove = [NSColor colorWithCalibratedWhite:0.659f alpha:1.f];
	NSColor *topBorderColorBelow = [NSColor colorWithCalibratedWhite:0.925f alpha:1.f];
	NSColor *bottomBorderColor = [NSColor colorWithCalibratedWhite:0.612f alpha:1.f];
	
	NSRect singlePixelRect = [self bounds];
	singlePixelRect.size.height = 1;
	
	[gradient drawInRect:rect angle:270];
	
	singlePixelRect.origin.y = 0;
	if(NSIntersectsRect(rect, singlePixelRect)) {
		[bottomBorderColor setFill];
		[NSBezierPath fillRect:NSIntersectionRect(rect, singlePixelRect)];
	}
	
	singlePixelRect.origin.y = [self bounds].size.height - 1;
	if(NSIntersectsRect(rect, singlePixelRect)) {
		[topBorderColorAbove setFill];
		[NSBezierPath fillRect:NSIntersectionRect(rect, singlePixelRect)];
	}
	
	singlePixelRect.origin.y -= 1;
	if(NSIntersectsRect(rect, singlePixelRect)) {
		[topBorderColorBelow setFill];
		[NSBezierPath fillRect:NSIntersectionRect(rect, singlePixelRect)];
	}
	
	[[NSColor colorWithCalibratedWhite:0.f alpha:0.03f] setFill];
	[NSBezierPath fillRect:rect];
	
	if(_pressed) {
		[[NSColor colorWithCalibratedWhite:0.f alpha:0.07f] setFill];
		[NSBezierPath fillRect:rect];
	}
}

- (void) mouseDown:(NSEvent *)theEvent
{

#pragma unused(theEvent)

	_pressed = YES;
	[self setNeedsDisplay:YES];
}

- (void) mouseDragged:(NSEvent *)event
{
	
#pragma unused(theEvent)

	NSPoint point = [self convertPoint:[event locationInWindow] fromView:nil];
	_pressed = NSPointInRect(point, [self bounds]);
	
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

@end
