//
//  MRCNodeLMDB.h
//  MRCloudDB
//
//  Created by Pavel Osipov on 31.08.15.
//  Copyright (c) 2015 Mail.Ru Group. All rights reserved.
//

#import "MRCNodeDB.h"

@interface MRCNodeLMDBCursor : NSObject <MRCNodeDBCursor>

@property (nonatomic, strong, readonly) MRCDirectoryNode *directoryNode;
@property (nonatomic, assign, readonly) NSUInteger count;
@property (nonatomic, assign, readonly) MRCNodeDBCursorSortType sortType;

- (MRCNode *)fetchNodeAtIndex:(NSUInteger)index error:(NSError **)error;

@end


@interface MRCNodeLMDB : NSObject <MRCNodeDB>

@property (nonatomic, strong, readonly) MRCDirectoryNode *rootDirectoryNode;

+ (instancetype)nodeDBWithPath:(NSString *)path error:(NSError **)error;

@end
