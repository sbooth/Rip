/*
 *  Copyright (C) 2009 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import "NSData+Base64Methods.h"

#include <openssl/bio.h>
#include <openssl/evp.h>

@implementation NSData(Base64Methods)

- (NSString *) base64EncodedString
{
	return [self base64EncodedStringWithNewlines:YES];
}

- (NSString *) base64EncodedStringWithNewlines:(BOOL)encodeWithNewlines
{
	// Create a memory buffer which will contain the Base64 encoded string
	BIO *mem = BIO_new(BIO_s_mem());

	// Push on a Base64 filter so that writing to the buffer encodes the data
	BIO *b64 = BIO_new(BIO_f_base64());
	if(!encodeWithNewlines)
		BIO_set_flags(b64, BIO_FLAGS_BASE64_NO_NL);
	mem = BIO_push(b64, mem);

	// Encode all the data
	BIO_write(mem, [self bytes], [self length]);
	BIO_flush(mem);

	// Create a new string from the data in the memory buffer
	char *base64Pointer = NULL;
	long base64Length = BIO_get_mem_data(mem, &base64Pointer);
	NSString *base64String = [[NSString alloc] initWithBytes:base64Pointer length:base64Length encoding:NSASCIIStringEncoding];

	// Clean up and go home
	BIO_free_all(mem);
	
	return base64String;
}

@end
