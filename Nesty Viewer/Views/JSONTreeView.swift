import SwiftUI

struct JSONTreeView: View {
    @ObservedObject var node: JSONNode
    let searchText: String
    let currentSearchResultIndex: Int
    let searchResults: [JSONNode]
    @State private var hoveredNodeId: UUID?
    @State private var debounceTimer: Timer?
    
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    JSONNodeRow(
                        node: node,
                        level: 0,
                        searchText: searchText,
                        hoveredNodeId: $hoveredNodeId,
                        currentSearchResultIndex: currentSearchResultIndex,
                        searchResults: searchResults,
                        scrollToNode: { nodeId in
                            proxy.scrollTo(nodeId, anchor: .center)
                        }
                    )
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
            .background(Color(NSColor.textBackgroundColor))
            .onChange(of: searchText) { _, newValue in
                debounceSearch(searchText: newValue)
            }
            .onAppear {
                updateSearchResults(searchText: searchText)
            }
        }
    }
    
    private func debounceSearch(searchText: String) {
        // Cancel previous timer
        debounceTimer?.invalidate()
        
        // If search is empty, clear immediately
        if searchText.isEmpty {
            updateSearchResults(searchText: searchText)
            return
        }
        
        // Set new timer for 300ms delay
        debounceTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { _ in
            DispatchQueue.main.async {
                self.updateSearchResults(searchText: searchText)
            }
        }
    }
    
    private func updateSearchResults(searchText: String) {
        if searchText.isEmpty {
            // Reset to default expansion state and free memory
            node.clearSearchResults()
            node.collapseAll()
            if node.key == "root" {
                node.isExpanded = true
            }
            // Free memory of collapsed nodes
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                node.unloadChildrenIfCollapsed()
            }
        } else if searchText.count >= 2 {
            // Only search for 2+ characters to avoid expensive single-character searches
            node.expandToShowSearchResults(searchText: searchText)
        } else {
            // Don't search for single characters - too expensive
            // Keep current state without expanding
        }
    }
}

struct JSONNodeRow: View {
    @ObservedObject var node: JSONNode
    let level: Int
    let searchText: String
    @Binding var hoveredNodeId: UUID?
    let currentSearchResultIndex: Int
    let searchResults: [JSONNode]
    let scrollToNode: (UUID) -> Void
    
    private var isHighlighted: Bool {
        !searchText.isEmpty && node.matches(searchText: searchText)
    }
    
    private var isCurrentSearchResult: Bool {
        guard !searchResults.isEmpty, currentSearchResultIndex < searchResults.count else { return false }
        return searchResults[currentSearchResultIndex].id == node.id
    }
    
    private var highlightColor: Color {
        if isCurrentSearchResult {
            return .blue.opacity(0.3) // Current result - blue highlight
        } else if isHighlighted {
            return .yellow.opacity(0.3) // Other matches - yellow highlight
        } else {
            return .clear
        }
    }
    
    private func scrollToCurrentResult() {
        if isCurrentSearchResult {
            withAnimation(.easeInOut(duration: 0.5)) {
                scrollToNode(node.id)
            }
        }
    }
    
    private var shouldShowNode: Bool {
        if searchText.isEmpty { return true }
        
        // Show if this node matches
        if node.matches(searchText: searchText) { return true }
        
        // For performance with large files, we'll show nodes that might have matching descendants
        // This is handled by the search expansion logic instead of checking all descendants
        return true
    }
    
