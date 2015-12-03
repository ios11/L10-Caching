//
//  MRCLevelDB.mm
//  MRCloudDB
//
//  Created by Osipov on 17.06.14.
//  Copyright (c) 2014 Pavel Osipov. All rights reserved.
//

#import "MRCLevelDB.h"
#import "MRCNode.h"
#import <leveldb/db.h>

@implementation MRCLevelDB {
    leveldb::DB *_db;
    uint64_t _lastNodeKey;
}

- (id)init {
    if (self = [super init]) {
        _db = nullptr;
    }
    return self;
}

- (void)dealloc {
    delete _db;
}

- (void)openAtPath:(NSString *)path {
    leveldb::Options options;
    options.create_if_missing = true;
    leveldb::Status status = leveldb::DB::Open(options, [[path stringByAppendingPathComponent:@"db"] UTF8String], &_db);
    if (!status.ok()) {
        NSLog(@"Failed to open at path %@: %s", path, status.ToString().c_str());
    }
    assert(status.ok());
}

- (void)test {
    UIAlertView* helloWorldAlert = [[UIAlertView alloc]
                                    initWithTitle:@"Getting Started with LevelDB"
                                    message:@"Hello, LevelDB World!"
                                    delegate:nil
                                    cancelButtonTitle:@"OK" otherButtonTitles:nil];
    [helloWorldAlert show];
}



- (uint64_t)generateNodeID {
    return _lastNodeKey++;
}

- (void)generateTree {
    MRCDirectoryNode *rootDirectory = [MRCDirectoryNode new];
    rootDirectory.name = @"/";
    rootDirectory.listingRevision = 0;
    
}

- (NSArray *)generateNodeListWithDirectoryCount:(uint32_t)directoryCount
                                      fileCount:(uint64_t)fileCount
                                          level:(uint32_t)level {
    static uint32_t maxLevel = 2;
    NSMutableArray *nodes = [NSMutableArray new];
    for (int i = 0; i < directoryCount; ++i) {
        MRCDirectoryNode *directory = [MRCDirectoryNode new];
        directory.name = [@(i) stringValue];
        directory.listingRevision = i;
        if (level < maxLevel) {
            directory.children = [self generateNodeListWithDirectoryCount:directoryCount
                                                                fileCount:fileCount
                                                                    level:(level + 1)];
        }
        [nodes addObject:directory];
    }
    uint64_t now = [[NSDate date] timeIntervalSince1970];
    for (int i = 0; i < fileCount; ++i) {
        MRCFileNode *file = [MRCFileNode new];
        file.name = [[@(i) stringValue] stringByAppendingString:@".txt"];
        file.mtime = now - (arc4random() % 100000);
        [nodes addObject:file];
    }
    return nodes;
}

@end
