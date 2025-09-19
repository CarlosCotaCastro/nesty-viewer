import SwiftUI

struct SearchBar: View {
    @Binding var searchText: String
    @FocusState private var isSearchFocused: Bool
    
    let onPrevious: () -> Void
    let onNext: () -> Void
    let searchResultCount: Int
    let currentResultIndex: Int
    let isDebouncing: Bool
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
            
            TextField(searchText.count < 2 && !searchText.isEmpty ? "Enter at least 2 characters..." : "Search JSON content...", text: $searchText)
                .textFieldStyle(.plain)
                .focused($isSearchFocused)
            
            // Debouncing indicator
            if isDebouncing && !searchText.isEmpty && searchText.count >= 2 {
                ProgressView()
                    .scaleEffect(0.7)
                    .progressViewStyle(CircularProgressViewStyle())
            }
            
            if !searchText.isEmpty {
                // Search navigation buttons
                HStack(spacing: 4) {
                    Button {
                        onPrevious()
                    } label: {
                        Image(systemName: "chevron.up")
                            .foregroundColor(.secondary)
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .disabled(searchResultCount == 0)
                    
                    Button {
                        onNext()
                    } label: {
                        Image(systemName: "chevron.down")
                            .foregroundColor(.secondary)
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .disabled(searchResultCount == 0)
                    
                    // Search result counter
                    if searchResultCount > 0 {
                        Text("\(currentResultIndex + 1) of \(searchResultCount)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 4)
                    } else if searchText.count == 1 {
                        Text("Enter 2+ chars")
                            .font(.caption)
                            .foregroundColor(.orange)
                            .padding(.horizontal, 4)
                    }
                }
                
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(NSColor.textBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                )
        )
        .onSubmit {
            isSearchFocused = false
        }
    }
}

#Preview {
    @State var searchText = ""
    
    SearchBar(
        searchText: $searchText,
        onPrevious: {},
        onNext: {},
        searchResultCount: 0,
        currentResultIndex: 0,
        isDebouncing: false
    )
    .padding()
}
