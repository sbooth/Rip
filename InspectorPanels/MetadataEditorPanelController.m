/*
 *  Copyright (C) 2009 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import "MetadataEditorPanelController.h"
#import "CompactDiscWindowController.h"

#import <SFBInspectors/SFBViewSelector.h>
#import <SFBInspectors/SFBViewSelectorBar.h>
#import <SFBInspectors/SFBViewSelectorBarItem.h>

@interface MetadataEditorPanelController ()
@property (readonly) NSManagedObjectContext * managedObjectContext;
@property (readonly) id managedObjectModel;

@property (assign) id inspectedDocument;
@end

@interface MetadataEditorPanelController (Private)
- (void) activeDocumentChanged;
- (void) applicationWillTerminate:(NSNotification *)notification;
@end

@implementation MetadataEditorPanelController

@synthesize inspectedDocument = _inspectedDocument;

- (id) init
{
	return [super initWithWindowNibName:@"MetadataEditorPanel"];
}

- (void) awakeFromNib
{
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(applicationWillTerminate:) name:NSApplicationWillTerminateNotification object:nil];

	NSViewController *viewController = [[NSViewController alloc] initWithNibName:@"AlbumMetadataInspectorView" bundle:nil];
	[viewController bind:@"representedObject" toObject:self withKeyPath:@"inspectedDocument" options:nil];
	
	SFBViewSelectorBarItem *item = [SFBViewSelectorBarItem itemWithIdentifier:@"org.sbooth.Rip.MetadataEditor.AlbumMetadata" 
																		label:NSLocalizedString(@"Album Metadata", @"")
																	  tooltip:NSLocalizedString(@"Album Metadata", @"")
																		image:[NSImage imageNamed:@"AlbumMetadataEditorPaneIcon"]
																		 view:[viewController view]];
	
	[[_viewSelector selectorBar] addItem:item];

	viewController = [[NSViewController alloc] initWithNibName:@"TrackMetadataInspectorView" bundle:nil];
	[viewController bind:@"representedObject" toObject:self withKeyPath:@"inspectedDocument" options:nil];
	
	item = [SFBViewSelectorBarItem itemWithIdentifier:@"org.sbooth.Rip.MetadataEditor.TrackMetadata" 
												label:NSLocalizedString(@"Track Metadata", @"")
											  tooltip:NSLocalizedString(@"Track Metadata", @"")
												image:[NSImage imageNamed:@"TrackMetadataEditorPaneIcon"]
												 view:[viewController view]];
	
	[[_viewSelector selectorBar] addItem:item];
	
	viewController = [[NSViewController alloc] initWithNibName:@"AlbumArtInspectorView" bundle:nil];
	[viewController bind:@"representedObject" toObject:self withKeyPath:@"inspectedDocument" options:nil];
	
	item = [SFBViewSelectorBarItem itemWithIdentifier:@"org.sbooth.Rip.MetadataEditor.AlbumArt" 
												label:NSLocalizedString(@"Album Art", @"")
											  tooltip:NSLocalizedString(@"Album Art", @"")
												image:[NSImage imageNamed:@"AlbumArtEditorPaneIcon"]
												 view:[viewController view]];
	
	[[_viewSelector selectorBar] addItem:item];

	viewController = [[NSViewController alloc] initWithNibName:@"TrackLyricsInspectorView" bundle:nil];
	[viewController bind:@"representedObject" toObject:self withKeyPath:@"inspectedDocument" options:nil];
	
	item = [SFBViewSelectorBarItem itemWithIdentifier:@"org.sbooth.Rip.MetadataEditor.Lyrics" 
												label:NSLocalizedString(@"Lyrics", @"")
											  tooltip:NSLocalizedString(@"Lyrics", @"")
												image:[NSImage imageNamed:@"LyricsMetadataEditorPaneIcon"]
												 view:[viewController view]];
	
	[[_viewSelector selectorBar] addItem:item];

	viewController = [[NSViewController alloc] initWithNibName:@"AdditionalAlbumMetadataInspectorView" bundle:nil];
	[viewController bind:@"representedObject" toObject:self withKeyPath:@"inspectedDocument" options:nil];
	
	item = [SFBViewSelectorBarItem itemWithIdentifier:@"org.sbooth.Rip.MetadataEditor.AdditionalAlbumMetadata" 
												label:NSLocalizedString(@"Additional Album Metadata", @"")
											  tooltip:NSLocalizedString(@"Additional Album Metadata", @"")
												image:[NSImage imageNamed:@"AdditionalAlbumMetadataEditorPaneIcon"]
												 view:[viewController view]];
	
	[[_viewSelector selectorBar] addItem:item];

	viewController = [[NSViewController alloc] initWithNibName:@"AdditionalTrackMetadataInspectorView" bundle:nil];
	[viewController bind:@"representedObject" toObject:self withKeyPath:@"inspectedDocument" options:nil];
	
	item = [SFBViewSelectorBarItem itemWithIdentifier:@"org.sbooth.Rip.MetadataEditor.AdditionalTrackMetadata" 
												label:NSLocalizedString(@"Additional Track Metadata", @"")
											  tooltip:NSLocalizedString(@"Additional Track Metadata", @"")
												image:[NSImage imageNamed:@"AdditionalTrackMetadataEditorPaneIcon"]
												 view:[viewController view]];
	
	[[_viewSelector selectorBar] addItem:item];

	// Restore the selected pane
	NSString *autosaveName = [[self window] frameAutosaveName];
	if(autosaveName) {
		NSString *selectedPaneDefaultsName = [autosaveName stringByAppendingFormat:@" Selected Pane"];		
		NSString *selectedIdentifier = [[NSUserDefaults standardUserDefaults] stringForKey:selectedPaneDefaultsName];
		
		if(selectedIdentifier)
			[[_viewSelector selectorBar] selectItemWithIdentifer:selectedIdentifier];
	}	
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
	return @"Metadata Editor Panel";
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

- (void) applicationWillTerminate:(NSNotification *)notification
{
	
#pragma unused(notification)
	
	[[NSNotificationCenter defaultCenter] removeObserver:self];
	
	// Save the selected pane
	NSString *autosaveName = [[self window] frameAutosaveName];
	if(autosaveName) {
		NSString *selectedIdentifier = [[[_viewSelector selectorBar] selectedItem] identifier];
		NSString *selectedPaneDefaultsName = [autosaveName stringByAppendingFormat:@" Selected Pane"];
		
		[[NSUserDefaults standardUserDefaults] setValue:selectedIdentifier forKey:selectedPaneDefaultsName];
		
		[[NSUserDefaults standardUserDefaults] synchronize];
	}	
}

@end
