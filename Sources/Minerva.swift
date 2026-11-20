import SwiftUI
import NaturalLanguage

// MARK: - Models & Persistence

struct MinervaMessage: Identifiable, Codable, Equatable {
    let id: UUID
    let role: Role
    let text: String
    let timestamp: Date
    let metadataTag: String?

    enum Role: String, Codable {
        case user
        case minerva
        case system
    }

    init(id: UUID = UUID(), role: Role, text: String, timestamp: Date = Date(), metadataTag: String? = nil) {
        self.id = id
        self.role = role
        self.text = text
        self.timestamp = timestamp
        self.metadataTag = metadataTag
    }
}

struct KnowledgeNote: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String
    var body: String
    var tags: [String]
    let createdAt: Date

    init(id: UUID = UUID(), title: String, body: String, tags: [String] = ["Minerva"], createdAt: Date = Date()) {
        self.id = id
        self.title = title
        self.body = body
        self.tags = tags
        self.createdAt = createdAt
    }
}

struct NLAnalysisResult {
    let detectedLanguage: String
    let dominantToneScore: Double
    let entities: [String]
    let wordCount: Int
}

// MARK: - On-Device NLP & Optional Remote AI Engine

final class MinervaEngine {
    static let shared = MinervaEngine()
    private init() {}

    func analyze(text: String) -> NLAnalysisResult {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return NLAnalysisResult(detectedLanguage: "unknown", dominantToneScore: 0, entities: [], wordCount: 0)
        }

        let recognizer = NLLanguageRecognizer()
        recognizer.processString(trimmed)
        let langCode = recognizer.dominantLanguage?.rawValue ?? "und"

        let sentimentTagger = NLTagger(tagSchemes: [.sentimentScore])
        sentimentTagger.string = trimmed
        let (sentimentTag, _) = sentimentTagger.tag(at: trimmed.startIndex, unit: .paragraph, scheme: .sentimentScore)
        let score = Double(sentimentTag?.rawValue ?? "0") ?? 0

        var foundEntities: [String] = []
        let entityTagger = NLTagger(tagSchemes: [.nameType, .lexicalClass])
        entityTagger.string = trimmed
        let options: NLTagger.Options = [.omitPunctuation, .omitWhitespace, .joinNames]
        entityTagger.enumerateTags(in: trimmed.startIndex..<trimmed.endIndex, unit: .word, scheme: .nameType, options: options) { tag, tokenRange in
            if let tag = tag {
                let value = String(trimmed[tokenRange])
                foundEntities.append("\(value) (\(tag.rawValue.replacingOccurrences(of: "NLTag", with: "")))")
            }
            return true
        }

        let words = trimmed.split { $0.isWhitespace || $0.isNewline }
        return NLAnalysisResult(
            detectedLanguage: langCode,
            dominantToneScore: score,
            entities: Array(Set(foundEntities)).prefix(8).map { $0 },
            wordCount: words.count
        )
    }

    func generateReply(
        prompt: String,
        endpointURLString: String,
        apiKey: String,
        modelName: String
    ) async -> (reply: String, tag: String) {
        let analysis = analyze(text: prompt)

        if let url = URL(string: endpointURLString.trimmingCharacters(in: .whitespacesAndNewlines)),
           !endpointURLString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           url.scheme == "https" {
            do {
                let remoteText = try await callOpenAICompatibleAPI(
                    url: url,
                    apiKey: apiKey,
                    model: modelName.isEmpty ? "gpt-4o-mini" : modelName,
                    prompt: prompt
                )
                return (remoteText, "Cloud • \(modelName)")
            } catch {
                let localFallback = buildLocalMinervaResponse(for: prompt, analysis: analysis)
                return ("\(localFallback)\n\n*(Cloud fallback: \(error.localizedDescription))*", "On-Device NLP")
            }
        }

        return (buildLocalMinervaResponse(for: prompt, analysis: analysis), "On-Device NLP")
    }

    private func buildLocalMinervaResponse(for prompt: String, analysis: NLAnalysisResult) -> String {
        let lower = prompt.lowercased()
        var lines: [String] = []

        if lower.contains("plan") || lower.contains("steps") || lower.contains("how") {
            lines.append("**Structured Execution Breakdown:**")
            lines.append("1. Define the exact input, target output, and constraints.")
            lines.append("2. Build a minimal working baseline and verify edge cases.")
            lines.append("3. Refine performance, persistence, and error handling.")
        } else if lower.contains("summarize") || lower.contains("tldr") {
            let sentences = prompt
                .components(separatedBy: CharacterSet(charactersIn: ".!?"))
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            let lead = sentences.first ?? prompt
            lines.append("**Key Summary:** \(lead)")
        } else {
            lines.append("**Minerva Synthesis:** Processed \(analysis.wordCount) words (lang: `\(analysis.detectedLanguage)`).")
            if !analysis.entities.isEmpty {
                lines.append("**Detected Entities:** \(analysis.entities.joined(separator: ", "))")
            }
            lines.append("Tone index: `\(String(format: "%+.2f", analysis.dominantToneScore))` (-1.0 negative to +1.0 positive).")
        }

        return lines.joined(separator: "\n")
    }

    private func callOpenAICompatibleAPI(
        url: URL,
        apiKey: String,
        model: String,
        prompt: String
    ) async throws -> String {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 25
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            request.setValue("Bearer \(apiKey.trimmingCharacters(in: .whitespacesAndNewlines))", forHTTPHeaderField: "Authorization")
        }

        let payload: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": "You are Minerva, a concise, analytical iOS intelligence assistant."],
                ["role": "user", "content": prompt]
            ],
            "temperature": 0.4
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let first = choices.first,
              let message = first["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw URLError(.cannotParseResponse)
        }

        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

