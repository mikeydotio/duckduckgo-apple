# Voice Chat 1-Click Access Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add two 1-click voice chat entry points — a tab bar button and two omnibar buttons (A/B) — each calling the existing `openNewVoiceChat()` action.

**Architecture:** PoC quality. No new files. All changes are additive to existing classes. Omnibar buttons are feature-flag-gated. Tab bar button is user-preference-gated via the existing `DuckAIChromeButtonsVisibilityManager`.

**Tech Stack:** Swift, AppKit, Combine, PixelKit, FeatureFlags, DesignResourcesKitIcons

---

### Task 1: Add AIChatSubfeature cases (omnibar flags)

**Files:**
- Modify: `SharedPackages/BrowserServicesKit/Sources/PrivacyConfig/Features/PrivacyFeature.swift:469`

- [ ] **Step 1: Add two new subfeature cases after `omnibarWebSearch` (line 469)**

```swift
    /// Enables web search tool in the Duck.ai omnibar
    case omnibarWebSearch

    /// Enables voice chat shortcut button on the left side of the Duck.ai omnibar (right of image attachment)
    case omnibarVoiceChatLeft

    /// Enables voice chat shortcut button on the right side of the Duck.ai omnibar (left of submit)
    case omnibarVoiceChatRight
```

- [ ] **Step 2: Add FeatureFlag cases + Config entries**

In `macOS/LocalPackages/FeatureFlags/Sources/FeatureFlags/FeatureFlag.swift`, after `case aiChatOmnibarWebSearch` (line 271):

```swift
    case aiChatOmnibarWebSearch

    /// Enables the voice chat shortcut button on the left of the Duck.ai omnibar (right of image attachment)
    case aiChatOmnibarVoiceChatLeft

    /// Enables the voice chat shortcut button on the right of the Duck.ai omnibar (left of submit arrow)
    case aiChatOmnibarVoiceChatRight
```

After `case .aiChatOmnibarWebSearch:` in the `var source: Config` switch (around line 551):

```swift
        case .aiChatOmnibarWebSearch:
            Config(defaultValue: .enabled, source: .remoteReleasable(.subfeature(AIChatSubfeature.omnibarWebSearch)), category: .duckAI)
        case .aiChatOmnibarVoiceChatLeft:
            Config(defaultValue: .internalOnly, source: .remoteReleasable(.subfeature(AIChatSubfeature.omnibarVoiceChatLeft)), category: .duckAI)
        case .aiChatOmnibarVoiceChatRight:
            Config(defaultValue: .internalOnly, source: .remoteReleasable(.subfeature(AIChatSubfeature.omnibarVoiceChatRight)), category: .duckAI)
```

- [ ] **Step 3: Build to verify no compile errors**

```bash
xcodebuild -scheme "macOS Browser" -destination "platform=macOS" build 2>&1 | grep -E "error:|BUILD"
```

Expected: `BUILD SUCCEEDED` (or only pre-existing errors, none from new cases)

- [ ] **Step 4: Commit**

```bash
git add SharedPackages/BrowserServicesKit/Sources/PrivacyConfig/Features/PrivacyFeature.swift \
        macOS/LocalPackages/FeatureFlags/Sources/FeatureFlags/FeatureFlag.swift
git commit -m "feat: add omnibar voice chat feature flags"
```

---

### Task 2: Add pixels

**Files:**
- Modify: `macOS/DuckDuckGo/AIChat/AIChatPixel.swift`

- [ ] **Step 1: Add three pixel cases after `aiChatNewVoiceChatMoreOptionsMenu` (around line 313)**

```swift
    /// Event Trigger: User opens a new Duck.ai voice chat from the tab bar button
    case aiChatNewVoiceChatTabBarButton

    /// Event Trigger: User opens a new Duck.ai voice chat from the omnibar left button (right of image attachment)
    case aiChatNewVoiceChatOmnibarLeft

    /// Event Trigger: User opens a new Duck.ai voice chat from the omnibar right button (left of submit)
    case aiChatNewVoiceChatOmnibarRight
```

