/*
 *  Copyright (C) 2008 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import <Cocoa/Cocoa.h>

// ========================================
// Identifiers for toolbar items
// ========================================
extern NSString	* const		GeneralPreferencesToolbarItemIdentifier;
extern NSString	* const		EncoderPreferencesToolbarItemIdentifier;
extern NSString	* const		MusicDatabasePreferencesToolbarItemIdentifier;
extern NSString * const		AdvancedPreferencesToolbarItemIdentifier;

// ========================================
// This class manages the preference window
// ========================================
@interface PreferencesWindowController : NSWindowController
{
	IBOutlet NSView *_preferencesView;

@private
	NSViewController *_preferencesViewController;
}

// ========================================
// The shared instance
+ (PreferencesWindowController *) sharedPreferencesWindowController;

- (void) selectPreferencePaneWithIdentifier:(NSString *)itemIdentifier;

@end
