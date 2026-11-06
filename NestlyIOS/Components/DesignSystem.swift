import NestlyCore
import SwiftUI
import UIKit

// MARK: - Tokens

enum Space {
    static let xs: CGFloat = 4
    static let s: CGFloat = 8
    static let m: CGFloat = 12
    static let l: CGFloat = 16
    static let xl: CGFloat = 24
}

enum Radius {
    static let s: CGFloat = 12
    static let m: CGFloat = 16
    static let l: CGFloat = 20
}

/// One-shot haptics for actions that dismiss their view, where `.sensoryFeedback` would never fire.
@MainActor
enum Haptics {
    static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    static func warning() { UINotificationFeedbackGenerator().notificationOccurred(.warning) }
    static func tap() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
}

// MARK: - Surfaces

/// Grouped content surface. No shadow — it sits on the system grouped background.
struct Card<Content: View>: View {
    var padding: CGFloat = Space.l
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) { content }
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: Radius.l, style: .continuous))
    }
}

/// Header row used by cards: tile, title, optional trailing accessory.
struct CardHeader<Trailing: View>: View {
    let title: String
    let icon: NestlyIcon
    let tint: Color
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: Space.m) {
            IconTile(icon: icon, tint: tint, size: 30)
            Text(title).font(.rounded(.headline))
            Spacer(minLength: 0)
            trailing
        }
    }
}

extension CardHeader where Trailing == EmptyView {
    init(title: String, icon: NestlyIcon, tint: Color) {
        self.init(title: title, icon: icon, tint: tint) { EmptyView() }
    }
}

// MARK: - Buttons

/// Subtle press feedback for tappable cards, tiles and rows.
struct PressableButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Rectangle())
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.snappy, value: configuration.isPressed)
    }
}

/// Full-width filled call to action.
struct PrimaryButtonStyle: ButtonStyle {
    var tint: Color = Palette.accent
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.rounded(.headline))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(tint.opacity(isEnabled ? 1 : 0.4), in: RoundedRectangle(cornerRadius: Radius.m, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(.snappy, value: configuration.isPressed)
    }
}

/// Full-width tinted secondary action.
struct SecondaryButtonStyle: ButtonStyle {
    var tint: Color = Palette.accent

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.rounded(.headline))
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: Radius.m, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.snappy, value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == PressableButtonStyle {
    static var pressable: PressableButtonStyle { PressableButtonStyle() }
}

extension ButtonStyle where Self == PrimaryButtonStyle {
    static var primary: PrimaryButtonStyle { PrimaryButtonStyle() }
}

extension ButtonStyle where Self == SecondaryButtonStyle {
    static var secondary: SecondaryButtonStyle { SecondaryButtonStyle() }
}

extension View {
    /// Hides the bar title (the screen draws its own header) but keeps it for back buttons.
    @ViewBuilder func hiddenNavigationTitle() -> some View {
        if #available(iOS 18.0, *) {
            toolbar(removing: .title)
        } else {
            toolbar { ToolbarItem(placement: .principal) { Color.clear.frame(width: 1, height: 1) } }
        }
    }
}

// MARK: - Small pieces

/// Large selectable tile (diaper type, milk type, …). Selected = soft tint fill and tinted label.
struct SelectTile: View {
    let title: String
    let icon: NestlyIcon
    let selected: Bool
    var tint: Color = Palette.accent
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                icon.image
                    .resizable()
                    .scaledToFit()
                    .frame(width: 22, height: 22)
                    .foregroundStyle(selected ? tint : .secondary)
                Text(title).font(.subheadline.weight(selected ? .semibold : .medium))
                    .foregroundStyle(selected ? tint : .primary)
            }
            .frame(maxWidth: .infinity, minHeight: 72)
            .background(selected ? tint.opacity(0.16) : Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: Radius.s, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.s, style: .continuous)
                    .strokeBorder(selected ? tint.opacity(0.5) : .clear, lineWidth: 1)
            )
        }
        .buttonStyle(.pressable)
        .sensoryFeedback(.selection, trigger: selected)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Compact capsule label, e.g. "Running", "+12%".
struct StatusPill: View {
    let text: String
    var systemImage: String?
    var tint: Color = .secondary

    var body: some View {
        HStack(spacing: 4) {
            if let systemImage { Image(systemName: systemImage).font(.caption2.weight(.bold)) }
            Text(text).font(.caption.weight(.semibold))
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(tint.opacity(0.12), in: Capsule())
    }
}

/// Settings-style row: tile, title, optional value and chevron.
struct IconRow: View {
    let title: String
    let icon: NestlyIcon
    var tint: Color = Palette.accent
    var subtitle: String?
    var value: String?
    var chevron = true

    var body: some View {
        HStack(spacing: Space.m) {
            IconTile(icon: icon, tint: tint, size: subtitle == nil ? 30 : 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                if let subtitle {
                    Text(subtitle).font(.subheadline).foregroundStyle(.secondary).monospacedDigit().lineLimit(2)
                }
            }
            Spacer(minLength: Space.s)
            if let value {
                Text(value).foregroundStyle(.secondary).monospacedDigit().lineLimit(1)
            }
            if chevron {
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
            }
        }
        .foregroundStyle(Color.primary)
        .contentShape(Rectangle())
    }
}

/// Centered empty / welcome / error state.
struct EmptyStateView<Actions: View>: View {
    let icon: NestlyIcon
    var tint: Color = Palette.accent
    let title: String
    var message: String?
    @ViewBuilder var actions: Actions

    var body: some View {
        VStack(spacing: Space.l) {
            IconTile(icon: icon, tint: tint, size: 72)
            VStack(spacing: Space.s) {
                Text(title).font(.rounded(.title2, weight: .bold)).multilineTextAlignment(.center)
                if let message {
                    Text(message).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
            }
            VStack(spacing: Space.m) { actions }
                .padding(.top, Space.s)
        }
        .padding(Space.xl)
        .frame(maxWidth: 420)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

extension EmptyStateView where Actions == EmptyView {
    init(icon: NestlyIcon, tint: Color = Palette.accent, title: String, message: String? = nil) {
        self.init(icon: icon, tint: tint, title: title, message: message) { EmptyView() }
    }
}

/// Child monogram on a soft accent circle; falls back to the baby icon before a name exists.
struct ChildAvatar: View {
    let name: String
    var size: CGFloat = 48

    var body: some View {
        let initial = name.trimmingCharacters(in: .whitespaces).first.map { String($0).uppercased() }
        ZStack {
            Circle().fill(Palette.accent.opacity(0.15))
            if let initial {
                Text(initial)
                    .font(.system(size: size * 0.44, weight: .bold, design: .rounded))
                    .foregroundStyle(Palette.accent)
            } else {
                NestlyIcon.child.image.resizable().scaledToFit()
                    .frame(width: size * 0.5, height: size * 0.5)
                    .foregroundStyle(Palette.accent)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// Small "live" indicator; pulses unless Reduce Motion is on.
struct LiveDot: View {
    var tint: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false

    var body: some View {
        Circle()
            .fill(tint)
            .frame(width: 8, height: 8)
            .background(
                Circle().stroke(tint.opacity(0.5), lineWidth: 2)
                    .scaleEffect(pulse ? 2.2 : 1)
                    .opacity(pulse ? 0 : 1)
            )
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeOut(duration: 1.4).repeatForever(autoreverses: false)) { pulse = true }
            }
            .accessibilityHidden(true)
    }
}
