/*
 *  Copyright (C) 2007 - 2009 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import "TrackInspectorPanelController.h"
#import "CompactDiscWindowController.h"

@interface TrackInspectorPanelController ()
@property (assign) id inspectedDocument;
@end

@interface TrackInspectorPanelController (Private)
- (void) activeDocumentChanged;
@end

@implementation TrackInspectorPanelController

@synthesize inspectedDocument = _inspectedDocument;

- (id) init
{
	return [super initWithWindowNibName:@"TrackInspectorPanel"];
}

- (void) windowDidLoad
{
	[self activeDocumentChanged];
	[[NSApplication sharedApplication] addObserver:self forKeyPath:@"mainWindow.windowController" options:0 context:[self class]];

	[super windowDidLoad];
}

- (void) observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
	if(context == [self class])
		[self activeDocumentChanged];
	else
		[super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
}

- (IBAction) toggleTrackInspectorPanel:(id)sender
{
    NSWindow *window = self.window;
	
	if(window.isVisible && window.isKeyWindow)
		[window orderOut:sender];
	else
		[window makeKeyAndOrderFront:sender];
}

- (BOOL) validateMenuItem:(NSMenuItem *)menuItem
{
	if([menuItem action] == @selector(toggleTrackInspectorPanel:)) {
		NSString *menuTitle = nil;

		if(!self.isWindowLoaded || !self.window.isVisible || !self. window.isKeyWindow)
			menuTitle = NSLocalizedString(@"Show Track Inspector", @"Menu Item");
		else
			menuTitle = NSLocalizedString(@"Hide Track Inspector", @"Menu Item");

		[menuItem setTitle:menuTitle];
	}
	
	return YES;
}

@end

@implementation TrackInspectorPanelController (Private)

- (void) activeDocumentChanged
{
	id mainDocument = [[[NSApplication sharedApplication] mainWindow] windowController];
	if(mainDocument != self.inspectedDocument)
		self.inspectedDocument = (mainDocument && [mainDocument isKindOfClass:[CompactDiscWindowController class]]) ? mainDocument : nil;   
}

@end
