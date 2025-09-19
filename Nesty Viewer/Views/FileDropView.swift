import SwiftUI
import UniformTypeIdentifiers

struct FileDropView: View {
    let onFileDrop: (URL) -> Void
    @State private var isDragOver = false
    
    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "doc.text")
                .font(.system(size: 64))
                .foregroundColor(.secondary)
            
            VStack(spacing: 8) {
                Text("Drop JSON File Here")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text("Or click to browse")
                    .font(.body)
                    .foregroundColor(.secondary)
            }
            
            Button("Browse Files") {
                openFilePanel()
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isDragOver ? Color.accentColor.opacity(0.1) : Color.clear)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(
                            isDragOver ? Color.accentColor : Color.secondary.opacity(0.3),
                            style: StrokeStyle(lineWidth: 2, dash: [8, 4])
                        )
                )
        )
        .padding(40)
        .onDrop(of: [.fileURL], isTargeted: $isDragOver) { providers in
            handleDrop(providers: providers)
        }
    }
    
    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, error in
            guard let data = item as? Data,
                  let url = URL(dataRepresentation: data, relativeTo: nil) else {
                return
            }
            
            DispatchQueue.main.async {
                if isJSONFile(url: url) {
                    onFileDrop(url)
                }
            }
        }
        
        return true
    }
    
    private func openFilePanel() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.json, .plainText]
        panel.title = "Select JSON File"
        
        if panel.runModal() == .OK, let url = panel.url {
            if isJSONFile(url: url) {
                onFileDrop(url)
            }
        }
    }
    
    private func isJSONFile(url: URL) -> Bool {
        let pathExtension = url.pathExtension.lowercased()
        return pathExtension == "json" || pathExtension == "txt"
    }
}

#Preview {
    FileDropView { url in
        print("File dropped: \(url)")
    }
}
