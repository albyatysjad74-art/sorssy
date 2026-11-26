import SwiftUI

struct AppEditorView: View {
    let source: SourceModel
    var app: CatalogApp? = nil
    var appIndex: Int? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var fields: AppFields
    @State private var showingConfirmation = false

    init(source: SourceModel, app: CatalogApp? = nil, appIndex: Int? = nil) {
        self.source = source
        self.app = app
        self.appIndex = appIndex
        _fields = State(initialValue: AppFields(app: app))
    }

    private var isEditing: Bool { app != nil }

    var body: some View {
        Form {
            Section("بيانات التطبيق") {
                TextField("اسم التطبيق", text: $fields.name)
                    .textContentType(.name)
                TextField("معرّف الحزمة · مثل com.example.app", text: $fields.bundleIdentifier)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .environment(\.layoutDirection, .leftToRight)
                TextField("الإصدار", text: $fields.version)
                    .textInputAutocapitalization(.never)
                    .environment(\.layoutDirection, .leftToRight)
                TextField("التصنيف", text: $fields.category)
            }

            Section("الأيقونة والتنزيل") {
                TextField("رابط الأيقونة HTTPS", text: $fields.iconURL)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .environment(\.layoutDirection, .leftToRight)
                TextField("رابط تنزيل IPA HTTPS", text: $fields.downloadURL)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .environment(\.layoutDirection, .leftToRight)
                TextField("الحجم بالميغابايت (اختياري)", text: $fields.sizeMB)
                    .keyboardType(.decimalPad)
                    .environment(\.layoutDirection, .leftToRight)
            }

            Section("الوصف") {
                TextEditor(text: $fields.description)
                    .frame(minHeight: 150)
                    .scrollContentBackground(.hidden)
                    .accessibilityLabel("وصف التطبيق")
            }

            if !fields.isValid {
                Section {
                    Text("أكمل الحقول المطلوبة، واستخدم معرّف حزمة صالحاً وروابط HTTPS. الحجم اختياري.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            Section {
                VStack(alignment: .leading, spacing: 7) {
                    Label("لن يرفع التطبيق ملف IPA أو يغيّر محتواه.", systemImage: "info.circle")
                    Text("سيُفتح نموذج GitHub؛ أرسله وأكّد الطلب بحساب مالك المستودع حتى تُحدّث بيانات السورس.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .font(.subheadline)
            }
        }
        .scrollContentBackground(.hidden)
        .background(SorssyTheme.background)
        .navigationTitle(isEditing ? "تعديل التطبيق" : "إضافة تطبيق")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("إلغاء") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("متابعة") { showingConfirmation = true }
                    .disabled(!fields.isValid)
            }
        }
        .alert(isEditing ? "إرسال التعديل إلى GitHub؟" : "إضافة التطبيق إلى GitHub؟", isPresented: $showingConfirmation) {
            Button("فتح GitHub") { submit() }
            Button("إلغاء", role: .cancel) { }
        } message: {
            Text("سيفتح GitHub بطلب مُعبّأ. سجّل بحساب albyatysjad74-art واضغط Create issue لتأكيد الحفظ.")
        }
        .tint(SorssyTheme.blue)
    }

    private func submit() {
        let payload: [String: Any]
        let title: String
        if let app, let appIndex {
            var target: [String: Any] = ["index": appIndex]
            if let value = app.name { target["name"] = value }
            if let value = app.bundleIdentifier { target["bundleIdentifier"] = value }
            if let value = app.version { target["version"] = value }
            if let value = app.downloadURL { target["downloadURL"] = value }
            if let value = app.iconURL { target["iconURL"] = value }
            payload = ["action": "edit_app", "target": target, "changes": fields.issueValues]
            title = "[Sorssy] تعديل تطبيق: \(fields.name.trimmingCharacters(in: .whitespacesAndNewlines))"
        } else {
            payload = ["action": "add_app"].merging(fields.issueValues) { _, new in new }
            title = "[Sorssy] إضافة تطبيق: \(fields.name.trimmingCharacters(in: .whitespacesAndNewlines))"
        }
        guard let url = GitHubSubmission.issueURL(title: title, payload: payload) else { return }
        openURL(url)
        dismiss()
    }
}

struct SourceEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var name = ""
    @State private var subtitle = ""
    @State private var sourceURL = ""
    @State private var iconURL = ""
    @State private var showingConfirmation = false

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && name.count <= 100
            && subtitle.count <= 200
            && AppFields.isHTTPS(sourceURL)
            && sourceURL.count <= 2048
            && (iconURL.isEmpty || AppFields.isHTTPS(iconURL))
            && iconURL.count <= 2048
    }

    var body: some View {
        Form {
            Section("بيانات المصدر") {
                TextField("اسم المصدر", text: $name)
                TextField("وصف مختصر (اختياري)", text: $subtitle)
                TextField("رابط ملف JSON العام", text: $sourceURL)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .environment(\.layoutDirection, .leftToRight)
                TextField("رابط الأيقونة (اختياري)", text: $iconURL)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .environment(\.layoutDirection, .leftToRight)
            }
            Section {
                Text("المصادر الخارجية تظهر للقراءة فقط. أرسل الطلب بحساب مالك المستودع لاعتماده.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if !isValid {
                Section {
                    Text("أدخل اسم المصدر ورابط JSON صحيحاً يبدأ بـ https://")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(SorssyTheme.background)
        .navigationTitle("إضافة مصدر")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("إلغاء") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("متابعة") { showingConfirmation = true }.disabled(!isValid)
            }
        }
        .alert("إرسال طلب المصدر إلى GitHub؟", isPresented: $showingConfirmation) {
            Button("فتح GitHub") { submit() }
            Button("إلغاء", role: .cancel) { }
        } message: {
            Text("سيفتح GitHub بطلب مُعبّأ. سجّل بحساب albyatysjad74-art واضغط Create issue لتأكيد الإضافة.")
        }
        .tint(SorssyTheme.blue)
    }

    private func submit() {
        var source: [String: Any] = [
            "name": name.trimmingCharacters(in: .whitespacesAndNewlines),
            "subtitle": subtitle.trimmingCharacters(in: .whitespacesAndNewlines),
            "url": sourceURL.trimmingCharacters(in: .whitespacesAndNewlines)
        ]
        if !iconURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            source["iconURL"] = iconURL.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard let url = GitHubSubmission.issueURL(title: "[Sorssy] إضافة مصدر: \(name)", payload: ["action": "add_source", "source": source]) else { return }
        openURL(url)
        dismiss()
    }
}
