import SwiftUI

/// The actual cover supplies the ambient colours, without per-frame image
/// processing or an animation timer. Motion happens only on a cover change.
struct ArtworkAmbientBackground: View {
    let image: NSImage?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        GeometryReader { geometry in
            Color.bgPrimary
                .overlay {
                    if let image, !self.reduceTransparency, self.contrast != .increased {
                        Image(nsImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: geometry.size.width, height: geometry.size.height)
                            .blur(radius: 70, opaque: true)
                            .opacity(0.22)
                            .overlay(Color.bgPrimary.opacity(0.45))
                            .id(ObjectIdentifier(image))
                            .transition(.opacity)
                    }
                }
                .clipped()
                .animation(
                    self.reduceMotion ? nil : .easeInOut(duration: 0.5),
                    value: self.image.map(ObjectIdentifier.init))
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
