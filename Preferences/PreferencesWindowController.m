/*
 *  Copyright (C) 2008 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import "PreferencesWindowController.h"

// ========================================
// Identifiers for toolbar items
// ========================================
NSString * const	GeneralPreferencesToolbarItemIdentifier						= @"org.sbooth.Rip.Preferences.Toolbar.General";
NSString * const	EncoderPreferencesToolbarItemIdentifier						= @"org.sbooth.Rip.Preferences.Toolbar.Encoder";
NSString * const	MusicDatabasePreferencesToolbarItemIdentifier				= @"org.sbooth.Rip.Preferences.Toolbar.MusicDatabase";
NSString * const	AdvancedPreferencesToolbarItemIdentifier					= @"org.sbooth.Rip.Preferences.Toolbar.Advanced";

// ========================================
// The global instance
// ========================================
static PreferencesWindowController *sSharedPreferencesWindowController = nil;

@interface PreferencesWindowController (Private)
- (IBAction) toolbarItemSelected:(id)sender;
@end

@implementation PreferencesWindowController

+ (PreferencesWindowController *) sharedPreferencesWindowController
{
	if(!sSharedPreferencesWindowController)
		sSharedPreferencesWindowController = [[self alloc] init];
	return sSharedPreferencesWindowController;
}

- (id) init
{
	return [super initWithWindowNibName:@"PreferencesWindow"];
}

- (void) awakeFromNib
{
	// Set up the toolbar
    NSToolbar *toolbar = [[NSToolbar alloc] initWithIdentifier:@"org.sbooth.Rip.Preferences.Toolbar"];

    [toolbar setAllowsUserCustomization:NO];
    [toolbar setDelegate:self];
	
    [[self window] setToolbar:toolbar];
	
	// Determine which preference view to select
	NSString *itemIdentifier = [[NSUserDefaults standardUserDefaults] stringForKey:@"selectedPreferencePane"];

	// If the item identifier is nil, fall back to a visible item
	if(!itemIdentifier) {
		if(nil != [toolbar visibleItems] && 0 != [[toolbar visibleItems] count])
			itemIdentifier = [[[toolbar visibleItems] objectAtIndex:0] itemIdentifier];
		else if(nil != [toolbar items] && 0 != [[toolbar items] count])
			itemIdentifier = [[[toolbar items] objectAtIndex:0] itemIdentifier];
		else
			itemIdentifier = GeneralPreferencesToolbarItemIdentifier;
	}
	
	[self selectPreferencePaneWithIdentifier:itemIdentifier];
	
	// Center our window
	[[self window] center];
}

- (void) selectPreferencePaneWithIdentifier:(NSString *)itemIdentifier
{
	NSParameterAssert(nil != itemIdentifier);

	// Select the appropriate toolbar item if it isn't already
	if(![[[[self window] toolbar] selectedItemIdentifier] isEqualToString:itemIdentifier])
		[[[self window] toolbar] setSelectedItemIdentifier:itemIdentifier];
	
	// Remove any encoder settings subviews that are currently being displayed
	if(_preferencesViewController)
		[_preferencesViewController.view removeFromSuperview];
	
	// Adjust the window and view's frame size to match the preference's view size
	Class preferencesViewControllerClass = NSClassFromString([[[itemIdentifier componentsSeparatedByString:@"."] lastObject] stringByAppendingString:@"PreferencesViewController"]);
	_preferencesViewController = [[preferencesViewControllerClass alloc] init];

	// Calculate the difference between the current and target encoder settings view sizes
	NSRect currentViewFrame = [_preferencesView frame];
	NSRect targetViewFrame = [_preferencesViewController.view frame];
	
	CGFloat viewDeltaX = targetViewFrame.size.width - currentViewFrame.size.width;
	CGFloat viewDeltaY = targetViewFrame.size.height - currentViewFrame.size.height;
	
	// Calculate the new window and view sizes
	NSRect currentWindowFrame = [self.window frame];
	NSRect newWindowFrame = currentWindowFrame;
	
	newWindowFrame.origin.x -= viewDeltaX / 2;
	newWindowFrame.origin.y -= viewDeltaY;
	newWindowFrame.size.width += viewDeltaX;
	newWindowFrame.size.height += viewDeltaY;
	
	NSRect newViewFrame = currentViewFrame;
	
	newViewFrame.size.width += viewDeltaX;
	newViewFrame.size.height += viewDeltaY;
	
	// Set the new sizes
	[self.window setFrame:newWindowFrame display:YES animate:YES];
	[_preferencesView setFrame:newViewFrame];
	
	// Now that the sizes are correct, add the view controller's view to the view hierarchy
	[_preferencesView addSubview:_preferencesViewController.view];
	
	// Set the window's title to the name of the preference view
	[[self window] setTitle:[[self toolbar:[[self window] toolbar] 
					 itemForItemIdentifier:itemIdentifier 
				 willBeInsertedIntoToolbar:NO] label]];
	
	// Save the selected pane
	[[NSUserDefaults standardUserDefaults] setObject:itemIdentifier forKey:@"selectedPreferencePane"];	
}

@end

@implementation PreferencesWindowController (NSToolbarDelegateMethods)

- (NSToolbarItem *) toolbar:(NSToolbar *)toolbar itemForItemIdentifier:(NSString *)itemIdentifier willBeInsertedIntoToolbar:(BOOL)flag 
{
	
#pragma unused (toolbar)
#pragma unused (flag)
	
    NSToolbarItem *toolbarItem = nil;
	
    if([itemIdentifier isEqualToString:GeneralPreferencesToolbarItemIdentifier]) {
        toolbarItem = [[[NSToolbarItem alloc] initWithItemIdentifier:itemIdentifier] autorelease];
		
		[toolbarItem setLabel:NSLocalizedStringFromTable(@"General", @"Preferences", @"")];
		[toolbarItem setPaletteLabel:NSLocalizedStringFromTable(@"General", @"Preferences", @"")];		
		[toolbarItem setToolTip:NSLocalizedStringFromTable(@"Options that control the general behavior of Play", @"Preferences", @"")];
		[toolbarItem setImage:[NSImage imageNamed:@"NSPreferencesGeneral"]];
		
		[toolbarItem setTarget:self];
		[toolbarItem setAction:@selector(toolbarItemSelected:)];
	}
    else if([itemIdentifier isEqualToString:EncoderPreferencesToolbarItemIdentifier]) {
        toolbarItem = [[[NSToolbarItem alloc] initWithItemIdentifier:itemIdentifier] autorelease];
		
		[toolbarItem setLabel:NSLocalizedStringFromTable(@"Encoders", @"Preferences", @"")];
		[toolbarItem setPaletteLabel:NSLocalizedStringFromTable(@"Encoders", @"Preferences", @"")];
		[toolbarItem setToolTip:NSLocalizedStringFromTable(@"Specify hot keys used to control Play", @"Preferences", @"")];
		[toolbarItem setImage:[NSImage imageNamed:@"HotKeyPreferencesToolbarImage"]];
		
		[toolbarItem setTarget:self];
		[toolbarItem setAction:@selector(toolbarItemSelected:)];
	}
    else if([itemIdentifier isEqualToString:MusicDatabasePreferencesToolbarItemIdentifier]) {
        toolbarItem = [[[NSToolbarItem alloc] initWithItemIdentifier:itemIdentifier] autorelease];
		
		[toolbarItem setLabel:NSLocalizedStringFromTable(@"Metadata", @"Preferences", @"")];
		[toolbarItem setPaletteLabel:NSLocalizedStringFromTable(@"Metadata", @"Preferences", @"")];
		[toolbarItem setToolTip:NSLocalizedStringFromTable(@"Set the output device and replay gain used by Play", @"Preferences", @"")];
		[toolbarItem setImage:[NSImage imageNamed:@"OutputPreferencesToolbarImage"]];
		
		[toolbarItem setTarget:self];
		[toolbarItem setAction:@selector(toolbarItemSelected:)];
	}
    else if([itemIdentifier isEqualToString:AdvancedPreferencesToolbarItemIdentifier]) {
        toolbarItem = [[[NSToolbarItem alloc] initWithItemIdentifier:itemIdentifier] autorelease];
		
		[toolbarItem setLabel:NSLocalizedStringFromTable(@"Advanced", @"Preferences", @"")];
		[toolbarItem setPaletteLabel:NSLocalizedStringFromTable(@"Advanced", @"Preferences", @"")];
		[toolbarItem setToolTip:NSLocalizedStringFromTable(@"Control the size of the audio buffers used by Play", @"Preferences", @"")];
		[toolbarItem setImage:[NSImage imageNamed:@"NSAdvanced"]];
		
		[toolbarItem setTarget:self];
		[toolbarItem setAction:@selector(toolbarItemSelected:)];
	}
	
    return toolbarItem;
}

- (NSArray *) toolbarDefaultItemIdentifiers:(NSToolbar *)toolbar 
{

#pragma unused (toolbar)

	return [NSArray arrayWithObjects:
			GeneralPreferencesToolbarItemIdentifier,
			EncoderPreferencesToolbarItemIdentifier,
			MusicDatabasePreferencesToolbarItemIdentifier,
			AdvancedPreferencesToolbarItemIdentifier,
			nil];
}

- (NSArray *) toolbarAllowedItemIdentifiers:(NSToolbar *)toolbar 
{
	
#pragma unused (toolbar)

	return [NSArray arrayWithObjects:
			GeneralPreferencesToolbarItemIdentifier,
			EncoderPreferencesToolbarItemIdentifier,
			MusicDatabasePreferencesToolbarItemIdentifier,
			AdvancedPreferencesToolbarItemIdentifier,
			NSToolbarSeparatorItemIdentifier,
			NSToolbarSpaceItemIdentifier,
			NSToolbarFlexibleSpaceItemIdentifier,
			nil];
}

- (NSArray *) toolbarSelectableItemIdentifiers:(NSToolbar *)toolbar
{
	
#pragma unused (toolbar)

	return [NSArray arrayWithObjects:
			GeneralPreferencesToolbarItemIdentifier,
			EncoderPreferencesToolbarItemIdentifier,
			MusicDatabasePreferencesToolbarItemIdentifier,
			AdvancedPreferencesToolbarItemIdentifier,
			nil];
}

@end

@implementation PreferencesWindowController (Private)

- (IBAction) toolbarItemSelected:(id)sender
{
	NSParameterAssert(nil != sender);
	NSParameterAssert([sender isKindOfClass:[NSToolbarItem class]]);
	
	NSToolbarItem *sendingToolbarItem = (NSToolbarItem *)sender;
	[self selectPreferencePaneWithIdentifier:[sendingToolbarItem itemIdentifier]];
}

@end
