//
//  MRCNodeDBSchema.mm
//  MRCloudDB
//
//  Created by Pavel Osipov on 10.08.14.
//  Copyright (c) 2014 Mail.Ru Group. All rights reserved.
//

#import "MRCNodeDBSchema.h"
#import "NSError+MRCSDK.h"

#import <objc/runtime.h>
#import <algorithm>
#import <limits>

#define KEY_PREFIX_TABLE_RELATIONSHIPS "R~"
#define KEY_PREFIX_INDEX_NODES         "N~"
#define KEY_PREFIX_TABLE_NODES         "z~"

typedef MRCNodeDBTableNodesNameIndex::Key NameIndexKey;
typedef MRCNodeDBTableNodesNameIndex::PartitialKey NameIndexPartitialKey;

namespace aux {
    template<class T, class = typename std::enable_if<std::is_integral<T>::value>::type>
    int Compare(T lhs, T rhs) {
        if (lhs < rhs) return -1;
        if (lhs > rhs) return 1;
        return 0;
    }
    inline int CompareMTimeTypes(uint64_t lhs, uint64_t rhs) {
        if (lhs == 0 && rhs == 0) {
            return 0;
        }
        return lhs == 0 ? -1 : 1;
    }
    
    template<class T>
    inline int MaxValue(T t) {
        return std::numeric_limits<T>::max();
    }
}

MRCNodeDBTableNodes::Key::Key(node_id_t _nodeID)
    : prefix(KEY_PREFIX_TABLE_NODES)
    , nodeID(htonl(_nodeID))
{}

MRCNodeDBTableNodesNameIndex::PartitialKey::PartitialKey(node_id_t _parentID)
    : prefix(KEY_PREFIX_INDEX_NODES)
    , parentID(htonl(_parentID))
{}

MRCNodeDBTableNodesNameIndex::Key::Key(node_id_t _parentID, node_id_t _nodeID, NodeType::Value _type)
    : PartitialKey(_parentID)
    , nodeID(_nodeID)
    , mtime(0)
    , type(_type)
    , UTF8NameLength(0)
{}

int MRCNodeDBTableNodesNameIndex::Key::Compare(const MRCNodeDBTableNodesNameIndex::Key &other, CFLocaleRef locale) const {
    if (const int result = aux::Compare(ntohl(this->parentID), ntohl(other.parentID))) {
        return result;
    }
    if (const int result = aux::Compare(this->type, other.type)) {
        return result;
    }
    static CFOptionFlags kFinderCompareOptions =
        kCFCompareCaseInsensitive |
        kCFCompareNonliteral |
        kCFCompareLocalized |
        kCFCompareNumerically |
        kCFCompareWidthInsensitive |
        kCFCompareForcedOrdering;
    CFStringRef selfName = this->UTF8NameString();
    CFStringRef otherName = other.UTF8NameString();
    const int nameCompareResult = ::CFStringCompareWithOptionsAndLocale(
        selfName,
        otherName,
        CFRangeMake(0, CFStringGetLength(selfName)),
        kFinderCompareOptions,
        locale);
    CFRelease(selfName);
    CFRelease(otherName);
    return nameCompareResult;
}

CFStringRef MRCNodeDBTableNodesNameIndex::Key::UTF8NameString() const {
    return ::CFStringCreateWithBytesNoCopy(
        kCFAllocatorDefault,
        this->UTF8Name,
        this->UTF8NameLength,
        kCFStringEncodingUTF8,
        false,
        kCFAllocatorNull);
}

bool MRCNodeDBTableNodesNameIndex::Key::assignUTF8Name(NSString *name, NSError **error) {
    const char *UTF8Name = [name UTF8String];
    const size_t UTF8NameLength = std::strlen(UTF8Name);
    if (UTF8NameLength > aux::MaxValue(this->UTF8NameLength)) {
        MRCAssignError(error, [NSError mrc_internalErrorWithFormat:@"Name '%@' is too long", name]);
        return false;
    }
    memcpy(this->UTF8Name, UTF8Name, UTF8NameLength);
    this->UTF8NameLength = UTF8NameLength;
    return true;
}

MRCNodeDBTableRelationships::PartitialKey::PartitialKey(node_id_t parentID_)
    : prefix(KEY_PREFIX_TABLE_RELATIONSHIPS)
    , parentID(parentID_)
{}

MRCNodeDBTableRelationships::Key::Key(node_id_t parentID_, node_id_t nodeID_)
    : PartitialKey(parentID_)
    , nodeID(nodeID_)
{}

namespace cloud {

NodeDBComarator::NodeDBComarator(): _locale(CFLocaleGetSystem()) {
}
 
NodeDBComarator::~NodeDBComarator() {
    CFRelease(_locale);
}
    
CFLocaleRef NodeDBComarator::locale() const {
    return _locale;
}
    
const char* NodeDBComarator::Name() const {
    return "ru.mail.cloud.NodeDBComarator";
}

int NodeDBComarator::Compare(const leveldb::Slice& a, const leveldb::Slice& b) const {
    // Only index keys can not be compared with BytewiseComparator.
    if (a.starts_with(KEY_PREFIX_INDEX_NODES) && a.size() > sizeof(NameIndexPartitialKey) &&
        b.starts_with(KEY_PREFIX_INDEX_NODES) && b.size() > sizeof(NameIndexPartitialKey)) {
        const NameIndexKey *aKey = reinterpret_cast<const NameIndexKey *>(a.data());
        const NameIndexKey *bKey = reinterpret_cast<const NameIndexKey *>(b.data());
        return aKey->Compare(*bKey, _locale);
    } else {
        return leveldb::BytewiseComparator()->Compare(a, b);
    }
}

void NodeDBComarator::FindShortestSeparator(std::string* start, const leveldb::Slice& limit) const { }
void NodeDBComarator::FindShortSuccessor(std::string* key) const { }

}
