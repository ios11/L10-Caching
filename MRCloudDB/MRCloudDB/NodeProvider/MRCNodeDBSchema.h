//
//  MRCNodeDBSchema.h
//  MRCloudDB
//
//  Created by Pavel Osipov on 10.08.14.
//  Copyright (c) 2014 Mail.Ru Group. All rights reserved.
//

#pragma once

#import <leveldb/comparator.h>
#import <leveldb/db.h>
#import <lmdb/lmdb.h>
#import "MRCNode.h"

#pragma mark - Table Descriptions

typedef uint32_t node_id_t;
enum {MRCNodeDBInvalidID = std::numeric_limits<node_id_t>::max()};

typedef struct MRCNodeDBTableNodes {
    static const node_id_t kRootDirectoryNodeID           = 1;
    static const node_id_t kRootDirectoryNodeParentNodeID = 0;
    typedef struct Key {
        char prefix[4];
        node_id_t nodeID;
        explicit Key(node_id_t nodeID);
        explicit Key(MRCNode *node);
    } Key;
} MRCNodeDBTableNodes;

typedef struct MRCNodeDBTableNodesNameIndex {
    typedef struct NodeType {
        enum Value {
            Directory = 0,
            File      = 1
        };
    } NodeType;
    typedef struct PartitialKey {
        char prefix[4];
        node_id_t parentID;
        explicit PartitialKey(node_id_t parentID);
    } PartitialKey;
    typedef struct Key : PartitialKey {
        node_id_t nodeID;
        uint64_t mtime;
        uint8_t type;
        uint8_t UTF8NameLength;
        unsigned char UTF8Name[UINT8_MAX];
        Key(node_id_t parentID, node_id_t nodeID, NodeType::Value type);
        int Compare(const Key &other, CFLocaleRef locale) const;
        CFStringRef UTF8NameString() const;
        bool assignUTF8Name(NSString *name, NSError **error);
    } Key;
} MRCNodeDBTableNodesNameIndex;

typedef struct MRCNodeDBTableRelationships {
    typedef struct PartitialKey {
        char prefix[4];
        node_id_t parentID;
        explicit PartitialKey(node_id_t parentID);
    } PartitialKey;
    typedef struct Key : PartitialKey {
        node_id_t nodeID;
        Key(node_id_t parentID, node_id_t nodeID);
    } Key;
} MRCNodeDBTableRelationships;

#pragma mark - NodeDB Comparator

namespace cloud {
class NodeDBComarator : public leveldb::Comparator {
public:
    NodeDBComarator();
    ~NodeDBComarator();
    
    CFLocaleRef locale() const;
    
public: // leveldb::Comparator
    const char* Name() const override;
    int Compare(const leveldb::Slice& a, const leveldb::Slice& b) const override;
    void FindShortestSeparator(std::string* start, const leveldb::Slice& limit) const override;
    void FindShortSuccessor(std::string* key) const override;
    
private:
    CFLocaleRef _locale;
};
}

#pragma mark - Slice Builders

namespace aux {
template <typename T, typename R>
std::size_t offset_of(R T::*M) {
    return reinterpret_cast<std::size_t>(&(((T*)0)->*M));
}
}

inline leveldb::Slice MRCMakeSlice(NSData * const data) {
    return leveldb::Slice(reinterpret_cast<const char *>([data bytes]), [data length]);
}

inline MDB_val MRCMakeMDBVal(NSData * const data) {
    MDB_val value;
    value.mv_data = const_cast<void *>([data bytes]);
    value.mv_size = [data length];
    return value;
}

inline leveldb::Slice MRCMakeSlice(const MRCNodeDBTableNodesNameIndex::Key &key) {
    return leveldb::Slice(
        reinterpret_cast<const char *>(&key),
        aux::offset_of(&MRCNodeDBTableNodesNameIndex::Key::UTF8Name) + key.UTF8NameLength);
}

inline MDB_val MRCMakeMDBVal(const MRCNodeDBTableNodesNameIndex::Key &key) {
    MDB_val value;
    value.mv_data = const_cast<void *>(reinterpret_cast<const void *>(&key));
    value.mv_size = aux::offset_of(&MRCNodeDBTableNodesNameIndex::Key::UTF8Name) + key.UTF8NameLength;
    return value;
}

inline MDB_val MRCMakeMDBEmptyVal() {
    MDB_val value;
    value.mv_data = nil;
    value.mv_size = 0;
    return value;
}

template<class Key>
inline leveldb::Slice MRCMakeSlice(const Key &key) {
    return leveldb::Slice(reinterpret_cast<const char *>(&key), sizeof(key));
}

template<class Key>
inline MDB_val MRCMakeMDBVal(const Key &key) {
    MDB_val value;
    value.mv_data = const_cast<void *>(reinterpret_cast<const void *>(&key));
    value.mv_size = sizeof(key);
    return value;
}
