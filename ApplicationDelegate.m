/*
 *  Copyright (C) 2007 - 2008 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import "ApplicationDelegate.h"
#import "CompactDiscDocument.h"
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
- (BOOL) validateLicense:(NSString *)licensePath;
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
			if([self.managedObjectContext hasChanges] && ![self.managedObjectContext save:&error]) {
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

	CFStringRef myUTI = UTTypeCreatePreferredIdentifierForTag(kUTTagClassFilenameExtension, (CFStringRef)pathExtension, kUTTypePlainText);
	NSLog(@"UTI = %@",myUTI);
	Boolean result = UTTypeConformsTo(myUTI, kUTTypeImage);

	if([pathExtension isEqualToString:@"riplicense"])
		return [self validateLicense:filename];
	else
		return NO;
}

- (NSString *) applicationSupportFolder
{
	NSArray *applicationSupportPaths = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES);
	NSString *applicationSupportPath = (0 < applicationSupportPaths.count) ? [applicationSupportPaths objectAtIndex:0] : NSTemporaryDirectory();
	NSString *applicationName = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleName"];

	return [applicationSupportPath stringByAppendingPathComponent:applicationName];
}

- (NSURL *) applicationLogURL
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
	NSString *applicationSupportFolder = self.applicationSupportFolder;
	NSError *error = nil;

	// Create the Application Support directory if it doesn't exist
	if(![fileManager fileExistsAtPath:applicationSupportFolder isDirectory:NULL] && ![fileManager createDirectoryAtPath:applicationSupportFolder withIntermediateDirectories:YES attributes:nil error:&error])
		[[NSApplication sharedApplication] presentError:error];

	NSURL *url = [NSURL fileURLWithPath:[applicationSupportFolder stringByAppendingPathComponent:@"Ripped CDs.xml"]];

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

- (NSUndoManager *) windowWillReturnUndoManager:(NSWindow *)window
{
	
#pragma unused(window)
	
	return self.managedObjectContext.undoManager;
}

- (IBAction) saveAction:(id)sender
{
#pragma unused(sender)

	NSError *error = nil;
	if(![self.managedObjectContext save:&error])
		[[NSApplication sharedApplication] presentError:error];
}

@end

@implementation ApplicationDelegate (Private)

- (void) diskAppeared:(DADiskRef)disk
{
	NSParameterAssert(NULL != disk);

	// Create a new document for this disk
	NSError *error = nil;
	id document = [[NSDocumentController sharedDocumentController] openUntitledDocumentAndDisplay:YES error:&error];
	
	if(nil == document)
		[[NSApplication sharedApplication] presentError:error];
	
	// Assign the disk to the document
	if([document isKindOfClass:[CompactDiscDocument class]])
		((CompactDiscDocument *)document).disk = disk;
}

- (void) diskDisappeared:(DADiskRef)disk
{
	NSParameterAssert(NULL != disk);

	NSDocument *matchingDocument = nil;
	
	// Iterate through open documents and determine which one matches this disk
	for(NSDocument *document in [[NSDocumentController sharedDocumentController] documents]) {
		if([document isKindOfClass:[CompactDiscDocument class]] && CFEqual(((CompactDiscDocument *)document).disk, disk)) {
			matchingDocument = document;
			break;
		}
	}
	
	if(matchingDocument)
		[matchingDocument close];
}

- (BOOL) validateLicense:(NSString *)licensePath
{
	// This string is specially constructed to prevent key replacement
 	// *** Begin Public Key ***
	NSMutableString *key = [NSMutableString string];
	[key appendString:@"0xECBDB"];
	[key appendString:@"E"];
	[key appendString:@"E"];
	[key appendString:@"C23701B8881308A2B0CCB"];
	[key appendString:@"C4D06FD2BA857CD26161E6504"];
	[key appendString:@"6"];
	[key appendString:@"6"];
	[key appendString:@"9F1"];
	[key appendString:@"5B68F46160719425714E4DAE950193"];
	[key appendString:@"80E03C2D"];
	[key appendString:@"5"];
	[key appendString:@"5"];
	[key appendString:@"C05A0C6CC93903591E35"];
	[key appendString:@"DA0E2534A6F39E9E18"];
	[key appendString:@"A"];
	[key appendString:@"A"];
	[key appendString:@"95A8ECDFA4"];
	[key appendString:@"ED83A6D7B3C0DF6"];
	[key appendString:@"D"];
	[key appendString:@"D"];
	[key appendString:@"7731F4E0E0E4B"];
	[key appendString:@"086"];
	[key appendString:@"8"];
	[key appendString:@"8"];
	[key appendString:@"B737B712C3C8CEA6BCC90CD44"];
	[key appendString:@"CA012E8E"];
	[key appendString:@"A"];
	[key appendString:@"A"];
	[key appendString:@"81B5566E6D4F684FAD8B"];
	[key appendString:@"8080ED6BEE1BE4BAE5"];
	// *** End Public Key *** 
	
	// Instantiate AquaticPrime
	AquaticPrime *licenseValidator = [AquaticPrime aquaticPrimeWithKey:key];

	// Get the dictionary from the license file
	// If the license is invalid, we get nil back instead of a dictionary
	NSDictionary *licenseDictionary = [licenseValidator dictionaryForLicenseFile:licensePath];

	if(nil == licenseDictionary)
		return NO;
	else
		return nil != [licenseDictionary objectForKey:@"Name"];
}

@end
