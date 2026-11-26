import SwiftUI

enum SorssyTheme {
    static let background = Color(red: 0.025, green: 0.065, blue: 0.12)
    static let panel = Color(red: 0.055, green: 0.115, blue: 0.19)
    static let blue = Color(red: 0.42, green: 0.78, blue: 1.0)
    static let muted = Color(red: 0.64, green: 0.72, blue: 0.82)
}

struct ContentView: View {
    @StateObject private var store = LibraryStore()
    @State private var showingAddSource = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("إدارة مصادر وتطبيقات iOS", systemImage: "square.stack.3d.up.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(SorssyTheme.blue)
                        Text("كل مصادر التطبيقات بمكان واحد")
                            .font(.title2.bold())
                            .foregroundStyle(.white)
                        Text("تصفّح الإدراجات، ابحث عنها، وعدّل بيانات مصدر sorssy من جهازك.")
                            .font(.subheadline)
                            .foregroundStyle(SorssyTheme.muted)
                        HStack(spacing: 18) {
                            Label("\(store.sources.count) مصدر", systemImage: "square.stack")
                            Label("\(store.sources.reduce(0) { $0 + $1.apps.count }) تطبيق", systemImage: "apps.iphone")
                        }
                        .font(.caption.weight(.medium))
                        .foregroundStyle(SorssyTheme.blue)
                        .padding(.top, 3)
                    }
                    .padding(.vertical, 10)
                    .listRowBackground(SorssyTheme.panel)
                }

                Section("مصادري") {
                    if store.isLoading && store.sources.isEmpty {
                        HStack(spacing: 12) {
                            ProgressView()
                            Text("جارٍ تحميل المصادر…").foregroundStyle(SorssyTheme.muted)
                        }
                        .listRowBackground(SorssyTheme.panel)
                    } else if let error = store.errorMessage, store.sources.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(error).foregroundStyle(SorssyTheme.muted)
                            Button("إعادة المحاولة") { Task { await store.refresh() } }
                                .buttonStyle(.borderedProminent)
                        }
                        .listRowBackground(SorssyTheme.panel)
                    } else if store.sources.isEmpty {
                        Text("ماكو مصادر مضافة بعد.")
                            .foregroundStyle(SorssyTheme.muted)
                            .listRowBackground(SorssyTheme.panel)
                    } else {
                        ForEach(store.sources) { source in
                            NavigationLink {
                                SourceDetailView(sourceID: source.id, store: store)
                            } label: {
                                SourceRow(source: source)
                            }
                            .listRowBackground(SorssyTheme.panel)
                        }
                    }
                }

                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("الإضافة والحفظ")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                        Text("المصادر الخارجية للقراءة فقط. تغييرات sorssy تُرسل إلى GitHub لتأكيدها بحساب مالك المستودع.")
                            .font(.caption)
                            .foregroundStyle(SorssyTheme.muted)
                    }
                    .padding(.vertical, 6)
                    .listRowBackground(SorssyTheme.panel)
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(SorssyTheme.background)
            .navigationTitle("sorssy")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Button {
                        Task { await store.refresh() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .accessibilityLabel("تحديث المصادر")
                    .disabled(store.isLoading)

                    Button {
                        showingAddSource = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("إضافة مصدر")
                }
            }
            .sheet(isPresented: $showingAddSource) {
                NavigationStack { SourceEditorView() }
            }
            .task {
                if store.sources.isEmpty { await store.refresh() }
            }
        }
        .tint(SorssyTheme.blue)
        .preferredColorScheme(.dark)
    }
}

private struct SourceRow: View {
    let source: SourceModel

    var body: some View {
        HStack(spacing: 13) {
            RemoteIcon(url: source.iconURL, size: 54, fallback: "square.stack.3d.up.fill")
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 7) {
                    Text(source.name).font(.headline).foregroundStyle(.white).lineLimit(1)
                    if source.canEdit {
                        Text("قابل للإدارة")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(SorssyTheme.blue)
                            .padding(.horizontal, 7).padding(.vertical, 3)
                            .background(SorssyTheme.blue.opacity(0.14), in: Capsule())
                    }
                }
                Text(source.loadError ?? (source.subtitle.isEmpty ? "" : source.subtitle))
                    .font(.caption)
                    .foregroundStyle(source.loadError == nil ? SorssyTheme.muted : .orange)
                    .lineLimit(2)
                Text("\(source.apps.count) تطبيق")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(SorssyTheme.blue)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 5)
    }
}