- [ ] **Step 2: Add pixel name strings in the `var name: String` switch**

Find the block containing `"aichat_new_voice_chat_more_options_menu"` (around line 516) and add after it:

```swift
        case .aiChatNewVoiceChatMoreOptionsMenu:
            return "aichat_new_voice_chat_more_options_menu"
        case .aiChatNewVoiceChatTabBarButton:
            return "aichat_new_voice_chat_tab_bar_button"
        case .aiChatNewVoiceChatOmnibarLeft:
            return "aichat_new_voice_chat_omnibar_left"
        case .aiChatNewVoiceChatOmnibarRight:
            return "aichat_new_voice_chat_omnibar_right"
```

- [ ] **Step 3: Add the three cases to every pixel group switch that includes `aiChatNewVoiceChatMoreOptionsMenu`**

There are four such switch statements (around lines 602, 608, 723, 729). In each one, add the three new cases alongside the existing voice chat cases. For example, each block that looks like:

```swift
.aiChatNewVoiceChatMainMenu,
.aiChatNewVoiceChatMoreOptionsMenu,
```

should become:

```swift
.aiChatNewVoiceChatMainMenu,
.aiChatNewVoiceChatMoreOptionsMenu,
.aiChatNewVoiceChatTabBarButton,
.aiChatNewVoiceChatOmnibarLeft,
.aiChatNewVoiceChatOmnibarRight,
```

- [ ] **Step 4: Build to verify**

```bash
xcodebuild -scheme "macOS Browser" -destination "platform=macOS" build 2>&1 | grep -E "error:|BUILD"
```

- [ ] **Step 5: Commit**

```bash
git add macOS/DuckDuckGo/AIChat/AIChatPixel.swift
git commit -m "feat: add voice chat entry point pixels"
```

---

### Task 3: Extend visibility infrastructure for the tab bar voice button

**Files:**
- Modify: `macOS/DuckDuckGo/TabBar/View/DuckAIChromeButtonsPreferences.swift`
- Modify: `macOS/DuckDuckGo/TabBar/View/DuckAIChromeButtonsVisibilityManager.swift`

- [ ] **Step 1: Add UserDefaults key and property to `DuckAIChromeButtonsPreferences.swift`**

```swift
    enum Key: String {
        case isDuckAIButtonHidden = "duck-ai-chrome.title-button.hidden"
        case isSidebarButtonHidden = "duck-ai-chrome.sidebar-button.hidden"
        case isVoiceChatButtonHidden = "duck-ai-chrome.voice-button.hidden"  // ADD THIS
    }

    // ADD after isSidebarButtonHidden:
    var isVoiceChatButtonHidden: Bool {
        get { boolValue(for: .isVoiceChatButtonHidden) }
        set { set(newValue, for: .isVoiceChatButtonHidden) }
    }
```

- [ ] **Step 2: Add `.voiceChat` case to `DuckAIChromeButtonsVisibilityManager.swift`**

```swift
enum DuckAIChromeButtonType {
    case duckAI
    case sidebar
    case voiceChat   // ADD THIS
}
```

Update `isHidden` switch:

```swift
    func isHidden(_ button: DuckAIChromeButtonType) -> Bool {
        switch button {
        case .duckAI:
            persistor.isDuckAIButtonHidden
        case .sidebar:
            persistor.isSidebarButtonHidden
        case .voiceChat:          // ADD THIS
            persistor.isVoiceChatButtonHidden
        }
    }
```

Update `setHidden` switch:

```swift
    func setHidden(_ hidden: Bool, for button: DuckAIChromeButtonType) {
        let currentValue = isHidden(button)
        guard currentValue != hidden else { return }

        switch button {
        case .duckAI:
            persistor.isDuckAIButtonHidden = hidden
        case .sidebar:
            persistor.isSidebarButtonHidden = hidden
        case .voiceChat:          // ADD THIS
            persistor.isVoiceChatButtonHidden = hidden
        }

        NotificationCenter.default.post(name: .duckAIChromeButtonsVisibilityChanged, object: nil)
    }
```

