//
//  CardVisualLottieRenderer.swift
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

#if os(iOS)

import SwiftUI

/// App-supplied renderer for ``CardVisual/lottie(name:)``.
///
/// `UIComponents` deliberately has no Lottie dependency, so the app injects a renderer (wrapping
/// `Lottie.LottieView`) through the environment. The card view derives the ``CardVisualPlayback``
/// and passes it here; the renderer maps it onto Lottie. When no renderer is injected, card views
/// render nothing for a `.lottie` visual.
public struct CardVisualLottieRenderer {
    private let render: (String, CardVisualPlayback) -> AnyView

    public init(_ render: @escaping (_ name: String, _ playback: CardVisualPlayback) -> AnyView) {
        self.render = render
    }

    func callAsFunction(name: String, playback: CardVisualPlayback) -> AnyView {
        render(name, playback)
    }
}

private struct CardVisualLottieRendererKey: EnvironmentKey {
    static let defaultValue: CardVisualLottieRenderer? = nil
}

public extension EnvironmentValues {
    /// The renderer used to draw ``CardVisual/lottie(name:)``. `nil` (the default) makes card views
    /// render nothing for a `.lottie` visual.
    var cardVisualLottieRenderer: CardVisualLottieRenderer? {
        get { self[CardVisualLottieRendererKey.self] }
        set { self[CardVisualLottieRendererKey.self] = newValue }
    }
}

public extension View {
    /// Injects the renderer used to draw ``CardVisual/lottie(name:)`` in this view's subtree.
    func cardVisualLottieRenderer(_ renderer: CardVisualLottieRenderer) -> some View {
        environment(\.cardVisualLottieRenderer, renderer)
    }
}

#endif
