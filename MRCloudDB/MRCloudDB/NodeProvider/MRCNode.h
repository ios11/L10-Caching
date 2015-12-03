//
//  MRCNode.h
//  MRCloudDB
//
//  Created by Pavel Osipov on 25.06.14.
//  Copyright (c) 2014 Pavel Osipov. All rights reserved.
//

#import <Foundation/Foundation.h>

@class MRCFileNode;
@class MRCDirectoryNode;

enum {
    MRCNodeNameLengthMax = UINT8_MAX
};

@interface MRCNode : NSObject

//@property (nonatomic, weak) MRCDirectoryNode *parent;
@property (nonatomic, strong) NSString *name;

- (BOOL)isDirectory;
- (BOOL)isRootDirectory;
- (NSComparisonResult)compare:(MRCNode *)other;

+ (instancetype)decodeFromXMLArchive:(NSData *)data error:(NSError **)error;
- (NSData *)encodeToXMLArchive;

- (void)visitWithFileHandler:(void(^)(MRCFileNode *file))fileHandler
            directoryHandler:(void(^)(MRCDirectoryNode *directory))directoryHandler;

@end


@interface MRCFileNode : MRCNode
@property (nonatomic) uint64_t mtime;
@end


@interface MRCDirectoryNode : MRCNode
+ (instancetype)rootDirectory;
@property (nonatomic) uint64_t listingRevision;
@property (nonatomic) NSArray *children;

- (void)enumerateChildrenWithFileHandler:(void (^)(MRCFileNode *))fileHandler
                        directoryHandler:(void (^)(MRCDirectoryNode *))directoryHandler;

@end