- [ ] **Step 3: Build to verify**

```bash
xcodebuild -scheme "macOS Browser" -destination "platform=macOS" build 2>&1 | grep -E "error:|BUILD"
```

- [ ] **Step 4: Commit**

```bash
git add macOS/DuckDuckGo/TabBar/View/DuckAIChromeButtonsPreferences.swift \
        macOS/DuckDuckGo/TabBar/View/DuckAIChromeButtonsVisibilityManager.swift
git commit -m "feat: add voiceChat case to chrome button visibility manager"
```

---

### Task 4: Add UserText strings

**Files:**
- Modify: `macOS/DuckDuckGo/Common/Localizables/UserText.swift`

- [ ] **Step 1: Add strings after the existing chrome button strings (around line 645)**

```swift
    static let aiChatChromeHideSidebarButton = NSLocalizedString("aichat.chrome.hide-sidebar-button", value: "Hide Sidebar Button", comment: "Context menu item to hide the Duck.ai sidebar toggle button in the tab bar")
    static let aiChatChromeShowSidebarButton = NSLocalizedString("aichat.chrome.show-sidebar-button", value: "Show Sidebar Button", comment: "Context menu item to show the Duck.ai sidebar toggle button in the tab bar")
    // ADD:
    static let aiChatChromeHideVoiceChatButton = NSLocalizedString("aichat.chrome.hide-voicechat-button", value: "Hide Voice Chat Button", comment: "Context menu item to hide the Duck.ai voice chat button in the tab bar")
    static let aiChatChromeShowVoiceChatButton = NSLocalizedString("aichat.chrome.show-voicechat-button", value: "Show Voice Chat Button", comment: "Context menu item to show the Duck.ai voice chat button in the tab bar")
    static let aiChatOpenVoiceChatButton = NSLocalizedString("aichat.chrome.open-voice-chat-button", value: "New Voice Chat", comment: "Tab bar button tooltip to open a new Duck.ai voice chat")
```

- [ ] **Step 2: Commit**

```bash
git add macOS/DuckDuckGo/Common/Localizables/UserText.swift
git commit -m "feat: add UserText strings for voice chat tab bar button"
```

---

### Task 5: Add `openNewDuckAIVoiceChatTab` to MainViewController

**Files:**
- Modify: `macOS/DuckDuckGo/MainWindow/MainViewController.swift:561`

- [ ] **Step 1: Add method after `openNewDuckAIChatTab` (line 566)**

```swift
    func openNewDuckAIChatTab() {
        let behavior: LinkOpenBehavior = tabCollectionViewModel.selectedTabViewModel?.tab.content == .newtab
            ? .currentTab
            : .newTab(selected: true)
        NSApp.delegateTyped.aiChatTabOpener.openNewAIChat(in: behavior)
    }

    // ADD:
    func openNewDuckAIVoiceChatTab() {
        let behavior: LinkOpenBehavior = tabCollectionViewModel.selectedTabViewModel?.tab.content == .newtab
            ? .currentTab
            : .newTab(selected: true)
        let url = AIChatURLParameters.voiceModeURL(from: AIChatRemoteSettings().aiChatURL)
        NSApp.delegateTyped.aiChatTabOpener.openAIChatTab(with: .url(url), behavior: behavior)
    }
```

- [ ] **Step 2: Build to verify**

```bash
xcodebuild -scheme "macOS Browser" -destination "platform=macOS" build 2>&1 | grep -E "error:|BUILD"
```

- [ ] **Step 3: Commit**

```bash
git add macOS/DuckDuckGo/MainWindow/MainViewController.swift
git commit -m "feat: add openNewDuckAIVoiceChatTab to MainViewController"
```

---

### Task 6: Add voice button to the tab bar chrome

**Files:**
- Modify: `macOS/DuckDuckGo/TabBar/View/TabBarViewController.swift`

This task has four changes in `TabBarViewController.swift`:
1. Add a stored property for the voice button
2. Add the button to `setupDuckAIChromeSegmentedControl()`
3. Add the button action + hide/show actions
4. Update `applyDuckAIChromeButtonVisibility()` and the context menu

