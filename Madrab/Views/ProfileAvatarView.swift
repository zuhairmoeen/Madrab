import SwiftUI
import UIKit

enum ProfileInitials {
    /// Up to two letters derived from the first two whitespace-separated
    /// words of `displayName`, uppercased. Falls back to "?" for a blank
    /// name so the avatar never renders empty.
    static func initials(for displayName: String) -> String {
        let words = displayName.split(separator: " ")
        let letters = words.prefix(2).compactMap { $0.first }
        let result = String(letters).uppercased()
        return result.isEmpty ? "?" : result
    }
}

struct ProfileAvatarView: View {
    let displayName: String
    let imageData: Data?
    var diameter: CGFloat = 44

    var body: some View {
        Group {
            if let imageData, let uiImage = UIImage(data: imageData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    Circle().fill(Color.accentColor.opacity(0.18))
                    Text(ProfileInitials.initials(for: displayName))
                        .font(.system(size: diameter * 0.4, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.accentColor)
                }
            }
        }
        .frame(width: diameter, height: diameter)
        .clipShape(Circle())
        .accessibilityHidden(true)
    }
}
