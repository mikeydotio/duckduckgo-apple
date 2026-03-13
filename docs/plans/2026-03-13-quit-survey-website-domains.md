# Quit Survey Domain Selector Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** When the "Websites didn't work" pill is selected in the quit survey, show the last 5 browsed domains as a multi-select list — available in two debug-switchable variants (inline and new step).

**Architecture:** Inject `HistoryCoordinating` into `QuitSurveyViewModel` to compute `recentDomains` at init. Add `selectedDomains` + `activeVariant` to the view model. Extend `QuitSurveyState` with a `.domainSelection` case (Variant B only). Both variants share a `DomainToggleRow` component.

**Tech Stack:** Swift, SwiftUI, Combine, PixelKit, HistoryCoordinating (BrowserServicesKit), NSMenuItem (AppKit)

---

### Task 1: Add `QuitSurveyDomainVariant` and persist it

**Files:**
- Modify: `macOS/DuckDuckGo/QuitSurvey/QuitSurveyDecider.swift`

**Step 1: Write the failing test**

Open `macOS/UnitTests/QuitSurvey/QuitSurveyDeciderTests.swift`.

Add to the `MockQuitSurveyPersistor` class (it already exists in the file):

```swift
var domainVariant: QuitSurveyDomainVariant = .inline
```

Add a new test:

```swift
func testDomainVariantDefaultsToInline() {
    let persistor = MockQuitSurveyPersistor()
    XCTAssertEqual(persistor.domainVariant, .inline)
}
```

**Step 2: Run test to verify it fails**

Run: `macOS/UnitTests` target → `QuitSurveyDeciderTests` in Xcode.
Expected: compile error — `QuitSurveyDomainVariant` not defined.

**Step 3: Add the enum and protocol property**

In `QuitSurveyDecider.swift`, add the enum *before* the `QuitSurveyPersistor` protocol:

```swift
enum QuitSurveyDomainVariant: String {
    case inline
    case newStep
}
```

Add to `QuitSurveyPersistor` protocol (after `alwaysShowQuitSurvey`):

```swift
var domainVariant: QuitSurveyDomainVariant { get set }
```

Add to `QuitSurveyUserDefaultsPersistor`:

1. New key in the `Key` enum:
```swift
case domainVariant = "quit-survey.domain-variant"
```

2. Computed property (add after `alwaysShowQuitSurvey`):
```swift
var domainVariant: QuitSurveyDomainVariant {
    get {
        do {
            guard let raw = try keyValueStore.object(forKey: Key.domainVariant.rawValue) as? String else {
                return .inline
            }
            return QuitSurveyDomainVariant(rawValue: raw) ?? .inline
        } catch {
            Logger.general.error("Failed to read domainVariant from keyValueStore: \(error)")
            return .inline
        }
    }
    set {
        do {
            try keyValueStore.set(newValue.rawValue, forKey: Key.domainVariant.rawValue)
        } catch {
            Logger.general.error("Failed to write domainVariant to keyValueStore: \(error)")
        }
    }
}
```

**Step 4: Run test to verify it passes**

Run `QuitSurveyDeciderTests`. Expected: PASS.

**Step 5: Commit**

```bash
git add macOS/DuckDuckGo/QuitSurvey/QuitSurveyDecider.swift \
        macOS/UnitTests/QuitSurvey/QuitSurveyDeciderTests.swift
git commit -m "feat: add QuitSurveyDomainVariant enum and persistor support"
```

---

### Task 2: Add history + domain state to the ViewModel

**Files:**
- Modify: `macOS/DuckDuckGo/QuitSurvey/QuitSurveyViewModel.swift`

**Step 1: Write failing tests**

Create `macOS/UnitTests/QuitSurvey/QuitSurveyViewModelTests.swift`:

