//
//  MRCNodeDB.h
//  MRCloudDB
//
//  Created by Osipov on 25.06.14.
//  Copyright (c) 2014 Pavel Osipov. All rights reserved.
//

#import "MRCNodeDB.h"

@interface MRCNodeLevelDBCursor : NSObject <MRCNodeDBCursor>

@property (nonatomic, strong, readonly) MRCDirectoryNode *directoryNode;
@property (nonatomic, assign, readonly) NSUInteger count;
@property (nonatomic, assign, readonly) MRCNodeDBCursorSortType sortType;

- (MRCNode *)fetchNodeAtIndex:(NSUInteger)index error:(NSError **)error;

@end


@interface MRCNodeLevelDB : NSObject <MRCNodeDB>

@property (nonatomic, strong, readonly) MRCDirectoryNode *rootDirectoryNode;

+ (instancetype)nodeDBWithPath:(NSString *)path error:(NSError **)error;

@end
