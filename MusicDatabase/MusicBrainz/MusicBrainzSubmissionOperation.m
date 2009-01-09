/*
 *  Copyright (C) 2009 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import "MusicBrainzSubmissionOperation.h"
#import <IOKit/storage/IOCDTypes.h>

#include <discid/discid.h>

@interface MusicDatabaseSubmissionOperation ()
@property (copy) NSError * error;
@end

@interface MusicBrainzSubmissionOperation (Private)
- (NSURL *) submissionURLForDiscTOC:(CDTOC *)toc;
@end

@implementation MusicBrainzSubmissionOperation

- (void) main
{
	NSAssert(NULL != self.discTOC, @"self.discTOC may not be nil");
	
	// Convert the disc's TOC to libcddb's format
	NSURL *submissionURL = [self submissionURLForDiscTOC:(CDTOC *)[self.discTOC bytes]];
	if(!submissionURL)
		return;

	[[NSWorkspace sharedWorkspace] performSelectorOnMainThread:@selector(openURL:) withObject:submissionURL waitUntilDone:NO];
}

@end

@implementation MusicBrainzSubmissionOperation (Private)

- (NSURL *) submissionURLForDiscTOC:(CDTOC *)toc
{
	NSParameterAssert(NULL != toc);
	
	DiscId *discID = discid_new();
	if(NULL == discID)
		return NULL;
	
	int offsets[100];
	int firstTrackNumber = 0, lastTrackNumber = 0;
	
	// Non-existent tracks are treated as zeroes
	memset(offsets, 0, 100 * sizeof(int));
	
	// Iterate through each descriptor and extract the information we need
	NSUInteger numDescriptors = CDTOCGetDescriptorCount(toc);
	NSUInteger i;
	for(i = 0; i < numDescriptors; ++i) {
		CDTOCDescriptor *desc = &toc->descriptors[i];
		
		// For multi-session discs only the first session is used to generate the MusicBrainz ID
		if(1 != desc->session)
			continue;
		
		// This is a normal audio or data track
		if(0x01 <= desc->point && 0x63 >= desc->point && 1 == desc->adr)
			offsets[desc->point] = CDConvertMSFToLBA(desc->p) + 150;
		// First track
		else if(0xA0 == desc->point && 1 == desc->adr)
			firstTrackNumber = desc->p.minute;
		// Last track
		else if(0xA1 == desc->point && 1 == desc->adr)
			lastTrackNumber = desc->p.minute;
		// Lead-out
		else if(0xA2 == desc->point && 1 == desc->adr)
			offsets[0] = CDConvertMSFToLBA(desc->p) + 150;
	}

	NSURL *submissionURL = nil;
	int result = discid_put(discID, firstTrackNumber, lastTrackNumber, offsets);
	if(result)
		submissionURL = [NSURL URLWithString:[NSString stringWithCString:discid_get_submission_url(discID) encoding:NSASCIIStringEncoding]];

	discid_free(discID);
	
	return submissionURL;
}

@end
