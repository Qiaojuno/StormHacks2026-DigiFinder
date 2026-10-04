import CoreGraphics
import SwiftUI
import DigiFinderCore

/// Judges' debug overlay (§6): 0.5× frame with YOLO/OCR boxes and the hand point, 1× preview, LiDAR heatmap with
/// steer lanes, Safety and Perception values, capture costs, step, speech line and queue, plus the debug panel.
struct DebugOverlayView: View {
    let model: AppViewModel
    @Environment(\.dismiss) private var dismiss

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 8)]

    var body: some View {
        let debug = model.debug
        let snap = debug.snapshot
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    section("Session") {
                        line("Step: \(model.stepTitle)")
                        line("Speech: \(model.lastMessage.isEmpty ? "–" : model.lastMessage)")
                        line("Walking: \(model.isWalking ? "yes" : "no")")
                        if !snap.speechQueue.isEmpty {
                            line("Queue: " + snap.speechQueue.joined(separator: " | "))
                        }
                    }

                    LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
                        imageTile("0.5× frame + boxes") {
                            UIDetectionCanvas(snapshot: snap)
                        }
                        imageTile("1× preview") {
                            cgImage(debug.previewImage, empty: "No preview")
                        }
                        imageTile("LiDAR heatmap") {
                            cgImage(debug.heatmapImage, empty: "No depth")
                                .overlay(UISteerLanesOverlay(snapshot: snap))
                        }
                    }

                    section("Safety") {
                        ForEach(snap.safetyLines, id: \.self, content: line)
                    }
                    section("Perception") {
                        ForEach(snap.perceptionLines, id: \.self, content: line)
                    }
                    section("Capture") {
                        ForEach(debug.captureLines, id: \.self, content: line)
                        if !debug.depthLine.isEmpty { line(debug.depthLine) }
                    }
                    if !snap.notes.isEmpty {
                        section("Notes") {
                            ForEach(snap.notes, id: \.self, content: line)
                        }
                    }

                    UIDebugPanelView(debug: debug)
                }
                .padding(16)
            }
            .background(UITheme.background.ignoresSafeArea())
            .foregroundStyle(UITheme.foreground)
            .navigationTitle("Debug")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(UITheme.panel, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Close") { dismiss() }
                        .font(.headline)
                        .frame(minWidth: UITheme.minTarget, minHeight: 44)
                        .accessibilityLabel("Close debug")
                }
            }
        }
        .onAppear { debug.setOverlayVisible(true) }
        .onDisappear { debug.setOverlayVisible(false) }
        .task {
            while !Task.isCancelled {
                debug.refresh()
                try? await Task.sleep(for: .milliseconds(500))
            }
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func line(_ text: String) -> some View {
        Text(text)
            .font(.system(.footnote, design: .monospaced))
            .foregroundStyle(UITheme.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func imageTile<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption.bold())
            content()
                .aspectRatio(3.0 / 4.0, contentMode: .fit)
                .frame(maxWidth: .infinity)
                .background(Color(white: 0.08))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(UITheme.border, lineWidth: 1))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
    }

    @ViewBuilder
    private func cgImage(_ image: CGImage?, empty: String) -> some View {
        if let image {
            Image(decorative: image, scale: 1, orientation: .up)
                .resizable()
                .scaledToFit()
        } else {
            Text(empty)
                .font(.caption)
                .foregroundStyle(UITheme.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

/// The 0.5× frame (or a blank one) with YOLO boxes (yellow), OCR boxes (cyan), the hand point (magenta)
/// and the approximate 1× / LiDAR field (dashed, nominal 2× zoom).
struct UIDetectionCanvas: View {
    let snapshot: UIDebugSnapshot

    var body: some View {
        GeometryReader { g in
            let size = g.size
            ZStack(alignment: .topLeading) {
                if let preview = snapshot.preview {
                    Image(decorative: preview, scale: 1, orientation: .up)
                        .resizable()
                        .frame(width: size.width, height: size.height)
                }
                Canvas { ctx, size in
                    func rect(_ r: NormRect) -> CGRect {
                        CGRect(x: r.x * size.width, y: r.y * size.height,
                               width: r.width * size.width, height: r.height * size.height)
                    }
                    let field = CGRect(x: size.width * 0.25, y: size.height * 0.25,
                                       width: size.width * 0.5, height: size.height * 0.5)
                    ctx.stroke(Path(field), with: .color(.white.opacity(0.6)),
                               style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    for d in snapshot.detections {
                        let r = rect(d.box)
                        ctx.stroke(Path(r), with: .color(.yellow), lineWidth: 2)
                        ctx.draw(Text(d.label).font(.caption2.bold()).foregroundColor(.yellow),
                                 at: CGPoint(x: r.minX + 2, y: max(r.minY - 7, 6)), anchor: .leading)
                    }
                    for t in snapshot.textBoxes {
                        ctx.stroke(Path(rect(t.box)), with: .color(.cyan), lineWidth: 1.5)
                    }
                    if let p = snapshot.handPoint {
                        let c = CGPoint(x: p.x * size.width, y: p.y * size.height)
                        ctx.fill(Path(ellipseIn: CGRect(x: c.x - 6, y: c.y - 6, width: 12, height: 12)),
                                 with: .color(.pink))
                    }
                }
            }
        }
    }
}

/// Steer lanes over the heatmap: center corridor and left/right lanes, green clear, red blocked, gray unknown.
struct UISteerLanesOverlay: View {
    let snapshot: UIDebugSnapshot

    var body: some View {
        GeometryReader { g in
            let w = g.size.width / 5
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                lane(snapshot.leftLaneClear).frame(width: w)
                lane(snapshot.corridorNearest.map { $0 >= 1.0 }).frame(width: w)
                lane(snapshot.rightLaneClear).frame(width: w)
                Spacer(minLength: 0)
            }
        }
        .allowsHitTesting(false)
    }

    private func lane(_ clear: Bool?) -> some View {
        let color: Color = clear.map { $0 ? .green : .red } ?? .gray
        return Rectangle()
            .stroke(color.opacity(0.9), lineWidth: 2)
            .background(color.opacity(0.12))
    }
}
