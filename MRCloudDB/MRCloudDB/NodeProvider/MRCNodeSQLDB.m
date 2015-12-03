//
//  MRCNodeSQLDB.m
//  MRCloudDB
//
//  Created by Osipov on 10.09.14.
//  Copyright (c) 2014 Mail.Ru Group. All rights reserved.
//

#import "MRCNodeSQLDB.h"
#import "MRCNode+MRCNodeDB.h"
#import "MRCExceptions.h"
#import "NSError+MRCSDK.h"
#import <FMDB/FMDB.h>

typedef uint32_t node_id_t;

static const node_id_t kRootDirectoryNodeID           = 1;
static const node_id_t kRootDirectoryNodeParentNodeID = 0;

//inline
//static void ExecErrorCheck(int status, char *err_msg) {
//    if (status != SQLITE_OK) {
//        fprintf(stderr, "SQL error: %s\n", err_msg);
//        sqlite3_free(err_msg);
//        exit(1);
//    }
//}

static int FinderLikeCompareStrings(CFStringRef lString, CFStringRef rString, CFLocaleRef locale) {
    static CFOptionFlags kFinderCompareOptions =
    kCFCompareCaseInsensitive |
    kCFCompareNonliteral |
    kCFCompareLocalized |
    kCFCompareNumerically |
    kCFCompareWidthInsensitive |
    kCFCompareForcedOrdering;
    return CFStringCompareWithOptionsAndLocale(
       lString,
       rString,
       CFRangeMake(0, CFStringGetLength(lString)),
       kFinderCompareOptions,
       locale);
}

static int FinderLikeCompare(void *context, int lLength, const void *lBytes, int rLength, const void *rBytes) {
    CFStringRef lString = CFStringCreateWithBytesNoCopy(
        kCFAllocatorDefault,
        lBytes,
        lLength,
        kCFStringEncodingUTF8,
        false,
        kCFAllocatorNull);
    CFStringRef rString = CFStringCreateWithBytesNoCopy(
        kCFAllocatorDefault,
        rBytes,
        rLength,
        kCFStringEncodingUTF8,
        false,
        kCFAllocatorNull);
    CFLocaleRef locale = (CFLocaleRef)context;
    const int result = FinderLikeCompareStrings(lString, rString, locale);
    CFRelease(lString);
    CFRelease(rString);
    return result;
}

#pragma mark - MRCNode (MRCNodeSQLDB)

@interface MRCNode (MRCNodeSQLDB)
@end

@implementation MRCNode (MRCNodeSQLDB)

+ (MRCNode *)nodeFromFMResultSet:(FMResultSet *)resultSet error:(NSError **)error {
    id typeObject = [resultSet objectForColumnName:@"is_folder"];
    if (![typeObject isKindOfClass:[NSNumber class]]) {
        MRCAssignError(error, [NSError mrc_internalErrorWithFormat:@"Unexpected type class '%@'.", typeObject]);
        return nil;
    }
    MRCNode *node = nil;
    if ([typeObject intValue]) {
        node = [MRCDirectoryNode new];
    } else {
        MRCFileNode *fileNode = [MRCFileNode new];
        fileNode.mtime = [resultSet longLongIntForColumn:@"mtime"];
        node = fileNode;
    }
    node.ID = [resultSet objectForColumnName:@"id"];
    node.name = [resultSet stringForColumn:@"name"];
    return node;
}

- (NSComparisonResult)compare:(MRCNode *)other usingLocale:(NSLocale *)locale {
    return FinderLikeCompareStrings((__bridge CFStringRef)self.name,
                                    (__bridge CFStringRef)other.name,
                                    (__bridge CFLocaleRef)locale);
}

@end

#pragma mark - MRCNodeSQLDBCursor

@interface MRCNodeSQLDBCursor ()

@property (nonatomic, strong) MRCNodeSQLDB *DB;
@property (nonatomic, strong) NSArray *childrenIDs;
@property (nonatomic, strong, readwrite) MRCDirectoryNode *directoryNode;

