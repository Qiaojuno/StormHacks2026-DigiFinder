import SwiftUI

/// Data, model and service credits (§7.1), shown at the bottom of Settings.
enum UICredits {
    struct Entry: Identifiable {
        let name: String
        let license: String
        let detail: String
        var id: String { name }
    }

    static let entries = [
        Entry(name: "Google Gemini", license: "Google API terms",
              detail: "Finds the item you ask for. Camera photos are sent only while searching or answering a question."),
        Entry(name: "Ultralytics YOLOv8", license: "AGPL-3.0",
              detail: "Object detection model (YOLOv8s, Open Images V7) by Ultralytics, ultralytics.com."),
        Entry(name: "Open Food Facts", license: "Open Database License (ODbL)",
              detail: "Product data © Open Food Facts contributors, openfoodfacts.org. "
                + "Changes to the database itself are shared under the same license."),
        Entry(name: "USDA FoodData Central", license: "Public domain",
              detail: "Branded food data from the U.S. Department of Agriculture, fdc.nal.usda.gov."),
    ]
}

struct UICreditRow: View {
    let entry: UICredits.Entry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(entry.name)
                .font(.headline)
            Text(entry.license)
                .font(.subheadline.weight(.semibold))
            Text(entry.detail)
                .font(.body)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }
}
