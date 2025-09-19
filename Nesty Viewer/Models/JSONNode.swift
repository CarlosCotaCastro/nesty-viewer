import Foundation

// MARK: - Memory-Efficient JSONNode for Large Files  
class JSONNode: ObservableObject, Identifiable {
    let id = UUID()
    let key: String
    private var rawValue: Any? // Weak reference that can be cleared
    private var _children: [JSONNode]? // Lazy-loaded children
    private let _childCount: Int // Cache count without loading all children
    private let _hasChildren: Bool // Quick check without parsing
    @Published var isExpanded: Bool = false
    @Published var isSearchResult: Bool = false // Track if this node is part of search results
    weak var parent: JSONNode?
    
    // Memory management
    private static let maxChildrenToKeepInMemory = 50 // Initial load limit
    private static let loadMoreBatchSize = 50 // How many more to load at once
    private static let maxVisibleItems = 200 // Maximum items to keep in memory
    private static let unloadDistance = 100 // Unload items this far from visible area
    private var lastAccessTime = Date()
    private var currentlyLoadedCount = 0 // Track how many children are currently loaded
    private var loadedRange: ClosedRange<Int> = 0...0 // Track which range is currently loaded
    private var visibleRange: ClosedRange<Int> = 0...0 // Track which range is currently visible
    
    init(key: String, rawValue: Any?, parent: JSONNode? = nil) {
        self.key = key
        self.rawValue = rawValue
        self.parent = parent
        
        // Pre-calculate ACTUAL child count (don't limit it here - that's for loading)
        switch rawValue {
        case let dict as [String: Any]:
            self._childCount = dict.count // Store ACTUAL count
            self._hasChildren = dict.count > 0
        case let array as [Any]:
            self._childCount = array.count // Store ACTUAL count
            self._hasChildren = array.count > 0
        default:
            self._childCount = 0
            self._hasChildren = false
        }
        
        // Be very conservative about auto-expansion
        if parent == nil {
            self.isExpanded = true
        } else if _childCount > 0 && _childCount <= 2 { // Even more conservative
            self.isExpanded = true
        }
    }
    
    // MARK: - Lazy Loading
    
    var children: [JSONNode] {
        if _children == nil && _childCount > 0 {
            loadChildren()
        }
        return _children ?? []
    }
    
    private func loadChildren() {
        guard _children == nil, let value = rawValue else { return }
        lastAccessTime = Date()
        
        // Start with initial batch
        loadMoreChildren(isInitialLoad: true)
    }
    
    func loadMoreChildren(isInitialLoad: Bool = false) {
        guard let value = rawValue else { 
            print("❌ loadMoreChildren: No rawValue for key '\(key)'")
            return 
        }
        lastAccessTime = Date()
        
        var existingChildren = _children ?? []
        var newChildren: [JSONNode] = []
        
        let startIndex = isInitialLoad ? 0 : currentlyLoadedCount
        let batchSize = isInitialLoad ? Self.maxChildrenToKeepInMemory : Self.loadMoreBatchSize
        let endIndex = min(startIndex + batchSize, _childCount)
        
        print("📥 loadMoreChildren: '\(key)' loading items \(startIndex)..<\(endIndex) of \(_childCount) total")
        
        switch value {
        case let dict as [String: Any]:
            let sortedKeys = dict.keys.sorted()
            let keysToLoad = Array(sortedKeys[startIndex..<endIndex])
            
            let newNodes = keysToLoad.map { key in
                JSONNode(key: key, rawValue: dict[key], parent: self)
            }
            
            if isInitialLoad {
                newChildren = newNodes
            } else {
                // Remove old "load more" button if it exists
                if let lastChild = existingChildren.last, lastChild is LoadMoreNode {
                    existingChildren.removeLast()
                }
                newChildren = existingChildren + newNodes
            }
            
        case let array as [Any]:
            let arraySlice = Array(array[startIndex..<endIndex])
            let newNodes = arraySlice.enumerated().map { offset, value in
                let actualIndex = startIndex + offset
                return JSONNode(key: "[\(actualIndex)]", rawValue: value, parent: self)
            }
            
            if isInitialLoad {
                newChildren = newNodes
            } else {
                // Remove old "load more" button if it exists
                if let lastChild = existingChildren.last, lastChild is LoadMoreNode {
                    existingChildren.removeLast()
                }
                newChildren = existingChildren + newNodes
            }
            
        default:
            break
        }
        
        currentlyLoadedCount = endIndex
        
        // Add "load more" indicator if there are more items
        if currentlyLoadedCount < _childCount {
            let remaining = _childCount - currentlyLoadedCount
            print("➕ Creating LoadMoreNode: \(currentlyLoadedCount)/\(_childCount) loaded, \(remaining) remaining")
            let loadMoreNode = LoadMoreNode(
                key: "⏳ Loading \(min(remaining, Self.loadMoreBatchSize)) more items... (\(remaining) remaining)",
                parent: self
            )
            newChildren.append(loadMoreNode)
        } else {
            print("✅ All items loaded: \(currentlyLoadedCount)/\(_childCount)")
        }
        
        _children = newChildren
        
        // Clear raw value after some time to save memory
        DispatchQueue.main.asyncAfter(deadline: .now() + 60) { // Increased time since we're loading progressively
            self.clearOldData()
        }
    }
    