- [ ] **Step 1: Add stored property alongside the other duck AI chrome button refs**

Find where `private weak var duckAIChromeTitleButton: MouseOverButton?` is declared and add:

```swift
private weak var duckAIVoiceChatButton: MouseOverButton?
```

- [ ] **Step 2: Build the voice button in `setupDuckAIChromeSegmentedControl()` and insert into the stack**

Inside `setupDuckAIChromeSegmentedControl()`, after the `sidebarButton` setup block (around line 524) and before the `contentStack` creation (line 526), add:

```swift
        let voiceButton = MouseOverButton(frame: .zero)
        voiceButton.translatesAutoresizingMaskIntoConstraints = false
        voiceButton.isBordered = false
        voiceButton.target = self
        voiceButton.action = #selector(duckAIVoiceChatButtonAction(_:))
        voiceButton.sendAction(on: .leftMouseDown)
        voiceButton.image = NSImage(resource: .voice16)
        voiceButton.imageScaling = .scaleProportionallyDown
        voiceButton.setAccessibilityIdentifier("TabBarViewController.duckAIVoiceChatButton")
        voiceButton.setAccessibilityTitle(UserText.aiChatOpenVoiceChatButton)
        voiceButton.toolTip = UserText.aiChatOpenVoiceChatButton
```

Then change the `contentStack` line from:

```swift
        let contentStack = NSStackView(views: [titleButton, divider, sidebarButton])
```

to:

```swift
        let contentStack = NSStackView(views: [titleButton, divider, voiceButton, sidebarButton])
```

Add the voice button height and width constraints alongside the existing ones (around line 544):

```swift
            titleButton.heightAnchor.constraint(equalTo: container.heightAnchor),
            divider.widthAnchor.constraint(equalToConstant: 1),
            voiceButton.heightAnchor.constraint(equalTo: container.heightAnchor),      // ADD
            voiceButton.widthAnchor.constraint(equalToConstant: theme.tabBarButtonSize + 4),  // ADD
            sidebarButton.heightAnchor.constraint(equalTo: container.heightAnchor),
            sidebarButton.widthAnchor.constraint(equalToConstant: theme.tabBarButtonSize + 4)
```

Store the reference and add it to the hover publisher (around lines 560-572):

```swift
        duckAIVoiceChatButton = voiceButton   // ADD after duckAIChromeSidebarButton = sidebarButton

        // Update the hover publisher to also track the voice button
        aiChatButtonHoverCancellable = Publishers.Merge6(       // change Merge4 -> Merge6
            titleButton.publisher(for: \.isMouseOver),
            titleButton.publisher(for: \.isMouseDown),
            voiceButton.publisher(for: \.isMouseOver),          // ADD
            voiceButton.publisher(for: \.isMouseDown),          // ADD
            sidebarButton.publisher(for: \.isMouseOver),
            sidebarButton.publisher(for: \.isMouseDown)
        )
        .receive(on: DispatchQueue.main)
        .sink { [weak self] _ in self?.updateDuckAIChromeDividerState() }
```

- [ ] **Step 3: Add the button action and hide/show actions**

After `duckAITitlebarButtonAction` (around line 917):

```swift
    @objc private func duckAIVoiceChatButtonAction(_ sender: NSButton) {
        if let mainViewController = parent as? MainViewController {
            PixelKit.fire(AIChatPixel.aiChatNewVoiceChatTabBarButton, frequency: .dailyAndStandard)
            mainViewController.openNewDuckAIVoiceChatTab()
            return
        }
        Logger.general.error("TabBarViewController: Failed to find MainViewController to open Duck.ai voice chat")
    }

    @objc private func hideVoiceChatButtonAction() {
        duckAIChromeButtonsVisibilityManager.setHidden(true, for: .voiceChat)
    }

    @objc private func showVoiceChatButtonAction() {
        duckAIChromeButtonsVisibilityManager.setHidden(false, for: .voiceChat)
    }
```

