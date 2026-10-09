import MoneyMatterKit
import SwiftUI

/// Pivot report (web: `analytics/pivot-report`): a row dimension against time buckets, in a grid
/// that scrolls both ways with the row labels pinned. Saved views live in user settings.
struct InsightsPivotScreen: View {
    private static let rowHeight: CGFloat = 44
    private static let labelWidth: CGFloat = 150
    private static let cellWidth: CGFloat = 104

    @Environment(AppServices.self) private var services
    @Environment(SessionStore.self) private var session

    @State private var config = InsightsPivotScreen.defaultConfig()
    @State private var report: LoadState<InsightsPivotReport> = .idle
    @State private var savedViews: [InsightsSavedPivotView] = []
    @State private var expanded: Set<String> = []
    @State private var showsOptions = false
    @State private var isNamingView = false
    @State private var newViewName = ""
    @State private var viewPendingDelete: InsightsSavedPivotView?
    @State private var alert: ErrorAlert?

    private var currencyCode: String {
        if let code = report.value?.currencyCode, !code.isEmpty { return code }
        return session.baseCurrency?.currencyCode ?? "USD"
    }

    static func defaultConfig() -> InsightsSavedPivotViewConfig {
        let today = CalendarDate(date: .now)
        var first = MonthPeriod(year: today.year, month: today.month)
        for _ in 0..<11 { first = first.previous }
        return InsightsSavedPivotViewConfig(
            rowDimension: .category,
            granularity: .monthly,
            measure: .expense,
            from: first.firstDay,
            to: today
        )
    }

