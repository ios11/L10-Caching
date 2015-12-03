//
//  MRCNodeLMDB.m
//  MRCloudDB
//
//  Created by Pavel Osipov on 31.08.15.
//  Copyright (c) 2015 Mail.Ru Group. All rights reserved.
//

#import "MRCNodeLMDB.h"
#import "MRCNode+MRCNodeDB.h"
#import "NSError+MRCSDK.h"
#import "MRCNodeDBSchema.h"

#import <POSRx/POSRx.h>
#import <vector>

typedef MRCNodeDBTableNodesNameIndex::NodeType NodeType;
typedef MRCNodeDBTableNodesNameIndex::Key NodeNameIndexKey;

namespace cloud {

static const NodeDBComarator* LMDBComparator() {
    static dispatch_once_t onceToken;
    static std::unique_ptr<NodeDBComarator> comparator;
    dispatch_once(&onceToken, ^{
        comparator.reset(new NodeDBComarator());
    });
    return comparator.get();
}
    
inline leveldb::Slice SliceFromMDBValue(const MDB_val *value) {
    return leveldb::Slice(reinterpret_cast<char *>(value->mv_data), value->mv_size);
}

inline NodeType::Value NodeTypeFromNode(MRCNode *node) {
    return [node isDirectory] ? NodeType::Directory : NodeType::File;
}

static MRCNode *NodeFromNameIndexKey(const NodeNameIndexKey *key) {
    MRCNode *node = nil;
    if (key->type == NodeType::File) {
        MRCFileNode *file = [MRCFileNode new];
        file.mtime = key->mtime;
        node = file;
    } else {
        MRCDirectoryNode *directory = [MRCDirectoryNode new];
        node = directory;
    }
    node.name = [[NSString alloc] initWithBytes:key->UTF8Name length:key->UTF8NameLength encoding:NSUTF8StringEncoding];
    return node;
}

static BOOL AddNameIndexKey(MDB_txn *txn, MDB_dbi dbi, const NodeNameIndexKey &newKey, NSError **error) {
    int rc;
    auto indexEntryKey = MRCMakeMDBVal(newKey);
    auto indexEntryValue = MRCMakeMDBEmptyVal();
    rc = mdb_put(txn, dbi, &indexEntryKey, &indexEntryValue, 0);
    if (rc != MDB_SUCCESS) {
        MRCAssignError(error, [NSError mrc_systemErrorWithFormat:@"Failed to insert record into the index: %d", rc]);
        return NO;
    }
    auto nodeTableEntryKey = MRCMakeMDBVal(MRCNodeDBTableNodes::Key(newKey.nodeID));
    rc = mdb_put(txn, dbi, &nodeTableEntryKey, &indexEntryKey, 0);
    if (rc != MDB_SUCCESS) {
        MRCAssignError(error, [NSError mrc_systemErrorWithFormat:@"Failed to insert record into the index: %d", rc]);
        return NO;
    }
    return YES;
}

static BOOL RemoveNameIndexKey(MDB_txn *txn, MDB_dbi dbi, const NodeNameIndexKey &existingKey, NSError **error) {
    int rc;
    auto indexEntryKey = MRCMakeMDBVal(existingKey);
    rc = mdb_del(txn, dbi, &indexEntryKey, NULL);
    if (rc != MDB_SUCCESS) {
        MRCAssignError(error, [NSError mrc_systemErrorWithFormat:@"Failed to remove record from the index: %d", rc]);
        return NO;
    }
    auto nodeTableEntryKey = MRCMakeMDBVal(MRCNodeDBTableNodes::Key(existingKey.nodeID));
    rc = mdb_del(txn, dbi, &nodeTableEntryKey, NULL);
    if (rc != MDB_SUCCESS) {
        MRCAssignError(error, [NSError mrc_systemErrorWithFormat:@"Failed to remove record from the index: %d", rc]);
        return NO;
    }
    return YES;
}

static BOOL UpdateNameIndexKey(
    MDB_txn *txn,
    MDB_dbi dbi,
    const NodeNameIndexKey &existingKey,
    const NodeNameIndexKey &actualKey,
    NSError **error) {
    if (leveldb::BytewiseComparator()->Compare(MRCMakeSlice(existingKey), MRCMakeSlice(actualKey)) == 0) {
        return YES;
    }
    return (RemoveNameIndexKey(txn, dbi, existingKey, error) &&
            AddNameIndexKey(txn, dbi, actualKey, error));
}

}