- [ ] **Step 4: Update `applyDuckAIChromeButtonVisibility()` to handle the voice button**

After the `let sidebarHidden = ...` line (line 602), add:

```swift
        let voiceHidden = duckAIChromeButtonsVisibilityManager.isHidden(.voiceChat)
```

After `sidebarButton.isHidden = sidebarHidden` (line 605), add:

```swift
        duckAIVoiceChatButton?.isHidden = voiceHidden
```

Update `container.isHidden` (line 607):

```swift
        container.isHidden = duckAIHidden && sidebarHidden && voiceHidden
```

Update `divider.isHidden` (line 606):

```swift
        divider.isHidden = duckAIHidden || (sidebarHidden && voiceHidden)
```

Also hide the voice button when `shouldDisplayAnyAIChatFeature` is false (inside the early return guard block around line 591):

```swift
            titleButton.isHidden = true
            sidebarButton.isHidden = true
            duckAIVoiceChatButton?.isHidden = true   // ADD
            divider.isHidden = true
            container.isHidden = true
```

- [ ] **Step 5: Add voice chat item to the context menu in `menuNeedsUpdate(_:)`**

After the `sidebarItem` block and before the separator (around line 2680), add:

```swift
        let voiceHidden = duckAIChromeButtonsVisibilityManager.isHidden(.voiceChat)
        let voiceItem = NSMenuItem(
            title: voiceHidden ? UserText.aiChatChromeShowVoiceChatButton : UserText.aiChatChromeHideVoiceChatButton,
            action: voiceHidden ? #selector(showVoiceChatButtonAction) : #selector(hideVoiceChatButtonAction),
            keyEquivalent: ""
        )
        voiceItem.target = self
        menu.addItem(voiceItem)
```

The final menu order becomes: Hide/Show Duck.ai Shortcut → Hide/Show Voice Chat Button → Show/Hide Sidebar Button → separator → Open AI Settings.

- [ ] **Step 6: Build to verify**

```bash
xcodebuild -scheme "macOS Browser" -destination "platform=macOS" build 2>&1 | grep -E "error:|BUILD"
```

- [ ] **Step 7: Commit**

```bash
git add macOS/DuckDuckGo/TabBar/View/TabBarViewController.swift
git commit -m "feat: add voice chat button to tab bar chrome"
```

---

### Task 7: Add omnibar voice buttons (A/B)

**Files:**
- Modify: `macOS/DuckDuckGo/AIChat/AIChatOmnibarContainerViewController.swift`

Two buttons are added conditionally based on feature flags, each checked once at `setupUI()` time (PoC — no runtime flag updates).

- [ ] **Step 1: Add button declarations alongside other button properties (around line 76)**

```swift
    private let submitButton = MouseOverButton()
    private let imageUploadButton = AIChatOmnibarToolButton()
    private let toolsButton = AIChatOmnibarToolButton()
    private let imageGenActiveButton = AIChatOmnibarToolButton()
    private let webSearchActiveButton = AIChatOmnibarToolButton()
    private let modelPickerButton = AIChatModelPickerButton()
    // ADD:
    private let voiceChatLeftButton = AIChatOmnibarToolButton()   // Position A: right of image attachment
    private let voiceChatRightButton = AIChatOmnibarToolButton()  // Position B: left of submit
```

- [ ] **Step 2: Add the action method**

After any existing `@objc` action in the file, add:

```swift
    @objc private func voiceChatButtonClicked() {
        let origin: AIChatPixel = (sender === voiceChatLeftButton)
            ? .aiChatNewVoiceChatOmnibarLeft
            : .aiChatNewVoiceChatOmnibarRight
        PixelKit.fire(origin, frequency: .dailyAndStandard)
        let url = AIChatURLParameters.voiceModeURL(from: AIChatRemoteSettings().aiChatURL)
        NSApp.delegateTyped.aiChatTabOpener.openAIChatTab(with: .url(url), behavior: .newTab(selected: true))
    }
```

Note: `sender` is not a parameter of the action here — simplify as two separate selectors:

