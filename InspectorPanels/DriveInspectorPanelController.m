/*
 *  Copyright (C) 2007 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import "DriveInspectorPanelController.h"
#import "CompactDiscDocument.h"

@interface DriveInspectorPanelController (Private)
- (void) activeDocumentChanged;
@end

@implementation DriveInspectorPanelController

@synthesize inspectedDocument;

- (id) init
{
	return [super initWithWindowNibName:@"DriveInspectorPanel"];
}

- (void) windowDidLoad
{
	[self activeDocumentChanged];
	[[NSApplication sharedApplication] addObserver:self forKeyPath:@"mainWindow.windowController.document" options:0 context:[DriveInspectorPanelController class]];

	[super windowDidLoad];
}

- (void) observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
	if(context == [DriveInspectorPanelController class])
		[self activeDocumentChanged];
	else
		[super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
}

- (IBAction) toggleDriveInspectorPanel:(id)sender
{
    NSWindow *window = [self window];
	
	if([window isVisible] && [window isKeyWindow])
		[window orderOut:sender];
	else
		[window makeKeyAndOrderFront:sender];
}

- (BOOL) validateMenuItem:(NSMenuItem *)menuItem
{
	if([menuItem action] == @selector(toggleDriveInspectorPanel:)) {
		NSString *menuTitle = nil;

		if(![self isWindowLoaded] || ![[self window] isVisible] || ![[self window] isKeyWindow])
			menuTitle = NSLocalizedStringFromTable(@"Show Drive Inspector", @"Menus", @"");
		else
			menuTitle = NSLocalizedStringFromTable(@"Hide Drive Inspector", @"Menus", @"");

		[menuItem setTitle:menuTitle];
	}
	
	return YES;
}

@end

@implementation DriveInspectorPanelController (Private)

- (void) activeDocumentChanged
{
	id mainDocument = [[[[NSApplication sharedApplication] mainWindow] windowController] document];
	if(mainDocument != inspectedDocument)
		self.inspectedDocument = (mainDocument && [mainDocument isKindOfClass:[CompactDiscDocument class]]) ? mainDocument : nil;   
}


@end
