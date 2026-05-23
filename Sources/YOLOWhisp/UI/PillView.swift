import SwiftUI

struct PillView: View {
    let state: PillState
    let audioLevel: Float

    private let barCount = 6

    var body: some View {
        HStack(spacing: 3) {
            if state == .recording {
                ForEach(0..<barCount, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.white.opacity(0.8))
                        .frame(width: 4, height: barHeight(for: i))
                }
            } else if state == .processing {
                ProgressView()
                    .scaleEffect(0.6)
                    .tint(.white)
                Text("Processing...")
                    .font(.caption)
                    .foregroundColor(.white)
            } else {
                Image(systemName: "waveform")
                    .foregroundColor(.white)
                Text("YOLOWhisp")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.7))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(backgroundColor)
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .strokeBorder(state == .dragMode ? Color.white : Color.clear, lineWidth: 2)
        )
        .opacity(state == .dragMode ? 0.7 : 1.0)
        .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
    }

    private var backgroundColor: Color {
        switch state {
        case .idle: return Color(.darkGray)
        case .recording: return Color.red
        case .processing: return Color.blue
        case .dragMode: return Color(.darkGray)
        }
    }

    private func barHeight(for index: Int) -> CGFloat {
        let base: CGFloat = 6
        let maxHeight: CGFloat = 24
        let stagger = Float(index) * 0.15
        let level = max(0, min(1, audioLevel + stagger * (index % 2 == 0 ? 1 : -1)))
        return base + CGFloat(level) * (maxHeight - base)
    }
}