```swift
    @objc private func voiceChatLeftButtonClicked() {
        PixelKit.fire(AIChatPixel.aiChatNewVoiceChatOmnibarLeft, frequency: .dailyAndStandard)
        let url = AIChatURLParameters.voiceModeURL(from: AIChatRemoteSettings().aiChatURL)
        NSApp.delegateTyped.aiChatTabOpener.openAIChatTab(with: .url(url), behavior: .newTab(selected: true))
    }

    @objc private func voiceChatRightButtonClicked() {
        PixelKit.fire(AIChatPixel.aiChatNewVoiceChatOmnibarRight, frequency: .dailyAndStandard)
        let url = AIChatURLParameters.voiceModeURL(from: AIChatRemoteSettings().aiChatURL)
        NSApp.delegateTyped.aiChatTabOpener.openAIChatTab(with: .url(url), behavior: .newTab(selected: true))
    }
```

- [ ] **Step 3: Set up Position A button in `setupUI()` after the `imageUploadButton` block (around line 456)**

After:
```swift
        containerView.addSubview(imageUploadButton)
```

Add:
```swift
        // Position A: right of image attachment — gated by feature flag
        let showVoiceLeft = NSApp.delegateTyped.featureFlagger.isFeatureOn(.aiChatOmnibarVoiceChatLeft)
        voiceChatLeftButton.translatesAutoresizingMaskIntoConstraints = false
        voiceChatLeftButton.target = self
        voiceChatLeftButton.action = #selector(voiceChatLeftButtonClicked)
        voiceChatLeftButton.image = DesignSystemImages.Glyphs.Size16.voice
        voiceChatLeftButton.toolTip = "New Voice Chat"
        voiceChatLeftButton.isHidden = !showVoiceLeft
        containerView.addSubview(voiceChatLeftButton)
```

- [ ] **Step 4: Set up Position B button in `setupUI()` after the `modelPickerButton` block (around line 500)**

After:
```swift
        containerView.addSubview(modelPickerButton)
```

Add:
```swift
        // Position B: left of submit — gated by feature flag
        let showVoiceRight = NSApp.delegateTyped.featureFlagger.isFeatureOn(.aiChatOmnibarVoiceChatRight)
        voiceChatRightButton.translatesAutoresizingMaskIntoConstraints = false
        voiceChatRightButton.target = self
        voiceChatRightButton.action = #selector(voiceChatRightButtonClicked)
        voiceChatRightButton.image = DesignSystemImages.Glyphs.Size16.voice
        voiceChatRightButton.toolTip = "New Voice Chat"
        voiceChatRightButton.isHidden = !showVoiceRight
        containerView.addSubview(voiceChatRightButton)
```

- [ ] **Step 5: Add constraints in the `NSLayoutConstraint.activate` block (around line 515)**

Inside the existing `NSLayoutConstraint.activate([...])` call, add at the end before the closing `])`:

```swift
            // Position A constraints (always laid out; hidden when flag off)
            voiceChatLeftButton.leadingAnchor.constraint(equalTo: imageUploadButton.trailingAnchor, constant: Constants.toolButtonSpacing),
            voiceChatLeftButton.widthAnchor.constraint(equalToConstant: Constants.toolButtonSize),
            voiceChatLeftButton.heightAnchor.constraint(equalToConstant: Constants.toolButtonSize),

            // Position B constraints (always laid out; hidden when flag off)
            voiceChatRightButton.trailingAnchor.constraint(equalTo: submitButton.leadingAnchor, constant: -Constants.modelPickerTrailingSpacing),
            voiceChatRightButton.widthAnchor.constraint(equalToConstant: Constants.toolButtonSize),
            voiceChatRightButton.heightAnchor.constraint(equalToConstant: Constants.toolButtonSize),
```

- [ ] **Step 6: Update `toolsLeadingToUploadButton` and `modelPickerButton` trailing constraints**

Find the line (around 599) that sets `toolsLeadingToUploadButton`:

```swift
        toolsLeadingToUploadButton = toolsButton.leadingAnchor.constraint(equalTo: imageUploadButton.trailingAnchor, constant: Constants.toolButtonSpacing)
```

