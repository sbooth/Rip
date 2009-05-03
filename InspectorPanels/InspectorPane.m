/*
 *  Copyright (C) 2009 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import "InspectorPane.h"
#import "InspectorPaneHeader.h"
#import "InspectorPaneBody.h"
#import "InspectorView.h"

#import <QuartzCore/QuartzCore.h>

#define ANIMATION_DURATION 0.15
#define SLOW_ANIMATION_DURATION (8 * ANIMATION_DURATION)

@interface InspectorPane ()
@property (assign, getter=isCollapsed) BOOL collapsed;
@end

@interface InspectorPane (Private)
- (void) createHeaderAndBody;
@end

@implementation InspectorPane

@synthesize collapsed = _collapsed;

- (id) initWithFrame:(NSRect)frame
{
	if((self = [super initWithFrame:frame]))
		[self createHeaderAndBody];
	return self;
}

- (void) awakeFromNib
{
	[self createHeaderAndBody];
}

- (NSString *) title
{
	return [_headerView title];
}

- (void) setTitle:(NSString *)title
{
	[_headerView setTitle:title];
}

- (IBAction) toggleCollapsed:(id)sender
{
	
#pragma unused(sender)
	
	[self setCollapsed:!self.isCollapsed animate:YES];
}

- (void) setCollapsed:(BOOL)collapsed animate:(BOOL)animate
{
	if(self.isCollapsed == collapsed)
		return;
	
	self.collapsed = collapsed;
	[[_headerView disclosureButton] setState:(collapsed ? NSOffState : NSOnState)];
	
	CGFloat headerHeight = [[self headerView] frame].size.height;
	
	NSRect currentFrame = [self frame];
	NSRect newFrame = currentFrame;
	
	newFrame.size.height = headerHeight + (self.isCollapsed ? -1 : [self bodyView].normalHeight);
	newFrame.origin.y += currentFrame.size.height - newFrame.size.height;
	
	if(animate) {
		BOOL shiftPressed = (NSShiftKeyMask & [[[NSApplication sharedApplication] currentEvent] modifierFlags]) != 0;
		
		// Modify the default animation for frame changes
		CABasicAnimation *frameSizeAnimation = [[self animator] animationForKey:@"frameSize"];
		
		// Don't modify the returned animation (in case it is shared)
		if(frameSizeAnimation) {
			frameSizeAnimation = [frameSizeAnimation copy];
			
			frameSizeAnimation.duration = shiftPressed ? SLOW_ANIMATION_DURATION : ANIMATION_DURATION;
			frameSizeAnimation.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
			
			[[self animator] setAnimations:[NSDictionary dictionaryWithObject:frameSizeAnimation forKey:@"frameSize"]];
		}
		
		[[self animator] setFrame:newFrame];
	}
	else
		[self setFrame:newFrame];
}

- (InspectorPaneHeader *) headerView
{
	return _headerView;
}

- (InspectorPaneBody *) bodyView
{
	return _bodyView;
}

@end

@implementation InspectorPane (Private)

- (void) createHeaderAndBody
{
	// Divide our bounds into the header and body areas
	NSRect headerFrame, bodyFrame;	
	NSDivideRect([self bounds], &headerFrame, &bodyFrame, INSPECTOR_PANE_HEADER_HEIGHT, NSMaxYEdge);
	
	_headerView = [[InspectorPaneHeader alloc] initWithFrame:headerFrame];
	
	[_headerView setAutoresizingMask:(NSViewWidthSizable | NSViewMinYMargin)];
	[[_headerView disclosureButton] setState:NSOnState];

	_bodyView = [[InspectorPaneBody alloc] initWithFrame:bodyFrame];

	[_bodyView setAutoresizingMask:(NSViewWidthSizable | NSViewHeightSizable)];
		
	[self addSubview:_headerView];
	[self addSubview:_bodyView];

	[self setAutoresizesSubviews:YES];
}

@end