+ (instancetype)nodeCursorWithNodeDB:(MRCNodeSQLDB *)DB
                       directoryNode:(MRCDirectoryNode *)directoryNode
                         childrenIDs:(NSArray *)childrenIDs
                            sortType:(MRCNodeDBCursorSortType)sortType;

@end

#pragma mark - MRCNodeDB

@interface MRCNodeSQLDB () {
    CFLocaleRef _locale;
}
@property (nonatomic) FMDatabase *DB;
@property (nonatomic, strong, readwrite) MRCDirectoryNode *rootDirectoryNode;
@property (nonatomic) NSDictionary *indices;
@end

@implementation MRCNodeSQLDB

- (instancetype)init {
    MRCThrowDeadlySelectorInvokation(_cmd, @selector(initWithDB:locale:));
}

- (instancetype)initWithDB:(FMDatabase *)DB locale:(CFLocaleRef)locale {
    NSParameterAssert(DB);
    NSParameterAssert(locale);
    if (self = [super init]) {
        _DB = DB;
        _DB.logsErrors = YES;
        _locale = locale;
        _indices = @{@"nodes": @[@"parent_id", @"is_folder", @"name", @"mtime"]};
    }
    return self;
}

+ (instancetype)nodeDBWithPath:(NSString *)path error:(NSError **)error {
    FMDatabase *DB = [FMDatabase databaseWithPath:[path stringByAppendingString:@".sqlite"]];
    if (![DB open]) {
        MRCAssignError(error, [NSError mrc_systemErrorWithReason:[DB lastError]]);
        return nil;
    }
    CFLocaleRef locale = CFLocaleGetSystem();
    sqlite3_create_collation([DB sqliteHandle], "FINDERCASE", SQLITE_UTF8, (void *)locale, FinderLikeCompare);

    if (![DB executeUpdate:
          @"CREATE TABLE IF NOT EXISTS nodes ("
          "    id          INTEGER NOT NULL PRIMARY KEY,"
          "    parent_id   INTEGER REFERENCES nodes(id) ON UPDATE CASCADE"
          "                                             ON DELETE CASCADE,"
          "    is_folder   INTEGER,"
          "    name        TEXT COLLATE FINDERCASE,"
          "    mtime       TIMESTAMP DEFAULT 0)"]) {
        MRCAssignError(error, [NSError mrc_systemErrorWithReason:[DB lastError]]);
        CFRelease(locale);
        return nil;
    }
    MRCNodeSQLDB *sqliteDB = [[MRCNodeSQLDB alloc] initWithDB:DB locale:locale];
    if (![sqliteDB p_buildIndicesForTable:@"nodes" error:error]) {
        MRCAssignError(error, [NSError mrc_systemErrorWithReason:[DB lastError]]);
        CFRelease(locale);
        return nil;
    }
    NSError *localError = nil;
    MRCNode *rootNode = [sqliteDB p_fetchNodeWithID:kRootDirectoryNodeID error:&localError];
    if (!rootNode) {
        rootNode = [MRCDirectoryNode rootDirectory];
        rootNode.ID = @(kRootDirectoryNodeID);
        if (![sqliteDB p_addNode:rootNode intoDirectoryWithID:kRootDirectoryNodeParentNodeID error:error]) {
            return nil;
        }
    }
    sqliteDB.rootDirectoryNode = (id)rootNode;
    return sqliteDB;
}

- (void)dealloc {
    [_DB close];
    CFRelease(_locale);
}

