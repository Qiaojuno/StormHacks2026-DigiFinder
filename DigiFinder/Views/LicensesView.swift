import SwiftUI

/// Data and model credits (§7.1).
struct LicensesView: View {
    private struct Entry: Identifiable {
        let name: String
        let license: String
        let detail: String
        var id: String { name }
    }

    private let entries = [
        Entry(name: "Open Food Facts", license: "Open Database License (ODbL)",
              detail: "Product data © Open Food Facts contributors, openfoodfacts.org. "
                + "Changes to the database itself are shared under the same license."),
        Entry(name: "USDA FoodData Central", license: "Public domain",
              detail: "Branded food data from the U.S. Department of Agriculture, fdc.nal.usda.gov."),
        Entry(name: "Ultralytics YOLOv8", license: "AGPL-3.0",
              detail: "Object detection model (YOLOv8s, Open Images V7) by Ultralytics, ultralytics.com."),
    ]

    var body: some View {
        List(entries) { entry in
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.name)
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                Text(entry.license)
                    .font(.subheadline.weight(.semibold))
                Text(entry.detail)
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 6)
            .accessibilityElement(children: .combine)
        }
        .navigationTitle("Licenses")
    }
}
