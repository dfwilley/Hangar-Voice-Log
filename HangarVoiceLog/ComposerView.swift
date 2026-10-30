import PhotosUI
import SwiftUI

/// The "New entry" card: job buttons, date, Hobbs, hours, who, entry text, voice, photos.
struct ComposerView: View {
    @EnvironmentObject private var store: EntryStore

    let isNew: Bool
    let onDone: (String) -> Void

    @State private var entry: LogEntry
    @State private var hobbsAuto: Bool
    @State private var hobbsArmed = false
    @State private var laborManual: Bool
    @State private var status: String?
    @State private var busy = false
    @State private var deleteArmed = false

    /// Files added while editing (removed again if never saved) and files the
    /// user removed (deleted only once the change is saved).
    @State private var filesAdded: [String] = []
    @State private var filesRemoved: [String] = []

    @StateObject private var recorder = VoiceRecorder()
    @State private var isTranscribing = false
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var showingCamera = false
    @State private var shareItems: ShareItems?
    @State private var showingCalendar = false

    init(existing: LogEntry?, onDone: @escaping (String) -> Void) {
        self.isNew = existing == nil
        self.onDone = onDone
        _entry = State(initialValue: existing ?? LogEntry())
        _hobbsAuto = State(initialValue: existing == nil)
        _laborManual = State(initialValue: !(existing?.laborHours.isEmpty ?? true))
    }

