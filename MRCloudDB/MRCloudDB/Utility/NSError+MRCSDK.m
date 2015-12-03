//
//  NSError+MRCSDK.m
//  MRCloudSDK
//
//  Created by Pavel Osipov on 01.10.12.
//  Copyright (c) 2012 Mail.Ru. All rights reserved.
//

#import "NSError+MRCSDK.h"
#import "NSString+MRCSDK.h"

NSString * const MRCloudSDKErrorDomain = @"ru.mail.cloud.SDKErrorDomain";

static NSString * const DescriptionErrorKey     = @"Description";
static NSString * const HTTPStatusCodeErrorKey  = @"HTTPStatusCode";
static NSString * const MetadStatusCodeErrorKey = @"MetadStatusCode";

NS_INLINE NSString *MetadStatusCodeLocalizationKey(MRCMetadStatusCode statusCode) {
    switch (statusCode) {
        case MRCMetadStatusCodeNotEnoughSpaceError:         return @"NotEnoughSpaceError";
        case MRCMetadStatusCodeNameTooLongError:            return @"NameTooLongError";
        case MRCMetadStatusCodeNodeAlreadyExistError:
        case MRCMetadStatusCodeNameCaseConflictError:       return @"AlreadyExistError";
        case MRCMetadStatusCodeBadNameError:                return @"BadNameError";
        case MRCMetadStatusCodeServiceTemporaryUnavailable: return @"ServiceTemporaryUnavailable";
        default:                                            return @"MetadError";
    }
}

@implementation NSError (MRCSDK)

#pragma mark - Properties

- (MRCErrorCode)mrc_code {
    if (![self mrc_isCloudError]) {
        return MRCUnknownError;
    }
    return [self code];
}

- (MRCHTTPStatusCode)mrc_HTTPStatusCode {
    NSNumber *statusCode = [self p_numberForKey:HTTPStatusCodeErrorKey];
    return (statusCode != nil) ? [statusCode integerValue] : MRCHTTPStatusCodeUnknown;
}

- (MRCMetadStatusCode)mrc_metadStatusCode {
    NSNumber *statusCode = [self p_numberForKey:MetadStatusCodeErrorKey];
    return (statusCode != nil) ? [statusCode integerValue] : MRCMetadStatusCodeSuccess;
}

#pragma mark - Methods

- (BOOL)mrc_isCloudError {
    return [[self domain] isEqualToString:MRCloudSDKErrorDomain];
}

- (BOOL)mrc_isAuthorizationError {
    if (![self mrc_isCloudError]) {
        return NO;
    }
    if (self.code == MRCAuthorizationError) {
        return YES;
    }
    return self.code == MRCServerError && self.mrc_HTTPStatusCode == MRCHTTPStatusCodeForbidden;
}

- (BOOL)mrc_isClientOutdatedError {
    return [self mrc_isCloudError] && self.code == MRCMetadServerError && self.mrc_metadStatusCode == MRCMetadStatusCodeClientOutdatedError;
}

+ (NSError *)mrc_authenticationError {
    NSDictionary *userInfo = @{NSLocalizedDescriptionKey: [@"AuthenticationError" mrc_localizedWithTable:@"MRCloudError"]};
    return [[NSError alloc] initWithDomain:MRCloudSDKErrorDomain code:MRCAuthenticationError userInfo:userInfo];
}

+ (NSError *)mrc_authorizationErrorWithReason:(NSError *)reason {
    NSMutableDictionary *userInfo = [NSMutableDictionary new];
    userInfo[NSLocalizedDescriptionKey] = [@"AuthorizationError" mrc_localizedWithTable:@"MRCloudError"];
    if (reason) {
        userInfo[NSUnderlyingErrorKey] = reason;
    }
    return [[NSError alloc] initWithDomain:MRCloudSDKErrorDomain code:MRCAuthorizationError userInfo:userInfo];
}

+ (NSError *)mrc_blobErrorWithReason:(NSError *)reason format:(NSString *)format, ... {
    NSParameterAssert(format);
    va_list args;
    va_start(args, format);
    NSString *description = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    NSMutableDictionary *userInfo = [NSMutableDictionary new];
    userInfo[NSLocalizedDescriptionKey] = [@"BlobError" mrc_localizedWithTable:@"MRCloudError"];
    userInfo[DescriptionErrorKey] = description;
    if (reason) {
        userInfo[NSUnderlyingErrorKey] = reason;
    }
    return [[NSError alloc] initWithDomain:MRCloudSDKErrorDomain code:MRCBlobError userInfo:userInfo];
}

+ (NSError *)mrc_internalErrorWithFormat:(NSString *)format, ... {
    NSParameterAssert(format);
    va_list args;
    va_start(args, format);
    NSString *description = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    NSDictionary *userInfo = @{NSLocalizedDescriptionKey : [@"InternalError" mrc_localizedWithTable:@"MRCloudError"],
                               DescriptionErrorKey       : description};
    return [[NSError alloc] initWithDomain:MRCloudSDKErrorDomain code:MRCInternalError userInfo:userInfo];
}

