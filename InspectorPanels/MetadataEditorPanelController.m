/*
 *  Copyright (C) 2009 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import "MetadataEditorPanelController.h"
#import "CompactDiscWindowController.h"
#import "ViewSelector.h"

@interface MetadataEditorPanelController ()
@property (readonly) NSManagedObjectContext * managedObjectContext;
@property (readonly) id managedObjectModel;

@property (assign) id inspectedDocument;
@end

@interface MetadataEditorPanelController (Private)
- (void) activeDocumentChanged;
@end

@implementation MetadataEditorPanelController

@synthesize inspectedDocument = _inspectedDocument;

- (id) init
{
	return [super initWithWindowNibName:@"MetadataEditorPanel"];
}

- (void) awakeFromNib
{
	NSImage *image = [NSImage imageNamed:@"AlbumMetadataEditorPaneIcon"];
	[image setSize:NSMakeSize(16, 16)];

	NSViewController *viewController = [[NSViewController alloc] initWithNibName:@"AlbumMetadataInspectorView" bundle:nil];
	[viewController bind:@"representedObject" toObject:self withKeyPath:@"inspectedDocument" options:nil];
	[_viewSelector addItemWithView:[viewController view] image:image tooltip:NSLocalizedString(@"Album Metadata", @"")];

	image = [NSImage imageNamed:@"TrackMetadataEditorPaneIcon"];
	[image setSize:NSMakeSize(16, 16)];

	viewController = [[NSViewController alloc] initWithNibName:@"TrackMetadataInspectorView" bundle:nil];
	[viewController bind:@"representedObject" toObject:self withKeyPath:@"inspectedDocument" options:nil];
	[_viewSelector addItemWithView:[viewController view] image:image tooltip:NSLocalizedString(@"Track Metadata", @"")];

	image = [NSImage imageNamed:@"NSAdvanced"];
	[image setSize:NSMakeSize(16, 16)];
	
	viewController = [[NSViewController alloc] initWithNibName:@"TrackLyricsInspectorView" bundle:nil];
	[viewController bind:@"representedObject" toObject:self withKeyPath:@"inspectedDocument" options:nil];
	[_viewSelector addItemWithView:[viewController view] image:image tooltip:NSLocalizedString(@"Lyrics", @"")];
	
	image = [NSImage imageNamed:@"AdditionalAlbumMetadataEditorPaneIcon"];
	[image setSize:NSMakeSize(16, 16)];

	viewController = [[NSViewController alloc] initWithNibName:@"AdditionalAlbumMetadataInspectorView" bundle:nil];
	[viewController bind:@"representedObject" toObject:self withKeyPath:@"inspectedDocument" options:nil];
	[_viewSelector addItemWithView:[viewController view] image:image tooltip:NSLocalizedString(@"Additional Album Metadata", @"")];

	image = [NSImage imageNamed:@"AdditionalTrackMetadataEditorPaneIcon"];
	[image setSize:NSMakeSize(16, 16)];

	viewController = [[NSViewController alloc] initWithNibName:@"AdditionalTrackMetadataInspectorView" bundle:nil];
	[viewController bind:@"representedObject" toObject:self withKeyPath:@"inspectedDocument" options:nil];
	[_viewSelector addItemWithView:[viewController view] image:image tooltip:NSLocalizedString(@"Additional Track Metadata", @"")];
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

#pragma mark Core Data

// All instances of this class share the application's ManagedObjectContext and ManagedObjectModel
- (NSManagedObjectContext *) managedObjectContext
{
	return [[[NSApplication sharedApplication] delegate] managedObjectContext];
}

- (id) managedObjectModel
{
	return [[[NSApplication sharedApplication] delegate] managedObjectModel];
}

- (IBAction) toggleMetadataEditorPanel:(id)sender
{
    NSWindow *window = self.window;
	
	if(window.isVisible && window.isKeyWindow)
		[window orderOut:sender];
	else
		[window makeKeyAndOrderFront:sender];
}

- (BOOL) validateMenuItem:(NSMenuItem *)menuItem
{
	if([menuItem action] == @selector(toggleMetadataEditorPanel:)) {
		NSString *menuTitle = nil;
		
		if(!self.isWindowLoaded || !self.window.isVisible/* || !self. window.isKeyWindow*/)
			menuTitle = NSLocalizedString(@"Show Metadata Editor", @"Menu Item");
		else
			menuTitle = NSLocalizedString(@"Hide Metadata Editor", @"Menu Item");
		
		[menuItem setTitle:menuTitle];
	}
	
	return YES;
}

@end

@implementation MetadataEditorPanelController (Private)

- (void) activeDocumentChanged
{
	id mainDocument = [[[NSApplication sharedApplication] mainWindow] windowController];
	if(mainDocument != self.inspectedDocument)
		self.inspectedDocument = (mainDocument && [mainDocument isKindOfClass:[CompactDiscWindowController class]]) ? mainDocument : nil;   
}

@end