final class MinervaStore: ObservableObject {
    @Published var messages: [MinervaMessage] = [] {
        didSet { saveJSON(messages, to: messagesURL) }
    }
    @Published var notes: [KnowledgeNote] = [] {
        didSet { saveJSON(notes, to: notesURL) }
    }

    private let messagesURL: URL
    private let notesURL: URL

    init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        self.messagesURL = docs.appendingPathComponent("minerva_messages.json")
        self.notesURL = docs.appendingPathComponent("minerva_notes.json")
        loadInitialData()
    }

    private func loadInitialData() {
        if let loadedMessages: [MinervaMessage] = loadJSON(from: messagesURL), !loadedMessages.isEmpty {
            self.messages = loadedMessages
        } else {
            self.messages = [
                MinervaMessage(
                    role: .minerva,
                    text: "Minerva online. Ask a question, run on-device NLP diagnostics, or save structured notes.",
                    metadataTag: "System Ready"
                )
            ]
        }

        if let loadedNotes: [KnowledgeNote] = loadJSON(from: notesURL), !loadedNotes.isEmpty {
            self.notes = loadedNotes
        } else {
            self.notes = [
                KnowledgeNote(
                    title: "Architecture Note",
                    body: "Uses SwiftUI + NaturalLanguage + local JSON storage with zero special entitlements.",
                    tags: ["Minerva", "iOS"]
                )
            ]
        }
    }

    func saveNoteFromMessage(_ text: String) {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        let title = String(clean.prefix(36))
        let note = KnowledgeNote(title: title, body: clean, tags: ["Minerva", "Saved"])
        notes.insert(note, at: 0)
    }

    func clearChat() {
        messages = [
            MinervaMessage(
                role: .minerva,
                text: "Session cleared. Minerva ready for a new prompt.",
                metadataTag: "Reset"
            )
        ]
    }

    private func saveJSON<T: Encodable>(_ value: T, to url: URL) {
        do {
            let data = try JSONEncoder().encode(value)
            try data.write(to: url, options: .atomic)
        } catch {
            // Ignore write errors in sandboxed container
        }
    }

    private func loadJSON<T: Decodable>(from url: URL) -> T? {
        guard FileManager.default.fileManagerExists(atPath: url.path),
              let data = try? Data(contentsOf: url) else {
            return nil
        }
        return try? JSONDecoder().decode(T.self, from: data)
    }
}

private extension FileManager {
    func fileManagerExists(atPath path: String) -> Bool {
        fileExists(atPath: path)
    }
}

// MARK: - Views

struct MinervaChatView: View {
    @ObservedObject var store: MinervaStore
    @AppStorage("minerva_endpoint_url") private var endpointURL = ""
    @AppStorage("minerva_api_key") private var apiKey = ""
    @AppStorage("minerva_model") private var modelName = "gpt-4o-mini"

    @State private var draftText = ""
    @State private var isThinking = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(store.messages) { msg in
                                MessageBubbleView(message: msg) {
                                    store.saveNoteFromMessage(msg.text)
                                }
                                .id(msg.id)
                            }
                            if isThinking {
                                HStack {
                                    ProgressView()
                                    Text("Minerva is reasoning...")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                }
                                .padding(.horizontal)
                            }
                        }
                        .padding()
                    }
                    .onChange(of: store.messages.count) { _ in
                        if let last = store.messages.last {
                            withAnimation {
                                proxy.scrollTo(last.id, anchor: .bottom)
                            }
                        }
                    }
                }

                Divider()

                HStack(spacing: 8) {
                    TextField("Ask Minerva anything...", text: $draftText, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(1...4)

                    Button {
                        sendPrompt()
                    } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.title2)
                    }
                    .disabled(draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isThinking)
                }
                .padding()
                .background(.bar)
            }
            .navigationTitle("Minerva")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .destructive) {
                        store.clearChat()
                    } label: {
                        Image(systemName: "trash")
                    }
                }
            }
        }
    }

    private func sendPrompt() {
        let prompt = draftText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return }

        draftText = ""
        store.messages.append(MinervaMessage(role: .user, text: prompt))
        isThinking = true

        Task {
            let result = await MinervaEngine.shared.generateReply(
                prompt: prompt,
                endpointURLString: endpointURL,
                apiKey: apiKey,
                modelName: modelName
            )
            await MainActor.run {
                store.messages.append(
                    MinervaMessage(
                        role: .minerva,
                        text: result.reply,
                        metadataTag: result.tag
                    )
                )
                isThinking = false
            }
        }
    }
}