#pragma mark - MRCNodeLevelDBCursor

@interface MRCNodeLMDBCursor ()

@property (nonatomic, strong) MRCNodeLMDB *DB;
@property (nonatomic, strong) NSArray *childrenIDs;
@property (nonatomic, strong, readwrite) MRCDirectoryNode *directoryNode;

+ (instancetype)nodeCursorWithNodeDB:(MRCNodeLMDB *)DB
                       directoryNode:(MRCDirectoryNode *)directoryNode
                         childrenIDs:(NSArray *)childrenIDs
                            sortType:(MRCNodeDBCursorSortType)sortType;

@end

#pragma mark - MRCNodeLMDB

@interface MRCNodeLMDB ()
@property (nonatomic, assign) MDB_env *env;
@property (nonatomic, assign) MDB_dbi dbi;
@property (nonatomic, assign) node_id_t nextNodeID;
@end

@implementation MRCNodeLMDB

#pragma mark Lifecycle

- (instancetype)initWithPath:(NSString *)path {
    POSRX_CHECK(path);
    if (self = [super init]) {
        int rc;
        MDB_txn *txn;
        rc = mdb_env_create(&_env);
        POSRX_CHECK_EX(rc == MDB_SUCCESS, @"Failed to create env: %d", rc);
        rc = mdb_env_set_mapsize(_env, 1024 * 1024 * 500);
        POSRX_CHECK_EX(rc == MDB_SUCCESS, @"Failed to setup db size: %d", rc);
        rc = mdb_env_open(_env, [path UTF8String], MDB_NOTLS, 0664);
        POSRX_CHECK_EX(rc == MDB_SUCCESS, @"Failed to open env: %d", rc);
        rc = mdb_txn_begin(_env, NULL, MDB_RDONLY, &txn);
        POSRX_CHECK_EX(rc == MDB_SUCCESS, @"Failed to begin initial transaction: %d", rc);
        rc = mdb_dbi_open(txn, NULL, 0, &_dbi);
        POSRX_CHECK_EX(rc == MDB_SUCCESS, @"Failed to open DBI: %d", rc);
        rc = mdb_set_compare(txn, _dbi, [](const MDB_val *lhs, const MDB_val *rhs) {
            return cloud::LMDBComparator()->Compare(cloud::SliceFromMDBValue(lhs), cloud::SliceFromMDBValue(rhs));
        });
        POSRX_CHECK_EX(rc == MDB_SUCCESS, @"Failed to assign custom comparator: %d", rc);
        mdb_txn_abort(txn);
        _nextNodeID = [self p_fetchMaxNodeID];
    }
    return self;
}

+ (instancetype)nodeDBWithPath:(NSString *)path error:(NSError **)error {
    NSError *destroyReason = nil;
    BOOL isDirectory = NO;
    if (![[NSFileManager defaultManager] fileExistsAtPath:path isDirectory:&isDirectory]) {
        if (![[NSFileManager defaultManager] createDirectoryAtPath:path
                                       withIntermediateDirectories:NO
                                                        attributes:nil
                                                             error:error]) {
            return nil;
        }
    }
    while (YES) {
        MRCNodeLMDB *nodeDB = [MRCNodeLMDB nodeDBOpenAtPath:path destroyReason:destroyReason error:error];
        if (!nodeDB) {
            return nil;
        }
        NSError *rootNodeError = nil;
        MRCNode *rootNode = [nodeDB p_fetchNodeWithID:MRCNodeDBTableNodes::kRootDirectoryNodeID error:&rootNodeError];
        if (!rootNode) {
            if (destroyReason) {
                MRCAssignError(error, rootNodeError);
                return nil;
            }
            if (rootNodeError) {
                destroyReason = rootNodeError;
                continue;
            }
            rootNode = [MRCDirectoryNode rootDirectory];
            rootNode.ID = @(MRCNodeDBTableNodes::kRootDirectoryNodeID);
            if (![nodeDB p_addNode:rootNode intoDirectoryWithID:MRCNodeDBTableNodes::kRootDirectoryNodeParentNodeID error:error]) {
                return nil;
            }
        } else if (![rootNode isKindOfClass:[MRCDirectoryNode class]]) {
            destroyReason = [NSError mrc_internalErrorWithFormat:@"Unexpected root directory %@.", rootNode];
            continue;
        }
        nodeDB.rootDirectoryNode = (id)rootNode;
        return nodeDB;
    }
}

