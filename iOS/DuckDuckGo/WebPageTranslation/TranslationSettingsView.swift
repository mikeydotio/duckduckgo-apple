//
//  TranslationSettingsView.swift
//  DuckDuckGo
//
//  Copyright © 2026 DuckDuckGo. All rights reserved.
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
import Translation
import UIKit

@available(iOS 18.0, *)
struct TranslationSettingsView: View {

    @StateObject private var viewModel = TranslationSettingsViewModel()

    var body: some View {
        List {
            Section {
                NavigationLink {
                    TranslationTargetPickerView(viewModel: viewModel)
                } label: {
                    HStack {
                        Text("Translate into")
                        Spacer()
                        Text(viewModel.targetDisplayName).foregroundColor(.secondary)
                    }
                }
            }

            Section {
                ForEach(viewModel.rows) { row in
                    TranslationLanguageRowView(row: row) { viewModel.download(row.code) }
                }
            } header: {
                Text("Languages")
            } footer: {
                Text("Translation runs on-device. Source language is detected automatically.")
            }

            Section {
                Button("Manage downloaded languages in iOS Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
            } footer: {
                Text("To remove a downloaded language, open iOS Settings → General → Translate.")
            }
        }
        .navigationTitle("Translation")
        .task { await viewModel.load() }
        // Hidden host that performs the armed download via a live session.
        .translationTask(viewModel.downloadConfiguration) { session in
            await viewModel.performDownload(using: session)
        }
    }
}

@available(iOS 18.0, *)
private struct TranslationLanguageRowView: View {
    let row: TranslationLanguageRow
    let onDownload: () -> Void

    var body: some View {
        HStack {
            Text(row.displayName)
            Spacer()
            accessory
        }
    }

    @ViewBuilder
    private var accessory: some View {
        if row.isDownloading {
            Text("Downloading").foregroundColor(.secondary)
        } else {
            switch row.status {
            case .installed:
                Text("Downloaded").foregroundColor(.secondary)
            case .downloadable:
                Button("Download", action: onDownload)
            case .unavailable:
                Text("Not available").foregroundColor(.secondary)
            }
        }
    }
}

@available(iOS 18.0, *)
private struct TranslationTargetPickerView: View {
    @ObservedObject var viewModel: TranslationSettingsViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List(viewModel.allLanguageCodes, id: \.self) { code in
            Button {
                Task { await viewModel.setTarget(code); dismiss() }
            } label: {
                HStack {
                    Text(translationLanguageDisplayName(forCode: code))
                    Spacer()
                    if code == viewModel.targetCode { Image(systemName: "checkmark") }
                }
            }
            .foregroundColor(.primary)
        }
        .navigationTitle("Translate into")
    }
}