struct MessageBubbleView: View {
    let message: MinervaMessage
    let onSaveNote: () -> Void

    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 36) }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(message.role == .user ? "You" : "Minerva")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                    if let tag = message.metadataTag {
                        Text("• \(tag)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if message.role == .minerva {
                        Button {
                            onSaveNote()
                        } label: {
                            Image(systemName: "bookmark")
                                .font(.caption)
                        }
                        .buttonStyle(.borderless)
                    }
                }

                Text(LocalizedStringKey(message.text))
                    .font(.body)
                    .textSelection(.enabled)
            }
            .padding(12)
            .background(message.role == .user ? Color.blue.opacity(0.16) : Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 14))

            if message.role != .user { Spacer(minLength: 36) }
        }
    }
}

struct MinervaAnalyzerView: View {
    @State private var inputText = "Minerva is analyzing Swift code on iPhone with NaturalLanguage."
    @State private var result: NLAnalysisResult?

    var body: some View {
        NavigationStack {
            Form {
                Section("Input Text") {
                    TextEditor(text: $inputText)
                        .frame(minHeight: 110)
                    Button("Run On-Device NLP") {
                        result = MinervaEngine.shared.analyze(text: inputText)
                    }
                }

                if let res = result {
                    Section("Diagnostics") {
                        LabeledContent("Language", value: res.detectedLanguage)
                        LabeledContent("Word Count", value: "\(res.wordCount)")
                        LabeledContent("Sentiment Score", value: String(format: "%+.2f", res.dominantToneScore))
                    }

                    Section("Detected Entities") {
                        if res.entities.isEmpty {
                            Text("No named entities detected")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(res.entities, id: \.self) { item in
                                Text(item)
                            }
                        }
                    }
                }
            }
            .navigationTitle("NLP Lab")
            .onAppear {
                result = MinervaEngine.shared.analyze(text: inputText)
            }
        }
    }
}

struct MinervaNotesView: View {
    @ObservedObject var store: MinervaStore
    @State private var newTitle = ""
    @State private var newBody = ""

    var body: some View {
        NavigationStack {
            List {
                Section("Add Note") {
                    TextField("Title", text: $newTitle)
                    TextField("Details", text: $newBody, axis: .vertical)
                    Button("Save Note") {
                        let t = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                        let b = newBody.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !t.isEmpty || !b.isEmpty else { return }
                        store.notes.insert(
                            KnowledgeNote(title: t.isEmpty ? "Untitled" : t, body: b),
                            at: 0
                        )
                        newTitle = ""
                        newBody = ""
                    }
                }

                Section("Saved Knowledge") {
                    ForEach(store.notes) { note in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(note.title).font(.headline)
                            if !note.body.isEmpty {
                                Text(note.body)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    .onDelete { offsets in
                        store.notes.remove(atOffsets: offsets)
                    }
                }
            }
            .navigationTitle("Memory")
        }
    }
}

struct MinervaSettingsView: View {
    @AppStorage("minerva_endpoint_url") private var endpointURL = ""
    @AppStorage("minerva_api_key") private var apiKey = ""
    @AppStorage("minerva_model") private var modelName = "gpt-4o-mini"

    var body: some View {
        NavigationStack {
            Form {
                Section("Optional HTTPS Inference Endpoint") {
                    TextField("https://api.example.com/v1/chat/completions", text: $endpointURL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("API Key (optional)", text: $apiKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Model Name", text: $modelName)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                Section("Build Profile") {
                    LabeledContent("Entitlements", value: "None (Sideload Ready)")
                    LabeledContent("Frameworks", value: "SwiftUI, NaturalLanguage")
                }
            }
            .navigationTitle("Settings")
        }
    }
}

struct ContentView: View {
    @StateObject private var store = MinervaStore()

    var body: some View {
        TabView {
            MinervaChatView(store: store)
                .tabItem {
                    Label("Minerva", systemImage: "sparkles")
                }

            MinervaAnalyzerView()
                .tabItem {
                    Label("NLP Lab", systemImage: "waveform.path.ecg")
                }

            MinervaNotesView(store: store)
                .tabItem {
                    Label("Memory", systemImage: "folder")
                }

            MinervaSettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gear")
                }
        }
    }
}

@main
struct MinervaApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
