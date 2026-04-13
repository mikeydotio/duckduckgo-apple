//
//  fullscreenvideo.js
//  DuckDuckGo
//
//  Copyright © 2020 DuckDuckGo. All rights reserved.
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

// WKWebView doesn't define the fullscreenEnabled property, although it does support webkitEnterFullscreen.
// The workaround is to override fullscreenEnabled (if it isn't already defined), and add a custom implementation of the requestFullscreen function.
// The implementation calls through to webkitEnterFullscreen, which is defined on HTMLVideoElement.

(function () {
    const canEnterFullscreen = HTMLVideoElement.prototype.webkitEnterFullscreen !== undefined
    const browserHasExistingFullScreenSupport = document.fullscreenEnabled || document.webkitFullscreenEnabled
    const pictureInPictureMessageHandler = 'pictureInPictureState'
    let isPictureInPictureActive = false

    // YouTube Mobile won't exit fullscreen correctly if requestFullscreen is overridden. Reference: https://github.com/brave/brave-ios/pull/2002
    const isMobile = /mobile/i.test(navigator.userAgent)

    function postPictureInPictureState(isActive) {
        if (isPictureInPictureActive === isActive) {
            return
        }

        isPictureInPictureActive = isActive
        window.webkit?.messageHandlers?.[pictureInPictureMessageHandler]?.postMessage({
            isActive
        })
    }

    function onPictureInPictureStateChange(video) {
        const presentationMode = typeof video.webkitPresentationMode === 'string' ? video.webkitPresentationMode : null
        const isActive = presentationMode === 'picture-in-picture'

        if (isActive) {
            postPictureInPictureState(true)
        } else if (isPictureInPictureActive) {
            postPictureInPictureState(false)
        }
    }

    function trackVideo(video) {
        if (video.ddgPictureInPictureTracked) {
            return
        }

        video.ddgPictureInPictureTracked = true
        video.addEventListener('enterpictureinpicture', () => postPictureInPictureState(true))
        video.addEventListener('leavepictureinpicture', () => postPictureInPictureState(false))
        video.addEventListener('webkitpresentationmodechanged', () => onPictureInPictureStateChange(video))
    }

    function trackVideos(root) {
        if (!root?.querySelectorAll) {
            return
        }

        root.querySelectorAll('video').forEach(trackVideo)
    }

    if (!browserHasExistingFullScreenSupport && canEnterFullscreen && !isMobile) {
        Object.defineProperty(document, 'fullscreenEnabled', {
            value: true
        })

        HTMLElement.prototype.requestFullscreen = function () {
            const video = this.querySelector('video')

            if (video) {
                video.webkitEnterFullscreen()
                return true
            }

            return false
        }
    }

    trackVideos(document)

    new MutationObserver(mutations => {
        mutations.forEach(mutation => {
            mutation.addedNodes.forEach(node => {
                if (node instanceof HTMLVideoElement) {
                    trackVideo(node)
                } else {
                    trackVideos(node)
                }
            })
        })
    }).observe(document.documentElement, {
        childList: true,
        subtree: true
    })
})()
