/*
 *  Copyright (C) 2007 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import "CompactDiscDocument.h"

#import "CompactDisc.h"
#import "SessionDescriptor.h"
#import "TrackDescriptor.h"
#import "AccurateRipDisc.h"
#import "DriveInformation.h"
#import "SectorRange.h"
#import "ExtractionOperation.h"
#import "BitArray.h"

// ========================================
// KVC key names for the metadata dictionaries
// ========================================
NSString * const	kMetadataTitleKey						= @"title";
NSString * const	kMetadataAlbumTitleKey					= @"albumTitle";
NSString * const	kMetadataArtistKey						= @"artist";
NSString * const	kMetadataAlbumArtistKey					= @"albumArtist";
NSString * const	kMetadataGenreKey						= @"genre";
NSString * const	kMetadataComposerKey					= @"composer";
NSString * const	kMetadataDateKey						= @"date";
NSString * const	kMetadataCompilationKey					= @"compilation";
NSString * const	kMetadataTrackNumberKey					= @"trackNumber";
NSString * const	kMetadataTrackTotalKey					= @"trackTotal";
NSString * const	kMetadataDiscNumberKey					= @"discNumber";
NSString * const	kMetadataDiscTotalKey					= @"discTotal";
NSString * const	kMetadataCommentKey						= @"comment";
NSString * const	kMetadataISRCKey						= @"isrc";
NSString * const	kMetadataMCNKey							= @"mcn";
NSString * const	kMetadataBPMKey							= @"bpm";
NSString * const	kMetadataMusicDNSPUIDKey				= @"musicDNSPUID";
NSString * const	kMetadataMusicBrainzIDKey				= @"musicBrainzID";

// ========================================
// Context objects for observeValueForKeyPath:ofObject:change:context:
// ========================================
NSString * const	kKVOExtractionContext					= @"org.sbooth.Rip.CompactDiscDocument.ExtractionContext";

@interface CompactDiscDocument ()
@property (copy) CompactDisc * compactDisc;
@property (copy) AccurateRipDisc * accurateRipDisc;
@property (copy) DriveInformation * driveInformation;
@end

@interface CompactDiscDocument (Private)
- (void) extractionStartedForOperation:(ExtractionOperation *)operation;
- (void) extractionStoppedForOperation:(ExtractionOperation *)operation;
@end

@implementation CompactDiscDocument

@synthesize trackController = _trackController;
@synthesize driveInformationController = _driveInformationController;
@synthesize extractionQueue = _extractionQueue;
@synthesize encodingQueue = _encodingQueue;

@synthesize disk = _disk;
@synthesize compactDisc = _compactDisc;
@synthesize accurateRipDisc = _accurateRipDisc;
@synthesize driveInformation = _driveInformation;
@synthesize metadata = _metadata;

- (id) init
{
	if((self = [super init])) {
		_tracks = [[NSMutableArray alloc] init];
		_metadata = [[NSMutableDictionary alloc] init];
		_extractionQueue = [[NSOperationQueue alloc] init];
		_encodingQueue = [[NSOperationQueue alloc] init];

		// Only extract one track at a time
		[self.extractionQueue setMaxConcurrentOperationCount:1];
		
		// Observe changes in the extraction operations array, to be notified when extraction starts and stops
		[self.extractionQueue addObserver:self forKeyPath:@"operations" options:(NSKeyValueObservingOptionOld |  NSKeyValueObservingOptionNew) context:kKVOExtractionContext];
	}
	return self;
}

- (void) finalize
{
	if(_disk)
		CFRelease(_disk), _disk = NULL;
	
	[super finalize];
}

- (void) awakeFromNib
{
	// Set the default sort descriptors for the track table
	NSSortDescriptor *trackNumberSortDescriptor = [[NSSortDescriptor alloc] initWithKey:@"number" ascending:YES];
	[self.trackController setSortDescriptors:[NSArray arrayWithObject:trackNumberSortDescriptor]];
}

- (BOOL) validateMenuItem:(NSMenuItem *)menuItem
{
	if([menuItem action] == @selector(copySelectedTracks:)) {
		NSPredicate *selectedTracksPredicate = [NSPredicate predicateWithFormat:@"selected == 1"];
		NSArray *selectedTracks = [_tracks filteredArrayUsingPredicate:selectedTracksPredicate];
		return (0 != selectedTracks.count);
	}
	else if([menuItem action] == @selector(copyImage:))
		return YES;
	else
		return [super validateMenuItem:menuItem];
}

- (BOOL) validateToolbarItem:(NSToolbarItem *)toolbarItem
{
	if([toolbarItem action] == @selector(copySelectedTracks:)) {
		NSPredicate *selectedTracksPredicate = [NSPredicate predicateWithFormat:@"selected == 1"];
		NSArray *selectedTracks = [_tracks filteredArrayUsingPredicate:selectedTracksPredicate];
		return (0 != selectedTracks.count);
	}
	else if([toolbarItem action] == @selector(copyImage:))
		return YES;
	else
		return [super validateToolbarItem:toolbarItem];
}

- (void) observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
	if(kKVOExtractionContext == context) {
		NSInteger changeKind = [[change objectForKey:NSKeyValueChangeKindKey] integerValue];
		
		if(NSKeyValueChangeInsertion == changeKind) {
			NSArray *startedOperations = [[change objectForKey:NSKeyValueChangeNewKey] objectsAtIndexes:[change objectForKey:NSKeyValueChangeIndexesKey]];
			for(ExtractionOperation *operation in startedOperations)
				[self extractionStartedForOperation:operation];
		}
		else if(NSKeyValueChangeRemoval == changeKind) {
			NSArray *stoppedOperations = [[change objectForKey:NSKeyValueChangeOldKey] objectsAtIndexes:[change objectForKey:NSKeyValueChangeIndexesKey]];
			for(ExtractionOperation *operation in stoppedOperations)
				[self extractionStoppedForOperation:operation];
		}
	}
	else
		[super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
}

- (void) setDisk:(DADiskRef)disk
{
	if(disk != _disk) {
		if(_disk)
			CFRelease(_disk), _disk = NULL;
		
		self.compactDisc = nil;
		self.accurateRipDisc = nil;
		self.driveInformation = nil;
		
		if(disk) {
			_disk = DADiskCopyWholeDisk(disk);
			self.compactDisc = [[CompactDisc alloc] initWithDADiskRef:self.disk];
			self.accurateRipDisc = [[AccurateRipDisc alloc] initWithCompactDisc:self.compactDisc];
			self.driveInformation = [[DriveInformation alloc] initWithDADiskRef:self.disk];
		}
	}
}

- (void) setCompactDisc:(CompactDisc *)compactDisc
{
	if(compactDisc != _compactDisc) {
		_compactDisc = [compactDisc copy];
		
		// For multi-session discs only the first session is used
		SessionDescriptor *session = [self.compactDisc sessionNumber:1];
		
		[self willChangeValueForKey:@"tracks"];
		_tracks = [[NSMutableArray alloc] init];
		
		NSUInteger trackNumber;
		for(trackNumber = session.firstTrack; trackNumber <= session.lastTrack; ++trackNumber) {
			TrackDescriptor *track = [self.compactDisc trackNumber:trackNumber];
			NSMutableDictionary *trackDictionary = [[NSMutableDictionary alloc] init];

			[trackDictionary setObject:[[NSMutableDictionary alloc] init] forKey:@"metadata"];

			[trackDictionary setObject:[NSNumber numberWithBool:NO] forKey:@"selected"];
			[trackDictionary setObject:[NSNumber numberWithInteger:track.number] forKey:@"number"];
			[trackDictionary setObject:[NSNumber numberWithInteger:track.firstSector] forKey:@"firstSector"];
			[trackDictionary setObject:[NSNumber numberWithInteger:track.channels] forKey:@"channels"];
			[trackDictionary setObject:[NSNumber numberWithBool:track.preEmphasis] forKey:@"preEmphasis"];
			[trackDictionary setObject:[NSNumber numberWithBool:track.copyPermitted] forKey:@"copyPermitted"];

			// Flesh out lastSector and sectorCount
			if(track.number != session.firstTrack) {
				NSMutableDictionary *previousTrackDictionary = [_tracks lastObject];
				[previousTrackDictionary setObject:[NSNumber numberWithInteger:(track.firstSector - 1)] forKey:@"lastSector"];
				[previousTrackDictionary setObject:[NSNumber numberWithInteger:([[previousTrackDictionary objectForKey:@"lastSector"] integerValue] - [[previousTrackDictionary objectForKey:@"firstSector"] integerValue])] forKey:@"sectorCount"];
			}
			
			if(track.number == session.lastTrack) {
				[trackDictionary setObject:[NSNumber numberWithInteger:(session.leadOut - 1)] forKey:@"lastSector"];
				[trackDictionary setObject:[NSNumber numberWithInteger:([[trackDictionary objectForKey:@"lastSector"] integerValue] - [[trackDictionary objectForKey:@"firstSector"] integerValue])] forKey:@"sectorCount"];
			}
			
			[_tracks addObject:trackDictionary];
		}
		
		[self didChangeValueForKey:@"tracks"];
	}
}

- (NSString *) windowNibName
{
	return @"CompactDiscDocument";
}

- (void) windowControllerDidLoadNib:(NSWindowController *)aController
{
	[super windowControllerDidLoadNib:aController];
}

- (NSData *) dataOfType:(NSString *)typeName error:(NSError **)outError
{
	
#pragma unused(typeName)
	
	if(NULL !=  outError)
		*outError = [NSError errorWithDomain:NSOSStatusErrorDomain code:unimpErr userInfo:NULL];

	return nil;
}

- (BOOL) readFromData:(NSData *)data ofType:(NSString *)typeName error:(NSError **)outError
{

#pragma unused(data)
#pragma unused(typeName)

	if(NULL !=  outError)
		*outError = [NSError errorWithDomain:NSOSStatusErrorDomain code:unimpErr userInfo:NULL];

	return YES;
}

- (void) tableView:(NSTableView *)aTableView willDisplayCell:(id)aCell forTableColumn:(NSTableColumn *)aTableColumn row:(NSInteger)rowIndex
{

#pragma unused(aTableView)

	if([[aTableColumn identifier] isEqualToString:@"selected"]) {
		[aCell setTitle:[[[[_trackController arrangedObjects] objectAtIndex:rowIndex] valueForKey:@"number"] stringValue]];
		
	}
}

#pragma mark Action Methods

- (IBAction) copySelectedTracks:(id)sender
{
	
#pragma unused(sender)
	
	NSPredicate *selectedTracksPredicate = [NSPredicate predicateWithFormat:@"selected == 1"];
	NSArray *selectedTracks = [_tracks filteredArrayUsingPredicate:selectedTracksPredicate];
	
	if(0 == selectedTracks.count) {
		NSBeep();
		return;
	}
	
	// Limit the audio extraction to the first session
	SessionDescriptor *session = [self.compactDisc sessionNumber:1];
	
	for(NSDictionary *trackDictionary in selectedTracks) {
		SectorRange *trackSectorRange = [SectorRange sectorRangeWithFirstSector:[[trackDictionary objectForKey:@"firstSector"] integerValue]
																	 lastSector:[[trackDictionary objectForKey:@"lastSector"] integerValue]];
		
		ExtractionOperation *trackExtractionOperation = [[ExtractionOperation alloc] init];
		
		trackExtractionOperation.disk = self.disk;
		trackExtractionOperation.sectorRange = trackSectorRange;
		trackExtractionOperation.session = session;
		trackExtractionOperation.readOffset = self.driveInformation.readOffset;
		trackExtractionOperation.path = [NSString stringWithFormat:@"/tmp/Track %@.raw", [trackDictionary objectForKey:@"number"]];
		
		[self.extractionQueue addOperation:trackExtractionOperation];
	}
}

- (IBAction) copyImage:(id)sender
{

#pragma unused(sender)

	
}

- (IBAction) ejectDisc:(id)sender
{

#pragma unused(sender)
	
}

@end

@implementation CompactDiscDocument (Private)

- (void) extractionStartedForOperation:(ExtractionOperation *)operation
{
	NSParameterAssert(nil != operation);

	NSLog(@"Extraction to %@ started", operation.path);
}

- (void) extractionStoppedForOperation:(ExtractionOperation *)operation
{
	NSParameterAssert(nil != operation);
	
	// Delete the output file if the operation was cancelled or did not succeed
	if(operation.error || operation.isCancelled) {
		if(operation.error)
			[self presentError:operation.error];
			
		NSError *error = nil;
		if(![[NSFileManager defaultManager] removeItemAtPath:operation.path error:&error])
			[self presentError:error];
		return;
	}

	NSLog(@"Extraction to %@ finished, %u C2 errors.  MD5 = %@", operation.path, operation.errorFlags.countOfOnes, operation.md5);
}

@end
