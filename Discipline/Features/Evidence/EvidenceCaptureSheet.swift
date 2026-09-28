import PhotosUI
import SwiftUI
import DisciplineCore

struct EvidenceCaptureSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(AppContainer.self) private var container
    @State private var model: EvidenceFlowModel

    @State private var showsCamera = false
    @State private var libraryItem: PhotosPickerItem?
    @State private var cameraMessage: String?
    @State private var cameraDenied = false

    init(habit: Habit, store: HabitsStore, container: AppContainer) {
        _model = State(initialValue: EvidenceFlowModel(
            habit: habit, store: store, evidence: container.evidence, verification: container.verification
        ))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    content
                }
                .padding(Theme.Spacing.md)
                .animation(.easeInOut(duration: 0.25), value: model.phase)
            }
            .screenBackground()
            .safeAreaInset(edge: .bottom) { actions }
            .navigationTitle(model.habit.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(isFinished ? "Done" : "Cancel") { dismiss() }
                        .disabled(model.isBusy)
                }
            }
            .interactiveDismissDisabled(model.isBusy)
            .fullScreenCover(isPresented: $showsCamera) {
                CameraPicker { model.use($0, source: .camera) }
                    .ignoresSafeArea()
            }
            .onChange(of: libraryItem) { _, item in
                guard let item else { return }
                Task { await loadLibraryImage(item) }
            }
        }
    }

    private var isFinished: Bool {
        if case .finished = model.phase { return true }
        return false
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .choosing:
            if !container.connectivity.isOnline {
                InlineMessage(text: "You're offline. Photo evidence needs a connection to upload and be verified.", style: .info)
            }
            intro
            criteriaCard
            if let cameraMessage {
                InlineMessage(text: cameraMessage, style: .info)
                if cameraDenied {
                    Button("Open Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                    }
                    .font(Theme.Typography.callout.weight(.semibold))
                }
            }
        case .preview:
            photoPreview
            if model.habit.unit != .sessions {
                quantityPicker
            }
            criteriaCard
        case .uploading:
            photoPreview
            progress("Uploading photo securely…")
        case .verifying:
            photoPreview
            progress("Checking evidence against the criteria…")
        case .finished(let result):
            VerificationResultView(result: result)
        case .failed(let error, _):
            if model.image != nil { photoPreview }
            InlineMessage(text: error.localizedDescription)
        }
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            HabitIcon(category: model.habit.category, size: 56)
            Text("Photo evidence")
                .font(Theme.Typography.title)
                .foregroundStyle(Theme.Palette.textPrimary)
            Text("Take a photo that shows your \(model.habit.name.lowercased()). It will be checked automatically against the criteria below.")
                .font(Theme.Typography.callout)
                .foregroundStyle(Theme.Palette.textSecondary)
        }
    }

    private var criteriaCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            SectionEyebrow(title: "What will be checked")
            ForEach(model.criteria) { criterion in
                Label(criterion.name, systemImage: "checkmark.circle")
                    .font(Theme.Typography.callout)
                    .foregroundStyle(Theme.Palette.textPrimary)
            }
            Divider().overlay(Theme.Palette.hairline)
            Text("Assessed by \(model.providerDescription). This is an automated assessment that can make mistakes. Photos are stored privately and location data is removed.")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Palette.textSecondary)
        }
        .card()
    }

    @ViewBuilder
    private var photoPreview: some View {
        if let image = model.image {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity)
                .frame(height: 320)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous))
                .overlay(alignment: .topLeading) {
                    Label(model.captureSource == .camera ? "Camera" : "Library", systemImage: model.captureSource == .camera ? "camera" : "photo")
                        .font(Theme.Typography.caption)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(Theme.Spacing.sm)
                }
                .accessibilityLabel("Selected evidence photo")
        }
    }

    private var quantityPicker: some View {
        Stepper(value: $model.quantity, in: 1...1000, step: 5) {
            LabeledContent("Amount", value: "\(model.quantity) \(model.habit.unit.displayName)")
        }
        .card()
    }

    private func progress(_ text: String) -> some View {
        HStack(spacing: Theme.Spacing.sm) {
            ProgressView()
            Text(text)
                .font(Theme.Typography.callout)
                .foregroundStyle(Theme.Palette.textSecondary)
        }
        .card()
    }

    // MARK: Actions

    @ViewBuilder
    private var actions: some View {
        VStack(spacing: Theme.Spacing.sm) {
            switch model.phase {
            case .choosing:
                Button {
                    Task { await openCamera() }
                } label: {
                    Label("Take photo", systemImage: "camera.fill")
                }
                .buttonStyle(.primary)
                .accessibilityIdentifier("evidence.camera")

                PhotosPicker(selection: $libraryItem, matching: .images, photoLibrary: .shared()) {
                    Label("Choose from library", systemImage: "photo.on.rectangle")
                }
                .buttonStyle(.secondary)
                .accessibilityIdentifier("evidence.library")
            case .preview:
                Button("Submit for verification") { Task { await model.submit() } }
                    .buttonStyle(.primary)
                    .disabled(!container.connectivity.isOnline)
                    .accessibilityIdentifier("evidence.submit")
                Button("Retake") { model.retake() }
                    .buttonStyle(.secondary)
            case .uploading, .verifying:
                EmptyView()
            case .finished(let result):
                if result.status == .rejected || result.status == .uncertain {
                    Button("Close") { dismiss() }
                        .buttonStyle(.secondary)
                } else {
                    Button("Done") { dismiss() }
                        .buttonStyle(.primary)
                }
                if result.status == .error {
                    Button("Retry verification") { Task { await model.verify() } }
                        .buttonStyle(.secondary)
                }
            case .failed(_, let canRetryVerification):
                if canRetryVerification {
                    Button("Retry verification") { Task { await model.verify() } }
                        .buttonStyle(.primary)
                } else {
                    Button("Try again") { Task { await model.submit() } }
                        .buttonStyle(.primary)
                        .disabled(model.image == nil)
                    Button("Choose a different photo") { model.retake() }
                        .buttonStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.sm)
        .background(Theme.Palette.background)
    }

    private func openCamera() async {
        switch await CameraPermission.request() {
        case .granted:
            cameraMessage = nil
            cameraDenied = false
            showsCamera = true
        case .denied:
            cameraMessage = "Camera access is turned off. Enable it in Settings, or choose a photo from your library."
            cameraDenied = true
        case .unavailable:
            cameraMessage = "No camera is available on this device. Choose a photo from your library instead."
        }
    }

    private func loadLibraryImage(_ item: PhotosPickerItem) async {
        defer { libraryItem = nil }
        do {
            guard let data = try await item.loadTransferable(type: Data.self), let image = UIImage(data: data) else {
                cameraMessage = "That photo couldn't be loaded. Try a different one."
                return
            }
            model.use(image, source: .library)
        } catch {
            cameraMessage = "That photo couldn't be loaded. Try a different one."
        }
    }
}