```swift
//
//  QuitSurveyViewModelTests.swift
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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

import History
import XCTest
@testable import DuckDuckGo_Privacy_Browser

// MARK: - Helpers

private func makeEntry(host: String, lastVisit: Date) -> HistoryEntry {
    let url = URL(string: "https://\(host)/path")!
    return HistoryEntry(identifier: UUID(), url: url, title: nil, failedToLoad: false, numberOfTotalVisits: 1, lastVisit: lastVisit, visits: [], blockedTrackingEntities: [], trackersFound: false)
}

// MARK: - Tests

@MainActor
final class QuitSurveyViewModelTests: XCTestCase {

    func testRecentDomainsReturnsLast5UniqueHostsSortedByMostRecent() {
        let now = Date()
        let entries: [HistoryEntry] = [
            makeEntry(host: "a.com", lastVisit: now.addingTimeInterval(-1)),
            makeEntry(host: "b.com", lastVisit: now.addingTimeInterval(-2)),
            makeEntry(host: "c.com", lastVisit: now.addingTimeInterval(-3)),
            makeEntry(host: "d.com", lastVisit: now.addingTimeInterval(-4)),
            makeEntry(host: "e.com", lastVisit: now.addingTimeInterval(-5)),
            makeEntry(host: "f.com", lastVisit: now.addingTimeInterval(-6)),
            makeEntry(host: "a.com", lastVisit: now.addingTimeInterval(-7)), // duplicate of a.com
        ]
        let historyCoordinating = MockHistoryCoordinating(entries: entries)
        let vm = QuitSurveyViewModel(historyCoordinating: historyCoordinating, onQuit: {})

        XCTAssertEqual(vm.recentDomains, ["a.com", "b.com", "c.com", "d.com", "e.com"])
    }

    func testRecentDomainsIsEmptyWhenNoHistory() {
        let historyCoordinating = MockHistoryCoordinating(entries: nil)
        let vm = QuitSurveyViewModel(historyCoordinating: historyCoordinating, onQuit: {})
        XCTAssertTrue(vm.recentDomains.isEmpty)
    }

    func testToggleDomainAddsAndRemovesDomain() {
        let vm = QuitSurveyViewModel(onQuit: {})
        vm.toggleDomain("foo.com")
        XCTAssertTrue(vm.selectedDomains.contains("foo.com"))
        vm.toggleDomain("foo.com")
        XCTAssertFalse(vm.selectedDomains.contains("foo.com"))
    }

    func testShouldShowDomainSelectorWhenWebsitesPillSelectedAndHistoryNonEmpty() {
        let historyCoordinating = MockHistoryCoordinating(entries: [
            makeEntry(host: "a.com", lastVisit: Date())
        ])
        let vm = QuitSurveyViewModel(historyCoordinating: historyCoordinating, onQuit: {})
        vm.selectNegativeResponse()
        vm.toggleOption("websites-didnt-work")
        XCTAssertTrue(vm.shouldShowDomainSelector)
    }

    func testShouldNotShowDomainSelectorWhenHistoryEmpty() {
        let historyCoordinating = MockHistoryCoordinating(entries: [])
        let vm = QuitSurveyViewModel(historyCoordinating: historyCoordinating, onQuit: {})
        vm.selectNegativeResponse()
        vm.toggleOption("websites-didnt-work")
        XCTAssertFalse(vm.shouldShowDomainSelector)
    }

    func testGoBackFromDomainSelectionReturnsToNegativeFeedbackAndClearsDomains() {
        let historyCoordinating = MockHistoryCoordinating(entries: [
            makeEntry(host: "a.com", lastVisit: Date())
        ])
        var persistor = MockQuitSurveyPersistor()
        persistor.domainVariant = .newStep
        let vm = QuitSurveyViewModel(persistor: persistor, historyCoordinating: historyCoordinating, onQuit: {})
        vm.selectNegativeResponse()
        vm.toggleOption("websites-didnt-work")
        vm.proceedToDomainSelection()
        vm.toggleDomain("a.com")
        vm.goBackFromDomainSelection()
        XCTAssertEqual(vm.state, .negativeFeedback)
        XCTAssertTrue(vm.selectedDomains.isEmpty)
    }
}

// MARK: - Mock

final class MockHistoryCoordinating: HistoryCoordinating {
    private let _entries: [HistoryEntry]?
    init(entries: [HistoryEntry]?) { _entries = entries }

    var history: BrowsingHistory? { _entries }
    var historyDictionary: [URL: HistoryEntry]? { nil }
    var historyDictionaryPublisher: AnyPublisher<[URL: HistoryEntry]?, Never> {
        Just(nil).eraseToAnyPublisher()
    }

    func addVisit(of url: URL) {}
    func updateTitleIfNeeded(title: String, url: URL) {}
    func markFailedToLoadUrl(_ url: URL) {}
    func commitChanges(url: URL) {}
    func title(for url: URL) -> String? { nil }
    func burnAll(completion: @escaping () -> Void) { completion() }
    func burnDomains(_ baseDomains: Set<String>, tld: TLD, completion: @escaping () -> Void) { completion() }
    func burnVisits(_ visits: [Visit], completion: @escaping () -> Void) { completion() }
    func loadHistory(onCleanFinished: @escaping () -> Void) {}
}
```

