/*
 *  Copyright (C) 2009 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import <Cocoa/Cocoa.h>

@interface MetadataEditorPanelController : NSWindowController
{
	IBOutlet NSObjectController *_documentObjectController;
	
@private
	id _inspectedDocument;
}

@property (readonly, assign) id inspectedDocument;

- (IBAction) toggleMetadataEditorPanel:(id)sender;

@end
