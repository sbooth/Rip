/*
 *  Copyright (C) 2009 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import "InspectorView.h"
#import "InspectorPane.h"

@interface InspectorView (Private)
- (void) inspectorPaneDidCollapseOrExpand:(NSNotification *)notification;
- (void) layoutSubviews;
@end

@implementation InspectorView

- (void) didAddSubview:(NSView *)subview
{
	NSParameterAssert(nil != subview);
	
	if([subview isKindOfClass:[InspectorPane class]]) {
		[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(inspectorPaneDidCollapseOrExpand:) name:InspectorPaneDidCollapseNotification object:subview];

		[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(inspectorPaneDidCollapseOrExpand:) name:InspectorPaneDidExpandNotification object:subview];
	}
}

- (void) willRemoveSubview:(NSView *)subview
{
	NSParameterAssert(nil != subview);

	if([subview isKindOfClass:[InspectorPane class]]) {
		[[NSNotificationCenter defaultCenter] removeObserver:self name:InspectorPaneDidCollapseNotification object:subview];
		[[NSNotificationCenter defaultCenter] removeObserver:self name:InspectorPaneDidExpandNotification object:subview];
	}
}

#pragma mark Pane management

- (void) addInspectorPaneController:(NSViewController *)paneController
{
	NSParameterAssert(nil != paneController);
	
	[self addInspectorPane:[paneController view] withTitle:[paneController title]];
	
}

- (void) addInspectorPane:(NSView *)paneBody withTitle:(NSString *)title
{
	NSParameterAssert(nil != paneBody);
	NSParameterAssert(nil != title);

	NSRect paneFrame;
	
	// Constrain the pane to our width and add extra height for the header
	paneFrame.size.width = [self frame].size.width;
	paneFrame.size.height = [paneBody frame].size.height + INSPECTOR_PANE_HEADER_HEIGHT;

	// This origin is never used; layoutSubviews will calculate the correct origin
	paneFrame.origin = NSZeroPoint;
	
	InspectorPane *pane = [[InspectorPane alloc] initWithFrame:paneFrame];
	
	[pane setTitle:title];
	[[pane bodyView] addSubview:paneBody];
	
	[self addSubview:pane];	
	
	// Lay out the panes correctly
	[self layoutSubviews];
}

@end

@implementation InspectorView (Private)

- (void) inspectorPaneDidCollapseOrExpand:(NSNotification *)notification
{
	
#pragma unused(notification)
	
	[self layoutSubviews];
}

- (void) layoutSubviews
{
	// Adjust the y origins of all the panes
	CGFloat paneHeight = 0.f;
	NSArray *reversedSubviews = [[[self subviews] reverseObjectEnumerator] allObjects];
	for(NSView *inspectorPane in reversedSubviews) {
		NSRect inspectorPaneFrame = [inspectorPane frame];
		NSPoint newPaneOrigin;
		
		newPaneOrigin.x = inspectorPaneFrame.origin.x;
		newPaneOrigin.y = paneHeight;
		
		[inspectorPane setFrameOrigin:newPaneOrigin];
		
		paneHeight += inspectorPaneFrame.size.height;
	}

	// Calculate the new window size
	NSRect currentViewFrame = [self frame]; 

	CGFloat deltaY = paneHeight - currentViewFrame.size.height;
	
	NSRect currentWindowFrame = [[self window] frame];
	NSRect newWindowFrame = currentWindowFrame;

	newWindowFrame.origin.y -= deltaY;
	newWindowFrame.size.height += deltaY;

	[[self window] setFrame:newWindowFrame display:YES animate:NO];
}

@end