> **Note on `MockHistoryCoordinating`:** `HistoryCoordinating` is defined in `SharedPackages/BrowserServicesKit/Sources/History/HistoryCoordinator.swift`. Check the protocol definition there and make sure the mock satisfies all required methods. Add any missing stubs as no-ops or returning `nil`/empty.

**Step 2: Run tests to verify they fail**

Expected: compile errors — `recentDomains`, `toggleDomain`, `shouldShowDomainSelector`, `proceedToDomainSelection`, `goBackFromDomainSelection` not defined.

**Step 3: Implement in ViewModel**

In `QuitSurveyViewModel.swift`:

1. Add import at top:
```swift
import History
```

2. Add new published properties (after `isSubmitting`):
```swift
@Published private(set) var selectedDomains: Set<String> = []
@Published private(set) var activeVariant: QuitSurveyDomainVariant = .inline
```

3. Add non-published stored property (after `availableOptions`):
```swift
let recentDomains: [String]
```

4. Update `init` signature to accept optional `historyCoordinating`:
```swift
init(
    feedbackSender: FeedbackSenderImplementing = FeedbackSender(),
    persistor: QuitSurveyPersistor? = nil,
    historyCoordinating: HistoryCoordinating? = nil,
    onQuit: @escaping () -> Void
) {
    self.feedbackSender = feedbackSender
    self.persistor = persistor
    self.onQuit = onQuit
    let randomOptions = Array(Self.allOptions.shuffled().prefix(8))
    self.availableOptions = randomOptions + [Self.somethingElseOption]
    self.recentDomains = Self.fetchRecentDomains(from: historyCoordinating)
    self.activeVariant = persistor?.domainVariant ?? .inline
    fireSurveyShown()
}
```

5. Add the static helper (after `init`):
```swift
private static func fetchRecentDomains(from history: HistoryCoordinating?) -> [String] {
    guard let entries = history?.history else { return [] }
    var seen = Set<String>()
    return entries
        .sorted { $0.lastVisit > $1.lastVisit }
        .compactMap { $0.url.host }
        .filter { seen.insert($0).inserted }
        .prefix(5)
        .map { $0 }
}
```

6. Add computed property (after `shouldEnableSubmit`):
```swift
var shouldShowDomainSelector: Bool {
    selectedOptions.contains("websites-didnt-work") && !recentDomains.isEmpty
}
```

7. Add actions (after `toggleOption`):
```swift
func toggleDomain(_ domain: String) {
    if selectedDomains.contains(domain) {
        selectedDomains.remove(domain)
    } else {
        selectedDomains.insert(domain)
    }
}

func proceedToDomainSelection() {
    state = .domainSelection
}

func goBackFromDomainSelection() {
    selectedDomains.removeAll()
    state = .negativeFeedback
}
```

**Step 4: Add `.domainSelection` to the state enum**

In `QuitSurveyViewModel.swift`, update `QuitSurveyState`:

```swift
enum QuitSurveyState: Equatable {
    case initialQuestion
    case positiveResponse
    case negativeFeedback
    case domainSelection
}
```

**Step 5: Run tests to verify they pass**

Run `QuitSurveyViewModelTests`. Expected: all PASS.

**Step 6: Commit**

```bash
git add macOS/DuckDuckGo/QuitSurvey/QuitSurveyViewModel.swift \
        macOS/UnitTests/QuitSurvey/QuitSurveyViewModelTests.swift
git commit -m "feat: add domain state, history injection, and domain selection to QuitSurveyViewModel"
```

