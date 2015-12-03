//
//  NSError+MRCNodeDB.h
//  MRCloudDB
//
//  Created by Osipov on 04.09.14.
//  Copyright (c) 2014 Mail.Ru Group. All rights reserved.
//

#import <Foundation/Foundation.h>

namespace leveldb {
    class Status;
}

FOUNDATION_EXTERN NSString * const MRCNodeDBErrorDomain;

typedef NS_ENUM(NSInteger, MRCNodeDBErrorCode) {
    MRCNodeDBErrorCodeOK,
    MRCNodeDBErrorCodeUnknown,
    MRCNodeDBErrorCodeNotFound,
    MRCNodeDBErrorCodeCorruption,
    MRCNodeDBErrorCodeIOError
};

@interface NSError (MRCNodeDB)
- (BOOL)mrc_isNodeDBCorruptionError;
@end

NSInteger NodeDBErrorCodeFromStatus(const leveldb::Status &status);
NSError *NodeDBErrorFromStatus(const leveldb::Status &status);
NSError *NodeDBErrorFromStatus(const leveldb::Status &status, NSError *reason);