    private func clearOldData() {
        // Clear raw value if not accessed recently and not expanded
        if !isExpanded && Date().timeIntervalSince(lastAccessTime) > 30 {
            rawValue = nil
        }
    }
    
    // MARK: - Display Properties
    
    var displayKey: String {
        if key == "root" {
            return "JSON Document"
        }
        return key
    }
    
    var displayValue: String {
        switch rawValue {
        case let string as String:
            // Truncate very long strings
            if string.count > 100 {
                let truncated = String(string.prefix(97))
                return "\"\(truncated)...\""
            }
            return "\"\(string)\""
        case let number as NSNumber:
            if CFBooleanGetTypeID() == CFGetTypeID(number) {
                return number.boolValue ? "true" : "false"
            } else {
                return "\(number)"
            }
        case is NSNull:
            return "null"
        case let dict as [String: Any]:
            return "{\(_childCount) \(_childCount == 1 ? "property" : "properties")}"
        case let array as [Any]:
            return "[\(_childCount) \(_childCount == 1 ? "item" : "items")]"
        default:
            return String(describing: rawValue ?? "null")
        }
    }
    
    var hasChildren: Bool {
        return _hasChildren
    }
    
    var valueType: JSONValueType {
        switch rawValue {
        case is String:
            return .string
        case let number as NSNumber:
            if CFBooleanGetTypeID() == CFGetTypeID(number) {
                return .bool
            } else {
                return .number
            }
        case is NSNull:
            return .null
        case is [String: Any]:
            return .object
        case is [Any]:
            return .array
        default:
            return .unknown
        }
    }
    
    // MARK: - Memory-Efficient Search
    
    func matches(searchText: String) -> Bool {
        guard !searchText.isEmpty else { return true }
        
        let lowercaseSearch = searchText.lowercased()
        
        // Check key
        if key.lowercased().contains(lowercaseSearch) {
            return true
        }
        
        // Check value efficiently
        switch rawValue {
        case let string as String:
            return string.lowercased().contains(lowercaseSearch)
        case let number as NSNumber:
            return "\(number)".contains(lowercaseSearch)
        default:
            return false
        }
    }
    
    func expandToShowSearchResults(searchText: String) -> Bool {
        guard !searchText.isEmpty else { return false }
        
        var hasMatch = false
        
        // Always check if this node matches first
        if matches(searchText: searchText) {
            isExpanded = true
            isSearchResult = true
            hasMatch = true
        }
        
        // Check if any direct children might match (without creating all nodes)
        var hasMatchingChild = false
        let lowercaseSearch = searchText.lowercased()
        
        switch rawValue {
        case let dict as [String: Any]:
            for (key, value) in dict {
                // Check key names
                if key.lowercased().contains(lowercaseSearch) {
                    hasMatchingChild = true
                    break
                }
                // Check string values
                if let stringValue = value as? String,
                   stringValue.lowercased().contains(lowercaseSearch) {
                    hasMatchingChild = true
                    break
                }
                // Check number values
                if let numberValue = value as? NSNumber,
                   "\(numberValue)".contains(lowercaseSearch) {
                    hasMatchingChild = true
                    break
                }
            }
        case let array as [Any]:
            for (index, value) in array.enumerated() {
                // Check array index notation
                if "[\(index)]".contains(lowercaseSearch) {
                    hasMatchingChild = true
                    break
                }
                // Check string values
                if let stringValue = value as? String,
                   stringValue.lowercased().contains(lowercaseSearch) {
                    hasMatchingChild = true
                    break
                }
                // Check number values
                if let numberValue = value as? NSNumber,
                   "\(numberValue)".contains(lowercaseSearch) {
                    hasMatchingChild = true
                    break
                }
            }
        default:
            break
        }
        
        if hasMatchingChild {
            isExpanded = true
            hasMatch = true
        }
        
        // Recursively check children and expand if they have matches
        for child in children {
            if child.expandToShowSearchResults(searchText: searchText) {
                isExpanded = true
                hasMatch = true
            }
        }
        
        return hasMatch
    }
    
    func clearSearchResults() {
        isSearchResult = false
        _children?.forEach { $0.clearSearchResults() }
    }
    
    // MARK: - Search Navigation
    
