/*
 *  Copyright (C) 2009 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import "InspectorPanelController.h"
#import "CompactDiscWindowController.h"

#import <SFBInspectors/SFBInspectorView.h>

@interface InspectorPanelController ()
@property (assign) id inspectedDocument;
@end

@interface InspectorPanelController (Private)
- (void) activeDocumentChanged;
@end

@implementation InspectorPanelController

@synthesize inspectedDocument = _inspectedDocument;

- (id) init
{
	return [super initWithWindowNibName:@"InspectorPanel"];
}

- (void) awakeFromNib
{
	// Create the various inspector panels
	NSViewController *viewController = [[NSViewController alloc] initWithNibName:@"TrackInspectorView" bundle:nil];
	viewController.title = NSLocalizedString(@"Track Information", @"The name of the track inspector panel");
	[viewController bind:@"representedObject" toObject:self withKeyPath:@"inspectedDocument" options:nil];
	[_inspectorView addInspectorPaneController:viewController];

	viewController = [[NSViewController alloc] initWithNibName:@"DiscInspectorView" bundle:nil];
	viewController.title = NSLocalizedString(@"Disc Information", @"The name of the disc inspector panel");
	[viewController bind:@"representedObject" toObject:self withKeyPath:@"inspectedDocument" options:nil];
	[_inspectorView addInspectorPaneController:viewController];

	viewController = [[NSViewController alloc] initWithNibName:@"DriveInspectorView" bundle:nil];
	viewController.title = NSLocalizedString(@"Drive Information", @"The name of the drive inspector panel");
	[viewController bind:@"representedObject" toObject:self withKeyPath:@"inspectedDocument" options:nil];
	[_inspectorView addInspectorPaneController:viewController];
}

- (void) windowDidLoad
{
	[[self window] setMovableByWindowBackground:YES];
	
	[self activeDocumentChanged];
	[[NSApplication sharedApplication] addObserver:self forKeyPath:@"mainWindow.windowController" options:0 context:[self class]];
	
	[super windowDidLoad];
}

- (NSString *) windowFrameAutosaveName
{
	return @"Inspector Panel";
}

- (void) observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
	if(context == [self class])
		[self activeDocumentChanged];
	else
		[super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
}

- (IBAction) toggleInspectorPanel:(id)sender
{
    NSWindow *window = self.window;
	
	if(window.isVisible)
		[window orderOut:sender];
	else
		[window orderFront:sender];
}

- (BOOL) validateMenuItem:(NSMenuItem *)menuItem
{
	if([menuItem action] == @selector(toggleInspectorPanel:)) {
		NSString *menuTitle = nil;		
		if(!self.isWindowLoaded || !self.window.isVisible)
			menuTitle = NSLocalizedString(@"Show Inspector", @"Menu Item");
		else
			menuTitle = NSLocalizedString(@"Hide Inspector", @"Menu Item");
		
		[menuItem setTitle:menuTitle];
		
		return YES;
	}
	else	
		return NO;
}

@end

@implementation InspectorPanelController (Private)

- (void) activeDocumentChanged
{
	id mainDocument = [[[NSApplication sharedApplication] mainWindow] windowController];
	if(mainDocument != self.inspectedDocument)
		self.inspectedDocument = (mainDocument && [mainDocument isKindOfClass:[CompactDiscWindowController class]]) ? mainDocument : nil;   
}

@end
