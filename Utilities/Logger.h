/*
 *  Copyright (C) 2008 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import <Cocoa/Cocoa.h>

// ========================================
// Enum for user defaults output file handling
// ========================================
enum _eLogMessageLevel {
	eLogMessageLevelNormal = 1,
	eLogMessageLevelDebug = 2,
	eLogMessageLevelFull = 3
};
typedef enum _eLogMessageLevel eLogMessageLevel;

// ========================================
// Class for logging messages to the application's log file
// ========================================
@interface Logger : NSObject
{
@private
	NSFileHandle *_logFile;
	eLogMessageLevel _logMessageLevel;
}

// ========================================
// The shared instance
+ (id) sharedLogger;

// ========================================
// Properties
@property (assign) eLogMessageLevel logMessageLevel;

// Log the specified string to the application's log file
- (void) logMessage:(NSString *)message;
- (void) logMessage:(NSString *)message level:(eLogMessageLevel)level;

@end
