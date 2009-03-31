/*
 *  Copyright (C) 2009 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import <Cocoa/Cocoa.h>

// ========================================
// The interface an external metadata source (Discogs, AlbumArtExchange, etc) must implement to integrate with Rip
// ========================================
@protocol MetadataSourceInterface

// The default settings, if any
- (NSDictionary *) defaultSettings;

// Create an instance of NSViewController allowing users to edit the metadata source's configuration
// The controller's representedObject will be set to the applicable metadata source settings (NSDictionary *)
- (NSViewController *) configurationViewController;

// Create an instance of NSViewController allowing users to edit the metadata source's configuration
// The controller's representedObject will be set to XXX
- (NSViewController *) metadataSourceViewController;

@end
