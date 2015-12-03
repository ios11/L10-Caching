//
//  MRCNodeSQLDB.h
//  MRCloudDB
//
//  Created by Osipov on 10.09.14.
//  Copyright (c) 2014 Mail.Ru Group. All rights reserved.
//

#import "MRCNodeDB.h"

@interface MRCNodeSQLDBCursor : NSObject <MRCNodeDBCursor>

@property (nonatomic, strong, readonly) MRCDirectoryNode *directoryNode;
@property (nonatomic, assign, readonly) NSUInteger count;
@property (nonatomic, assign, readonly) MRCNodeDBCursorSortType sortType;

- (MRCNode *)fetchNodeAtIndex:(NSUInteger)index error:(NSError **)error;

@end


@interface MRCNodeSQLDB : NSObject <MRCNodeDB>

@property (nonatomic, strong, readonly) MRCDirectoryNode *rootDirectoryNode;

+ (instancetype)nodeDBWithPath:(NSString *)path error:(NSError **)error;

@end
