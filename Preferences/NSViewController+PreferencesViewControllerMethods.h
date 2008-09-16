/*
 *  Copyright (C) 2008 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import <Cocoa/Cocoa.h>

// ========================================
// Informal protocol for NSViewController subclasses controlling a preferences view
// ========================================
@interface NSViewController (PreferencesViewControllerMethods)
- (IBAction) restoreDefaults:(id)sender;
- (IBAction) savePreferences:(id)sender;
@end