---

### Task 3: Update pixel and feedback submission to include domains

**Files:**
- Modify: `macOS/DuckDuckGo/QuitSurvey/QuitSurveyPixels.swift`
- Modify: `macOS/DuckDuckGo/QuitSurvey/QuitSurveyViewModel.swift`

**Step 1: Write failing tests**

Add to `QuitSurveyViewModelTests.swift`:

```swift
func testSubmitFeedbackIncludesDomainsInFeedbackText() {
    let historyCoordinating = MockHistoryCoordinating(entries: [
        makeEntry(host: "a.com", lastVisit: Date())
    ])
    let sender = MockFeedbackSender()
    let vm = QuitSurveyViewModel(feedbackSender: sender, historyCoordinating: historyCoordinating, onQuit: {})
    vm.selectNegativeResponse()
    vm.toggleOption("websites-didnt-work")
    vm.toggleDomain("a.com")
    vm.submitFeedback()
    XCTAssertTrue(sender.lastFeedback?.body?.contains("a.com") == true)
}
```

> **Note on `MockFeedbackSender`:** Look at how `FeedbackSenderImplementing` is defined in `macOS/DuckDuckGo/Feedback/`. The mock only needs to capture the last `Feedback` passed to `sendFeedback`. Also check what property on `Feedback` holds the user text body — it may be `description`, `comment`, or similar.

**Step 2: Run to verify it fails**

Expected: compile error — `MockFeedbackSender` not defined; or test fails since domains not yet included.

**Step 3: Update `QuitSurveyPixels`**

Add a `affectedDomainsKey` and update `quitSurveyThumbsDownSubmission`:

```swift
private static let affectedDomainsKey = "affected_domains"
```

Change the associated value of `quitSurveyThumbsDownSubmission`:
```swift
case quitSurveyThumbsDownSubmission(reasons: String, affectedDomains: String?)
```

Update `parameters`:
```swift
case let .quitSurveyThumbsDownSubmission(reasons, affectedDomains):
    var params = [QuitSurveyPixels.reasonsKey: reasons]
    if let domains = affectedDomains, !domains.isEmpty {
        params[QuitSurveyPixels.affectedDomainsKey] = domains
    }
    return params
```

**Step 4: Update `submitFeedback` in ViewModel**

Replace the existing `submitFeedback()` body with:

```swift
func submitFeedback() {
    isSubmitting = true

    let domainsPrefix = selectedDomains.isEmpty
        ? ""
        : "Affected domains: \(selectedDomains.sorted().joined(separator: ", "))\n\n"
    let combinedText = domainsPrefix + feedbackText

    let feedback = Feedback.from(
        selectedPillIds: Array(selectedOptions),
        text: combinedText,
        appVersion: AppVersion.shared.versionNumber,
        category: .firstTimeQuitSurvey,
        problemCategory: Self.firstTimeQuitSurveyCategory
    )

    let reasons = getReasonsForPixel()
    let affectedDomains = selectedDomains.isEmpty ? nil : selectedDomains.sorted().joined(separator: ",")
    fireThumbsDownPixelSubmission(reasons: reasons, affectedDomains: affectedDomains)

    persistor?.pendingReturnUserReasons = reasons

    feedbackSender.sendFeedback(feedback) { [weak self] in
        DispatchQueue.main.async {
            Logger.general.debug("Quit survey feedback submitted")
            self?.isSubmitting = false
            self?.quit()
        }
    }
}
```

Update the private `fireThumbsDownPixelSubmission` call site:
```swift
private func fireThumbsDownPixelSubmission(reasons: String, affectedDomains: String?) {
    PixelKit.fire(QuitSurveyPixels.quitSurveyThumbsDownSubmission(reasons: reasons, affectedDomains: affectedDomains))
}
```

**Step 5: Run tests to verify they pass**

Expected: all PASS.

**Step 6: Commit**

```bash
git add macOS/DuckDuckGo/QuitSurvey/QuitSurveyPixels.swift \
        macOS/DuckDuckGo/QuitSurvey/QuitSurveyViewModel.swift \
        macOS/UnitTests/QuitSurvey/QuitSurveyViewModelTests.swift
git commit -m "feat: include affected_domains in pixel and feedback body"
```

