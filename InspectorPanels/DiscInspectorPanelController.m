/*
 *  Copyright (C) 2007 - 2008 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import "DiscInspectorPanelController.h"
#import "CompactDiscWindowController.h"

@interface DiscInspectorPanelController ()
@property (assign) id inspectedDocument;
@end

@interface DiscInspectorPanelController (Private)
- (void) activeDocumentChanged;
@end

@implementation DiscInspectorPanelController

@synthesize inspectedDocument = _inspectedDocument;

- (id) init
{
	return [super initWithWindowNibName:@"DiscInspectorPanel"];
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

- (IBAction) toggleDiscInspectorPanel:(id)sender
{
    NSWindow *window = self.window;
	
	if(window.isVisible && window.isKeyWindow)
		[window orderOut:sender];
	else
		[window makeKeyAndOrderFront:sender];
}

- (BOOL) validateMenuItem:(NSMenuItem *)menuItem
{
	if([menuItem action] == @selector(toggleDiscInspectorPanel:)) {
		NSString *menuTitle = nil;

		if(!self.isWindowLoaded || !self.window.isVisible || !self. window.isKeyWindow)
			menuTitle = NSLocalizedString(@"Show Disc Inspector", @"Menu Item");
		else
			menuTitle = NSLocalizedString(@"Hide Disc Inspector", @"Menu Item");

		[menuItem setTitle:menuTitle];
	}
	
	return YES;
}

@end

@implementation DiscInspectorPanelController (Private)

- (void) activeDocumentChanged
{
	id mainDocument = [[[NSApplication sharedApplication] mainWindow] windowController];
	if(mainDocument != self.inspectedDocument)
		self.inspectedDocument = (mainDocument && [mainDocument isKindOfClass:[CompactDiscWindowController class]]) ? mainDocument : nil;   
}

@end
