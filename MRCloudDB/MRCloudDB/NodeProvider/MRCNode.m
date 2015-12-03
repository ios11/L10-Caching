//
//  MRCNode.m
//  MRCloudDB
//
//  Created by Pavel Osipov on 25.06.14.
//  Copyright (c) 2014 Pavel Osipov. All rights reserved.
//

#import "MRCNode.h"
#import "NSError+MRCSDK.h"

static NSString * const kRootDirectoryName = @"/";

#pragma mark - MRCNode

@interface MRCNode () <NSCoding>
@end

@implementation MRCNode

- (id)initWithCoder:(NSCoder *)aDecoder {
    if (self = [super init]) {
        _name = [aDecoder decodeObjectForKey:@"name"];
    }
    return self;
}

- (BOOL)isDirectory {
    return NO;
}

- (BOOL)isRootDirectory {
    return [self.name isEqualToString:kRootDirectoryName];
}

- (NSComparisonResult)compare:(MRCNode *)other {
    if (self == other) {
        return NSOrderedSame;
    }
    if ([self isDirectory] && ![other isDirectory]) {
        return NSOrderedAscending;
    }
    if (![self isDirectory] && [other isDirectory]) {
        return NSOrderedDescending;
    }
//    const NSComparisonResult stateComparisonResult = MRCCompareNodeStates([self state], [other state]);
//    if (stateComparisonResult != NSOrderedSame) {
//        return stateComparisonResult;
//    }
    return [self.name caseInsensitiveCompare:other.name];
}

- (void)visitWithFileHandler:(void(^)(MRCFileNode *file))fileHandler
            directoryHandler:(void(^)(MRCDirectoryNode *directory))directoryHandler
{}

- (void)encodeWithCoder:(NSCoder *)aCoder {
    [aCoder encodeObject:_name forKey:@"name"];
}

- (NSString *)description {
    return [NSString stringWithFormat:@"%@:%@", [super description], _name];
}

+ (instancetype)decodeFromXMLArchive:(NSData *)data error:(NSError **)error {
    @try {
        id node = [NSKeyedUnarchiver unarchiveObjectWithData:data];
        if (![node isKindOfClass:[MRCNode class]]) {
            @throw [NSException exceptionWithName:NSInternalInconsistencyException
                                           reason:[NSString stringWithFormat:@"Failed to unarchive node from '%@' data: %@", node, data]
                                         userInfo:nil];
        }
        return node;
    } @catch (NSException *exception) {
        MRCAssignError(error, [NSError mrc_internalErrorWithFormat:@"Failed to unarchive node: %@", exception]);
        return nil;
    }
}

- (NSData *)encodeToXMLArchive {
    return [NSKeyedArchiver archivedDataWithRootObject:self];
}

@end

#pragma mark - MRCFileNode

@implementation MRCFileNode

- (id)initWithCoder:(NSCoder *)aDecoder {
    if (self = [super initWithCoder:aDecoder]) {
        _mtime = [[aDecoder decodeObjectForKey:@"mtime"] unsignedLongLongValue];
    }
    return self;
}

- (void)visitWithFileHandler:(void(^)(MRCFileNode *file))fileHandler
            directoryHandler:(void(^)(MRCDirectoryNode *directory))directoryHandler {
    if (fileHandler) {
        fileHandler(self);
    }
}

- (void)encodeWithCoder:(NSCoder *)aCoder {
    [super encodeWithCoder:aCoder];
    [aCoder encodeObject:@(_mtime) forKey:@"mtime"];
}

- (NSString *)description {
    return [NSString stringWithFormat:@"%@:%llu", [super description], _mtime];
}

@end

#pragma mark - MRCDirectoryNode

@implementation MRCDirectoryNode

- (id)initWithCoder:(NSCoder *)aDecoder {
    if (self = [super initWithCoder:aDecoder]) {
        _listingRevision = [[aDecoder decodeObjectForKey:@"listingRevision"] unsignedLongLongValue];
    }
    return self;
}

- (BOOL)isDirectory {
    return YES;
}

- (void)visitWithFileHandler:(void(^)(MRCFileNode *file))fileHandler
            directoryHandler:(void(^)(MRCDirectoryNode *directory))directoryHandler {
    if (directoryHandler) {
        directoryHandler(self);
    }
}

- (void)enumerateChildrenWithFileHandler:(void (^)(MRCFileNode *))fileHandler
                        directoryHandler:(void (^)(MRCDirectoryNode *))directoryHandler {
    for (MRCNode *node in _children) {
        [node visitWithFileHandler:fileHandler directoryHandler:^(MRCDirectoryNode *directory) {
            if (directoryHandler) {
                directoryHandler(directory);
            }
            [directory enumerateChildrenWithFileHandler:fileHandler directoryHandler:directoryHandler];
        }];
    }
}

- (void)encodeWithCoder:(NSCoder *)aCoder {
    [super encodeWithCoder:aCoder];
    [aCoder encodeObject:@(_listingRevision) forKey:@"listingRevision"];
}

+ (instancetype)rootDirectory {
    MRCDirectoryNode *node = [MRCDirectoryNode new];
    node.name = kRootDirectoryName;
    return node;
}

@end
