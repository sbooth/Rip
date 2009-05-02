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

NSString * const InspectorPaneDidCollapseNotification	= @"InspectorPaneDidCollapseNotification";
NSString * const InspectorPaneDidExpandNotification		= @"InspectorPaneDidExpandNotification";

@interface InspectorPane (Private)
- (void) createHeaderAndBody;
- (void) toggleCollapsedWithAnimation:(BOOL)animate;
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
	
	[self toggleCollapsedWithAnimation:YES];
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

- (void) toggleCollapsedWithAnimation:(BOOL)animate
{
	self.collapsed = !self.isCollapsed;
	
	CGFloat headerHeight = [[self headerView] frame].size.height;
	
	NSRect currentFrame = [self frame];
	NSRect newFrame = currentFrame;

	newFrame.size.height = headerHeight + (self.isCollapsed ? -1 : [self bodyView].normalHeight);
	newFrame.origin.y += currentFrame.size.height - newFrame.size.height;
	
	// FIXME: this doesn't work
	if(0&&animate)
		[[self animator] setFrame:newFrame];
	else
		[self setFrame:newFrame];

	if(self.collapsed)
		[[NSNotificationCenter defaultCenter] postNotificationName:InspectorPaneDidCollapseNotification object:self];
	else
		[[NSNotificationCenter defaultCenter] postNotificationName:InspectorPaneDidExpandNotification object:self];
}

@end
