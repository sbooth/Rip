//
// AquaticPrime.m
// AquaticPrime Framework
//
// Copyright (c) 2005, Lucas Newman
// All rights reserved.
//
// Redistribution and use in source and binary forms, with or without modification,
// are permitted provided that the following conditions are met:
//	•Redistributions of source code must retain the above copyright notice,
//	 this list of conditions and the following disclaimer.
//	•Redistributions in binary form must reproduce the above copyright notice,
//	 this list of conditions and the following disclaimer in the documentation and/or
//	 other materials provided with the distribution.
//	•Neither the name of Aquatic nor the names of its contributors may be used to 
//	 endorse or promote products derived from this software without specific prior written permission.
//
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR
// IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND
// FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR
// CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL 
// DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, 
// DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER 
// IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT 
// OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

// Modifications Copright (C) 2009 Stephen F. Booth <me@sbooth.org>

#import "AquaticPrime.h"

@interface AquaticPrime ()
@property (copy) NSString * lastError;
@end

@implementation AquaticPrime

@synthesize hash = _hash;
@synthesize blacklist = _blacklist;
@synthesize lastError = _lastError;

+ (id) aquaticPrimeWithKey:(NSString *)key privateKey:(NSString *)privateKey
{
	return [[AquaticPrime alloc] initWithKey:key privateKey:privateKey];
}

+ (id) aquaticPrimeWithKey:(NSString *)key
{
	return [[AquaticPrime alloc] initWithKey:key privateKey:nil];
}

- (id) init
{
	[self doesNotRecognizeSelector:_cmd];
	return nil;
}

- (id) initWithKey:(NSString *)key
{
	NSParameterAssert(nil != key);
	
	return [self initWithKey:key privateKey:nil];
}

- (id) initWithKey:(NSString *)key privateKey:(NSString *)privateKey
{	
	NSParameterAssert(nil != key);
	
	if((self = [super init])) {
		ERR_load_crypto_strings();
		[self setKey:key privateKey:privateKey];
	}
	return self;
}

- (void) finalize
{
	ERR_free_strings();
	
	if(_rsaKey)
		RSA_free(_rsaKey);
	
	[super finalize];
}

- (BOOL) setKey:(NSString *)key 
{
	NSParameterAssert(nil != key);
	
	return [self setKey:key privateKey:nil];
}

- (BOOL) setKey:(NSString *)key privateKey:(NSString *)privateKey
{
	NSParameterAssert(nil != key);
	NSParameterAssert([key length]);

	if(_rsaKey)
		RSA_free(_rsaKey);
		
	_rsaKey = RSA_new();
	
	// We are using the constant public exponent e = 3
	BN_dec2bn(&_rsaKey->e, "3");
	
	// Determine if we have hex or decimal values
	int result;
	if([[key lowercaseString] hasPrefix:@"0x"])
		result = BN_hex2bn(&_rsaKey->n, (const char *)[[key substringFromIndex:2] UTF8String]);
	else
		result = BN_dec2bn(&_rsaKey->n, (const char *)[key UTF8String]);
		
	if(!result) {
		self.lastError = [NSString stringWithUTF8String:(char*)ERR_error_string(ERR_get_error(), NULL)];
		return NO;
	}
	
	// Do the private portion if it exists
	if(privateKey && ![privateKey isEqualToString:@""]) {
		if([[privateKey lowercaseString] hasPrefix:@"0x"])
			result = BN_hex2bn(&_rsaKey->d, (const char *)[[privateKey substringFromIndex:2] UTF8String]);
		else
			result = BN_dec2bn(&_rsaKey->d, (const char *)[privateKey UTF8String]);
			
		if(!result) {
			self.lastError = [NSString stringWithUTF8String:(char*)ERR_error_string(ERR_get_error(), NULL)];
			return NO;
		}
	}
	
	return YES;
}

- (NSString *) key
{
	if(!_rsaKey || !_rsaKey->n)
		return nil;
	
	char *cString = BN_bn2hex(_rsaKey->n);
	
	NSString *nString = [[NSString alloc] initWithUTF8String:cString];
	OPENSSL_free(cString);
	
	return nString;
}

- (NSString *) privateKey
{	
	if(!_rsaKey || !_rsaKey->d)
		return nil;
	
	char *cString = BN_bn2hex(_rsaKey->d);
	
	NSString *dString = [[NSString alloc] initWithUTF8String:cString];
	OPENSSL_free(cString);
	
	return dString;
}

#pragma mark Signing