+ (instancetype)nodeDBOpenAtPath:(NSString *)path
                   destroyReason:(NSError *)destroyReason
                           error:(NSError **)error {
    @try {
        POSRX_CHECK(destroyReason == nil); // TODO: handle destroyReason
        return [[self alloc] initWithPath:path];
    } @catch (NSException *exception) {
        MRCAssignError(error, [NSError mrc_internalErrorWithFormat:exception.reason]);
        return nil;
    }
}

- (void)setRootDirectoryNode:(MRCDirectoryNode *)rootDirectoryNode {
    NSParameterAssert(rootDirectoryNode);
    _rootDirectoryNode = rootDirectoryNode;
}

- (void)dealloc {
    mdb_dbi_close(_env, _dbi);
    mdb_env_close(_env);
}

#pragma mark MRCNodeDB

- (MRCNodeLMDBCursor *)cursorForDirectory:(MRCDirectoryNode *)directoryNode
                                 sortType:(MRCNodeDBCursorSortType)sortType
                                    error:(NSError **)error {
    NSParameterAssert(directoryNode);
    if (!directoryNode) {
        MRCAssignError(error, [NSError mrc_internalErrorWithFormat:@"Unexpected nil directory node."]);
        return nil;
    }
    NSParameterAssert(directoryNode.ID);
    if (!directoryNode.ID) {
        MRCAssignError(error, [NSError mrc_internalErrorWithFormat:@"Unexpected attempt to get cursor for non persistent directory %@", directoryNode]);
        return nil;
    }
    NSArray *childrenIDs = [self p_fetchChildrenWithParentID:[directoryNode.ID intValue]
                                                    sortType:sortType
                                                       error:error];
    if (!childrenIDs) {
        return nil;
    }
    return [MRCNodeLMDBCursor nodeCursorWithNodeDB:self
                                     directoryNode:directoryNode
                                       childrenIDs:childrenIDs
                                          sortType:sortType];
}

- (BOOL)replaceNodesInDirectory:(MRCDirectoryNode *)targetDirectory
                      withNodes:(NSArray *)sourceNodes
                          error:(NSError **)error {
    NSParameterAssert(targetDirectory.ID);
    if (!targetDirectory.ID) {
        MRCAssignError(error, [NSError mrc_internalErrorWithFormat:@"Target directory %@ has no ID.", targetDirectory]);
        return NO;
    }
    int rc;
    MDB_txn *txn;
    rc = mdb_txn_begin(_env, NULL, 0, &txn);
    if (rc != MDB_SUCCESS) {
        MRCAssignError(error, [NSError mrc_internalErrorWithFormat:@"Failed to begin write transaction: %d", rc]);
        return NO;
    }
    BOOL replaced = [self p_replaceNodesInDirectoryWithID:[targetDirectory.ID intValue] transaction:txn withNodes:sourceNodes error:error];
    if (!replaced) {
        mdb_txn_abort(txn);
        return NO;
    }
    rc = mdb_txn_commit(txn);
    if (rc != MDB_SUCCESS) {
        MRCAssignError(error, [NSError mrc_internalErrorWithFormat:@"Failed to commit write transaction: %d", rc]);
        return NO;
    }
    return YES;
}

#pragma mark Private