    var body: some View {
        if shouldShowNode {
            VStack(alignment: .leading, spacing: 0) {
                // Current node
                HStack(spacing: 4) {
                    // Indentation
                    if level > 0 {
                        HStack(spacing: 0) {
                            ForEach(0..<level, id: \.self) { _ in
                                Rectangle()
                                    .fill(Color.secondary.opacity(0.2))
                                    .frame(width: 1)
                                    .padding(.trailing, 19)
                            }
                        }
                    }
                    
                    // Expand/collapse button
                    Group {
                        if node.hasChildren {
                            Button {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    node.isExpanded.toggle()
                                }
                            } label: {
                                Image(systemName: node.isExpanded ? "chevron.down" : "chevron.right")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.secondary)
                                    .frame(width: 12, height: 12)
                            }
                            .buttonStyle(.plain)
                        } else {
                            Spacer()
                                .frame(width: 12, height: 12)
                        }
                    }
                    
                    // Key
                    Text(node.displayKey)
                        .font(.system(.body, design: .monospaced))
                        .fontWeight(.medium)
                        .foregroundColor(getKeyColor())
                    
                    // Separator
                    if node.key != "root" {
                        Text(":")
                            .font(.system(.body, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                    
                    // Value
                    if let loadMoreNode = node as? LoadMoreNode {
                        HStack(spacing: 6) {
                            ProgressView()
                                .scaleEffect(0.6)
                                .foregroundColor(.blue)
                            Text("Loading more items...")
                                .font(.system(.body, design: .monospaced))
                                .foregroundColor(.blue)
                        }
                        .onAppear {
                            print("👁️ LoadMoreNode appeared: '\(loadMoreNode.key)'")
                            // Auto-load when this view appears (becomes visible)
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                withAnimation(.easeInOut(duration: 0.3)) {
                                    loadMoreNode.loadMore()
                                }
                            }
                        }
                    } else {
                        Text(node.displayValue)
                            .font(.system(.body, design: .monospaced))
                            .foregroundColor(getValueColor())
                            .lineLimit(1)
                    }
                    
                    Spacer()
                    
                    // Copy button (on hover)
                    if hoveredNodeId == node.id && !node.hasChildren {
                        Button {
                            copyValueToClipboard()
                        } label: {
                            Image(systemName: "doc.on.doc")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Copy value")
                    }
                }
                .padding(.vertical, 2)
                .padding(.trailing, 8)
                .background(
                    Rectangle()
                        .fill(getBackgroundColor())
                        .opacity(0.8)
                )
                .onHover { isHovering in
                    hoveredNodeId = isHovering ? node.id : nil
                }
                .contextMenu {
                    if !(node is LoadMoreNode) {
                        Button("Copy Key") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(node.key, forType: .string)
                        }
                        
                        if !node.hasChildren {
                            Button("Copy Value") {
                                copyValueToClipboard()
                            }
                        }
                        
                        Divider()
                        
                        if node.hasChildren {
                            Button(node.isExpanded ? "Collapse" : "Expand") {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    node.isExpanded.toggle()
                                }
                            }
                            
                            Button("Expand All") {
                                expandAllChildren()
                            }
                            
                            Button("Collapse All") {
                                node.collapseAll()
                            }
                        }
                    } else if node is LoadMoreNode {
                        Text("Loading automatically...")
                            .foregroundColor(.secondary)
                    }
                }
                
                // Children
                if node.isExpanded && node.hasChildren {
                    ForEach(node.children) { child in
                        JSONNodeRow(
                            node: child,
                            level: level + 1,
                            searchText: searchText,
                            hoveredNodeId: $hoveredNodeId,
                            currentSearchResultIndex: currentSearchResultIndex,
                            searchResults: searchResults,
                            scrollToNode: scrollToNode
                        )
                    }
                }
            }
            .id(node.id)
            .onChange(of: currentSearchResultIndex) { _, _ in
                scrollToCurrentResult()
            }
            .onAppear {
                scrollToCurrentResult()
            }
        }
    }
    
    private func getKeyColor() -> Color {
        if isHighlighted {
            return .primary
        }
        
        switch node.valueType {
        case .object:
            return .blue
        case .array:
            return .purple
        default:
            return .primary
        }
    }
    
    private func getValueColor() -> Color {
        if isHighlighted {
            return .primary
        }
        
        switch node.valueType {
        case .string:
            return .green
        case .number:
            return .orange
        case .bool:
            return .red
        case .null:
            return .secondary
        case .object, .array:
            return .secondary
        case .unknown:
            return .secondary
        }
    }
    
    private func getBackgroundColor() -> Color {
        if isCurrentSearchResult {
            return .blue.opacity(0.3) // Current result - blue highlight
        } else if isHighlighted {
            return .yellow.opacity(0.3) // Other matches - yellow highlight
        } else if hoveredNodeId == node.id {
            return Color.secondary.opacity(0.1)
        } else {
            return .clear
        }
    }
    
    private func copyValueToClipboard() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(node.copyableValue, forType: .string)
    }
    
    private func expandAllChildren() {
        func expandRecursively(_ node: JSONNode) {
            node.isExpanded = true
            for child in node.children {
                expandRecursively(child)
            }
        }
        
        withAnimation(.easeInOut(duration: 0.3)) {
            expandRecursively(node)
        }
    }
}

#Preview {
    let sampleJSON = """
    {
        "name": "John Doe",
        "age": 30,
        "isActive": true,
        "address": {
            "street": "123 Main St",
            "city": "New York",
            "zipCode": "10001"
        },
        "hobbies": ["reading", "swimming", "coding"],
        "spouse": null
    }
    """.data(using: .utf8)!
    
    let jsonObject = try! JSONSerialization.jsonObject(with: sampleJSON)
    let rootNode = JSONNode.create(from: jsonObject, key: "root")
    
    return JSONTreeView(
        node: rootNode, 
        searchText: "", 
        currentSearchResultIndex: 0, 
        searchResults: []
    )
}
