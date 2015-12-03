//
//  NSString+MRCSDK.m
//  MRCloudSDK
//
//  Created by Pavel Osipov on 29.10.13.
//  Copyright (c) 2013 Mail.Ru Group. All rights reserved.
//

#import "NSString+MRCSDK.h"
#import "NSBundle+MRCSDK.h"
#import <CommonCrypto/CommonDigest.h>

NS_INLINE NSString *CreateStringByAddingPercentEscapes(NSString *unescaped, NSString *escapedSymbols) {
    return (__bridge_transfer NSString*)CFURLCreateStringByAddingPercentEscapes(kCFAllocatorDefault,
                                                                                (CFStringRef)unescaped,
                                                                                NULL,
                                                                                (CFStringRef)escapedSymbols,
                                                                                kCFStringEncodingUTF8);
}

@implementation NSString (MRCSDK)

+ (NSString *)mrc_stringFromSHA1Digest:(NSData *)digest {
    assert(digest);
    assert([digest length] == CC_SHA1_DIGEST_LENGTH);
    static const char *validDigestCharacterSet = "0123456789ABCDEF";
    const uint8_t *digestBytes = (uint8_t *)[digest bytes];
    char digestCharacterSet[2 * CC_SHA1_DIGEST_LENGTH + 1];
    digestCharacterSet[2 * CC_SHA1_DIGEST_LENGTH] = '\0';
    for (int i = 0; i < CC_SHA1_DIGEST_LENGTH; ++i) {
        digestCharacterSet[2 * i]     = validDigestCharacterSet[(digestBytes[i] & 0xF0) >> 4];
        digestCharacterSet[2 * i + 1] = validDigestCharacterSet[ digestBytes[i] & 0x0F];
    }
    return [NSString stringWithFormat:@"%s", digestCharacterSet];

}

- (NSString *)mrc_localizedWithTable:(NSString *)table {
    return [[NSBundle mrc_SDKBundle] localizedStringForKey:self value:self table:table];
}

- (NSString *)mrc_percentEscapedString {
    // Encode all the reserved characters, per RFC 3986
    // (<http://www.ietf.org/rfc/rfc3986.txt>)
    return CreateStringByAddingPercentEscapes(self, @"!*'();:@&=+$,/?%#[]");
}

- (NSString *)mrc_percentEscapedLinkHash {
    return CreateStringByAddingPercentEscapes(self, @"!*'();:@&=+$,?%#[]");
}

@end