---

### Task 4: Add `DomainToggleRow` and `QuitSurveyDomainSelectionView` (Variant B view)

**Files:**
- Modify: `macOS/DuckDuckGo/QuitSurvey/QuitSurveyView.swift`

**Step 1: Add `DomainToggleRow`**

Add this new private struct inside `QuitSurveyView.swift`, after the `QuitSurveyOptionRow` struct (around line 211):

```swift
// MARK: - Domain Toggle Row

private struct DomainToggleRow: View {
    let domain: String
    let isSelected: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack {
                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                    .foregroundColor(isSelected ? Color(baseColor: .blue50) : Color(.secondaryLabelColor))
                Text(domain)
                    .systemLabel()
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
```

**Step 2: Add `QuitSurveyDomainSelectionView`**

Add after `QuitSurveyNegativeView` (before the `#if DEBUG` preview section):

```swift
// MARK: - Domain Selection View (Variant B)

private struct QuitSurveyDomainSelectionView: View {
    @ObservedObject var viewModel: QuitSurveyViewModel
    var onResize: ((CGFloat, CGFloat) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header()
            domainList()
            footer()
        }
        .frame(width: QuitSurveyViewController.Constants.negativeWidth)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear {
            // Use a similar height to the negative feedback view
            onResize?(QuitSurveyViewController.Constants.negativeWidth,
                      QuitSurveyViewController.Constants.negativeBaseHeight)
        }
    }

    private func header() -> some View {
        HStack(alignment: .center, spacing: 12) {
            Button {
                viewModel.goBackFromDomainSelection()
            } label: {
                Image(nsImage: DesignSystemImages.Glyphs.Size16.arrowLeft)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 8) {
                Text(UserText.quitSurveyAffectedDomainsTitle)
                    .systemTitle2()

                Text(UserText.quitSurveyAffectedDomainsSubtitle)
                    .systemLabel()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(24)
    }

    private func domainList() -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(viewModel.recentDomains, id: \.self) { domain in
                DomainToggleRow(
                    domain: domain,
                    isSelected: viewModel.selectedDomains.contains(domain)
                ) {
                    viewModel.toggleDomain(domain)
                }
            }
        }
        .padding([.leading, .trailing], 24)
        .padding(.bottom, 24)
    }

    private func footer() -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Divider()
                .background(Color(.separatorColor))
                .frame(maxWidth: .infinity)
                .frame(height: 1)

            Text(UserText.quitSurveyDisclaimer)
                .caption2()
                .multilineTextAlignment(.leading)
                .padding([.leading, .trailing], 24)

            Button {
                viewModel.submitFeedback()
            } label: {
                HStack(spacing: 8) {
                    if viewModel.isSubmitting {
                        ProgressView()
                            .controlSize(.small)
                            .progressViewStyle(.circular)
                    }
                    Text(viewModel.isSubmitting ? UserText.quitSurveySubmitting : UserText.quitSurveySubmitAndQuit)
                }
                .frame(maxWidth: .infinity)
            }
            .disabled(viewModel.isSubmitting)
            .buttonStyle(DefaultActionButtonStyle(enabled: !viewModel.isSubmitting))
            .padding([.leading, .trailing], 24)
            .padding(.bottom, 16)
        }
    }
}
```

**Step 3: Wire `.domainSelection` into `QuitSurveyFlowView`**

In `QuitSurveyFlowView.body`, add a new case to the switch:

```swift
case .domainSelection:
    QuitSurveyDomainSelectionView(viewModel: viewModel, onResize: onResize)
```

**Step 4: Add `UserText` strings**

In `macOS/DuckDuckGo/Common/Localizables/UserText.swift`, add:

```swift
static let quitSurveyAffectedDomainsTitle = NSLocalizedString("quit-survey.affected-domains.title", value: "Which websites had problems?", comment: "Title for quit survey domain selection screen")
static let quitSurveyAffectedDomainsSubtitle = NSLocalizedString("quit-survey.affected-domains.subtitle", value: "Select all that apply", comment: "Subtitle for quit survey domain selection screen")
static let quitSurveyNext = NSLocalizedString("quit-survey.next", value: "Next", comment: "Next button in quit survey")
```