- (id<MRCNodeDBCursor>)cursorForDirectory:(MRCDirectoryNode *)directoryNode
                                 sortType:(MRCNodeDBCursorSortType)sortType
                                    error:(NSError **)error {
    NSString *queryFormat = nil;
    switch (sortType) {
        case MRCNodeDBCursorSortTypeUnsorted:
            queryFormat = @"SELECT id FROM nodes WHERE parent_id = ?";
            break;
        case MRCNodeDBCursorSortTypeByName:
            queryFormat = @"SELECT id FROM nodes WHERE parent_id = ? ORDER BY is_folder DESC, name ASC";
            break;
    }
    FMResultSet *results = [_DB executeQuery:queryFormat, directoryNode.ID];
    NSMutableArray *childrenIDs = [NSMutableArray new];
    while([results next]) {
        id childID = [results objectForColumnName:@"id"];
        NSParameterAssert([childID isKindOfClass:[NSNumber class]]);
        [childrenIDs addObject:childID];
    }
    MRCNodeSQLDBCursor *cursor = [MRCNodeSQLDBCursor nodeCursorWithNodeDB:self
                                                            directoryNode:directoryNode
                                                              childrenIDs:childrenIDs
                                                                 sortType:sortType];
    return cursor;
}

- (BOOL)replaceNodesInDirectory:(MRCDirectoryNode *)targetDirectory
                      withNodes:(NSArray *)sourceNodes
                          error:(NSError **)error {
    NSParameterAssert(targetDirectory.ID);
    if (!targetDirectory.ID) {
        MRCAssignError(error, [NSError mrc_internalErrorWithFormat:@"Target directory %@ has no ID.", targetDirectory]);
        return NO;
    }
    [_DB beginTransaction];
    if (![self p_dropIndicesForTable:@"nodes" error:error]) {
        [_DB rollback];
        return NO;
    }
    if (![self p_replaceNodesInDirectoryWithID:[targetDirectory.ID intValue] withNodes:sourceNodes error:error]) {
        [_DB rollback];
        return NO;
    }
    if (![self p_buildIndicesForTable:@"nodes" error:error]) {
        [_DB rollback];
        return NO;
    }
    if (![_DB commit]) {
        MRCAssignError(error, [NSError mrc_systemErrorWithReason:[_DB lastError]]);
        return NO;
    }
    return YES;
}

- (BOOL)p_replaceNodesInDirectoryWithID:(node_id_t)targetDirectoryID
                              withNodes:(NSArray *)sourceNodes
                                  error:(NSError **)error {
    NSArray *insertingNodes = [sourceNodes sortedArrayUsingComparator:^NSComparisonResult(MRCNode *lhs, MRCNode *rhs) {
        return [lhs compare:rhs usingLocale:(__bridge NSLocale *)_locale];
    }];
    __block NSError *insertingError = nil;
    __block NSUInteger insertingNodeIndex = 0;
    [self p_enumerateNodesWithParentID:targetDirectoryID usingBlock:^(MRCNode *node, BOOL *stop) {
        while (insertingNodeIndex < [insertingNodes count]) {
            MRCNode *insertingNode = insertingNodes[insertingNodeIndex];
            switch ([insertingNode compare:node usingLocale:(__bridge NSLocale *)_locale]) {
                case  NSOrderedAscending: {
//                    NSLog(@"+ %@", insertingNode);
                    if (![self p_addNode:insertingNode intoDirectoryWithID:targetDirectoryID error:&insertingError]) {
                        *stop = YES;
                        return;
                    }
                    ++insertingNodeIndex;
                } break;
                case NSOrderedSame: {
//                    NSLog(@"= %@", insertingNode);
                    if (![self p_updateExistingNode:node withActualNode:insertingNode error:&insertingError]) {
                        *stop = YES;
                        return;
                    }
                    if ([node isDirectory]) {
                        MRCDirectoryNode *directory = (id)insertingNode;
                        if (directory.children != nil) {
                            if (![self p_replaceNodesInDirectoryWithID:[node.ID intValue]
                                                             withNodes:directory.children
                                                                 error:&insertingError]) {
                                *stop = YES;
                                return;
                            }
                        }
                    }
                    ++insertingNodeIndex;
                } return;
                case NSOrderedDescending: {
//                    NSLog(@"- %@", node);
                    if (![self p_removeNode:node error:&insertingError]) {
                        *stop = YES;
                        return;
                    }
                } return;
            }
        }
        if (insertingNodeIndex == [insertingNodes count]) {
//            NSLog(@"- %@", node);
            if (![self p_removeNode:node error:&insertingError]) {
                *stop = YES;
                return;
            }
        }
    }];
    if (insertingError != nil) {
        MRCAssignError(error, insertingError);
        return NO;
    }
    while (insertingNodeIndex != [insertingNodes count]) {
        MRCNode *insertingNode = insertingNodes[insertingNodeIndex];
//        NSLog(@"+ %@", insertingNode);
        if (![self p_addNode:insertingNode intoDirectoryWithID:targetDirectoryID error:error]) {
            return NO;
        }
        ++insertingNodeIndex;
    }
    return YES;
}