- (BOOL)p_replaceNodesInDirectoryWithID:(node_id_t)targetDirectoryID
                            transaction:(MDB_txn *)txn
                              withNodes:(NSArray *)sourceNodes
                                  error:(NSError **)error {
    typedef struct {
        NodeNameIndexKey key;
        MRCNode *node;
    } InsertingValue;
    __block std::vector<InsertingValue> insertingValues;
    insertingValues.reserve([sourceNodes count]);
    for (MRCNode *node in sourceNodes) {
        __block InsertingValue insertingValue = {
            NodeNameIndexKey(targetDirectoryID, MRCNodeDBInvalidID, cloud::NodeTypeFromNode(node)),
            node
        };
        if (!insertingValue.key.assignUTF8Name(node.name, error)) {
            return NO;
        }
        [node visitWithFileHandler:^(MRCFileNode *file) {
            insertingValue.key.mtime = file.mtime;
        } directoryHandler:nil];
        insertingValues.push_back(insertingValue);
    }
    std::sort(insertingValues.begin(), insertingValues.end(), [&](const InsertingValue &lhs, const InsertingValue &rhs) {
        return lhs.key.Compare(rhs.key, cloud::LMDBComparator()->locale()) < 0;
    });
    __block auto insertingValueIterator = insertingValues.begin();
    __block NSError *insertingError = nil;
    [self p_enumerateNodeNameIndexKeysWithParentID:targetDirectoryID usingBlock:^(const NodeNameIndexKey &existingKey, BOOL *stop) {
        while (insertingValueIterator != insertingValues.end()) {
            int comparisionResult = insertingValueIterator->key.Compare(existingKey, cloud::LMDBComparator()->locale());
            if (comparisionResult < 0) {
//                NSLog(@"+ %@", insertingValueIterator->node);
                insertingValueIterator->key.nodeID = _nextNodeID++;
                insertingValueIterator->node.ID = @(insertingValueIterator->key.nodeID);
                if ([insertingValueIterator->node isDirectory] &&
                    [((MRCDirectoryNode *)insertingValueIterator->node).children count] > 0) {
                    MRCDirectoryNode *directory = (id)insertingValueIterator->node;
                    if (![self p_addNode:directory intoDirectoryWithID:targetDirectoryID transaction:txn error:&insertingError]) {
                        *stop = YES;
                        return;
                    }
                } else {
                    if (!cloud::AddNameIndexKey(txn, _dbi, insertingValueIterator->key, &insertingError)) {
                        *stop = YES;
                        return;
                    }
                }
                ++insertingValueIterator;
            } else if (comparisionResult == 0) {
//                NSLog(@"= %@", insertingValueIterator->node);
                insertingValueIterator->key.nodeID = existingKey.nodeID;
                insertingValueIterator->node.ID = @(insertingValueIterator->key.nodeID);
                if (!cloud::UpdateNameIndexKey(txn, _dbi, existingKey, insertingValueIterator->key, &insertingError)) {
                    *stop = YES;
                    return;
                }
                if ([insertingValueIterator->node isDirectory]) {
                    MRCDirectoryNode *directory = (id)insertingValueIterator->node;
                    if (directory.children != nil) {
                        if (![self p_replaceNodesInDirectoryWithID:existingKey.nodeID
                                                       transaction:txn
                                                         withNodes:directory.children
                                                             error:&insertingError]) {
                            *stop = YES;
                            return;
                        }
                    }
                }
                ++insertingValueIterator;
                return;
            } else {
//                NSLog(@"- %@", (__bridge NSString *)existingKey.UTF8NameString());
                if (![self p_removeNodeWithKey:existingKey transaction:txn error:&insertingError]) {
                    *stop = YES;
                    return;
                }
                break;
            }
        }
        if (insertingValueIterator == insertingValues.end()) {
//            NSLog(@"- %@", (__bridge NSString *)existingKey.UTF8NameString());
            if (![self p_removeNodeWithKey:existingKey transaction:txn error:&insertingError]) {
                *stop = YES;
                return;
            }
        }
    }];
    if (insertingError != nil) {
        MRCAssignError(error, insertingError);
        return NO;
    }
    while (insertingValueIterator != insertingValues.end()) {
//        NSLog(@"+ %@", insertingValueIterator->node);
        insertingValueIterator->key.nodeID = _nextNodeID++;
        insertingValueIterator->node.ID = @(insertingValueIterator->key.nodeID);
        if ([insertingValueIterator->node isDirectory] && [((MRCDirectoryNode *)insertingValueIterator->node).children count] > 0) {
            MRCDirectoryNode *directory = (id)insertingValueIterator->node;
            if (![self p_addNode:directory intoDirectoryWithID:targetDirectoryID transaction:txn error:error]) {
                return NO;
            }
        } else {
            if (!cloud::AddNameIndexKey(txn, _dbi, insertingValueIterator->key, error)) {
                return NO;
            }
        }
        ++insertingValueIterator;
    }
    return YES;
}