**Step 5: Build and verify no compile errors**

Build `DuckDuckGo-macOS` target. Expected: compiles cleanly.

**Step 6: Commit**

```bash
git add macOS/DuckDuckGo/QuitSurvey/QuitSurveyView.swift \
        macOS/DuckDuckGo/Common/Localizables/UserText.swift
git commit -m "feat: add DomainToggleRow and QuitSurveyDomainSelectionView for variant B"
```

---

### Task 5: Update `QuitSurveyNegativeView` for both variants

**Files:**
- Modify: `macOS/DuckDuckGo/QuitSurvey/QuitSurveyView.swift`

**Step 1: Add domain section height tracking state**

In `QuitSurveyNegativeView`, add a new `@State` variable after `pillsSectionHeight`:

```swift
@State private var domainSectionHeight: CGFloat = 0
```

**Step 2: Add domain section for Variant A (inline)**

In `QuitSurveyNegativeView.body`, after the `if viewModel.shouldShowTextInput { userTextInput() }` block and before `footer()`, add:

```swift
if viewModel.shouldShowDomainSelector && viewModel.activeVariant == .inline {
    inlineDomainSection()
}
```

Add the method:

```swift
private func inlineDomainSection() -> some View {
    VStack(alignment: .leading, spacing: 12) {
        Text(UserText.quitSurveyAffectedDomainsTitle)
            .systemLabel()

        ForEach(viewModel.recentDomains, id: \.self) { domain in
            DomainToggleRow(
                domain: domain,
                isSelected: viewModel.selectedDomains.contains(domain)
            ) {
                viewModel.toggleDomain(domain)
            }
        }
    }
    .padding([.leading, .trailing], 24)
    .padding(.bottom, 8)
    .background(
        GeometryReader { geometry in
            Color.clear
                .onAppear { domainSectionHeight = geometry.size.height }
                .onChange(of: geometry.size) { domainSectionHeight = $0.height }
        }
    )
}
```

**Step 3: Include domain section height in height calculation**

In `calculateTotalHeight()`, add domain height:

```swift
private func calculateTotalHeight() -> CGFloat {
    let baseHeight = ComponentHeights.header + ComponentHeights.footer
    let pillsHeight = pillsSectionHeight > 0 ? pillsSectionHeight : 80
    let textInputHeight = viewModel.shouldShowTextInput ? ComponentHeights.textInputSection : 0
    let domainHeight = (viewModel.shouldShowDomainSelector && viewModel.activeVariant == .inline)
        ? (domainSectionHeight > 0 ? domainSectionHeight : 0)
        : 0
    return baseHeight + pillsHeight + textInputHeight + domainHeight
}
```

**Step 4: Update height recalculation triggers**

In `QuitSurveyNegativeView.body`, add an `onChange` for `selectedOptions` to also recalculate when the domain section appears/disappears. The existing `.onChange(of: viewModel.selectedOptions)` already calls `updateDialogHeight()`, so this is handled. Also add:

```swift
.onChange(of: domainSectionHeight) { _ in
    updateDialogHeight()
}
```

**Step 5: Update submit button for Variant B**

In `QuitSurveyNegativeView.footer()`, change the `Button` action and label to:

```swift
Button {
    if viewModel.activeVariant == .newStep && viewModel.shouldShowDomainSelector {
        viewModel.proceedToDomainSelection()
    } else {
        viewModel.submitFeedback()
    }
} label: {
    HStack(spacing: 8) {
        if viewModel.isSubmitting {
            ProgressView()
                .controlSize(.small)
                .progressViewStyle(.circular)
        }
        Text(submitButtonTitle)
    }
    .frame(maxWidth: .infinity)
}
.disabled(!viewModel.shouldEnableSubmit || viewModel.isSubmitting)
.buttonStyle(DefaultActionButtonStyle(enabled: viewModel.shouldEnableSubmit && !viewModel.isSubmitting))
.padding([.leading, .trailing], 24)
.padding(.bottom, 16)
```

Add a computed property to the struct:

