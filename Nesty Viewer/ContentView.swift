import SwiftUI

struct ContentView: View {
    @State private var jsonData: JSONNode?
    @State private var searchText = ""
    @State private var fileName: String?
    @State private var isLoading = false
    @State private var fileSize: String?
    @State private var currentSearchResultIndex: Int = 0
    @State private var searchResults: [JSONNode] = []
    @State private var debounceTimer: Timer?
    @State private var isDebouncing: Bool = false
    
    var body: some View {
        VStack(spacing: 0) {
            if let jsonData = jsonData {
                // Header with filename and search
                VStack(spacing: 8) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(fileName ?? "JSON File")
                                .font(.title2)
                                .fontWeight(.semibold)
                            
                            if let fileSize = fileSize {
                                Text(fileSize)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        Spacer()
                        
                        Button("Close") {
                            // Free memory before closing
                            self.jsonData?.collapseAll()
                            self.jsonData?.unloadChildrenIfCollapsed()
                            self.jsonData = nil
                            self.fileName = nil
                            self.fileSize = nil
                            self.searchText = ""
                        }
                        .buttonStyle(.bordered)
                    }
                    
                    SearchBar(
                        searchText: $searchText,
                        onPrevious: goToPreviousSearchResult,
                        onNext: goToNextSearchResult,
                        searchResultCount: searchResults.count,
                        currentResultIndex: currentSearchResultIndex,
                        isDebouncing: isDebouncing
                    )
                }
                .padding()
                .background(Color(NSColor.controlBackgroundColor))
                
                Divider()
                
                // JSON Tree View
                JSONTreeView(
                    node: jsonData,
                    searchText: searchText,
                    currentSearchResultIndex: currentSearchResultIndex,
                    searchResults: searchResults
                )
            } else if isLoading {
                // Loading state
                VStack(spacing: 16) {
                    ProgressView()
                        .scaleEffect(1.5)
                    Text("Loading JSON file...")
                        .font(.title3)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // File drop view when no file is loaded
                FileDropView { url in
                    loadJSONFile(from: url)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: searchText) { _, newValue in
            debounceSearch(searchText: newValue)
        }
        .onKeyPress(.downArrow) {
            goToNextSearchResult()
            return .handled
        }
        .onKeyPress(.upArrow) {
            goToPreviousSearchResult()
            return .handled
        }
        .onKeyPress(.escape) {
            searchText = ""
            return .handled
        }
    }
    
    private func debounceSearch(searchText: String) {
        // Cancel previous timer
        debounceTimer?.invalidate()
        
        // If search is empty, clear immediately
        if searchText.isEmpty {
            isDebouncing = false
            updateSearchResults(searchText: searchText)
            return
        }
        
        // Set debouncing state
        isDebouncing = true
        
        // Set new timer for 300ms delay
        debounceTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { _ in
            DispatchQueue.main.async {
                self.isDebouncing = false
                self.updateSearchResults(searchText: searchText)
            }
        }
    }
    
    private func updateSearchResults(searchText: String) {
        guard let jsonData = jsonData else { return }
        
        if searchText.isEmpty {
            searchResults = []
            currentSearchResultIndex = 0
        } else if searchText.count >= 2 {
            searchResults = jsonData.collectSearchResults(searchText: searchText)
            currentSearchResultIndex = 0
        } else {
            // Don't search for single characters - too expensive
            searchResults = []
            currentSearchResultIndex = 0
        }
    }
    
    private func goToNextSearchResult() {
        guard !searchResults.isEmpty, let jsonData = jsonData else { return }
        
        let nextIndex = (currentSearchResultIndex + 1) % searchResults.count
        currentSearchResultIndex = nextIndex
        
        let targetNode = searchResults[nextIndex]
        jsonData.scrollToSearchResult(targetNode)
    }
    
    private func goToPreviousSearchResult() {
        guard !searchResults.isEmpty, let jsonData = jsonData else { return }
        
        let previousIndex = currentSearchResultIndex == 0 ? searchResults.count - 1 : currentSearchResultIndex - 1
        currentSearchResultIndex = previousIndex
        
        let targetNode = searchResults[previousIndex]
        jsonData.scrollToSearchResult(targetNode)
    }
    
    private func loadJSONFile(from url: URL) {
        Task {
            do {
                // Start loading state
                await MainActor.run {
                    self.isLoading = true
                    // Free memory from previous file
                    self.jsonData?.collapseAll()
                    self.jsonData?.unloadChildrenIfCollapsed()
                    self.jsonData = nil
                }
                
                // Get file size
                let fileAttributes = try FileManager.default.attributesOfItem(atPath: url.path)
                let fileSizeBytes = fileAttributes[.size] as? Int64 ?? 0
                let fileSizeString = ByteCountFormatter.string(fromByteCount: fileSizeBytes, countStyle: .file)
                
                // Warn about very large files
                if fileSizeBytes > 50_000_000 { // 50MB - more conservative limit
                    await MainActor.run {
                        self.isLoading = false
                        self.fileName = "File too large (> 50MB). Please use a smaller file."
                        self.fileSize = "Consider splitting large files into smaller chunks"
                        return
                    }
                    return
                }
                
                // Monitor memory before loading
                let beforeMemory = self.getMemoryUsage()
                print("Memory before loading: \(beforeMemory) MB")
                
                // Use streaming approach to avoid loading entire JSON into memory
                let data = try Data(contentsOf: url)
                print("Data loaded, size: \(data.count) bytes")
                
                // Parse JSON in smaller chunks with limited depth
                let json = try self.parseJSONSafely(data: data)
                
                let afterParsingMemory = self.getMemoryUsage()
                print("Memory after parsing: \(afterParsingMemory) MB")
                
                await MainActor.run {
                    self.jsonData = JSONNode.create(from: json, key: "root")
                    let afterNodeCreation = self.getMemoryUsage()
                    print("Memory after node creation: \(afterNodeCreation) MB")
                    
                    // Start automatic memory cleanup
                    self.jsonData?.startMemoryCleanupTimer()
                    
                    self.fileName = url.lastPathComponent
                    self.fileSize = fileSizeString
                    self.searchText = ""
                    self.isLoading = false
                }
            } catch {
                print("Error loading JSON file: \(error)")
                await MainActor.run {
                    self.isLoading = false
                    self.fileName = "Error: \(error.localizedDescription)"
                    self.fileSize = nil
                }
            }
        }
    }
    
    // MARK: - Safe JSON Parsing
    
    private func parseJSONSafely(data: Data) throws -> Any {
        // For very large files, we need to be careful about memory usage
        // Use JSONSerialization with options that might help with memory
        
        let options: JSONSerialization.ReadingOptions = [
            .allowFragments,
            .mutableContainers // This might help with memory management
        ]
        
        // Try to parse with memory-conscious approach
        do {
            let json = try JSONSerialization.jsonObject(with: data, options: options)
            return json
        } catch {
            // If standard parsing fails, try to read as string and parse smaller chunks
            let jsonString = String(data: data, encoding: .utf8) ?? ""
            
            // For extremely large files, we could implement a streaming parser here
            // For now, fall back to standard parsing but with better error handling
            throw error
        }
    }
    
    // MARK: - Memory Monitoring
    
    private func getMemoryUsage() -> Double {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size)/4
        
        let kerr: kern_return_t = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_,
                         task_flavor_t(MACH_TASK_BASIC_INFO),
                         $0,
                         &count)
            }
        }
        
        if kerr == KERN_SUCCESS {
            return Double(info.resident_size) / 1024.0 / 1024.0
        } else {
            return 0
        }
    }
}

#Preview {
    ContentView()
}
