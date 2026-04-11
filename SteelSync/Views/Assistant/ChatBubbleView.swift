import SwiftUI

struct ChatBubbleView: View {
    let message: AssistantMessage

    var body: some View {
        HStack(alignment: .top, spacing: AppTheme.Spacing.sm) {
            if message.role == .user { Spacer(minLength: 60) }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: message.role == .user ? "person.circle.fill" : "cpu.fill")
                        .font(.caption)
                        .foregroundColor(message.role == .user ? AppTheme.primaryOrange : .blue)
                    Text(message.role == .user ? "You" : "SteelSync Assistant")
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(message.timestamp, style: .time)
                        .font(.caption2)
                        .foregroundColor(AppTheme.tertiaryText)
                }

                Text(LocalizedStringKey(message.content))
                    .font(.callout)
                    .textSelection(.enabled)
                    .padding(AppTheme.Spacing.sm)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(message.role == .user
                                  ? AppTheme.primaryOrange.opacity(0.12)
                                  : Color.gray.opacity(0.12))
                    )
            }

            if message.role == .assistant { Spacer(minLength: 60) }
        }
        .padding(.horizontal, AppTheme.Spacing.sm)
    }
}