```swift
private var submitButtonTitle: String {
    if viewModel.isSubmitting { return UserText.quitSurveySubmitting }
    if viewModel.activeVariant == .newStep && viewModel.shouldShowDomainSelector {
        return UserText.quitSurveyNext
    }
    return UserText.quitSurveySubmitAndQuit
}
```

**Step 6: Build and run the app manually to verify visual appearance**

Use the debug flag `alwaysShowQuitSurvey` to trigger the survey. Toggle the "websites-didnt-work" pill and confirm the domain section appears inline (Variant A default).

**Step 7: Commit**

```bash
git add macOS/DuckDuckGo/QuitSurvey/QuitSurveyView.swift
git commit -m "feat: update QuitSurveyNegativeView with inline domain section and variant B next button"
```

---

### Task 6: Wire `HistoryCoordinating` through to ViewModel

**Files:**
- Modify: `macOS/DuckDuckGo/QuitSurvey/QuitSurveyView.swift`
- Modify: `macOS/DuckDuckGo/QuitSurvey/QuitSurveyPresenter.swift`
- Modify: `macOS/DuckDuckGo/Application/AppDelegate.swift`

**Step 1: Update `QuitSurveyFlowView` init**

In `QuitSurveyView.swift`, update `QuitSurveyFlowView`:

```swift
struct QuitSurveyFlowView: View {
    @StateObject private var viewModel: QuitSurveyViewModel
    var onResize: ((CGFloat, CGFloat) -> Void)?

    init(
        persistor: QuitSurveyPersistor?,
        historyCoordinating: HistoryCoordinating? = nil,
        onQuit: @escaping () -> Void,
        onResize: ((CGFloat, CGFloat) -> Void)? = nil
    ) {
        self._viewModel = StateObject(wrappedValue: QuitSurveyViewModel(
            persistor: persistor,
            historyCoordinating: historyCoordinating,
            onQuit: onQuit
        ))
        self.onResize = onResize
    }
    // body unchanged
}
```

**Step 2: Update `QuitSurveyPresenter`**

Update `QuitSurveyPresenter` to accept and forward `historyCoordinating`:

```swift
@MainActor
final class QuitSurveyPresenter {
    private let windowControllersManager: WindowControllersManager
    private let persistor: QuitSurveyPersistor
    private let historyCoordinating: HistoryCoordinating?

    init(windowControllersManager: WindowControllersManager,
         persistor: QuitSurveyPersistor,
         historyCoordinating: HistoryCoordinating? = nil) {
        self.windowControllersManager = windowControllersManager
        self.persistor = persistor
        self.historyCoordinating = historyCoordinating
    }
    ...
}
```

In `showSurvey()`, update the `QuitSurveyFlowView` construction to pass `historyCoordinating`:

```swift
let surveyView = QuitSurveyFlowView(
    persistor: persistor,
    historyCoordinating: historyCoordinating,
    onQuit: { ... },
    onResize: { ... }
)
```

**Step 3: Update `AppDelegate`**

In `AppDelegate.swift`, find where `QuitSurveyPresenter` is instantiated (around line 1554) and pass `historyCoordinator`:

```swift
let presenter = QuitSurveyPresenter(
    windowControllersManager: self.windowControllersManager,
    persistor: persistor,
    historyCoordinating: self.historyCoordinator
)
```

**Step 4: Build and verify no compile errors**

Build target `DuckDuckGo-macOS`. Expected: compiles cleanly.

**Step 5: Commit**

```bash
git add macOS/DuckDuckGo/QuitSurvey/QuitSurveyView.swift \
        macOS/DuckDuckGo/QuitSurvey/QuitSurveyPresenter.swift \
        macOS/DuckDuckGo/Application/AppDelegate.swift
git commit -m "feat: wire HistoryCoordinating through presenter to QuitSurveyViewModel"
```

---

### Task 7: Add debug menu item for variant switching

**Files:**
- Modify: `macOS/DuckDuckGo/Menus/MainMenu.swift`
- Modify: `macOS/DuckDuckGo/Menus/MainMenuActions.swift`

**Step 1: Add menu item property to `MainMenu`**

