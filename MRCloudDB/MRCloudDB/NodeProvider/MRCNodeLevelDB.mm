//
//  MRCNodeDB.mm
//  MRCloudDB
//
//  Created by Osipov on 25.06.14.
//  Copyright (c) 2014 Pavel Osipov. All rights reserved.
//

#import "MRCNodeLevelDB.h"
#import "MRCNodeDBSchema.h"
#import "MRCErrorHandler.h"
#import "MRCNode+MRCNodeDB.h"
#import "NSError+MRCNodeDB.h"
#import "NSError+MRCSDK.h"
#import "MRCExceptions.h"

#import <objc/runtime.h>

#import <leveldb/db.h>
#import <leveldb/cache.h>
#import <leveldb/iterator.h>
#import <leveldb/write_batch.h>

#import <vector>

#import <CommonCrypto/CommonCrypto.h>

typedef MRCNodeDBTableNodesNameIndex::NodeType NodeType;
typedef MRCNodeDBTableNodesNameIndex::Key NodeNameIndexKey;

NSData *DataFromSlice(const leveldb::Slice &slice) {
    return [NSData dataWithBytesNoCopy:(void *)slice.data() length:slice.size() freeWhenDone:NO];
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

static void AddNameIndexKey(const NodeNameIndexKey &newKey, leveldb::WriteBatch &batchUpdates) {
    batchUpdates.Put(
        MRCMakeSlice(newKey),
        MRCMakeSlice(leveldb::Slice()));
    batchUpdates.Put(
        MRCMakeSlice(MRCNodeDBTableNodes::Key(newKey.nodeID)),
        MRCMakeSlice(newKey));
}

static void RemoveNameIndexKey(const NodeNameIndexKey &existingKey, leveldb::WriteBatch &batchUpdates) {
    batchUpdates.Delete(MRCMakeSlice(existingKey));
    batchUpdates.Delete(MRCMakeSlice(MRCNodeDBTableNodes::Key(existingKey.nodeID)));
}

static void UpdateNameIndexKey(const NodeNameIndexKey &existingKey, const NodeNameIndexKey &actualKey, leveldb::WriteBatch &batchUpdates) {
    if (leveldb::BytewiseComparator()->Compare(MRCMakeSlice(existingKey), MRCMakeSlice(actualKey)) == 0) {
        return;
    }
    RemoveNameIndexKey(existingKey, batchUpdates);
    AddNameIndexKey(actualKey, batchUpdates);
}

#pragma mark - MRCNodeLevelDBCursor

@interface MRCNodeLevelDBCursor ()

@property (nonatomic, strong) MRCNodeLevelDB *DB;
@property (nonatomic, strong) NSArray *childrenIDs;
@property (nonatomic, strong, readwrite) MRCDirectoryNode *directoryNode;

+ (instancetype)nodeCursorWithNodeDB:(MRCNodeLevelDB *)DB
                       directoryNode:(MRCDirectoryNode *)directoryNode
                         childrenIDs:(NSArray *)childrenIDs
                            sortType:(MRCNodeDBCursorSortType)sortType;

@end

#pragma mark - MRCNodeLevelDB

@interface MRCNodeLevelDB ()
@property (nonatomic, strong, readwrite) MRCDirectoryNode *rootDirectoryNode;
@end

@implementation MRCNodeLevelDB {
    std::unique_ptr<leveldb::DB> _DB;
    std::unique_ptr<cloud::NodeDBComarator> _DBComparator;
    node_id_t _nextNodeID;
}

- (id)init {
    MRCThrowDeadlySelectorInvokation(_cmd, @selector(nodeDBWithPath:error:));
}

- (id)initWithDBValue:(NSValue *)DBValue DBComparatorValue:(NSValue *)DBComparatorValue {
    NSParameterAssert([DBValue pointerValue]);
    NSParameterAssert([DBComparatorValue pointerValue]);
    if (self = [super init]) {
        _DB.reset(reinterpret_cast<leveldb::DB *>([DBValue pointerValue]));
        _DBComparator.reset(reinterpret_cast<cloud::NodeDBComarator *>([DBComparatorValue pointerValue]));
        _nextNodeID = [self p_fetchMaxNodeID];
    }
    return self;
}

+ (instancetype)nodeDBWithPath:(NSString *)path error:(NSError **)error {
    NSError *destroyReason = nil;
    while (YES) {
        MRCNodeLevelDB *nodeDB = [MRCNodeLevelDB nodeDBOpenAtPath:path destroyReason:destroyReason error:error];
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
            if (rootNodeError.code != MRCNodeDBErrorCodeNotFound) {
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
    std::unique_ptr<cloud::NodeDBComarator> comparator(new cloud::NodeDBComarator());
    leveldb::Options options;
    leveldb::DB *DB = nullptr;
    options.create_if_missing = true;
    options.max_open_files = 0;
    options.comparator = comparator.get();
    NSError *currentDestroyReason = destroyReason;
    BOOL shouldTryRepairBeforeDestruction = YES;
    const char * const dbname = [path UTF8String];
    while (YES) {
        if (currentDestroyReason) {
            NSLog(@"[WARNING] Destroying DB with reason \"%@\"...", currentDestroyReason);
            const leveldb::Status status = leveldb::DestroyDB(dbname, options);
            if (!status.ok()) {
                MRCAssignError(error, [NSError mrc_internalErrorWithFormat:@"Failed to destroy database: %@."]);
                return nil;
            }
        }
        const leveldb::Status status = leveldb::DB::Open(options, dbname, &DB);
        if (status.ok()) {
            if (DB == nullptr) {
                MRCAssignError(error, [NSError mrc_internalErrorWithFormat:@"Unexpected DB null pointer after successful opening."]);
                return nil;
            }
            return [[MRCNodeLevelDB alloc] initWithDBValue:[NSValue valueWithPointer:DB]
                                         DBComparatorValue:[NSValue valueWithPointer:comparator.release()]];
        } else if ((status.IsCorruption() || status.IsIOError()) && !currentDestroyReason) {
            if (shouldTryRepairBeforeDestruction && leveldb::RepairDB(dbname, options).ok()) {
                NSLog(@"[INFO] DB repaired.");
                shouldTryRepairBeforeDestruction = NO;
            } else {
                currentDestroyReason = NodeDBErrorFromStatus(status);
            }
            continue;
        } else {
            MRCAssignError(error, NodeDBErrorFromStatus(status));
            return nil;
        }
    }
}


- (void)setRootDirectoryNode:(MRCDirectoryNode *)rootDirectoryNode {
    NSParameterAssert(rootDirectoryNode);
    _rootDirectoryNode = rootDirectoryNode;
}

- (MRCNodeLevelDBCursor *)cursorForDirectory:(MRCDirectoryNode *)directoryNode
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
    return [MRCNodeLevelDBCursor nodeCursorWithNodeDB:self
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
    return [self p_replaceNodesInDirectoryWithID:[targetDirectory.ID intValue] withNodes:sourceNodes error:error];
}

- (BOOL)p_replaceNodesInDirectoryWithID:(node_id_t)targetDirectoryID
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
            NodeNameIndexKey(targetDirectoryID, MRCNodeDBInvalidID, NodeTypeFromNode(node)),
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
        return lhs.key.Compare(rhs.key, _DBComparator->locale()) < 0;
    });
    __block auto insertingValueIterator = insertingValues.begin();
    __block leveldb::WriteBatch batchUpdates;
    __block NSError *insertingError = nil;
    [self p_enumerateNodeNameIndexKeysWithParentID:targetDirectoryID usingBlock:^(const NodeNameIndexKey &existingKey, BOOL *stop) {
        while (insertingValueIterator != insertingValues.end()) {
            int comparisionResult = insertingValueIterator->key.Compare(existingKey, _DBComparator->locale());
            if (comparisionResult < 0) {
//                NSLog(@"+ %@", insertingValueIterator->node);
                insertingValueIterator->key.nodeID = _nextNodeID++;
                insertingValueIterator->node.ID = @(insertingValueIterator->key.nodeID);
                if ([insertingValueIterator->node isDirectory] &&
                    [((MRCDirectoryNode *)insertingValueIterator->node).children count] > 0) {
                    MRCDirectoryNode *directory = (id)insertingValueIterator->node;
                    if (![self p_addNode:directory intoDirectoryWithID:targetDirectoryID writeBatch:batchUpdates error:&insertingError]) {
                        *stop = YES;
                        return;
                    }
                } else {
                    AddNameIndexKey(insertingValueIterator->key, batchUpdates);
                }
                ++insertingValueIterator;
            } else if (comparisionResult == 0) {
//                NSLog(@"= %@", insertingValueIterator->node);
                insertingValueIterator->key.nodeID = existingKey.nodeID;
                insertingValueIterator->node.ID = @(insertingValueIterator->key.nodeID);
                UpdateNameIndexKey(existingKey, insertingValueIterator->key, batchUpdates);
                if ([insertingValueIterator->node isDirectory]) {
                    MRCDirectoryNode *directory = (id)insertingValueIterator->node;
                    if (directory.children != nil) {
                        if (![self p_replaceNodesInDirectoryWithID:existingKey.nodeID
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
                [self p_removeNodeWithKey:existingKey writeBatch:batchUpdates];
                break;
            }
        }
        if (insertingValueIterator == insertingValues.end()) {
//            NSLog(@"- %@", (__bridge NSString *)existingKey.UTF8NameString());
            [self p_removeNodeWithKey:existingKey writeBatch:batchUpdates];
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
            if (![self p_addNode:directory intoDirectoryWithID:targetDirectoryID writeBatch:batchUpdates error:error]) {
                return NO;
            }
        } else {
            AddNameIndexKey(insertingValueIterator->key, batchUpdates);
        }
        ++insertingValueIterator;
    }
    const leveldb::Status status = _DB->Write(leveldb::WriteOptions(), &batchUpdates);
    if (!status.ok()) {
        MRCAssignError(error, [NSError mrc_internalErrorWithFormat:@"Failed to destroy database: %@."]);
        return NO;
    }
    return YES;
}

#pragma mark - Private

- (node_id_t)p_fetchMaxNodeID {
    return MRCNodeDBTableNodes::kRootDirectoryNodeID;
}

- (MRCNode *)p_fetchNodeWithID:(node_id_t)nodeID error:(NSError **)error {
    std::string nodeBytes;
    leveldb::ReadOptions options;
    options.fill_cache = false;
    const leveldb::Status status = _DB->Get(options, MRCMakeSlice(MRCNodeDBTableNodes::Key(nodeID)), &nodeBytes);
    if (!status.ok()) {
        MRCAssignError(error, NodeDBErrorFromStatus(status));
        return nil;
    }
    MRCNode *node = NodeFromNameIndexKey(reinterpret_cast<const NodeNameIndexKey *>(nodeBytes.data()));
    node.ID = @(nodeID);
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

- (NSArray *)p_sortNodeIDs:(NSArray *)nodeIDs withNodeComparator:(NSComparator)comparator error:(NSError **)error {
    NSMutableArray *nodes = [NSMutableArray new];
    for (NSNumber *nodeID in nodeIDs) {
        MRCNode *node = [self p_fetchNodeWithID:[nodeID intValue] error:error];
        if (!node) {
            return nil;
        }
        [nodes addObject:node];
    }
    NSMutableArray *sortedNodeIDs = [NSMutableArray new];
    [nodes sortUsingComparator:comparator];
    for (MRCNode *node in nodes) {
        [sortedNodeIDs addObject:node.ID];
    }
    return sortedNodeIDs;
}

- (void)p_enumerateNodeNameIndexKeysWithParentID:(node_id_t)ID usingBlock:(void (^)(const NodeNameIndexKey &key, BOOL *stop))block {
    leveldb::ReadOptions options;
    options.fill_cache = false;
    std::unique_ptr<leveldb::Iterator> keyIterator(_DB->NewIterator(options));
    const leveldb::Slice partitialKey(MRCMakeSlice(MRCNodeDBTableNodesNameIndex::PartitialKey(ID)));
    for (keyIterator->Seek(partitialKey);
         keyIterator->Valid() && keyIterator->key().starts_with(partitialKey);
         keyIterator->Next()) {
        BOOL stop = NO;
        block(*reinterpret_cast<const NodeNameIndexKey *>(keyIterator->key().data()), &stop);
        if (stop) {
            break;
        }
    }
}

- (void)p_removeNodeWithKey:(const NodeNameIndexKey &)key writeBatch:(leveldb::WriteBatch &)writeBatch {
    RemoveNameIndexKey(key, writeBatch);
    if (key.type == NodeType::Directory) {
        [self p_enumerateNodeNameIndexKeysWithParentID:key.nodeID usingBlock:^(const NodeNameIndexKey &key, BOOL *stop) {
            [self p_removeNodeWithKey:key writeBatch:writeBatch];
        }];
    }
}

- (BOOL)p_addNode:(MRCNode *)node intoDirectoryWithID:(node_id_t)parentDirectoryID error:(NSError **)error {
    leveldb::WriteBatch batchUpdates;
    if (![self p_addNode:node intoDirectoryWithID:parentDirectoryID writeBatch:batchUpdates error:error]) {
        return NO;
    }
    const leveldb::Status status = _DB->Write(leveldb::WriteOptions(), &batchUpdates);
    if (!status.ok()) {
        MRCAssignError(error, NodeDBErrorFromStatus(status));
        return NO;
    }
    return YES;
}

- (BOOL)p_addNode:(MRCNode *)node
intoDirectoryWithID:(node_id_t)parentDirectoryID
       writeBatch:(leveldb::WriteBatch &)batchUpdates
            error:(NSError **)error {
    NSParameterAssert(node);
    if (!node) {
        MRCAssignError(error, [NSError mrc_internalErrorWithFormat:@"Unexpected nil putting node."]);
        return NO;
    }
    __block NodeNameIndexKey nameIndexKey(parentDirectoryID, _nextNodeID, NodeTypeFromNode(node));
    if (!nameIndexKey.assignUTF8Name(node.name, error)) {
        return NO;
    }
    [node visitWithFileHandler:^(MRCFileNode *file) {
        nameIndexKey.mtime = file.mtime;
    } directoryHandler:nil];
    AddNameIndexKey(nameIndexKey, batchUpdates);
    node.ID = @(nameIndexKey.nodeID);
    ++_nextNodeID;
    if ([node isDirectory]) {
        MRCDirectoryNode *directory = (id)node;
        for (MRCNode *node in directory.children) {
            if (![self p_addNode:node intoDirectoryWithID:nameIndexKey.nodeID writeBatch:batchUpdates error:error]) {
                return NO;
            }
        }
    }
    return YES;
}

@end

#pragma mark - MRCNodeCursor implementation

@implementation MRCNodeLevelDBCursor
@dynamic count;

- (id)init {
    MRCThrowDeadlySelectorInvokation(_cmd, @selector(nodeCursorWithNodeDB:directoryNode:childrenIDs:sortType:));
}

- (id)initWithNodeDB:(MRCNodeLevelDB *)DB
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

+ (instancetype)nodeCursorWithNodeDB:(MRCNodeLevelDB *)DB
                       directoryNode:(MRCDirectoryNode *)directoryNode
                         childrenIDs:(NSArray *)childrenIDs
                            sortType:(MRCNodeDBCursorSortType)sortType {
    return [[MRCNodeLevelDBCursor alloc] initWithNodeDB:DB
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
