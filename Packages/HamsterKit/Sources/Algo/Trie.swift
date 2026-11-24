//
//  Trie.swift
//
//
//  Created by morse on 2023/9/8.
//

import Foundation

public class TrieNode<Key: Hashable> {
  public var key: Key?
  public weak var parent: TrieNode?
  public var children: [Key: TrieNode] = [:]
  public var isTerminating = false

  public init(key: Key?, parent: TrieNode?) {
    self.key = key
    self.parent = parent
  }
}

/// Tire 算法
public class Trie<CollectionType: Collection> where CollectionType.Element: Hashable {
  public typealias Node = TrieNode<CollectionType.Element>
  
  private let root = Node(key: nil, parent: nil)
  
  public init() {}
  
  public func insert(_ collection: CollectionType) {
    var current = root
    for element in collection {
      if current.children[element] == nil {
        current.children[element] = Node(key: element, parent: current)
      }
      current = current.children[element]!
    }
    current.isTerminating = true
  }
  
  public func contains(_ collection: CollectionType) -> Bool {
    var current = root
    for element in collection {
      guard let child = current.children[element] else {
        return false
      }
      current = child
    }
    return current.isTerminating
  }

  /// 前缀匹配: collection 是已插入的某个 key 的前缀 (含自身就是 key 的情况)。
  /// 注意 contains() 要求整串是一个完整 key (isTerminating); 像 "782" 这样
  /// 只是 "7826" 的前缀、本身不是 key 的串, contains() 返回 false, 不能用它
  /// 判断“还能不能继续往下走”——否则九宫格边栏会丢掉 7826→quan/ruan/suan、
  /// 9826→xuan/yuan/zuan 这类长音节 (第 13 轮, 用户实测: 9826 边栏只有 xu)。
  public func hasPrefix(_ collection: CollectionType) -> Bool {
    var current = root
    for element in collection {
      guard let child = current.children[element] else {
        return false
      }
      current = child
    }
    return true
  }
  
  public func remove(_ collection: CollectionType) {
    var current = root
    for element in collection {
      guard let child = current.children[element] else {
        return
      }
      current = child
    }
    guard current.isTerminating else {
      return
    }
    current.isTerminating = false
    while let parent = current.parent, current.children.isEmpty && !current.isTerminating {
      parent.children[current.key!] = nil
      current = parent
    }
  }
}

public extension Trie where CollectionType: RangeReplaceableCollection {
  func collections(startingWith prefix: CollectionType) -> [CollectionType] {
    var current = root
    for element in prefix {
      guard let child = current.children[element] else {
        return []
      }
      current = child
    }
    return collections(startingWith: prefix, after: current)
  }
  
  private func collections(startingWith prefix: CollectionType, after node: Node) -> [CollectionType] {
    // 1
    var results: [CollectionType] = []
    
    if node.isTerminating {
      results.append(prefix)
    }
    
    // 2
    for child in node.children.values {
      var prefix = prefix
      prefix.append(child.key!)
      results.append(contentsOf: collections(startingWith: prefix, after: child))
    }
    
    return results
  }
}
