import SwiftUI

extension View {
    /// Accepts files dropped onto the view and shows a frame while they hover.
    func fileDrop(_ target: AppModel.OpenTarget) -> some View {
        modifier(FileDropModifier(target: target))
    }
}

private struct FileDropModifier: ViewModifier {
    @Environment(AppModel.self) private var model
    let target: AppModel.OpenTarget
    @State private var isTargeted = false

    private var message: String {
        switch target {
        case .review: L("Drop to review")
        case .translate: L("Drop to translate")
        case .automatic: L("Drop to open")
        }
    }

    func body(content: Content) -> some View {
        content
            .dropDestination(for: URL.self) { urls, _ in
                model.open(urls, in: target)
            } isTargeted: { isTargeted = $0 }
            .overlay {
                if isTargeted {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.accentColor.opacity(0.08))
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 3, dash: [10, 6]))
                        Label(message, systemImage: "arrow.down.doc")
                            .font(.title2.weight(.semibold))
                            .padding(.horizontal, 20)
                            .padding(.vertical, 12)
                            .background(.regularMaterial, in: Capsule())
                    }
                    .padding(8)
                    .allowsHitTesting(false)
                }
            }
    }
}
