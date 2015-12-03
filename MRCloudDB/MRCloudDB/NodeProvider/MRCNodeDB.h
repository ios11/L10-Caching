//
//  MRCNodeDB.h
//  MRCloudDB
//
//  Created by Osipov on 10.09.14.
//  Copyright (c) 2014 Mail.Ru Group. All rights reserved.
//

#import <Foundation/Foundation.h>

@class MRCNode;
@class MRCDirectoryNode;

//
// Make separate framework with 'MCDB' prefix.
//

//
// MRCNodeDBCursor sorting types.
//
typedef NS_ENUM(int, MRCNodeDBCursorSortType) {
    // No sorting.
    MRCNodeDBCursorSortTypeUnsorted,
    // Directories before files. Both node types are sorted by name in direct order (A-Z).
    MRCNodeDBCursorSortTypeByName,
    // Directories before files. Both node types are sorted by name in reversed order (Z-A).
    // MRCNodeDBCursorSortTypeByNameReversed,
    // Directories before files. Files are sorted by time in direct order (newest first).
    // MRCNodeDBCursorSortTypeByTime,
    // Directories before files. Files are sorted by time in reversed order (oldest first).
    // MRCNodeDBCursorSortTypeByTimeReversed
};

//
// Iterates over nodes in a specified directory.
//
@protocol MRCNodeDBCursor <NSObject>

- (MRCDirectoryNode *)directoryNode;
- (NSUInteger)count;
- (MRCNodeDBCursorSortType)sortType;

- (MRCNode *)fetchNodeAtIndex:(NSUInteger)index error:(NSError **)error;

@end

//
// Persistent storage for cache with nodes.
//
@protocol MRCNodeDB

- (MRCDirectoryNode *)rootDirectoryNode;

//
// Returns cursor for iterating over persisted children of directory.
// Returns nil if there is not such directory.
//
- (id<MRCNodeDBCursor>)cursorForDirectory:(MRCDirectoryNode *)directoryNode
                                      sortType:(MRCNodeDBCursorSortType)sortType
                                         error:(NSError **)error;

//
// TODO: - (RACSignal *)performChanges:(void(^)(id<MRCNodeDBEditor> editor))changeBlock;
//
- (BOOL)replaceNodesInDirectory:(MRCDirectoryNode *)targetDirectory
                      withNodes:(NSArray *)sourceNodes
                          error:(NSError **)error;

@end
