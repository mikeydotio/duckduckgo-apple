//
//  translation.js  (POC — extract + write-back)
//  DuckDuckGo
//
//  Copyright © 2026 DuckDuckGo. All rights reserved.
//  Licensed under the Apache License, Version 2.0.
//
//  Defines window.__ddgPOC with two methods, invoked on-demand via evaluateJavaScript:
//    extract()        -> walks the page, records each visible text node, returns [{id, text}].
//    apply(updates)   -> writes new text back into the recorded nodes, matched by id.
//  Node references persist on `window` between the two calls. Throwaway spike — see
//  docs/superpowers/plans/2026-06-18-web-page-translation.md for the real design.
//

(function () {
    'use strict';

    var SKIP_TAGS = { SCRIPT: 1, STYLE: 1, NOSCRIPT: 1, TEXTAREA: 1, TITLE: 1, HEAD: 1 };

    function isVisible(el) {
        if (!el) return false;
        var style = window.getComputedStyle(el);
        if (!style) return true;
        return style.display !== 'none' && style.visibility !== 'hidden' && style.opacity !== '0';
    }

    var api = {
        _nodes: [],

        extract: function () {
            this._nodes = [];
            this._originals = [];
            var out = [];
            var vh = window.innerHeight || document.documentElement.clientHeight;
            var root = document.body || document.documentElement;
            if (!root) return out;
            var walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT, null);
            var node;
            while ((node = walker.nextNode())) {
                var text = (node.nodeValue || '').replace(/\s+/g, ' ').trim();
                if (!text) continue;
                if (!/\p{L}/u.test(text)) { continue; } // skip strings with no letters (punctuation / numbers / symbols)
                var parent = node.parentElement;
                if (!parent || SKIP_TAGS[parent.tagName]) continue;
                if (!isVisible(parent)) continue;
                var rect = parent.getBoundingClientRect();
                var vp = (rect.bottom > 0 && rect.top < vh) ? 1 : 0;
                var id = this._nodes.length;
                this._nodes.push(node);
                this._originals.push(node.nodeValue);
                out.push({ id: id, text: text, vp: vp });
            }
            return out;
        },

        apply: function (updates) {
            if (typeof updates === 'string') { updates = JSON.parse(updates); }
            var count = 0;
            for (var i = 0; i < updates.length; i++) {
                var node = this._nodes[updates[i].id];
                if (node) {
                    node.nodeValue = updates[i].text;
                    count++;
                }
            }
            return count;
        },

        revert: function () {
            var count = 0;
            for (var i = 0; i < this._nodes.length; i++) {
                if (this._nodes[i] && this._originals[i] != null) {
                    this._nodes[i].nodeValue = this._originals[i];
                    count++;
                }
            }
            return count;
        }
    };

    window.__ddgPOC = api;
    return true;
})();