+ (NSError *)mrc_metadErrorWithStatusCode:(MRCMetadStatusCode)statusCode {
    NSDictionary *userInfo = @{NSLocalizedDescriptionKey : [MetadStatusCodeLocalizationKey(statusCode) mrc_localizedWithTable:@"MRCloudError"],
                               MetadStatusCodeErrorKey   : [NSNumber numberWithInt:statusCode]};
    return [[NSError alloc] initWithDomain:MRCloudSDKErrorDomain code:MRCMetadServerError userInfo:userInfo];
}

+ (NSError *)mrc_networkErrorWithReason:(NSError *)reason {
    NSMutableDictionary *userInfo = [NSMutableDictionary new];
    userInfo[NSLocalizedDescriptionKey] = [@"NetworkError" mrc_localizedWithTable:@"MRCloudError"];
    if (reason) {
        userInfo[NSUnderlyingErrorKey] = reason;
    }
    return [[NSError alloc] initWithDomain:MRCloudSDKErrorDomain code:MRCNetworkError userInfo:userInfo];
}

+ (NSError *)mrc_serverErrorWithFormat:(NSString *)format, ... {
    NSParameterAssert(format);
    va_list args;
    va_start(args, format);
    NSString *description = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    NSDictionary *userInfo = @{NSLocalizedDescriptionKey : [@"ServerError" mrc_localizedWithTable:@"MRCloudError"],
                               DescriptionErrorKey       : description};
    return [[NSError alloc] initWithDomain:MRCloudSDKErrorDomain code:MRCServerError userInfo:userInfo];
}

+ (NSError *)mrc_serverErrorWithReason:(NSError *)reason format:(NSString *)format, ... {
    NSParameterAssert(format);
    va_list args;
    va_start(args, format);
    NSString *description = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    NSMutableDictionary *userInfo = [NSMutableDictionary new];
    userInfo[NSLocalizedDescriptionKey] = [@"ServerError" mrc_localizedWithTable:@"MRCloudError"];
    userInfo[DescriptionErrorKey] = description;
    if (reason) {
        userInfo[NSUnderlyingErrorKey] = reason;
    }
    return [[NSError alloc] initWithDomain:MRCloudSDKErrorDomain code:MRCServerError userInfo:userInfo];
}

+ (NSError *)mrc_serverErrorWithHTTPStatusCode:(NSInteger)statusCode URL:(NSURL *)URL {
    NSParameterAssert(URL);
    if (statusCode == MRCHTTPStatusCodeForbidden) {
        return [NSError mrc_authorizationErrorWithReason:[NSError errorWithDomain:MRCloudSDKErrorDomain
                                                                             code:MRCServerError
                                                                         userInfo:@{NSURLErrorKey          : URL,
                                                                                    HTTPStatusCodeErrorKey : [NSNumber numberWithInteger:statusCode]}]];
        
    } else {
        NSDictionary *userInfo = @{NSLocalizedDescriptionKey : [@"ServerError" mrc_localizedWithTable:@"MRCloudError"],
                                   NSURLErrorKey             : URL,
                                   HTTPStatusCodeErrorKey    : [NSNumber numberWithInteger:statusCode]};
        return [[NSError alloc] initWithDomain:MRCloudSDKErrorDomain code:MRCServerError userInfo:userInfo];

    }
}

+ (NSError *)mrc_systemErrorWithReason:(NSError *)reason {
    NSMutableDictionary *userInfo = [NSMutableDictionary new];
    userInfo[NSLocalizedDescriptionKey] = [@"SystemError" mrc_localizedWithTable:@"MRCloudError"];
    if (reason) {
        userInfo[NSUnderlyingErrorKey] = reason;
    }
    return [[NSError alloc] initWithDomain:MRCloudSDKErrorDomain code:MRCSystemError userInfo:userInfo];
}

+ (NSError *)mrc_systemErrorWithFormat:(NSString *)format, ... {
    NSParameterAssert(format);
    va_list args;
    va_start(args, format);
    NSString *description = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    NSDictionary *userInfo = @{NSLocalizedDescriptionKey : [@"SystemError" mrc_localizedWithTable:@"MRCloudError"],
                               DescriptionErrorKey       : description};
    return [[NSError alloc] initWithDomain:MRCloudSDKErrorDomain code:MRCSystemError userInfo:userInfo];
}

#pragma mark - Private

- (NSNumber *)p_numberForKey:(NSString *)key {
    if ([self mrc_isCloudError] && self.userInfo != nil) {
        id number = [self.userInfo objectForKey:key];
        if (number != nil && [number isKindOfClass:[NSNumber class]]) {
            return number;
        }
    }
    return nil;
}

@end
