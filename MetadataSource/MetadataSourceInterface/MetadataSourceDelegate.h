/*
 *  Copyright (C) 2009 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

// ========================================
// Protocol implemented by the delegate, to be called when the metadata source is finished processing
// ========================================
@protocol MetadataSourceDelegate
- (void) metadataSourceViewController:(NSViewController *)viewController finishedWithReturnCode:(int)returnCode;
@end
