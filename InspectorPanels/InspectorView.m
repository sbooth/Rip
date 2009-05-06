/*
 *  Copyright (C) 2009 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import "InspectorView.h"
#import "InspectorPane.h"

@interface InspectorView (Private)
- (void) inspectorPaneFrameDidChange:(NSNotification *)notification;
- (void) applicationWillTerminate:(NSNotification *)notification;
- (void) layoutSubviews;
@end

@implementation InspectorView

- (void) awakeFromNib
{
	_initialWindowSize = [[self window] frame].size;
	
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(applicationWillTerminate:) name:NSApplicationWillTerminateNotification object:nil];

	// Iterate through each pane and restore its state
	NSString *autosaveName = [[self window] frameAutosaveName];
	if(!autosaveName)
		return;
	
	for(NSView *inspectorPane in [self subviews]) {
		if(![inspectorPane isKindOfClass:[InspectorPane class]])
			continue;
		
		InspectorPane *pane = (InspectorPane *)inspectorPane;
		NSString *paneAutosaveName = [autosaveName stringByAppendingFormat:@" %@ Pane", [pane title]];
		
		[[NSUserDefaults standardUserDefaults] setBool:pane.isCollapsed forKey:paneAutosaveName];
	}
}

- (void) didAddSubview:(NSView *)subview
{
	NSParameterAssert(nil != subview);
	
	if([subview isKindOfClass:[InspectorPane class]]) {
		// Restore the pane's size
		NSString *autosaveName = [[self window] frameAutosaveName];
		if(autosaveName) {
			InspectorPane *pane = (InspectorPane *)subview;
			NSString *paneAutosaveName = [autosaveName stringByAppendingFormat:@" %@ Pane", [pane title]];
			[pane setCollapsed:[[NSUserDefaults standardUserDefaults] boolForKey:paneAutosaveName] animate:NO];
		}

		[subview setPostsFrameChangedNotifications:YES];
		[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(inspectorPaneFrameDidChange:) name:NSViewFrameDidChangeNotification object:subview];
	}
}

- (void) willRemoveSubview:(NSView *)subview
{
	NSParameterAssert(nil != subview);

	if([subview isKindOfClass:[InspectorPane class]]) {
		[subview setPostsFrameChangedNotifications:NO];
		[[NSNotificationCenter defaultCenter] removeObserver:self name:NSViewFrameDidChangeNotification object:subview];
	}
}

#pragma mark Pane management

- (void) addInspectorPaneController:(NSViewController *)paneController
{
	NSParameterAssert(nil != paneController);
	
	[self addInspectorPane:[paneController view] title:[paneController title]];
	
}

- (void) addInspectorPane:(NSView *)paneBody title:(NSString *)title
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

- (void) inspectorPaneFrameDidChange:(NSNotification *)notification
{
	NSParameterAssert(nil != notification);
	NSParameterAssert(nil != [notification object]);
	NSParameterAssert([[notification object] isKindOfClass:[InspectorPane class]]);
	
	InspectorPane *pane = [notification object];
	
	[pane setPostsFrameChangedNotifications:NO];
	
	[self layoutSubviews];

	[pane setPostsFrameChangedNotifications:YES];
}

- (void) applicationWillTerminate:(NSNotification *)notification
{
	
#pragma unused(notification)
	
	[[NSNotificationCenter defaultCenter] removeObserver:self];
	
	// Iterate through each pane and save its state
	NSString *autosaveName = [[self window] frameAutosaveName];
	if(!autosaveName)
		return;
	
	for(NSView *inspectorPane in [self subviews]) {
		if(![inspectorPane isKindOfClass:[InspectorPane class]])
			continue;
		
		InspectorPane *pane = (InspectorPane *)inspectorPane;
		NSString *paneAutosaveName = [autosaveName stringByAppendingFormat:@" %@ Pane", [pane title]];

		[[NSUserDefaults standardUserDefaults] setBool:pane.isCollapsed forKey:paneAutosaveName];
	}
	
	[[NSUserDefaults standardUserDefaults] synchronize];

	// Reset the window's frame to its initial size
	NSRect currentWindowFrame = [[self window] frame];
	NSRect newWindowFrame = currentWindowFrame;

	CGFloat deltaY = _initialWindowSize.height - currentWindowFrame.size.height;
	
	newWindowFrame.origin.y -= deltaY;
	newWindowFrame.size.height += deltaY;

	[[self window] setFrame:newWindowFrame display:NO animate:NO];
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