#pragma mark - Private

- (BOOL)p_addNode:(MRCNode *)node intoDirectoryWithID:(node_id_t)parentDirectoryID error:(NSError **)error {
    NSParameterAssert(node);
    if (!node) {
        MRCAssignError(error, [NSError mrc_internalErrorWithFormat:@"Unexpected nil putting node."]);
        return NO;
    }
    __block uint64_t mtime = 0;
    [node visitWithFileHandler:^(MRCFileNode *file) {
        mtime = file.mtime;
    } directoryHandler:nil];
    NSNumber *isFolder = [node isDirectory] ? @(1) : @(0);
    if (![_DB executeUpdate:@"INSERT INTO nodes VALUES(NULL, ?, ?, ?, ?)", @(parentDirectoryID), isFolder, node.name, @(mtime)]) {
        MRCAssignError(error, [NSError mrc_systemErrorWithReason:[_DB lastError]]);
        return NO;
    }
    sqlite_int64 lastRowID = [_DB lastInsertRowId];
    node.ID = @(lastRowID);//[NSNumber numberWithLongLong:[_DB lastInsertRowId]];
    NSParameterAssert([node.ID intValue] > 0);
    if ([node isDirectory]) {
        MRCDirectoryNode *directory = (id)node;
        for (MRCNode *childNode in directory.children) {
            if (![self p_addNode:childNode intoDirectoryWithID:[node.ID intValue] error:error]) {
                return NO;
            }
        }
    }
    return YES;
}

- (BOOL)p_updateExistingNode:(MRCNode *)existingNode withActualNode:(MRCNode *)actualNode error:(NSError **)error {
    __block uint64_t mtime = 0;
    [actualNode visitWithFileHandler:^(MRCFileNode *file) {
        mtime = file.mtime;
    } directoryHandler:nil];
    if (![_DB executeUpdate:@"UPDATE nodes SET mtime = ? WHERE id = ?", @(mtime), existingNode.ID]) {
        MRCAssignError(error, [NSError mrc_systemErrorWithReason:[_DB lastError]]);
        return NO;
    }
    return YES;
}

- (BOOL)p_removeNode:(MRCNode *)node error:(NSError **)error {
    if (![_DB executeUpdate:@"DELETE FROM nodes WHERE id = ?", node.ID]) {
        MRCAssignError(error, [NSError mrc_systemErrorWithReason:[_DB lastError]]);
        return NO;
    }
    return YES;
}

- (void)p_enumerateNodesWithParentID:(node_id_t)ID usingBlock:(void (^)(MRCNode *node, BOOL *stop))block {
    NSParameterAssert(block);
    if (!block) {
        return;
    }
    FMResultSet *results = [_DB executeQuery:@"SELECT * FROM nodes WHERE parent_id = ? ORDER BY name ASC", @(ID)];
    while ([results next]) {
        BOOL stop = NO;
        NSError *error = nil;
        MRCNode *node = [MRCNode nodeFromFMResultSet:results error:&error];
        NSParameterAssert(node);
        if (!node) {
            NSLog(@"%@: Failed to parse select results: %@", self, error);
            return;
        }
        block(node, &stop);
        if (stop) {
            break;
        }
    }
}