struct SourceDetailView: View {
    let sourceID: String
    @ObservedObject var store: LibraryStore
    @State private var searchText = ""
    @State private var selectedCategory = "الكل"
    @State private var showingAddApp = false

    private var source: SourceModel? { store.source(id: sourceID) }
    private var categories: [String] {
        guard let source else { return [] }
        return Array(Set(source.apps.compactMap { $0.category }.filter { !$0.isEmpty })).sorted()
    }
    private var filteredApps: [IndexedApp] {
        guard let source else { return [] }
        return source.apps.enumerated().compactMap { index, app in
            let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).localizedLowercase
            let matchesQuery = query.isEmpty || [app.name, app.bundleIdentifier, app.category]
                .compactMap { $0?.localizedLowercase }
                .contains { $0.contains(query) }
            let matchesCategory = selectedCategory == "الكل" || app.category == selectedCategory
            return matchesQuery && matchesCategory ? IndexedApp(index: index, app: app) : nil
        }
    }

    var body: some View {
        List {
            if let source {
                Section {
                    HStack(spacing: 12) {
                        RemoteIcon(url: source.iconURL, size: 48, fallback: "square.stack.3d.up.fill")
                        VStack(alignment: .leading, spacing: 3) {
                            Text(source.subtitle.isEmpty ? "مصدر تطبيقات iOS" : source.subtitle)
                                .font(.subheadline)
                                .foregroundStyle(SorssyTheme.muted)
                            Text("\(source.apps.count) تطبيق")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(SorssyTheme.blue)
                        }
                        Spacer()
                        if let url = URL(string: source.definition.url) {
                            Link(destination: url) {
                                Image(systemName: "doc.text.magnifyingglass")
                                    .font(.title3)
                            }
                            .accessibilityLabel("فتح ملف المصدر JSON")
                        }
                    }
                    .padding(.vertical, 5)
                    .listRowBackground(SorssyTheme.panel)
                }

                if let error = source.loadError {
                    Section {
                        Text(error).foregroundStyle(.orange)
                            .listRowBackground(SorssyTheme.panel)
                    }
                } else {
                    Section {
                        if filteredApps.isEmpty {
                            Text("ماكو تطبيقات تطابق البحث.")
                                .foregroundStyle(SorssyTheme.muted)
                                .listRowBackground(SorssyTheme.panel)
                        } else {
                            ForEach(filteredApps) { item in
                                NavigationLink {
                                    AppDetailView(source: source, app: item.app, index: item.index)
                                } label: {
                                    AppRow(app: item.app)
                                }
                                .listRowBackground(SorssyTheme.panel)
                            }
                        }
                    } header: {
                        HStack {
                            Text("التطبيقات · \(filteredApps.count)")
                            Spacer()
                            if source.canEdit {
                                Button {
                                    showingAddApp = true
                                } label: {
                                    Label("إضافة", systemImage: "plus.circle.fill")
                                        .labelStyle(.titleAndIcon)
                                }
                                .font(.caption.weight(.semibold))
                                .textCase(nil)
                            }
                        }
                    }
                }
            } else {
                ProgressView("جارٍ تحديث المصدر…")
                    .listRowBackground(SorssyTheme.panel)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(SorssyTheme.background)
        .navigationTitle(source?.name ?? "المصدر")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "ابحث باسم التطبيق أو الحزمة")
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                if !categories.isEmpty {
                    Menu {
                        Button("كل التصنيفات") { selectedCategory = "الكل" }
                        ForEach(categories, id: \.self) { category in
                            Button(category) { selectedCategory = category }
                        }
                    } label: {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                    }
                    .accessibilityLabel("تصفية حسب التصنيف")
                }
                Button {
                    Task { await store.refresh() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(store.isLoading)
                .accessibilityLabel("تحديث")
            }
        }
        .sheet(isPresented: $showingAddApp) {
            if let source, source.canEdit {
                NavigationStack { AppEditorView(source: source) }
            }
        }
    }
}

private struct AppRow: View {
    let app: CatalogApp