    private var jobs: [HangarData.Job] { store.hangarData.jobs }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                CardTitle(text: isNew ? "New entry" : entry.title)
                Spacer()
                if !isNew {
                    Button("+ New") { onDone("") }
                        .buttonStyle(HangarButtonStyle())
                }
            }

            if entry.status == .sent, let sentAt = entry.sentAt {
                notice("Added to the Access import file on \(LogbookFormatter.longDate(sentAt)). Changes here stay on the phone.")
            }

            jobPicker
            fields
            entryEditor
            voiceRow
            photos
            actions

            if let status {
                Text(status)
                    .font(Theme.body(14, relativeTo: .footnote))
                    .foregroundStyle(Theme.muted)
                    .accessibilityAddTraits(.updatesFrequently)
            }
        }
        .card()
        .onAppear(perform: fillHobbsIfNew)
        .onChange(of: store.hangarData) { _, _ in fillHobbsIfNew() }
        .onChange(of: pickerItems) { _, items in Task { await importPhotos(items) } }
        .fullScreenCover(isPresented: $showingCamera) {
            CameraPicker { addPhoto($0) }.ignoresSafeArea()
        }
        .sheet(item: $shareItems) { ShareSheet(items: $0.items) }
    }

    // MARK: Job buttons

    private var jobPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: "What did you work on?")
            FlowLayout(spacing: 8) {
                ForEach(jobs) { job in
                    Chip(title: HangarData.chipName(for: job), selected: entry.job == job.name) {
                        pick(job: job)
                    }
                }
                ForEach(HangarData.extraJobs, id: \.self) { name in
                    Chip(title: name, selected: entry.job == name) {
                        pickExtra(name)
                    }
                }
            }
        }
    }

    private func pick(job: HangarData.Job) {
        if entry.job == job.name {
            clearJob()
            return
        }
        entry.job = job.name
        entry.recurringId = job.recurringId
        entry.equipmentIds = job.equipmentIds ?? []
        if !laborManual, let hours = job.laborHours {
            entry.laborHours = LogbookFormatter.hobbs(hours)
        }
        let current = entry.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let isStandard = jobs.contains { $0.entry == current }
        if current.isEmpty || isStandard {
            entry.text = job.entry
            status = "Filled in your standard \(job.name) wording. Change anything that was different this time."
        } else {
            status = "Set this up as \(job.name). Your wording was kept."
        }
    }

    private func pickExtra(_ name: String) {
        if entry.job == name {
            clearJob()
            return
        }
        entry.job = name
        entry.recurringId = 0
        entry.equipmentIds = []
        let current = entry.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if jobs.contains(where: { $0.entry == current }) { entry.text = "" }
        status = nil
    }

    private func clearJob() {
        entry.job = ""
        entry.recurringId = 0
        entry.equipmentIds = []
        status = nil
    }

    // MARK: Fields

    private var fields: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                FieldLabel(text: "Date")
                Button {
                    withAnimation { showingCalendar.toggle() }
                } label: {
                    HStack {
                        Text(LogbookFormatter.longDate(entry.workDate))
                            .font(Theme.body())
                            .foregroundStyle(Theme.ink)
                        Spacer()
                        Image(systemName: "calendar")
                            .font(.title3)
                            .foregroundStyle(Theme.ink)
                    }
                    .field()
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Date, \(LogbookFormatter.longDate(entry.workDate)). Tap to change.")
                if showingCalendar {
                    DatePicker("Date", selection: $entry.workDate, displayedComponents: .date)
                        .datePickerStyle(.graphical)
                        .tint(Theme.accent)
                        .onChange(of: entry.workDate) { _, _ in
                            withAnimation { showingCalendar = false }
                        }
                }
            }

            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    FieldLabel(text: "Hobbs")
                    TextField("e.g. 142.6", text: Binding(
                        get: { entry.hobbs },
                        set: { entry.hobbs = $0; hobbsAuto = false; hobbsArmed = false }
                    ))
                    .keyboardType(.decimalPad)
                    .font(Theme.data())
                    .field()
                }
                VStack(alignment: .leading, spacing: 4) {
                    FieldLabel(text: "Hours of work")
                    TextField("e.g. 1.5", text: Binding(
                        get: { entry.laborHours },
                        set: { entry.laborHours = $0; laborManual = !$0.isEmpty }
                    ))
                    .keyboardType(.decimalPad)
                    .font(Theme.data())
                    .field()
                }
            }

            if let last = store.lastHobbs {
                Text("Last logged \(LogbookFormatter.hobbs(last.value)) on \(LogbookFormatter.longDate(last.date))\(last.fromAccess ? " in Access" : "")\(hobbsAuto ? ". Update it if you've flown since." : ".")")
                    .font(Theme.body(13, relativeTo: .footnote))
                    .foregroundStyle(Theme.muted)
            }

            VStack(alignment: .leading, spacing: 4) {
                FieldLabel(text: "Performed by")
                Menu {
                    ForEach(store.hangarData.maintainers) { person in
                        Button(person.name) {
                            entry.performedById = person.id
                            entry.performedByName = person.name
                        }
                    }
                } label: {
                    HStack {
                        Text(entry.performedByName)
                            .font(Theme.body())
                            .foregroundStyle(Theme.ink)
                        Spacer()
                        Image(systemName: "chevron.up.chevron.down")
                            .foregroundStyle(Theme.muted)
                    }
                    .field()
                }
            }
        }
    }

    private func fillHobbsIfNew() {
        guard isNew, hobbsAuto, let last = store.lastHobbs else { return }
        entry.hobbs = LogbookFormatter.hobbs(last.value)
    }

    // MARK: Entry text

    private var entryEditor: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                FieldLabel(text: "Logbook entry")
                Text("Edit anything. Fill in any [ ] blanks.")
                    .font(Theme.body(13, relativeTo: .footnote))
                    .foregroundStyle(Theme.muted)
            }
            ZStack(alignment: .topLeading) {
                if entry.text.isEmpty {
                    Text("Changed oil, 8 quarts Phillips 20W-50. Cut open the filter, no metal. Safety-wired the filter.")
                        .font(Theme.data(15))
                        .foregroundStyle(Theme.muted.opacity(0.7))
                        .padding(.horizontal, 15)
                        .padding(.vertical, 18)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $entry.text)
                    .font(Theme.data(15))
                    .foregroundStyle(Theme.ink)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .frame(minHeight: 200)
                    .accessibilityLabel("Logbook entry")
            }
            .background(Theme.field, in: RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(Theme.line, lineWidth: 1))
        }
    }

    // MARK: Voice

    private var voiceRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                if recorder.isRecording {
                    Button {
                        stopAndTranscribe()
                    } label: {
                        Label("Stop  \(VoiceRecorder.format(recorder.elapsed))", systemImage: "stop.circle.fill")
                    }
                    .buttonStyle(HangarButtonStyle(kind: .danger))
                } else {
                    Button {
                        startRecording()
                    } label: {
                        Label("Talk", systemImage: "mic.fill")
                    }
                    .buttonStyle(HangarButtonStyle(kind: .primary))
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
                        Label(recorder.isPlaying ? "Stop" : "Play", systemImage: recorder.isPlaying ? "stop.fill" : "play.fill")
                    }
                    .buttonStyle(HangarButtonStyle())
                }
                if isTranscribing { ProgressView() }
            }
            Text(recorder.errorMessage ?? "Tap Talk and describe the work. Your words are added to the entry, and the recording stays with it.")
                .font(Theme.body(14, relativeTo: .footnote))
                .foregroundStyle(Theme.ink)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.accentSoft, in: RoundedRectangle(cornerRadius: 10))
        }
    }

    private func startRecording() {
        let name = store.newAudioFileName()
        Task {
            await recorder.startRecording(to: store.fileURL(for: name))
            if recorder.isRecording {
                if let old = entry.audioFileName { markRemoved(old) }
                entry.audioFileName = name
                filesAdded.append(name)
            }
        }
    }

    private func stopAndTranscribe() {
        recorder.stopRecording()
        guard let audio = entry.audioFileName else { return }
        isTranscribing = true
        let url = store.fileURL(for: audio)
        Task {
            do {
                let text = try await Transcriber.transcribe(url: url)
                let existing = entry.text.trimmingCharacters(in: .whitespacesAndNewlines)
                entry.text = existing.isEmpty ? text : existing + " " + text
                status = "Added what you said to the entry. Check it for misheard words."
            } catch {
                status = error.localizedDescription + " The recording is saved."
            }
            isTranscribing = false
        }
    }

    // MARK: Photos

    private var photos: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: "Photos")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 88), spacing: 8)], spacing: 8) {
                ForEach(entry.photoFileNames, id: \.self) { name in
                    PhotoTile(image: store.image(named: name)) { removePhoto(name) }
                }
                if CameraPicker.isAvailable {
                    Button { showingCamera = true } label: { addTile("Take photo", systemImage: "camera") }
                        .buttonStyle(.plain)
                }
                PhotosPicker(selection: $pickerItems, maxSelectionCount: 10, matching: .images) {
                    addTile("Add photo", systemImage: "photo.on.rectangle")
                }
            }
        }
    }

    private func addTile(_ title: String, systemImage: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: systemImage)
            Text(title).font(Theme.bodySemibold(14, relativeTo: .footnote))
        }
        .foregroundStyle(Theme.muted)
        .frame(maxWidth: .infinity)
        .aspectRatio(1, contentMode: .fit)
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(Theme.line, style: StrokeStyle(lineWidth: 2, dash: [6, 4])))
    }

    private func addPhoto(_ image: UIImage) {
        if let name = store.savePhoto(image) {
            entry.photoFileNames.append(name)
            filesAdded.append(name)
        }
    }

    private func importPhotos(_ items: [PhotosPickerItem]) async {
        guard !items.isEmpty else { return }
        for item in items {
            if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
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
        if let index = filesAdded.firstIndex(of: name) {
            filesAdded.remove(at: index)
            store.deleteMedia(named: name)
        } else {
            filesRemoved.append(name)
        }
    }

    // MARK: Actions

    private var actions: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                if entry.status != .sent {
                    Button("Send to Access") { send() }
                        .buttonStyle(HangarButtonStyle(kind: .primary))
                }
                Button(entry.status == .sent ? "Save changes" : "Save draft") { saveDraft() }
                    .buttonStyle(HangarButtonStyle())
            }
            HStack(spacing: 10) {
                Button {
                    var items: [Any] = [shareText]
                    items.append(contentsOf: entry.photoFileNames.map { store.fileURL(for: $0) })
                    shareItems = ShareItems(items: items)
                } label: {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(HangarButtonStyle())
                .disabled(entry.text.isEmpty)

                if !isNew || !entry.text.isEmpty || !filesAdded.isEmpty {
                    Button(deleteArmed ? "Tap again to delete" : (isNew ? "Discard" : "Delete")) { deleteTapped() }
                        .buttonStyle(HangarButtonStyle(kind: .danger))
                }
            }
        }
        .disabled(busy || recorder.isRecording || isTranscribing)
    }

    private var shareText: String {
        var header = "N721NE — \(LogbookFormatter.longDate(entry.workDate))"
        if !entry.hobbs.isEmpty { header += " — Hobbs \(entry.hobbs)" }
        return "\(header)\n\n\(entry.text)\n\n\(entry.performedByName)"
    }

    private func send() {
        guard AccessFolder.isChosen else {
            status = "Choose your Dropbox Maintenance Software folder at the bottom of the page first."
            return
        }
        guard let hobbs = LogbookFormatter.number(entry.hobbs), hobbs > 0 else {
            status = "Add the Hobbs time before sending."
            return
        }
        if hobbsAuto && !hobbsArmed {
            hobbsArmed = true
            status = "The Hobbs is still the last logged \(entry.hobbs). If that's right, tap Send to Access again. Otherwise update it."
            return
        }
        guard !entry.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            status = "Write or say the logbook entry first."
            return
        }
        guard !LogbookFormatter.hasBlanks(entry.text) else {
            status = "The entry still has [ ] blanks. Fill them in first."
            return
        }
        busy = true
        status = "Adding it to Claude Logbook Import.txt…"
        recorder.stopPlayback()
        Task {
            do {
                _ = try await store.sendToAccess(entry)
                filesRemoved.forEach(store.deleteMedia)
                busy = false
                onDone("Added to Claude Logbook Import.txt in Dropbox. In Access, open Maintenance Record and run ImportClaudeLogbookEntries.")
            } catch {
                busy = false
                status = "Didn't send: \(error.localizedDescription) Your entry is still here."
            }
        }
    }

    private func saveDraft() {
        recorder.stopPlayback()
        filesRemoved.forEach(store.deleteMedia)
        store.upsert(entry)
        onDone(entry.status == .sent ? "Changes saved on the phone." : "Draft saved. It's in the queue below.")
    }

    private func deleteTapped() {
        guard deleteArmed else {
            deleteArmed = true
            Task {
                try? await Task.sleep(nanoseconds: 4_000_000_000)
                deleteArmed = false
            }
            return
        }
        recorder.stopPlayback()
        if isNew {
            filesAdded.forEach(store.deleteMedia)
            onDone("")
        } else {
            filesAdded.forEach(store.deleteMedia)
            store.delete(entry)
            onDone("Entry deleted.")
        }
    }

    private func notice(_ text: String) -> some View {
        Text(text)
            .font(Theme.body(15))
            .foregroundStyle(Theme.ink)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.field, in: RoundedRectangle(cornerRadius: 10))
    }
}

private struct PhotoTile: View {
    let image: UIImage?
    let onRemove: () -> Void
    @State private var confirming = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.clear
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    if let image {
                        Image(uiImage: image).resizable().scaledToFill()
                    } else {
                        Theme.field
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 9))
                .overlay(RoundedRectangle(cornerRadius: 9).stroke(Theme.line, lineWidth: 1))
            Button { confirming = true } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(Color.black.opacity(0.6), in: Circle())
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