- (BOOL)p_buildIndicesForTable:(NSString *)tableName error:(NSError **)error {
    NSArray *indexNames = [_indices objectForKey:tableName];
    if (!indexNames) {
        return YES;
    }
    for (NSString *indexName in indexNames) {
        NSString *queue = [NSString stringWithFormat:@"CREATE INDEX IF NOT EXISTS %@_index ON nodes(%@)", indexName, indexName];
        if (![_DB executeUpdate:queue]) {
            MRCAssignError(error, [NSError mrc_systemErrorWithReason:[_DB lastError]]);
            return NO;
        }
    }
    return YES;
}

- (BOOL)p_dropIndicesForTable:(NSString *)tableName error:(NSError **)error {
    NSArray *indexNames = [_indices objectForKey:tableName];
    if (!indexNames) {
        return YES;
    }
    for (NSString *indexName in indexNames) {
        NSString *queue = [NSString stringWithFormat:@"DROP INDEX %@_index", indexName];
        if (![_DB executeUpdate:queue]) {
            MRCAssignError(error, [NSError mrc_systemErrorWithReason:[_DB lastError]]);
            return NO;
        }
    }
    return YES;
}

- (MRCNode *)p_fetchNodeWithID:(node_id_t)nodeID error:(NSError **)error {
    FMResultSet *results = [_DB executeQuery:@"SELECT * FROM nodes WHERE id = ?", @(nodeID)];
    if (!results) {
        MRCAssignError(error, [NSError mrc_systemErrorWithReason:[_DB lastError]]);
        return nil;
    }
    if ([results next]) {
        return [MRCNode nodeFromFMResultSet:results error:error];
    } else {
        MRCAssignError(error, [NSError mrc_internalErrorWithFormat:@"Row with ID = %@ was not found.", @(nodeID)]);
        return nil;
    }
}

@end

#pragma mark - MRCNodeSQLDBCursor

@implementation MRCNodeSQLDBCursor
@dynamic count;

- (id)init {
    MRCThrowDeadlySelectorInvokation(_cmd, @selector(nodeCursorWithNodeDB:directoryNode:childrenIDs:sortType:));
}

- (id)initWithNodeDB:(MRCNodeSQLDB *)DB
       directoryNode:(MRCDirectoryNode *)directoryNode
         childrenIDs:(NSArray *)childrenIDs
            sortType:(MRCNodeDBCursorSortType)sortType {
    NSParameterAssert(DB);
    NSParameterAssert(directoryNode);
    if (self = [super init]) {
        _DB = DB;
        _directoryNode = directoryNode;
        _childrenIDs = childrenIDs;
        _sortType = sortType;
    }
    return self;
}

- (NSUInteger)count {
    return [_childrenIDs count];
}

+ (instancetype)nodeCursorWithNodeDB:(MRCNodeSQLDB *)DB
                       directoryNode:(MRCDirectoryNode *)directoryNode
                         childrenIDs:(NSArray *)childrenIDs
                            sortType:(MRCNodeDBCursorSortType)sortType {
    return [[MRCNodeSQLDBCursor alloc] initWithNodeDB:DB
                                        directoryNode:directoryNode
                                          childrenIDs:childrenIDs
                                             sortType:sortType];
}

- (MRCNode *)fetchNodeAtIndex:(NSUInteger)index error:(NSError **)error {
    NSParameterAssert(index < [_childrenIDs count]);
    if (!([_childrenIDs count])) {
        @throw [NSException exceptionWithName:NSInternalInconsistencyException
                                       reason:[NSString stringWithFormat:@"Invalid node index %@, whild only %@ chldren available.", @(index), @([_childrenIDs count])]
                                     userInfo:nil];
    }
    return [_DB p_fetchNodeWithID:[_childrenIDs[index] intValue] error:error];
}

@end
