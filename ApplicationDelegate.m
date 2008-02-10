/*
 *  Copyright (C) 2007 - 2008 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import "ApplicationDelegate.h"
#import "ByteSizeValueTransformer.h"
#import "DurationValueTransformer.h"
#import "CompactDiscWindowController.h"
#import "AquaticPrime.h"

#include <CoreFoundation/CoreFoundation.h>
#include <DiskArbitration/DiskArbitration.h>

#include <IOKit/IOKitLib.h>
#include <IOKit/storage/IOCDMedia.h>

// ========================================
// Class extensions
// ========================================

@interface ApplicationDelegate ()
@property (assign) NSPersistentStoreCoordinator * persistentStoreCoordinator;
@property (assign) NSManagedObjectModel * managedObjectModel;
@property (assign) NSManagedObjectContext * managedObjectContext;
@end


// ========================================
// Private methods for the ApplicationDelegate class
// ========================================

@interface ApplicationDelegate (Private)
- (void) diskAppeared:(DADiskRef)disk;
- (void) diskDisappeared:(DADiskRef)disk;
- (NSURL *) locateLicenseURL;
- (BOOL) validateLicenseURL:(NSURL *)licenseURL error:(NSError **)error;
- (void) displayNagDialog;
@end


// ========================================
// DiskArbitration callbacks
// ========================================

#pragma mark DiskArbitration callback functions

static void diskAppearedCallback(DADiskRef disk, void *context);
static void diskDisappearedCallback(DADiskRef disk, void *context);

static void 
diskAppearedCallback(DADiskRef disk, void *context)
{
	NSCParameterAssert(NULL != context);
	
	[(ApplicationDelegate *)context diskAppeared:disk];
}

static void 
diskDisappearedCallback(DADiskRef disk, void *context)
{
	NSCParameterAssert(NULL != context);
	
	[(ApplicationDelegate *)context diskDisappeared:disk];
}

@implementation ApplicationDelegate

+ (void) initialize
{
	// Register custom value transformer classes
	NSValueTransformer *transformer = nil;
	
	transformer = [[ByteSizeValueTransformer alloc] init];
	[NSValueTransformer setValueTransformer:transformer forName:@"ByteSizeValueTransformer"];
	
	transformer = [[DurationValueTransformer alloc] init];
	[NSValueTransformer setValueTransformer:transformer forName:@"DurationValueTransformer"];
}

@synthesize persistentStoreCoordinator = _persistentStoreCoordinator;
@synthesize managedObjectModel = _managedObjectModel;
@synthesize managedObjectContext = _managedObjectContext;

// Don't automatically open an untitled document
- (BOOL) applicationShouldOpenUntitledFile:(NSApplication *)sender
{
	
#pragma unused(sender)
	
	return NO;
}

- (void) applicationDidFinishLaunching:(NSNotification *)aNotification
{

#pragma unused(aNotification)
	
	// Determine if this application is registered, and if not, display a nag dialog
	NSURL *licenseURL = [self locateLicenseURL];
	if(licenseURL) {
		NSError *error = nil;
		if(![self validateLicenseURL:licenseURL error:&error])
			[[NSApplication sharedApplication] presentError:error];
	}
	else
		[self displayNagDialog];
	
	// Use DiskArbitration to request mount/unmount information for audio CDs
	
	// Create a dictionary which will match IOMedia objects of type kIOCDMediaClass
	CFMutableDictionaryRef matchDictionary = CFDictionaryCreateMutable(kCFAllocatorDefault, 0, &kCFCopyStringDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
	if(NULL == matchDictionary) {
		NSLog(@"Unable to create a CFMutableDictionaryRef for kIOCDMediaClass matching");
		
		return;
	}
	
	CFDictionarySetValue(matchDictionary, kDADiskDescriptionMediaKindKey, CFSTR(kIOCDMediaClass));
	CFDictionarySetValue(matchDictionary, kDADiskDescriptionMediaWholeKey, kCFBooleanTrue);
	
	// Create a DiskArbitration session in the current run loop
	_diskArbitrationSession = DASessionCreate(kCFAllocatorDefault);
	DASessionScheduleWithRunLoop(_diskArbitrationSession, CFRunLoopGetCurrent(), kCFRunLoopDefaultMode);
	
	// Register our disk appeared and disappeared callbacks
	DARegisterDiskAppearedCallback(_diskArbitrationSession, matchDictionary, diskAppearedCallback, self);
	DARegisterDiskDisappearedCallback(_diskArbitrationSession, matchDictionary, diskDisappearedCallback, self);
	
	CFRelease(matchDictionary);
}

- (NSApplicationTerminateReply) applicationShouldTerminate:(NSApplication *)sender
{
	
#pragma unused(sender)
	
	NSApplicationTerminateReply reply = NSTerminateNow;

	if(nil != self.managedObjectContext) {
		if([self.managedObjectContext commitEditing]) {
			NSError *error = nil;
			if(self.managedObjectContext.hasChanges && ![self.managedObjectContext save:&error]) {
				BOOL errorResult = [[NSApplication sharedApplication] presentError:error];

				if(errorResult)
					reply = NSTerminateCancel;
				else {
					NSInteger alertReturn = NSRunAlertPanel(nil, @"Could not save changes while quitting. Quit anyway?" , @"Quit anyway", @"Cancel", nil);
					if(NSAlertAlternateReturn == alertReturn)
						reply = NSTerminateCancel;	
				}
			}
		}
		else
			reply = NSTerminateCancel;
	}

	return reply;
}

- (void) applicationWillTerminate:(NSNotification *)aNotification
{
	
#pragma unused(aNotification)
	
	// Unregister our disk appeared and disappeared callbacks
	DAUnregisterCallback(_diskArbitrationSession, diskAppearedCallback, self);
	DAUnregisterCallback(_diskArbitrationSession, diskDisappearedCallback, self);
	
	// Unschedule and dispose of the DiskArbitration session created for this run loop
	DASessionUnscheduleFromRunLoop(_diskArbitrationSession, CFRunLoopGetCurrent(), kCFRunLoopDefaultMode);
	CFRelease(_diskArbitrationSession), _diskArbitrationSession = NULL;
}

- (BOOL) application:(NSApplication *)theApplication openFile:(NSString *)filename
{

#pragma unused(theApplication)
	
	NSParameterAssert(nil != filename);

	NSString *pathExtension = [filename pathExtension];

//	CFStringRef myUTI = UTTypeCreatePreferredIdentifierForTag(kUTTagClassFilenameExtension, (CFStringRef)pathExtension, kUTTypePlainText);

	if([pathExtension isEqualToString:@"riplicense"]) {
		NSError *error = nil;
		if([self validateLicenseURL:[NSURL fileURLWithPath:filename] error:&error]) {
			NSString *licenseCopyPath = [self.applicationSupportFolderURL.path stringByAppendingPathComponent:filename.lastPathComponent];
			if(![[NSFileManager defaultManager] copyItemAtPath:filename toPath:licenseCopyPath error:&error])
				[[NSApplication sharedApplication] presentError:error];
		}
		else
			[[NSApplication sharedApplication] presentError:error];
		
		
		return YES;
	}
	else
		return NO;
}

- (NSURL *) applicationSupportFolderURL
{
	NSArray *applicationSupportPaths = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES);
	NSString *applicationSupportPath = (0 < applicationSupportPaths.count) ? [applicationSupportPaths objectAtIndex:0] : NSTemporaryDirectory();
	NSString *applicationName = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleName"];
	NSString *applicationSupportFolder = [applicationSupportPath stringByAppendingPathComponent:applicationName];
	
	return [NSURL fileURLWithPath:applicationSupportFolder];
}

- (NSURL *) applicationLogFileURL
{
	NSArray *userLibraryPaths = NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES);
	NSString *userLibraryPath = (0 < userLibraryPaths.count) ? [userLibraryPaths objectAtIndex:0] : NSTemporaryDirectory();
	NSString *userLogsPath = [userLibraryPath stringByAppendingPathComponent:@"Logs"];
	NSString *applicationName = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleName"];
	NSString *logFileName = [applicationName stringByAppendingPathExtension:@"log"];
	NSString *applicationLogPath = [userLogsPath stringByAppendingPathComponent:logFileName];
	
	return [NSURL fileURLWithPath:applicationLogPath];
}

#pragma mark Standard Core Data

- (NSManagedObjectModel *) managedObjectModel
{
	if(nil == _managedObjectModel)
		self.managedObjectModel = [NSManagedObjectModel mergedModelFromBundles:nil];

	return _managedObjectModel;
}

- (NSPersistentStoreCoordinator *) persistentStoreCoordinator
{
	if(nil != _persistentStoreCoordinator)
		return _persistentStoreCoordinator;

	NSFileManager *fileManager = [NSFileManager defaultManager];
	NSString *applicationSupportFolderPath = self.applicationSupportFolderURL.path;
	
	NSError *error = nil;

	// Create the Application Support directory if it doesn't exist
	if(![fileManager fileExistsAtPath:applicationSupportFolderPath isDirectory:NULL] && ![fileManager createDirectoryAtPath:applicationSupportFolderPath withIntermediateDirectories:YES attributes:nil error:&error])
		[[NSApplication sharedApplication] presentError:error];

	NSURL *url = [NSURL fileURLWithPath:[applicationSupportFolderPath stringByAppendingPathComponent:@"Ripped CDs.xml"]];

	self.persistentStoreCoordinator = [[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel:self.managedObjectModel];

	if(![_persistentStoreCoordinator addPersistentStoreWithType:NSXMLStoreType configuration:nil URL:url options:nil error:&error])
		[[NSApplication sharedApplication] presentError:error];

	return _persistentStoreCoordinator;
}

- (NSManagedObjectContext *) managedObjectContext
{
	if(nil != _managedObjectContext)
		return _managedObjectContext;

	NSPersistentStoreCoordinator *coordinator = self.persistentStoreCoordinator;
	if(nil != coordinator) {
		self.managedObjectContext = [[NSManagedObjectContext alloc] init];
		[_managedObjectContext setPersistentStoreCoordinator:coordinator];
	}

	return _managedObjectContext;
}

- (IBAction) saveAction:(id)sender
{

#pragma unused(sender)

	if(!self.managedObjectContext.hasChanges)
		return;
	
	NSError *error = nil;
	if(![self.managedObjectContext save:&error])
		[[NSApplication sharedApplication] presentError:error];
}

@end

@implementation ApplicationDelegate (Private)

- (void) diskAppeared:(DADiskRef)disk
{
	NSParameterAssert(NULL != disk);

	// Create a new window for this disk
	CompactDiscWindowController *compactDiscWindow = [[CompactDiscWindowController alloc] init];
	compactDiscWindow.disk = disk;

	// Actions such as querying AccurateRip pass objectIDs across threads, so the managed object context
	// must be saved before any queries are performed
	[self saveAction:nil];
	
	[compactDiscWindow showWindow:self];

	if([[NSUserDefaults standardUserDefaults] boolForKey:@"automaticallyQueryAccurateRip"])
		[compactDiscWindow queryAccurateRip:nil];
	
	if([[NSUserDefaults standardUserDefaults] boolForKey:@"automaticallyQueryMusicDatabase"])
		[compactDiscWindow queryDefaultMusicDatabase:nil];
}

- (void) diskDisappeared:(DADiskRef)disk
{
	NSParameterAssert(NULL != disk);

	NSDocument *matchingDocument = nil;
	
	// Iterate through open documents and determine which one matches this disk
	for(NSDocument *document in [[NSDocumentController sharedDocumentController] documents]) {
		if([document isKindOfClass:[CompactDiscWindowController class]] && CFEqual(((CompactDiscWindowController *)document).disk, disk)) {
			matchingDocument = document;
			break;
		}
	}
	
	if(matchingDocument)
		[matchingDocument close];
}

- (NSURL *) locateLicenseURL
{
	// Search for a license file in the Application Support folder
	NSString *applicationSupportFolderPath = self.applicationSupportFolderURL.path;
	NSDirectoryEnumerator *directoryEnumerator = [[NSFileManager defaultManager] enumeratorAtPath:applicationSupportFolderPath];
	
	NSString *path = nil;
	while((path = [directoryEnumerator nextObject])) {
		// Just return the first one found
		if([path.pathExtension isEqualToString:@"riplicense"])
			return [NSURL fileURLWithPath:[applicationSupportFolderPath stringByAppendingPathComponent:path]];			
	}
	
	return nil;
}

		   
- (BOOL) validateLicenseURL:(NSURL *)licenseURL error:(NSError **)error
{
	NSParameterAssert(nil != licenseURL);
	
	// This string is specially constructed to prevent key replacement
	NSMutableString *publicKey = [NSMutableString string];
	[publicKey appendString:@"0xECBDB"];
	[publicKey appendString:@"E"];
	[publicKey appendString:@"E"];
	[publicKey appendString:@"C23701B8881308A2B0CCB"];
	[publicKey appendString:@"C4D06FD2BA857CD26161E6504"];
	[publicKey appendString:@"6"];
	[publicKey appendString:@"6"];
	[publicKey appendString:@"9F1"];
	[publicKey appendString:@"5B68F46160719425714E4DAE950193"];
	[publicKey appendString:@"80E03C2D"];
	[publicKey appendString:@"5"];
	[publicKey appendString:@"5"];
	[publicKey appendString:@"C05A0C6CC93903591E35"];
	[publicKey appendString:@"DA0E2534A6F39E9E18"];
	[publicKey appendString:@"A"];
	[publicKey appendString:@"A"];
	[publicKey appendString:@"95A8ECDFA4"];
	[publicKey appendString:@"ED83A6D7B3C0DF6"];
	[publicKey appendString:@"D"];
	[publicKey appendString:@"D"];
	[publicKey appendString:@"7731F4E0E0E4B"];
	[publicKey appendString:@"086"];
	[publicKey appendString:@"8"];
	[publicKey appendString:@"8"];
	[publicKey appendString:@"B737B712C3C8CEA6BCC90CD44"];
	[publicKey appendString:@"CA012E8E"];
	[publicKey appendString:@"A"];
	[publicKey appendString:@"A"];
	[publicKey appendString:@"81B5566E6D4F684FAD8B"];
	[publicKey appendString:@"8080ED6BEE1BE4BAE5"];
	
	AquaticPrime *licenseValidator = [AquaticPrime aquaticPrimeWithKey:publicKey];
	NSDictionary *licenseDictionary = [licenseValidator dictionaryForLicenseFile:licenseURL.path];

	// This is an invalid license
	if(nil == licenseDictionary) {
		if(error) {
			NSMutableDictionary *userInfo = [NSMutableDictionary dictionary];
			[userInfo setObject:licenseURL.path forKey:NSFilePathErrorKey];
			[userInfo setObject:NSLocalizedStringFromTable(@"Unable to read the license file", @"Errors", @"") forKey:NSLocalizedDescriptionKey];
			[userInfo setObject:NSLocalizedStringFromTable(@"The license could be incomplete or might contain an invalid key.", @"Errors", @"") forKey:NSLocalizedRecoverySuggestionErrorKey];
			
			*error = [NSError errorWithDomain:@"org.sbooth.Rip.ErrorDomain" code:20 userInfo:userInfo];
		}
		
		return NO;		
	}

	// TODO: Make sure the license is sane
	return YES;
}

- (void) displayNagDialog
{
	NSRunAlertPanel(NSLocalizedStringFromTable(@"This copy of Rip is unregistered.", @"", @""), 
					NSLocalizedStringFromTable(@"You may purchase a license from http://sbooth.org/Rip/", @"", @""), 
					NSLocalizedStringFromTable(@"OK", @"Buttons", @""), nil, nil);
}

@end
