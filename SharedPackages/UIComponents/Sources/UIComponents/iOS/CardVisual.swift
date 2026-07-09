//
//  CardVisual.swift
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

/// A visual displayed by a card component: either a static image or a Lottie animation.
///
/// `.image` renders statically. `.lottie` is drawn by an app-injected renderer (`UIComponents` has
/// no Lottie dependency); see ``CardVisualLottieRenderer``. Animation is therefore opt-in per use.
public enum CardVisual {
    case image(Image)
    case lottie(name: String)
}

/// The playback a host should apply to a ``CardVisual/lottie(name:)``.
///
/// The card views derive this value (Lottie-free) from appearance and Reduce Motion, so the
/// app-supplied ``CardVisualLottieRenderer`` only has to map it onto a Lottie playback mode.
public enum CardVisualPlayback: Equatable {
    /// Not yet on screen; the animation should not play.
    case idle
    /// Play once, forward, from start to end.
    case playOnce
    /// Freeze on the final frame (used under Reduce Motion).
    case frozenAtEnd

    /// Resolves the playback for a `.lottie` visual: play once on appear, or freeze on the final
    /// frame when Reduce Motion is enabled.
    static func resolve(hasAppeared: Bool, reduceMotion: Bool) -> CardVisualPlayback {
        guard hasAppeared else { return .idle }
        return reduceMotion ? .frozenAtEnd : .playOnce
    }
}

#endif