#pragma mark Private

- (node_id_t)p_fetchMaxNodeID {
    return MRCNodeDBTableNodes::kRootDirectoryNodeID;
}

- (MRCNode *)p_fetchNodeWithID:(node_id_t)nodeID error:(NSError **)error {
    int rc;
    MDB_txn *txn;
    rc = mdb_txn_begin(_env, NULL, MDB_RDONLY, &txn);
    if (rc != MDB_SUCCESS) {
        MRCAssignError(error, [NSError mrc_internalErrorWithFormat:@"Failed to begin read transaction: %d", rc]);
        return nil;
    }
    MDB_val key = MRCMakeMDBVal(MRCNodeDBTableNodes::Key(nodeID));
    MDB_val value;
    MRCNode *node = nil;
    rc = mdb_get(txn, _dbi, &key, &value);
    if (rc == MDB_SUCCESS) {
        node = cloud::NodeFromNameIndexKey(reinterpret_cast<const NodeNameIndexKey *>(value.mv_data));
        node.ID = @(nodeID);
    } else if (rc != MDB_NOTFOUND) {
        MRCAssignError(error, [NSError mrc_internalErrorWithFormat:@"Failed to open cursor: %d", rc]);
    }
    mdb_txn_abort(txn);
    return node;
}

- (NSArray *)p_fetchChildrenWithParentID:(node_id_t)ID
                                sortType:(MRCNodeDBCursorSortType)sortType
                                   error:(NSError **)error {
    switch (sortType) {
        case MRCNodeDBCursorSortTypeUnsorted:
            return [self p_fetchChildrenWithParentID:ID];
        case MRCNodeDBCursorSortTypeByName:
            return [self p_fetchSortedByNameChildrenIDsForDirectoryNodeWithID:ID error:error];
    }
}

- (NSArray *)p_fetchChildrenWithParentID:(node_id_t)ID {
    NSMutableArray *IDs = [NSMutableArray new];
    [self p_enumerateNodeNameIndexKeysWithParentID:ID usingBlock:^(const NodeNameIndexKey &key, BOOL *stop) {
        [IDs addObject:@(key.nodeID)];
    }];
    return IDs;
}

- (NSArray *)p_fetchSortedByNameChildrenIDsForDirectoryNodeWithID:(node_id_t)ID error:(NSError **)error {
    return [self p_fetchChildrenWithParentID:ID];
}

- (void)p_enumerateNodeNameIndexKeysWithParentID:(node_id_t)ID usingBlock:(void (^)(const NodeNameIndexKey &key, BOOL *stop))block {
    int rc;
    MDB_txn *txn;
    MDB_val fullKey, data;
    MDB_cursor *cursor;
    rc = mdb_txn_begin(_env, NULL, MDB_RDONLY, &txn);
    POSRX_CHECK_EX(rc == MDB_SUCCESS, @"Failed to create transaction: %d", rc);
    rc = mdb_cursor_open(txn, _dbi, &cursor);
    POSRX_CHECK_EX(rc == MDB_SUCCESS, @"Failed to open cursor: %d", rc);
    BOOL nodesFound = NO;
    const MDB_val partitialKey(MRCMakeMDBVal(MRCNodeDBTableNodesNameIndex::PartitialKey(ID)));
    while ((rc = mdb_cursor_get(cursor, &fullKey, &data, MDB_NEXT)) == MDB_SUCCESS) {
        BOOL stop = NO;
        // Instead of nodesFound flag we can call some enumeration func and then break.
        if ((fullKey.mv_size >= partitialKey.mv_size) &&
            (memcmp(fullKey.mv_data, partitialKey.mv_data, partitialKey.mv_size) == 0)) {
            block(*reinterpret_cast<const NodeNameIndexKey *>(fullKey.mv_data), &stop);
            nodesFound = YES;
            continue;
        }
        if (stop || nodesFound) {
            break;
        }
    }
    mdb_cursor_close(cursor);
    mdb_txn_abort(txn);
}

