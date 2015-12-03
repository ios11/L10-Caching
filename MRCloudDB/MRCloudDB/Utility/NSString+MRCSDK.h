//
//  NSString+MRCSDK.h
//  MRCloudSDK
//
//  Created by Pavel Osipov on 29.10.13.
//  Copyright (c) 2013 Mail.Ru Group. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface NSString (MRCSDK)

//
// Creates string from SHA1 digest.
// Digest data should have strickly 20 bytes.
//
+ (NSString *)mrc_stringFromSHA1Digest:(NSData *)digest;

//
// Treats self as a localization key in 'table'.strings file.
// 'table'.strings file should be situated in app/xctest bundle.
//
- (NSString *)mrc_localizedWithTable:(NSString *)table;

- (NSString *)mrc_percentEscapedString;
- (NSString *)mrc_percentEscapedLinkHash;

@end