In `MainMenu.swift`, after the `alwaysShowFirstTimeQuitSurvey` property declaration (line 121), add:

```swift
let quitSurveyVariantInlineMenuItem = NSMenuItem(title: "Quit Survey Variant: Inline", action: #selector(MainViewController.setQuitSurveyVariantInline))
let quitSurveyVariantNewStepMenuItem = NSMenuItem(title: "Quit Survey Variant: New Step", action: #selector(MainViewController.setQuitSurveyVariantNewStep))
```

**Step 2: Add to the debug submenu**

In `MainMenu.swift`, find where `alwaysShowFirstTimeQuitSurvey` is placed in the menu builder (around line 834). Add the new items directly after it:

```swift
alwaysShowFirstTimeQuitSurvey
quitSurveyVariantInlineMenuItem
quitSurveyVariantNewStepMenuItem
```

**Step 3: Update `updateMenus()` to reflect current state**

In `MainMenu.swift`, find `updateAlwaysShowFirstTimeQuitSurvey()` and add a sibling method:

```swift
private func updateQuitSurveyVariantMenuItems() {
    let currentVariant = quitSurveyPersistor.domainVariant
    quitSurveyVariantInlineMenuItem.state = currentVariant == .inline ? .on : .off
    quitSurveyVariantNewStepMenuItem.state = currentVariant == .newStep ? .on : .off
}
```

Call it from `updateMenus()` next to the existing `updateAlwaysShowFirstTimeQuitSurvey()` call:

```swift
updateAlwaysShowFirstTimeQuitSurvey()
updateQuitSurveyVariantMenuItems()
```

**Step 4: Verify `quitSurveyPersistor` is accessible in `MainMenu`**

Search `MainMenu.swift` for `quitSurveyPersistor` to confirm it's already a stored property (it's used by `updateAlwaysShowFirstTimeQuitSurvey`). It should already exist — no changes needed.

**Step 5: Add actions to `MainMenuActions.swift`**

In `MainMenuActions.swift`, after `alwaysShowFirstTimeQuitSurvey(_:)` (around line 1654), add:

```swift
@objc func setQuitSurveyVariantInline(_ sender: Any?) {
    let persistor = QuitSurveyUserDefaultsPersistor(keyValueStore: NSApp.delegateTyped.keyValueStore)
    persistor.domainVariant = .inline
}

@objc func setQuitSurveyVariantNewStep(_ sender: Any?) {
    let persistor = QuitSurveyUserDefaultsPersistor(keyValueStore: NSApp.delegateTyped.keyValueStore)
    persistor.domainVariant = .newStep
}
```

**Step 6: Build and manually verify**

Build, open Debug menu → confirm "Quit Survey Variant: Inline" has a checkmark. Click "New Step" → checkmark moves. Trigger the survey via "Always Show First-Time Quit Survey", select the "Websites didn't work" pill, and confirm the correct variant's UX appears.

**Step 7: Commit**

```bash
git add macOS/DuckDuckGo/Menus/MainMenu.swift \
        macOS/DuckDuckGo/Menus/MainMenuActions.swift
git commit -m "feat: add debug menu items for quit survey domain variant switching"
```

---

### Task 8: Add `QuitSurveyViewModelTests` file to Xcode project

**Files:**
- Modify: `macOS/DuckDuckGo-macOS.xcodeproj/project.pbxproj`

**Step 1: Add the test file to the test target in Xcode**

In Xcode, open the `macOS/UnitTests` group. Right-click the `QuitSurvey` subgroup → "Add Files" → select `QuitSurveyViewModelTests.swift`. Ensure the target membership is `macOS Unit Tests`.

Alternatively, in `project.pbxproj` add a reference following the exact same pattern as `QuitSurveyDeciderTests.swift`.

**Step 2: Run all QuitSurvey tests**

Run: `macOS Unit Tests` → filter for `QuitSurvey`.

Expected: all pass — `QuitSurveyDeciderTests` and `QuitSurveyViewModelTests`.

**Step 3: Commit**

```bash
git add macOS/DuckDuckGo-macOS.xcodeproj/project.pbxproj
git commit -m "chore: add QuitSurveyViewModelTests to Xcode project"
```
