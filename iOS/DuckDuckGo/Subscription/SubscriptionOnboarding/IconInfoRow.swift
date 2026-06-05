//
//  IconInfoRow.swift
//  DuckDuckGo
//
//  Copyright © 2026 DuckDuckGo. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

import SwiftUI
import DesignResourcesKit

struct IconInfoRow: View {

    let icon: Image
    let topAccessory: Text?
    let title: Text
    let description: Text?
    let trailingText: Text?

    init(
        icon: Image,
        topAccessory: Text? = nil,
        title: Text,
        description: Text? = nil,
        trailingText: Text? = nil
    ) {
        self.icon = icon
        self.topAccessory = topAccessory
        self.title = title
        self.description = description
        self.trailingText = trailingText
    }

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 12) {
                icon

                VStack(alignment: .leading, spacing: 2) {
                    if let topAccessory {
                        topAccessory
                    }
                    title
                    if let description {
                        description
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let trailingText {
                trailingText
            }
        }
    }
}

// MARK: - Previews

#Preview("Bare row") {
    IconInfoRow(
        icon: Image(systemName: "globe"),
        title: Text("VPN Connection").font(.headline)
    )
    .padding()
    .background(Color(designSystemColor: .surface))
}

#Preview("As card") {
    IconInfoRow(
        icon: Image(systemName: "globe"),
        title: Text("31.120.130.50").font(.headline),
        description: Text("🇪🇸 Madrid, Spain")
    )
    .padding(16)
    .background(Color(designSystemColor: .background))
    .clipShape(RoundedRectangle(cornerRadius: 24))
    .padding()
    .background(Color(designSystemColor: .surface))
}

#Preview("Card with top accessory") {
    IconInfoRow(
        icon: Image(systemName: "lock.shield"),
        topAccessory: Text("YOUR IP ADDRESS").font(.caption.weight(.semibold)),
        title: Text("31.120.130.50").font(.headline),
        description: Text("🇪🇸 Madrid, Spain")
    )
    .padding(16)
    .background(Color(designSystemColor: .background))
    .clipShape(RoundedRectangle(cornerRadius: 24))
    .padding()
    .background(Color(designSystemColor: .surface))
}

#Preview("With trailing text") {
    IconInfoRow(
        icon: Image(systemName: "lock.shield"),
        title: Text("GPT-5.4").font(.subheadline.weight(.semibold)),
        trailingText: Text("PLUS").font(.caption.weight(.bold)).foregroundColor(.secondary)
    )
    .padding(.horizontal, 16)
    .padding(.vertical, 6)
    .frame(maxWidth: .infinity)
    .background(Color.gray.opacity(0.1))
    .clipShape(RoundedRectangle(cornerRadius: 16))
    .padding()
    .background(Color(designSystemColor: .surface))
}

#Preview("Stacked group") {
    VStack(spacing: 16) {
        IconInfoRow(
            icon: Image(systemName: "globe"),
            title: Text("Your IP Address").font(.headline),
            description: Text("31.120.130.50")
        )
        .padding(16)
        .background(Color(designSystemColor: .background))
        .clipShape(RoundedRectangle(cornerRadius: 24))

        IconInfoRow(
            icon: Image(systemName: "lock.shield"),
            topAccessory: Text("NEW LOCATION").font(.caption.weight(.semibold)),
            title: Text("Your Location").font(.headline),
            description: Text("🇪🇸 Madrid, Spain")
        )
        .padding(16)
        .background(Color(designSystemColor: .background))
        .clipShape(RoundedRectangle(cornerRadius: 24))
    }
    .padding()
    .background(Color(designSystemColor: .surface))
}
