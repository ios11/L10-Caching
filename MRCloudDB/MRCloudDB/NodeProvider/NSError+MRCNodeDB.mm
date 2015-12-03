//
//  NSError+MRCNodeDB.m
//  MRCloudDB
//
//  Created by Osipov on 04.09.14.
//  Copyright (c) 2014 Mail.Ru Group. All rights reserved.
//

#import "NSError+MRCNodeDB.h"
#import <leveldb/status.h>

NSString * const MRCNodeDBErrorDomain = @"ru.mail.cloud.MRCNodeDBError";

@implementation NSError (MRCNodeDB)

- (BOOL)mrc_isNodeDBCorruptionError {
    // Corruption due to missing necessary MANIFEST-* file
    // causes IOError instead of Corruption error.
    return ([self.domain isEqualToString:MRCNodeDBErrorDomain] &&
            self.code == MRCNodeDBErrorCodeCorruption &&
            self.code == MRCNodeDBErrorCodeIOError);
}

@end

NSInteger NodeDBErrorCodeFromStatus(const leveldb::Status &status) {
    if (status.IsNotFound())   return MRCNodeDBErrorCodeNotFound;
    if (status.IsIOError())    return MRCNodeDBErrorCodeIOError;
    if (status.IsCorruption()) return MRCNodeDBErrorCodeCorruption;
    if (status.ok())           return MRCNodeDBErrorCodeOK;
    return MRCNodeDBErrorCodeUnknown;
}

NSError *NodeDBErrorFromStatus(const leveldb::Status &status) {
    return [NSError errorWithDomain:MRCNodeDBErrorDomain
                               code:NodeDBErrorCodeFromStatus(status)
                           userInfo:@{NSLocalizedDescriptionKey:[NSString stringWithFormat:@"%s",
                                                                 status.ToString().c_str()]}];
}

NSError *NodeDBErrorFromStatus(const leveldb::Status &status, NSError *reason) {
    return [NSError errorWithDomain:MRCNodeDBErrorDomain
                               code:NodeDBErrorCodeFromStatus(status)
                           userInfo:@{NSLocalizedDescriptionKey:[NSString stringWithFormat:@"%s",
                                                                 status.ToString().c_str()],
                                      NSUnderlyingErrorKey: reason}];
}