Change to chain off `voiceChatLeftButton` when the flag is on:

```swift
        let voiceLeftEnabled = NSApp.delegateTyped.featureFlagger.isFeatureOn(.aiChatOmnibarVoiceChatLeft)
        toolsLeadingToUploadButton = voiceLeftEnabled
            ? toolsButton.leadingAnchor.constraint(equalTo: voiceChatLeftButton.trailingAnchor, constant: Constants.toolButtonSpacing)
            : toolsButton.leadingAnchor.constraint(equalTo: imageUploadButton.trailingAnchor, constant: Constants.toolButtonSpacing)
        toolsLeadingToUploadButton?.isActive = true
```

Find the line (around 566) that constrains `modelPickerButton` trailing:

```swift
        modelPickerButton.trailingAnchor.constraint(equalTo: submitButton.leadingAnchor, constant: -Constants.modelPickerTrailingSpacing).isActive = true
```

Change to chain off `voiceChatRightButton` when the flag is on:

```swift
        let voiceRightEnabled = NSApp.delegateTyped.featureFlagger.isFeatureOn(.aiChatOmnibarVoiceChatRight)
        if voiceRightEnabled {
            modelPickerButton.trailingAnchor.constraint(equalTo: voiceChatRightButton.leadingAnchor, constant: -Constants.modelPickerTrailingSpacing).isActive = true
        } else {
            modelPickerButton.trailingAnchor.constraint(equalTo: submitButton.leadingAnchor, constant: -Constants.modelPickerTrailingSpacing).isActive = true
        }
```

Also add bottom constraints for both voice buttons in `setupSuggestionsView()` alongside the other tool button bottom constraints (around line 591):

```swift
            toolsButton.bottomAnchor.constraint(equalTo: suggestionsView.topAnchor, constant: -Constants.toolButtonBottomInset),
            imageGenActiveButton.bottomAnchor.constraint(equalTo: suggestionsView.topAnchor, constant: -Constants.toolButtonBottomInset),
            webSearchActiveButton.bottomAnchor.constraint(equalTo: suggestionsView.topAnchor, constant: -Constants.toolButtonBottomInset),
            imageUploadButton.bottomAnchor.constraint(equalTo: suggestionsView.topAnchor, constant: -Constants.toolButtonBottomInset),
            modelPickerButton.bottomAnchor.constraint(equalTo: suggestionsView.topAnchor, constant: -Constants.toolButtonBottomInset),
            voiceChatLeftButton.bottomAnchor.constraint(equalTo: suggestionsView.topAnchor, constant: -Constants.toolButtonBottomInset),   // ADD
            voiceChatRightButton.bottomAnchor.constraint(equalTo: suggestionsView.topAnchor, constant: -Constants.toolButtonBottomInset),  // ADD
```

- [ ] **Step 7: Build to verify**

```bash
xcodebuild -scheme "macOS Browser" -destination "platform=macOS" build 2>&1 | grep -E "error:|BUILD"
```

- [ ] **Step 8: Commit**

```bash
git add macOS/DuckDuckGo/AIChat/AIChatOmnibarContainerViewController.swift
git commit -m "feat: add voice chat shortcut buttons to Duck.ai omnibar (A/B positions)"
```

---

## Testing the PoC

**Tab bar button:**
- Launch the app — the voice icon appears between "Duck.ai" and the sidebar toggle
- Click it → a new voice chat tab opens
- Right-click the Duck.ai area → "Hide Voice Chat Button" appears in context menu
- Hide it → button disappears; menu item changes to "Show Voice Chat Button"

**Omnibar buttons (via internal override):**
- Enable `aiChatOmnibarVoiceChatLeft` or `aiChatOmnibarVoiceChatRight` via internal feature flag override
- Open the Duck.ai new tab page → the mic icon appears in the configured position
- Click it → a new voice chat tab opens
- Check Pixel Kit logs to confirm the right pixel fires (`aichat_new_voice_chat_omnibar_left` or `_right`)