    var body: some View {
        HStack(spacing: 12) {
            RemoteIcon(url: app.iconURL, size: 50, fallback: "app.fill")
            VStack(alignment: .leading, spacing: 4) {
                Text(app.name ?? "بدون اسم")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text([app.category, app.version].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(SorssyTheme.muted)
                    .lineLimit(1)
                if let bundle = app.bundleIdentifier {
                    Text(bundle).font(.caption2).foregroundStyle(SorssyTheme.muted.opacity(0.85)).lineLimit(1)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

struct AppDetailView: View {
    let source: SourceModel
    let app: CatalogApp
    let index: Int
    @State private var showingEditor = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 15) {
                    RemoteIcon(url: app.iconURL, size: 82, fallback: "app.fill")
                    VStack(alignment: .leading, spacing: 6) {
                        Text(app.name ?? "بدون اسم")
                            .font(.title3.bold()).foregroundStyle(.white)
                        Text(app.category ?? "بدون تصنيف")
                            .font(.subheadline).foregroundStyle(SorssyTheme.muted)
                        if let version = app.version {
                            Text("الإصدار \(version)")
                                .font(.caption.weight(.medium)).foregroundStyle(SorssyTheme.blue)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(18)
                .background(SorssyTheme.panel, in: RoundedRectangle(cornerRadius: 18))

                if let bundle = app.bundleIdentifier {
                    detailCard(title: "معرّف الحزمة", value: bundle, ltr: true)
                }
                if let size = app.size, size > 0 {
                    detailCard(title: "الحجم التقريبي", value: ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file))
                }
                if let description = app.localizedDescription, !description.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("الوصف").font(.headline).foregroundStyle(.white)
                        Text(description).font(.subheadline).foregroundStyle(SorssyTheme.muted).textSelection(.enabled)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .background(SorssyTheme.panel, in: RoundedRectangle(cornerRadius: 16))
                }
                if let downloadURL = app.downloadURL, let url = URL(string: downloadURL), AppFields.isHTTPS(downloadURL) {
                    Link(destination: url) {
                        Label("فتح رابط تنزيل IPA", systemImage: "arrow.down.circle.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                    .buttonStyle(.borderedProminent)
                }
                if let versions = app.versions, !versions.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("الإصدارات السابقة").font(.headline).foregroundStyle(.white)
                        ForEach(versions.prefix(8)) { version in
                            HStack {
                                Text(version.version ?? "إصدار")
                                Spacer()
                                if let size = version.size, size > 0 {
                                    Text(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file))
                                        .foregroundStyle(SorssyTheme.muted)
                                }
                                if let urlString = version.downloadURL, let url = URL(string: urlString), AppFields.isHTTPS(urlString) {
                                    Link("تنزيل", destination: url).font(.caption.weight(.semibold))
                                }
                            }
                            .font(.subheadline)
                            .foregroundStyle(.white)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .background(SorssyTheme.panel, in: RoundedRectangle(cornerRadius: 16))
                }
            }
            .padding(16)
        }
        .background(SorssyTheme.background)
        .navigationTitle("تفاصيل التطبيق")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if source.canEdit {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("تعديل") { showingEditor = true }
                }
            }
        }
        .sheet(isPresented: $showingEditor) {
            NavigationStack { AppEditorView(source: source, app: app, appIndex: index) }
        }
    }

    private func detailCard(title: String, value: String, ltr: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.caption).foregroundStyle(SorssyTheme.muted)
            Text(value).font(.subheadline.weight(.medium)).foregroundStyle(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
                .environment(\.layoutDirection, ltr ? .leftToRight : .rightToLeft)
        }
        .padding(15)
        .background(SorssyTheme.panel, in: RoundedRectangle(cornerRadius: 14))
    }
}

struct RemoteIcon: View {
    let url: String?
    let size: CGFloat
    let fallback: String

    var body: some View {
        Group {
            if let url, AppFields.isHTTPS(url), let imageURL = URL(string: url) {
                AsyncImage(url: imageURL) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFill()
                    } else {
                        fallbackView
                    }
                }
            } else {
                fallbackView
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.25, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: size * 0.25, style: .continuous).stroke(.white.opacity(0.10), lineWidth: 1))
    }

    private var fallbackView: some View {
        ZStack {
            LinearGradient(colors: [SorssyTheme.blue.opacity(0.35), SorssyTheme.panel], startPoint: .topLeading, endPoint: .bottomTrailing)
            Image(systemName: fallback).font(.system(size: size * 0.36, weight: .medium)).foregroundStyle(SorssyTheme.blue)
        }
    }
}
