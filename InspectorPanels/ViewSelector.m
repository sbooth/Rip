/*
 *  Copyright (C) 2009 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import "ViewSelector.h"
#import "ViewSelectorBar.h"

@interface ViewSelector (Private)
- (void) createSelectorBarAndBody;
- (void) applicationWillTerminate:(NSNotification *)notification;
@end

@implementation ViewSelector

- (id) initWithFrame:(NSRect)frame
{
	if((self = [super initWithFrame:frame])) {
		_views = [NSMutableArray array];
		[self createSelectorBarAndBody];
	}
	return self;
}

- (id) initWithCoder:(NSCoder *)decoder
{
	if((self = [super initWithCoder:decoder])) {
		_views = [NSMutableArray array];
		[self createSelectorBarAndBody];
	}
	return self;
}

- (void) awakeFromNib
{
	_initialWindowSize = [[self window] frame].size;
	
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(applicationWillTerminate:) name:NSApplicationWillTerminateNotification object:nil];

	// Iterate through each pane and restore its state
	NSString *autosaveName = [[self window] frameAutosaveName];
	if(!autosaveName)
		return;
	
	for(NSView *subview in _views) {
//		NSString *viewAutosaveName = [autosaveName stringByAppendingFormat:@" %@ Pane", [pane title]];
//		
//		[[NSUserDefaults standardUserDefaults] setBool:pane.isCollapsed forKey:paneAutosaveName];
	}
}

- (void) observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
	
#pragma unused(keyPath)
#pragma unused(object)
#pragma unused(context)
	
	NSNumber *oldIndex = [change objectForKey:NSKeyValueChangeOldKey];
	NSNumber *newIndex = [change objectForKey:NSKeyValueChangeNewKey];
	
	NSView *oldView = nil, *newView = nil;
	
	if(-1 != [oldIndex integerValue]) {
		oldView = [_views objectAtIndex:[oldIndex unsignedIntegerValue]];
		[oldView removeFromSuperview];
	}
	else
		oldView = _bodyView;

	if(-1 != [newIndex integerValue])
		newView = [_views objectAtIndex:[newIndex unsignedIntegerValue]];
	
	// Calculate the new window size
	CGFloat deltaY = [newView frame].size.height - [oldView frame].size.height;
//	CGFloat deltaX = [newView frame].size.width - [oldView frame].size.width;
	
	NSRect currentWindowFrame = [[self window] frame];
	NSRect newWindowFrame = currentWindowFrame;
	
//	newWindowFrame.origin.x -= deltaX / 2;
	newWindowFrame.origin.y -= deltaY;

//	newWindowFrame.size.width += deltaX;
	newWindowFrame.size.height += deltaY;
	
	[[self window] setFrame:newWindowFrame display:YES animate:YES];
	
	if(newView) {
		[_bodyView addSubview:newView];
		[[self window] setTitle:[_selectorBar tooltipAtIndex:[newIndex integerValue]]];
	}
}

- (void) addItemWithView:(NSView *)view image:(NSImage *)image tooltip:(NSString *)tooltip
{
	NSParameterAssert(nil != view);
	NSParameterAssert(nil != image);
	
	[_views addObject:view];
	[[self selectorBar] addItemWithImage:image tooltip:tooltip];
}

- (ViewSelectorBar *) selectorBar
{
	return _selectorBar;
}

@end

@implementation ViewSelector (Private)

- (void) createSelectorBarAndBody
{
	// Divide our bounds into the bar and body areas
	NSRect selectorBarFrame, bodyFrame;	
	NSDivideRect([self bounds], &selectorBarFrame, &bodyFrame, VIEW_SELECTOR_BAR_HEIGHT, NSMaxYEdge);
	
	_selectorBar = [[ViewSelectorBar alloc] initWithFrame:selectorBarFrame];
	
	[_selectorBar setAutoresizingMask:(NSViewWidthSizable | NSViewMinYMargin)];
	
	[_selectorBar addObserver:self forKeyPath:@"selectedIndex" options:(NSKeyValueObservingOptionOld | NSKeyValueObservingOptionNew) context:NULL];
	
	_bodyView = [[NSView alloc] initWithFrame:bodyFrame];
	
	[_bodyView setAutoresizingMask:(NSViewWidthSizable | NSViewHeightSizable)];
	
	[self addSubview:_selectorBar];
	[self addSubview:_bodyView];

	[self setAutoresizesSubviews:YES];
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
//		NSString *paneAutosaveName = [autosaveName stringByAppendingFormat:@" %@ Pane", [pane title]];
//		
//		[[NSUserDefaults standardUserDefaults] setBool:pane.isCollapsed forKey:paneAutosaveName];
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

@end