- (NSData *) licenseDataForDictionary:(NSDictionary *)dict
{	
	// Make sure we have a good key
	if(!_rsaKey || !_rsaKey->n || !_rsaKey->d) {
		self.lastError = @"RSA key is invalid";
		return nil;
	}
	
	// Grab all values from the dictionary
	NSMutableArray *keyArray = [[dict allKeys] mutableCopy];
	NSMutableData *dictData = [NSMutableData data];
	
	// Sort the keys so we always have a uniform order
	[keyArray sortUsingSelector:@selector(caseInsensitiveCompare:)];
	
	for(NSString *key in keyArray) {
		id curValue = [dict objectForKey:key];
		const char *desc = [[curValue description] UTF8String];
		// We use strlen instead of [string length] so we can get all the bytes of accented characters
		[dictData appendBytes:desc length:strlen(desc)];
	}
	
	// Hash the data
	unsigned char digest[20];
	SHA1([dictData bytes], [dictData length], digest);
	
	// Create the signature from 20 byte hash
	int rsaLength = RSA_size(_rsaKey);
	unsigned char *signature = (unsigned char *)malloc(rsaLength);
	int bytes = RSA_private_encrypt(20, digest, signature, _rsaKey, RSA_PKCS1_PADDING);
	
	if(-1 == bytes) {
		self.lastError = [NSString stringWithUTF8String:(char*)ERR_error_string(ERR_get_error(), NULL)];
		return nil;
	}
	
	// Create the license dictionary
	NSMutableDictionary *licenseDict = [NSMutableDictionary dictionaryWithDictionary:dict];
	[licenseDict setObject:[NSData dataWithBytes:signature length:bytes] forKey:@"Signature"];
	
	// Create the data from the dictionary
	NSString *error;
	NSData *licenseFile = [NSPropertyListSerialization dataFromPropertyList:licenseDict 
																	 format:kCFPropertyListXMLFormat_v1_0 
														   errorDescription:&error];
	
	if(!licenseFile) {
		self.lastError = error;
		return nil;
	}
	
	return licenseFile;
}

- (BOOL) writeLicenseFileForDictionary:(NSDictionary *)dict toPath:(NSString *)path
{
	NSData *licenseFile = [self licenseDataForDictionary:dict];
	
	if(!licenseFile)
		return NO;
	
	return [licenseFile writeToFile:path atomically:YES];
}

// This method only logs errors on developer problems, so don't expect to grab an error message if it's just an invalid license
- (NSDictionary *) dictionaryForLicenseData:(NSData *)data
{	
	NSParameterAssert(nil != data);
	
	// Make sure public key is set up
	if(!_rsaKey || !_rsaKey->n) {
		self.lastError = @"RSA key is invalid";
		return nil;
	}

	// Create a dictionary from the data
	NSPropertyListFormat format;
	NSString *error;
	NSMutableDictionary *licenseDict = [NSPropertyListSerialization propertyListFromData:data 
																		mutabilityOption:NSPropertyListMutableContainersAndLeaves 
																				  format:&format 
																		errorDescription:&error];
	if(error)
		return nil;
		
	NSData *signature = [licenseDict objectForKey:@"Signature"];
	if(!signature)
		return nil;
	
	// Decrypt the signature - should get 20 bytes back
	unsigned char checkDigest[20];
	if(20 != RSA_public_decrypt((int)[signature length], [signature bytes], checkDigest, _rsaKey, RSA_PKCS1_PADDING))
		return nil;
	
	// Make sure the license hash isn't on the blacklist
	NSMutableString *hashCheck = [NSMutableString string];
	int hashIndex;
	for(hashIndex = 0; hashIndex < 20; ++hashIndex)
		[hashCheck appendFormat:@"%02x", checkDigest[hashIndex]];
	
	if([self.blacklist containsObject:hashCheck])
		return nil;
	
	// Store the license hash in case we need it later
	self.hash = hashCheck;
	
	// Remove the signature element
	[licenseDict removeObjectForKey:@"Signature"];
	
	// Grab all values from the dictionary
	NSMutableArray *keyArray = [NSMutableArray arrayWithArray:[licenseDict allKeys]];
	NSMutableData *dictData = [NSMutableData data];
	
	// Sort the keys so we always have a uniform order
	[keyArray sortUsingSelector:@selector(caseInsensitiveCompare:)];
	
	for(NSString *key in keyArray) {
		id currentValue = [licenseDict objectForKey:key];
		char *description = (char *)[[currentValue description] UTF8String];
		// We use strlen instead of [string length] so we can get all the bytes of accented characters
		[dictData appendBytes:description length:strlen(description)];
	}
	
	// Hash the data
	unsigned char digest[20];
	SHA1([dictData bytes], [dictData length], digest);
	
	// Check if the signature is a match	
	int checkIndex;
	for(checkIndex = 0; checkIndex < 20; ++checkIndex) {
		if(checkDigest[checkIndex] ^ digest[checkIndex])
			return nil;
	}
	
	return [licenseDict copy];
}

- (NSDictionary *) dictionaryForLicenseFile:(NSString *)path
{
	NSParameterAssert(nil != path);
	
	NSData *licenseFile = [NSData dataWithContentsOfFile:path];
	
	if(!licenseFile)
		return nil;
	
	return [self dictionaryForLicenseData:licenseFile];
}

- (NSDictionary *) dictionaryForLicenseURL:(NSURL *)fileURL
{
	NSParameterAssert(nil != fileURL);
	
	NSData *licenseFile = [NSData dataWithContentsOfURL:fileURL];
	
	if(!licenseFile)
		return nil;
	
	return [self dictionaryForLicenseData:licenseFile];
}

- (BOOL) verifyLicenseData:(NSData *)data
{
	NSParameterAssert(nil != data);
	
	if([self dictionaryForLicenseData:data])
		return YES;
	else
		return NO;
}

- (BOOL) verifyLicenseFile:(NSString *)path
{
	NSParameterAssert(nil != path);
	
	return [self verifyLicenseData:[NSData dataWithContentsOfFile:path]];
}

- (BOOL) verifyLicenseURL:(NSURL *)fileURL
{
	NSParameterAssert(nil != fileURL);
	
	return [self verifyLicenseData:[NSData dataWithContentsOfURL:fileURL]];
}

@end
