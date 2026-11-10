import FragmentsCore
import SwiftUI

struct PanelRoot: View {
    var model: AppModel

    var body: some View {
        Group {
            switch model.mode {
            case .capture: CaptureView(model: model)
            case .list: ListView(model: model)
            case .detail: DetailView(model: model)
            }
        }
        .frame(width: 680, height: 400)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.quaternary))
    }
}

struct CaptureView: View {
    @Bindable var model: AppModel
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Editor(text: $model.draft, focused: $focused)
            Footer(["⌘↩ keep", "⌘⇧↩ Rex", "esc discard"])
        }
        .padding(16)
        .onAppear { DispatchQueue.main.async { focused = true } }
    }
}

struct DetailView: View {
    @Bindable var model: AppModel
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Editor(text: $model.draft, focused: $focused)
            Footer(["esc back (saves)"])
        }
        .padding(16)
        .onAppear { DispatchQueue.main.async { focused = true } }
    }
}

struct ListView: View {
    var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if model.fragments.isEmpty {
                Spacer()
                Text("No fragments yet. Press n to capture one.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                Spacer()
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 2) {
                            ForEach(Array(model.fragments.enumerated()), id: \.element.id) { index, fragment in
                                Row(
                                    fragment: fragment, hint: model.hints[index], pending: model.pendingHint,
                                    selected: index == model.selection
                                )
                                .id(fragment.id)
                            }
                        }
                    }
                    .onChange(of: model.selection) { _, index in
                        if model.fragments.indices.contains(index) { proxy.scrollTo(model.fragments[index].id) }
                    }
                }
            }
            Footer(["j/k move", "type a label to jump", "↩ open", "n new", "x trash", "esc close"])
        }
        .padding(16)
    }
}

private struct Row: View {
    let fragment: Fragment
    let hint: String
    let pending: String
    let selected: Bool

    var body: some View {
        HStack(spacing: 10) {
            Text(hint)
                .font(.system(.caption, design: .monospaced).bold())
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(
                    !pending.isEmpty && hint.hasPrefix(pending) ? Color.accentColor : Color.secondary.opacity(0.2),
                    in: RoundedRectangle(cornerRadius: 4))
            Image(systemName: fragment.session == nil ? "note.text" : "terminal")
                .foregroundStyle(.secondary)
            Text(fragment.title).lineLimit(1)
            Spacer()
            Text(fragment.createdAt, format: .relative(presentation: .named))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(8)
        .background(selected ? Color.accentColor.opacity(0.2) : .clear, in: RoundedRectangle(cornerRadius: 6))
    }
}

private struct Editor: View {
    @Binding var text: String
    var focused: FocusState<Bool>.Binding

    var body: some View {
        TextEditor(text: $text)
            .font(.system(size: 17))
            .scrollContentBackground(.hidden)
            .focused(focused)
            .accessibilityIdentifier("draft")
    }
}

private struct Footer: View {
    let items: [String]

    init(_ items: [String]) {
        self.items = items
    }

    var body: some View {
        Text(items.joined(separator: "   ·   "))
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}
