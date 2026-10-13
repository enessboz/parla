import SwiftUI
import AppKit

extension Color {
    static let cardBackground = Color(nsColor: .controlBackgroundColor)
}

struct CardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.primary.opacity(0.08)))
    }
}

extension View {
    func card() -> some View { modifier(CardStyle()) }
}

@MainActor
struct StatCard: View {
    let icon: String
    let color: Color
    let value: String
    let label: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color)
                .frame(width: 44, height: 44)
                .background(color.opacity(0.15), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(value).font(.title2.bold()).monospacedDigit()
                Text(label).font(.caption).foregroundStyle(.secondary)
            }
        }
        .card()
    }
}
