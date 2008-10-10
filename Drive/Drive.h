/*
 *  Copyright (C) 2005 - 2007 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import <Cocoa/Cocoa.h>
#include <DiskArbitration/DiskArbitration.h>

@class SectorRange;

// ========================================
// Byte sizes of various CDDA sector areas
// ========================================
enum {
	kCDSectorSizeQSubchannel		= 16,
	kCDSectorSizeErrorFlags			= 294
};

// ========================================
// This class encapsulates operations useful on an IOKit
// device that can read IOCDMedia.
// ========================================
@interface Drive : NSObject
{
@private
	__strong DADiskRef _disk;
	int _fd;
	NSUInteger _cacheSize;
	NSError *_error;
}

@property (readonly, assign) DADiskRef disk;
@property (readonly, copy) NSError * error;
@property (assign) NSUInteger cacheSize;
@property (readonly) NSUInteger cacheSizeInSectors;
@property (readonly) BOOL deviceIsOpen;

// ========================================
// Set up to use the drive corresponding to disk
- (id) initWithDADiskRef:(DADiskRef)disk;

// ========================================
// Device management
- (BOOL) openDevice;
- (BOOL) closeDevice;

// ========================================
// Drive speed
- (uint16_t) speed;
- (BOOL) setSpeed:(uint16_t)speed;

// ========================================
// Clear the drive's cache by filling with sectors outside of range
- (BOOL) clearCache:(SectorRange *)range;

// ========================================
// Read a chunk of CD-DA data (buffer should be kCDSectorSizeCDDA * sectorCount bytes)
- (NSUInteger) readAudio:(void *)buffer sector:(NSUInteger)sector;
- (NSUInteger) readAudio:(void *)buffer sectorRange:(SectorRange *)range;
- (NSUInteger) readAudio:(void *)buffer startSector:(NSUInteger)startSector sectorCount:(NSUInteger)sectorCount;

// ========================================
// Read a chunk of CD-DA data, with Q sub-channel (buffer should be (kCDSectorSizeCDDA + kCDSectorSizeQSubchannel) * sectorCount bytes)
- (NSUInteger) readAudioAndQSubchannel:(void *)buffer sector:(NSUInteger)sector;
- (NSUInteger) readAudioAndQSubchannel:(void *)buffer sectorRange:(SectorRange *)range;
- (NSUInteger) readAudioAndQSubchannel:(void *)buffer startSector:(NSUInteger)startSector sectorCount:(NSUInteger)sectorCount;

// ========================================
// Read a chunk of CD-DA data, with error flags (buffer should be (kCDSectorSizeCDDA + kCDSectorSizeErrorFlags) * sectorCount bytes)
- (NSUInteger) readAudioAndErrorFlags:(void *)buffer sector:(NSUInteger)sector;
- (NSUInteger) readAudioAndErrorFlags:(void *)buffer sectorRange:(SectorRange *)range;
- (NSUInteger) readAudioAndErrorFlags:(void *)buffer startSector:(NSUInteger)startSector sectorCount:(NSUInteger)sectorCount;

// ========================================
// Read a chunk of CD-DA data, with error flags and Q sub-channel (buffer should be (kCDSectorSizeCDDA + kCDSectorSizeErrorFlags + kCDSectorSizeQSubchannel) * sectorCount bytes)
- (NSUInteger) readAudioAndErrorFlagsWithQSubchannel:(void *)buffer sector:(NSUInteger)sector;
- (NSUInteger) readAudioAndErrorFlagsWithQSubchannel:(void *)buffer sectorRange:(SectorRange *)range;
- (NSUInteger) readAudioAndErrorFlagsWithQSubchannel:(void *)buffer startSector:(NSUInteger)startSector sectorCount:(NSUInteger)sectorCount;

// ========================================
// Get the CD's media catalog number
- (NSString *) readMCN;

// ========================================
// Get the ISRC for the specified track
- (NSString *) readISRC:(NSUInteger)trackNumber;

@end