    var body: some View {
        content
            .navigationTitle("Pivot Report")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .top) { controls }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { viewsMenu }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Options", systemImage: "slider.horizontal.3") { showsOptions = true }
                }
            }
            .sheet(isPresented: $showsOptions) {
                InsightsPivotOptionsSheet(config: $config)
            }
            .alert("Save View", isPresented: $isNamingView) {
                TextField("Name", text: $newViewName)
                Button("Cancel", role: .cancel) {}
                Button("Save") { Task { await saveCurrentView() } }
                    .disabled(newViewName.trimmingCharacters(in: .whitespaces).isEmpty)
            } message: {
                Text("Saves the rows, columns, period, and filters so you can reopen this report.")
            }
            .confirmationDialog(
                "Delete View?",
                isPresented: Binding(get: { viewPendingDelete != nil }, set: { if !$0 { viewPendingDelete = nil } }),
                titleVisibility: .visible,
                presenting: viewPendingDelete
            ) { view in
                Button("Delete \(view.name)", role: .destructive) { Task { await delete(view) } }
            }
            .errorAlert($alert)
            .task(id: config) { await load() }
            .task { await loadSavedViews() }
            .refreshable { await load() }
    }

    // MARK: Controls

    private var controls: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Menu {
                    Picker("Rows", selection: $config.rowDimension) {
                        ForEach(InsightsPivotRowDimension.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                } label: {
                    InsightsPivotChip(title: "Rows", value: config.rowDimension.title)
                }
                Menu {
                    Picker("Columns", selection: $config.granularity) {
                        ForEach(InsightsPivotGranularity.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                } label: {
                    InsightsPivotChip(title: "Columns", value: config.granularity.title)
                }
                Menu {
                    Picker("Measure", selection: $config.measure) {
                        ForEach(InsightsPivotMeasure.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                } label: {
                    InsightsPivotChip(title: "Measure", value: config.measure.title)
                }
                Button { showsOptions = true } label: {
                    InsightsPivotChip(
                        title: "Period",
                        value: "\(config.from.startDate().formatted(date: .abbreviated, time: .omitted)) – \(config.to.startDate().formatted(date: .abbreviated, time: .omitted))"
                    )
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .background(.bar)
    }

    private var viewsMenu: some View {
        Menu {
            if savedViews.isEmpty {
                Text("No saved views")
            } else {
                Section("Saved Views") {
                    ForEach(savedViews) { view in
                        Button(view.name) {
                            config = view.config
                            expanded = []
                        }
                    }
                }
            }
            Button("Save Current View…", systemImage: "square.and.arrow.down") {
                newViewName = ""
                isNamingView = true
            }
            if !savedViews.isEmpty {
                Menu("Delete View", systemImage: "trash") {
                    ForEach(savedViews) { view in
                        Button(view.name, role: .destructive) { viewPendingDelete = view }
                    }
                }
            }
        } label: {
            Label("Saved Views", systemImage: "bookmark")
        }
    }

    // MARK: Grid

    @ViewBuilder
    private var content: some View {
        switch report {
        case .failed(let error):
            LoadFailedView(error: error) { await load() }
        case .loaded(let pivot) where pivot.isEmpty:
            ContentUnavailableView {
                Label("No Data", systemImage: "tablecells")
            } description: {
                Text("No transactions match this period and filters.")
            } actions: {
                Button("Change Options") { showsOptions = true }
            }
        case .loaded(let pivot):
            grid(pivot)
        case .idle, .loading:
            grid(.placeholder)
                .redactedWhileLoading(true)
        }
    }

    private func grid(_ pivot: InsightsPivotReport) -> some View {
        let rows = pivot.visibleRows(expanded: expanded)
        let peak = rows.flatMap { row in pivot.columns.map { abs(row.value(for: $0)) } }.max() ?? 0
        return ScrollView(.vertical) {
            HStack(alignment: .top, spacing: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    headerCell(Text(config.rowDimension.title), width: Self.labelWidth, alignment: .leading)
                    ForEach(rows) { row in
                        labelCell(row)
                    }
                    headerCell(Text("Total"), width: Self.labelWidth, alignment: .leading)
                }
                .background(Color(.systemBackground))
                .zIndex(1)

                ScrollView(.horizontal) {
                    VStack(alignment: .trailing, spacing: 0) {
                        HStack(spacing: 0) {
                            ForEach(pivot.columns) { column in
                                headerCell(Text(column.title(granularity: config.granularity)), width: Self.cellWidth, alignment: .trailing)
                            }
                            headerCell(Text("Total"), width: Self.cellWidth, alignment: .trailing)
                        }
                        ForEach(rows) { row in
                            HStack(spacing: 0) {
                                ForEach(pivot.columns) { column in
                                    amountCell(row.value(for: column), peak: peak, isHeat: config.heatmap)
                                }
                                amountCell(row.total, peak: peak, isHeat: false)
                                    .fontWeight(.semibold)
                            }
                        }
                        HStack(spacing: 0) {
                            ForEach(pivot.columns) { column in
                                amountCell(pivot.columnTotal(for: column), peak: peak, isHeat: false)
                                    .fontWeight(.semibold)
                            }
                            amountCell(pivot.grandTotal, peak: peak, isHeat: false)
                                .fontWeight(.bold)
                        }
                        .background(Color(.secondarySystemBackground))
                    }
                }
            }
        }
        .accessibilityLabel("Pivot grid with \(rows.count) rows and \(pivot.columns.count) columns")
    }

    private func headerCell(_ text: Text, width: CGFloat, alignment: Alignment) -> some View {
        text
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .frame(width: width, height: Self.rowHeight, alignment: alignment)
            .background(Color(.secondarySystemBackground))
            .accessibilityAddTraits(.isHeader)
    }

    private func labelCell(_ row: InsightsPivotRow) -> some View {
        let isParent = row.kind == .parent
        return Button {
            guard isParent else { return }
            withAnimation {
                if expanded.contains(row.id) { expanded.remove(row.id) } else { expanded.insert(row.id) }
            }
        } label: {
            HStack(spacing: 6) {
                if isParent {
                    Image(systemName: expanded.contains(row.id) ? "chevron.down" : "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
                if let color = Color(hex: row.color) {
                    Circle().fill(color).frame(width: 8, height: 8)
                        .accessibilityHidden(true)
                }
                Text(row.label.isEmpty ? String(localized: "Unknown") : row.label)
                    .font(.subheadline)
                    .lineLimit(1)
            }
            .padding(.leading, row.kind == .child ? 24 : 8)
            .padding(.trailing, 8)
            .frame(width: Self.labelWidth, height: Self.rowHeight, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint(isParent ? Text("Shows or hides subcategories") : Text(""))
    }

    private func amountCell(_ amount: Decimal, peak: Decimal, isHeat: Bool) -> some View {
        let intensity = peak > 0 ? NSDecimalNumber(decimal: abs(amount) / peak).doubleValue : 0
        let tint: Color = config.measure == .income ? .green : .red
        return Text(amount == 0 ? "—" : MoneyFormat.string(amount, currencyCode: currencyCode, digits: 0))
            .font(.subheadline)
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .foregroundStyle(amount == 0 ? Color.secondary : Color.primary)
            .padding(.horizontal, 8)
            .frame(width: Self.cellWidth, height: Self.rowHeight, alignment: .trailing)
            .background(isHeat ? tint.opacity(0.08 + intensity * 0.4) : Color.clear)
    }

    // MARK: Loading

    private func load() async {
        guard let client = services.client else { return }
        if report.value == nil { report = .loading }
        do {
            let pivot = try await client.send(Endpoints.pivotReport(
                from: config.from,
                to: config.to,
                granularity: config.granularity,
                rowDimension: config.rowDimension,
                measure: config.measure,
                accountIds: config.accountIds ?? [],
                categoryIds: config.categoryIds ?? [],
                payeeIds: config.payeeIds ?? []
            ))
            report = .loaded(pivot)
        } catch {
            let apiError = APIError(error)
            guard !apiError.isCancellation else { return }
            if report.value == nil { report = .failed(apiError) } else { alert = ErrorAlert(error) }
        }
    }

    private func loadSavedViews() async {
        guard let client = services.client else { return }
        if let loaded = try? await client.send(Endpoints.savedPivotViews()) {
            savedViews = loaded.views
        }
    }

    private func saveCurrentView() async {
        let name = String(newViewName.trimmingCharacters(in: .whitespaces).prefix(120))
        guard !name.isEmpty else { return }
        let view = InsightsSavedPivotView(name: name, config: config)
        await persist { $0 + [view] }
    }

    private func delete(_ view: InsightsSavedPivotView) async {
        await persist { $0.filter { $0.id != view.id } }
    }

    /// Re-reads the stored list before writing, so a view saved elsewhere since this screen
    /// opened survives: the server replaces the whole array.
    private func persist(_ change: ([InsightsSavedPivotView]) -> [InsightsSavedPivotView]) async {
        guard let client = services.client else { return }
        do {
            let current = try await client.send(Endpoints.savedPivotViews()).views
            let saved = try await client.send(Endpoints.saveSavedPivotViews(change(current)))
            savedViews = saved.views
        } catch {
            alert = ErrorAlert(error)
        }
    }
}

private struct InsightsPivotChip: View {
    let title: LocalizedStringKey
    let value: String

    var body: some View {
        HStack(spacing: 4) {
            Text(title)
                .foregroundStyle(.secondary)
            Text(value)
                .fontWeight(.semibold)
            Image(systemName: "chevron.down")
                .font(.caption2)
                .accessibilityHidden(true)
        }
        .font(.subheadline)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .glassEffect(.regular.interactive(), in: .capsule)
    }
}

/// Period, filters, and display options for the pivot.
private struct InsightsPivotOptionsSheet: View {
    @Binding var config: InsightsSavedPivotViewConfig

    @Environment(ReferenceDataStore.self) private var referenceData
    @Environment(\.dismiss) private var dismiss
    @State private var draft: InsightsSavedPivotViewConfig

    init(config: Binding<InsightsSavedPivotViewConfig>) {
        _config = config
        _draft = State(initialValue: config.wrappedValue)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Layout") {
                    Picker("Rows", selection: $draft.rowDimension) {
                        ForEach(InsightsPivotRowDimension.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    Picker("Columns", selection: $draft.granularity) {
                        ForEach(InsightsPivotGranularity.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    Picker("Measure", selection: $draft.measure) {
                        ForEach(InsightsPivotMeasure.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    Toggle("Heatmap", isOn: $draft.heatmap)
                }
                Section("Period") {
                    DatePicker("From", selection: dateBinding(\.from), in: ...dateBinding(\.to).wrappedValue, displayedComponents: .date)
                    DatePicker("To", selection: dateBinding(\.to), in: dateBinding(\.from).wrappedValue..., displayedComponents: .date)
                }
                Section {
                    ForEach(referenceData.accounts.filter { !$0.isArchived }) { account in
                        let ids = draft.accountIds ?? []
                        Button {
                            var updated = ids
                            if let index = updated.firstIndex(of: account.id) { updated.remove(at: index) } else { updated.append(account.id) }
                            draft.accountIds = updated.isEmpty ? nil : updated
                        } label: {
                            HStack {
                                Text(account.name)
                                    .foregroundStyle(.primary)
                                Spacer()
                                if ids.contains(account.id) {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.tint)
                                }
                            }
                        }
                        .accessibilityAddTraits(ids.contains(account.id) ? .isSelected : [])
                    }
                } header: {
                    Text("Accounts")
                } footer: {
                    Text("No selection includes every account.")
                }
            }
            .navigationTitle("Pivot Options")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") {
                        config = draft
                        dismiss()
                    }
                }
            }
        }
    }

    private func dateBinding(_ keyPath: WritableKeyPath<InsightsSavedPivotViewConfig, CalendarDate>) -> Binding<Date> {
        Binding(
            get: { draft[keyPath: keyPath].startDate() },
            set: { draft[keyPath: keyPath] = CalendarDate(date: $0) }
        )
    }
}

extension InsightsPivotRowDimension {
    var title: String {
        switch self {
        case .category: String(localized: "Category")
        case .subcategory: String(localized: "Subcategory")
        case .payee: String(localized: "Payee")
        case .tag: String(localized: "Tag")
        case .unknown: String(localized: "Category")
        }
    }
}

extension InsightsPivotGranularity {
    var title: String {
        switch self {
        case .yearly: String(localized: "Years")
        case .quarterly: String(localized: "Quarters")
        case .monthly: String(localized: "Months")
        case .weekly: String(localized: "Weeks")
        case .unknown: String(localized: "Months")
        }
    }
}

extension InsightsPivotMeasure {
    var title: String {
        switch self {
        case .expense: String(localized: "Expenses")
        case .income: String(localized: "Income")
        case .unknown: String(localized: "Expenses")
        }
    }
}

extension InsightsPivotColumn {
    /// A localized label built from the bucket start.
    func title(granularity: InsightsPivotGranularity) -> String {
        let date = periodStart.startDate()
        switch granularity {
        case .yearly: return date.formatted(.dateTime.year())
        case .quarterly: return date.formatted(.dateTime.quarter().year())
        case .monthly, .unknown: return date.formatted(.dateTime.month(.abbreviated).year(.twoDigits))
        case .weekly: return date.formatted(.dateTime.month(.abbreviated).day())
        }
    }
}

extension InsightsPivotReport {
    static let placeholder: InsightsPivotReport = {
        let today = CalendarDate(date: .now)
        let columns = (0..<4).map { index in
            InsightsPivotColumn(key: "c\(index)", periodStart: today, periodEnd: today, label: "")
        }
        let rows = (0..<6).map { index in
            InsightsPivotRow(
                id: "r\(index)",
                label: "Category name",
                values: Dictionary(uniqueKeysWithValues: columns.map { ($0.key, Decimal(100 * (index + 1))) }),
                total: Decimal(400 * (index + 1))
            )
        }
        return InsightsPivotReport(columns: columns, rows: rows, columnTotals: [:], grandTotal: 1000, currencyCode: "")
    }()
}
