import SwiftUI

/// Shared pieces of the window, named after the Paper layers.

/// "Right ⌥" drawn as a physical key: light face, hairline border, 2 pt lip.
struct Keycap: View {
    let label: String

    var body: some View {
        Text(label)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(Color.primary.opacity(0.85))
            .padding(.vertical, 8)
            .padding(.horizontal, 14)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
            )
            .shadow(color: Color(nsColor: .separatorColor), radius: 0, x: 0, y: 2)
    }
}

/// Title and subtitle on the left, a fixed 180 pt control lane on the right,
/// hairline underneath. The fixed lane keeps controls aligned across rows.
struct PreferenceRow<Control: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let control: () -> Control

    var body: some View {
        HStack(alignment: .center, spacing: 20) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 15, weight: .medium))
                Text(subtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            control()
                .frame(width: 180, alignment: .trailing)
        }
        .padding(.vertical, 18)
        .overlay(alignment: .bottom) { Divider() }
    }
}

/// Small uppercase caption, as above the permissions list.
struct Caption: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
    }
}
