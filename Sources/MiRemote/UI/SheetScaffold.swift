import SwiftUI

// MARK: - 统一 sheet 骨架（settings-ui-redesign「Sheet 与对话框统一样式」）

/// 标题 + 可选副标题 + 可选右上角关闭、正文、底部操作区；背景走 `glassSheetBackground()`。
/// 宽高不在骨架里定，由各调用方原样保留。底部左侧说明与 `Spacer` 由调用方放，主按钮在最右。
struct SheetScaffold<Content: View, Footer: View>: View {
    let title: String
    let subtitle: String?
    let onClose: (() -> Void)?
    let closeHelp: String
    let content: Content
    let footer: Footer

    init(title: String, subtitle: String?, onClose: (() -> Void)?, closeHelp: String = "关闭",
         @ViewBuilder content: () -> Content, @ViewBuilder footer: () -> Footer) {
        self.title = title
        self.subtitle = subtitle
        self.onClose = onClose
        self.closeHelp = closeHelp
        self.content = content()
        self.footer = footer()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline).lineLimit(2)
                    if let subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 8)
                if let onClose {
                    Button(action: onClose) {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.cancelAction)
                    .help(closeHelp)
                    .accessibilityLabel("关闭")
                }
            }
            content
            HStack(spacing: 8) { footer }
        }
        .padding(Spacing.sheetPadding)
        .glassSheetBackground()
    }
}

extension SheetScaffold where Footer == EmptyView {
    init(title: String, subtitle: String?, onClose: (() -> Void)?, closeHelp: String = "关闭",
         @ViewBuilder content: () -> Content) {
        self.init(title: title, subtitle: subtitle, onClose: onClose, closeHelp: closeHelp,
                  content: content, footer: { EmptyView() })
    }
}
