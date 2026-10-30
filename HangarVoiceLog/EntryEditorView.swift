import PhotosUI
import SwiftUI

struct EntryEditorView: View {
    @EnvironmentObject private var store: EntryStore
    @Environment(\.dismiss) private var dismiss
    @AppStorage(AppSettings.tailKey) private var tail = AppSettings.defaultTail

    @State private var entry: LogEntry
    let isNew: Bool
    /// Files created while editing, removed again if the edit is cancelled.
    @State private var filesAddedThisEdit: [String] = []
    /// Files the user removed, deleted for good only when the edit is saved.
    @State private var filesRemovedThisEdit: [String] = []

    @StateObject private var recorder = VoiceRecorder()
    @State private var isTranscribing = false
    @State private var statusMessage: String?

    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var showingCamera = false
    @State private var shareItems: ShareItems?
    @State private var copied = false

    init(entry: LogEntry, isNew: Bool) {
        _entry = State(initialValue: entry)
        self.isNew = isNew
    }

    private var draftText: String {
        LogbookFormatter.draft(for: entry, tail: tail)
    }

    var body: some View {
        NavigationStack {
            Form {
                voiceSection
                detailsSection
                descriptionSection
                photosSection
                draftSection
            }
            .navigationTitle(isNew ? "New Entry" : "Edit Entry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: cancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .bold()
                        .disabled(recorder.isRecording || isTranscribing)
                }
            }
            .sheet(item: $shareItems) { share in
                ShareSheet(items: share.items)
            }
            .fullScreenCover(isPresented: $showingCamera) {
                CameraPicker { image in addPhoto(image) }
                    .ignoresSafeArea()
            }
            .onChange(of: pickerItems) { _, items in
                Task { await importPhotos(items) }
            }
            .interactiveDismissDisabled()
        }
    }

    // MARK: Sections

    private var voiceSection: some View {
        Section {
            if recorder.isRecording {
                Button(role: .destructive) {
                    stopAndTranscribe()
                } label: {
                    Label("Stop  \(VoiceRecorder.format(recorder.elapsed))", systemImage: "stop.circle.fill")
                        .font(.title3.bold())
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
            } else {
                Button {
                    startRecording()
                } label: {
                    Label(entry.audioFileName == nil ? "Record Voice Note" : "Record Again (adds to text)",
                          systemImage: "mic.circle.fill")
                        .font(.title3.bold())
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .disabled(isTranscribing)
            }

            if let audio = entry.audioFileName, !recorder.isRecording {
                Button {
                    if recorder.isPlaying {
                        recorder.stopPlayback()
                    } else {
                        recorder.play(url: store.fileURL(for: audio))
                    }
                } label: {
                    Label(recorder.isPlaying ? "Stop Playback" : "Play Recording",
                          systemImage: recorder.isPlaying ? "stop.fill" : "play.fill")
                }
                Button {
                    transcribe(audio)
                } label: {
                    Label("Convert Recording to Text Again", systemImage: "text.bubble")
                }
                .disabled(isTranscribing)
            }

            if isTranscribing {
                HStack {
                    ProgressView()
                    Text("Converting speech to text…")
                }
            }
            if let message = recorder.errorMessage ?? statusMessage {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Voice Note")
        } footer: {
            Text("Speak naturally, for example: “Changed oil and filter, eight quarts, safety-wired the filter, no metal in the filter.”")
        }
    }

    private var detailsSection: some View {
        Section("Details") {
            DatePicker("Date", selection: $entry.workDate, displayedComponents: .date)
            LabeledContent("Tach") {
                TextField("e.g. 512.3", text: $entry.tach)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
            }
            LabeledContent("Hobbs") {
                TextField("optional", text: $entry.hobbs)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
            }
            Picker("Type", selection: $entry.category) {
                ForEach(EntryCategory.allCases) { category in
                    Text(category.label).tag(category)
                }
            }
        }
    }

    private var descriptionSection: some View {
        Section {
            TextEditor(text: $entry.details)
                .frame(minHeight: 140)
                .accessibilityLabel("Work performed")
        } header: {
            Text("Work Performed")
        } footer: {
            Text("Your recording appears here as text. Fix any words it misheard.")
        }
    }

    private var photosSection: some View {
        Section("Photos") {
            if !entry.photoFileNames.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(entry.photoFileNames, id: \.self) { name in
                            PhotoThumbnail(image: store.image(named: name)) {
                                removePhoto(name)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            if CameraPicker.isAvailable {
                Button {
                    showingCamera = true
                } label: {
                    Label("Take Photo", systemImage: "camera")
                }
            }
            PhotosPicker(selection: $pickerItems, maxSelectionCount: 10, matching: .images) {
                Label("Add From Photo Library", systemImage: "photo.on.rectangle")
            }
        }
    }

    private var draftSection: some View {
        Section {
            Text(draftText)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
            Button {
                UIPasteboard.general.string = draftText
                copied = true
            } label: {
                Label(copied ? "Copied" : "Copy Logbook Text", systemImage: copied ? "checkmark" : "doc.on.doc")
            }
            Button {
                var items: [Any] = [draftText]
                items.append(contentsOf: entry.photoFileNames.map { store.fileURL(for: $0) })
                shareItems = ShareItems(items: items)
            } label: {
                Label("Share Entry and Photos", systemImage: "square.and.arrow.up")
            }
        } header: {
            Text("Draft Logbook Entry")
        } footer: {
            Text("A draft only. Review it and sign it in the aircraft logbook as required.")
        }
        .onChange(of: entry) { _, _ in copied = false }
    }

    // MARK: Actions

    private func startRecording() {
        statusMessage = nil
        let name = store.newAudioFileName()
        Task {
            await recorder.startRecording(to: store.fileURL(for: name))
            if recorder.isRecording {
                if let old = entry.audioFileName { markRemoved(old) }
                entry.audioFileName = name
                filesAddedThisEdit.append(name)
            }
        }
    }

    private func stopAndTranscribe() {
        recorder.stopRecording()
        if let audio = entry.audioFileName {
            transcribe(audio)
        }
    }

    private func transcribe(_ audioName: String) {
        isTranscribing = true
        statusMessage = nil
        let url = store.fileURL(for: audioName)
        Task {
            do {
                let text = try await Transcriber.transcribe(url: url)
                let existing = entry.details.trimmingCharacters(in: .whitespacesAndNewlines)
                entry.details = existing.isEmpty ? text : existing + "\n" + text
            } catch {
                statusMessage = error.localizedDescription + " Your recording is saved either way."
            }
            isTranscribing = false
        }
    }

    private func addPhoto(_ image: UIImage) {
        if let name = store.savePhoto(image) {
            entry.photoFileNames.append(name)
            filesAddedThisEdit.append(name)
        }
    }

    private func importPhotos(_ items: [PhotosPickerItem]) async {
        guard !items.isEmpty else { return }
        for item in items {
            if let data = try? await item.loadTransferable(type: Data.self),
               let image = UIImage(data: data) {
                addPhoto(image)
            }
        }
        pickerItems = []
    }

    private func removePhoto(_ name: String) {
        entry.photoFileNames.removeAll { $0 == name }
        markRemoved(name)
    }

    private func markRemoved(_ name: String) {
        if let index = filesAddedThisEdit.firstIndex(of: name) {
            // Never saved, so it can go right away.
            filesAddedThisEdit.remove(at: index)
            store.deleteMedia(named: name)
        } else {
            filesRemovedThisEdit.append(name)
        }
    }

    private func save() {
        recorder.stopPlayback()
        filesRemovedThisEdit.forEach(store.deleteMedia)
        store.upsert(entry)
        dismiss()
    }

    private func cancel() {
        if recorder.isRecording { recorder.stopRecording() }
        recorder.stopPlayback()
        filesAddedThisEdit.forEach(store.deleteMedia)
        dismiss()
    }
}

private struct PhotoThumbnail: View {
    let image: UIImage?
    let onRemove: () -> Void
    @State private var confirming = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Group {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    Color.secondary.opacity(0.2)
                }
            }
            .frame(width: 96, height: 96)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            Button {
                confirming = true
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, .black.opacity(0.6))
            }
            .buttonStyle(.plain)
            .padding(4)
            .accessibilityLabel("Remove photo")
        }
        .confirmationDialog("Remove this photo?", isPresented: $confirming) {
            Button("Remove Photo", role: .destructive, action: onRemove)
        }
    }
}