    func collectSearchResults(searchText: String) -> [JSONNode] {
        var results: [JSONNode] = []
        
        if matches(searchText: searchText) {
            results.append(self)
        }
        
        for child in children {
            results.append(contentsOf: child.collectSearchResults(searchText: searchText))
        }
        
        return results
    }
    
    func findNextSearchResult(currentNode: JSONNode, searchText: String) -> JSONNode? {
        let allResults = collectSearchResults(searchText: searchText)
        
        guard let currentIndex = allResults.firstIndex(where: { $0.id == currentNode.id }) else {
            return allResults.first
        }
        
        let nextIndex = (currentIndex + 1) % allResults.count
        return allResults[nextIndex]
    }
    
    func findPreviousSearchResult(currentNode: JSONNode, searchText: String) -> JSONNode? {
        let allResults = collectSearchResults(searchText: searchText)
        
        guard let currentIndex = allResults.firstIndex(where: { $0.id == currentNode.id }) else {
            return allResults.last
        }
        
        let previousIndex = currentIndex == 0 ? allResults.count - 1 : currentIndex - 1
        return allResults[previousIndex]
    }
    
    func scrollToSearchResult(_ node: JSONNode) {
        // Expand all parent nodes to make the result visible
        var currentNode = node.parent
        while let parent = currentNode {
            parent.isExpanded = true
            currentNode = parent.parent
        }
    }
    
    func collapseAll() {
        isExpanded = false
        isSearchResult = false
        // Only collapse loaded children to save memory
        _children?.forEach { $0.collapseAll() }
    }
    
    // MARK: - Memory Management
    
    func unloadChildrenIfCollapsed() {
        if !isExpanded && _children != nil {
            // Unload children to free memory when collapsed
            _children = nil
            loadedRange = 0...0
            currentlyLoadedCount = 0
        }
        
        // Recursively unload grandchildren
        _children?.forEach { $0.unloadChildrenIfCollapsed() }
    }
    
    // MARK: - Automatic Memory Cleanup
    
    func startMemoryCleanupTimer() {
        // Clean up memory every 10 seconds
        Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { _ in
            self.performMemoryCleanup()
        }
    }
    
    private func performMemoryCleanup() {
        guard let children = _children, children.count > Self.maxVisibleItems else { return }
        
        // Don't clean up if we're in the middle of a search
        // This prevents removing search results
        if isSearchActive() {
            print("🔍 Skipping memory cleanup - search active")
            return
        }
        
        // Keep only the most recently accessed items
        let itemsToKeep = min(Self.maxVisibleItems, children.count)
        let itemsToRemove = children.count - itemsToKeep
        
        if itemsToRemove > 0 {
            // Remove oldest items (assuming they're at the beginning)
            let itemsToKeep = Array(children.suffix(itemsToKeep))
            
            // Unload removed items
            for i in 0..<itemsToRemove {
                children[i].unloadChildrenIfCollapsed()
            }
            
            _children = itemsToKeep
            currentlyLoadedCount = itemsToKeep.count
            
            print("🧹 Memory cleanup: Removed \(itemsToRemove) items, kept \(itemsToKeep.count)")
        }
    }
    
    private func isSearchActive() -> Bool {
        // Check if this node or any child is a search result
        if isSearchResult {
            return true
        }
        
        // Check children recursively
        return _children?.contains { $0.isSearchResult } == true
    }
    
    // MARK: - Copy Support
    
    var copyableValue: String {
        switch rawValue {
        case let string as String:
            return string
        case let number as NSNumber:
            return "\(number)"
        case is NSNull:
            return "null"
        default:
            return displayValue
        }
    }
}

// MARK: - Value Type Enum

enum JSONValueType {
    case string
    case number
    case bool
    case null
    case object
    case array
    case unknown
}

// MARK: - Factory Method

extension JSONNode {
    static func create(from jsonObject: Any, key: String = "root") -> JSONNode {
        return JSONNode(key: key, rawValue: jsonObject, parent: nil)
    }
}

// MARK: - Load More Node

class LoadMoreNode: JSONNode {
    weak var parentNode: JSONNode?
    
    init(key: String, parent: JSONNode?) {
        self.parentNode = parent
        super.init(key: key, rawValue: nil, parent: parent)
    }
    
    override var displayValue: String {
        return "Auto-loading items..."
    }
    
    override var valueType: JSONValueType {
        return .unknown
    }
    
    override var hasChildren: Bool {
        return false
    }
    
    override var copyableValue: String {
        return ""
    }
    
    private var isLoading = false
    
    func loadMore() {
        guard !isLoading else { 
            print("⏭️ LoadMoreNode: Already loading, skipping")
            return 
        }
        isLoading = true
        
        print("🔄 LoadMoreNode: Loading more for parent '\(parentNode?.key ?? "unknown")'")
        parentNode?.loadMoreChildren(isInitialLoad: false)
        
        // Reset loading state after a short delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.isLoading = false
        }
    }
}