- (BOOL)p_removeNodeWithKey:(const NodeNameIndexKey &)key
                transaction:(MDB_txn *)txn
                      error:(NSError **)error {
    if (!cloud::RemoveNameIndexKey(txn, _dbi, key, error)) {
        return NO;
    }
    if (key.type == NodeType::Directory) {
        [self p_enumerateNodeNameIndexKeysWithParentID:key.nodeID usingBlock:^(const NodeNameIndexKey &key, BOOL *stop) {
            [self p_removeNodeWithKey:key transaction:txn error:error];
        }];
    }
    return YES;
}

- (BOOL)p_addNode:(MRCNode *)node intoDirectoryWithID:(node_id_t)parentDirectoryID error:(NSError **)error {
    int rc;
    MDB_txn *txn;
    rc = mdb_txn_begin(_env, NULL, 0, &txn);
    if (rc != MDB_SUCCESS) {
        MRCAssignError(error, [NSError mrc_internalErrorWithFormat:@"Failed to begin write transaction: %d", rc]);
        return NO;
    }
    if (![self p_addNode:node intoDirectoryWithID:parentDirectoryID transaction:txn error:error]) {
        mdb_txn_abort(txn);
        return NO;
    }
    rc = mdb_txn_commit(txn);
    if (rc != MDB_SUCCESS) {
        MRCAssignError(error, [NSError mrc_internalErrorWithFormat:@"Failed to commit write transaction: %d", rc]);
        return NO;
    }
    return YES;
}

- (BOOL)p_addNode:(MRCNode *)node
intoDirectoryWithID:(node_id_t)parentDirectoryID
      transaction:(MDB_txn *)txn
            error:(NSError **)error {
    NSParameterAssert(node);
    if (!node) {
        MRCAssignError(error, [NSError mrc_internalErrorWithFormat:@"Unexpected nil putting node."]);
        return NO;
    }
    __block NodeNameIndexKey nameIndexKey(parentDirectoryID, _nextNodeID, cloud::NodeTypeFromNode(node));
    if (!nameIndexKey.assignUTF8Name(node.name, error)) {
        return NO;
    }
    [node visitWithFileHandler:^(MRCFileNode *file) {
        nameIndexKey.mtime = file.mtime;
    } directoryHandler:nil];
    if (!cloud::AddNameIndexKey(txn, _dbi, nameIndexKey, error)) {
        return NO;
    }
    node.ID = @(nameIndexKey.nodeID);
    ++_nextNodeID;
    if ([node isDirectory]) {
        MRCDirectoryNode *directory = (id)node;
        for (MRCNode *node in directory.children) {
            if (![self p_addNode:node intoDirectoryWithID:nameIndexKey.nodeID transaction:txn error:error]) {
                return NO;
            }
        }
    }
    return YES;
}

@end

@implementation MRCNodeLMDBCursor
@dynamic count;

- (id)initWithNodeDB:(MRCNodeLMDB *)DB
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

+ (instancetype)nodeCursorWithNodeDB:(MRCNodeLMDB *)DB
                       directoryNode:(MRCDirectoryNode *)directoryNode
                         childrenIDs:(NSArray *)childrenIDs
                            sortType:(MRCNodeDBCursorSortType)sortType {
    return [[MRCNodeLMDBCursor alloc] initWithNodeDB:DB
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
