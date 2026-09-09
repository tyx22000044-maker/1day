# 1Day — Swiss Ledger visual pass (handoff)

**Prepared:** 2026-09-09 · **For:** any coding agent (Claude Code or otherwise) picking this up as a fresh session · **Repo:** `/Volumes/ExtraStorage/XcodeProject/1Day` (**no git yet at all** — see "Git state" below)

This is the **4th of 7** app-level handoffs for the same family-wide direction (1Cash, 1Life, 1Track already have equivalent packages, prepared the same day). Each app's implementation is independent — nothing here depends on the others landing first or in a particular way.

---

## 0. The one rule that matters most

> **This is a re-skin, not a redesign.** Change colors, type, corner radii, borders/shadows, spacing tokens, and the visual treatment of status tags/buttons/panels. Do **not** change:
> - which tab shows which content, or the tab order (Today · Plan · AI · Notes · Settings stays exactly as-is)
> - navigation structure (NavigationStack usage, sheet vs. push, screen hierarchy)
> - what data appears where, what any button/row/gesture *does*
> - view models, services, SwiftData models, business logic of any kind
> - existing feature behavior, copy/wording of user-facing content (unless a string is purely a design artifact like a status-tag label)
>
> If implementing the new visual language seems to require touching interaction logic, **stop and flag it rather than deciding unilaterally** — that's a product decision, not a styling one.

**Extra caution for this specific app:** 1Day is explicitly still in **V1.0 MVP** development (per its own `README.md`) — notifications, full task editing, AI task creation, JSON backup, and localization are all still active work-in-progress. Move carefully around anything that looks like an unfinished feature rather than a finished screen; if a view looks incomplete, that's probably intentional MVP scoping, not something to "fix" as part of a visual pass.

---

## 1. Background (context only, nothing here needs to be redone)

1Day is part of a 7-app family ("1App Family": 1Cash, 1Day, 1Fit, 1Life, 1Parcel, 1Pet, 1Track) that mostly shares a design-token system called Family UI V2, with `1Life/1Life/Extensions.swift` as the reference implementation the others are diffed against. The user chose a new direction called **"Swiss Ledger"** (cold, grid-first, grotesk type, single accent, hairline borders) to replace the current warm-parchment Family UI V2 across the whole family, out of 5 proposed directions. Nine mockup screens were built to pressure-test it, then the user asked for this direction to be handed off app-by-app to separate coding sessions, one at a time, pure visual re-skin only.

## 2. Scope for *this* handoff

**In scope:** `/Volumes/ExtraStorage/XcodeProject/1Day` only.

**Good news for how contained this pass can be:** 1Day already went through a full Family UI V2 alignment pass (documented in `1Day/docs/1LIFE_UI_VISUAL_CONSISTENCY_REVIEW.md` §12, dated 2026-07-15) — tab titles, AI Chat structure, Settings information architecture, and sheet/form layouts were all brought in line with 1Life's patterns, and Today/Plan already share one row component (`FamilyTaskRow`, in `Components/SystemPanel.swift`). That means this pass is largely a *token-value* change cascading through already-consistent structure, not a screen-by-screen rebuild. Confirm this is still accurate by reading the current source before assuming.

Priority order:
1. Shared design tokens — `1Day/1Day/Extensions.swift`.
2. Today — `1Day/1Day/Views/Today/TodayView.swift` — this app's flagship screen for the direction; see `mockups/1day-today.html`. Plan (`Views/Plan/PlanListView.swift`) shares the same `FamilyTaskRow` component, so it should follow along once Today and the shared row component are done — verify rather than assume.
3. Settings — `1Day/1Day/Views/Settings/SettingsView.swift` — see `mockups/settings-shared.html`.
4. AI Chat's confirmation-card visual treatment — `1Day/1Day/Views/AIChat/*.swift` (`AIChatView`, `AIChatComponents`, `AIChatFormatting`; leave `SpeechInputController.swift` and `AIImagePicker.swift` alone, those are capture mechanics not visuals) — see `mockups/aichat-shared.html`. Only the confirmation card's *look* — the mockup shows a parsed 1Cash transaction; 1Day's equivalent is a parsed task/note draft.
5. Notes (`Views/Notes/NotesListView.swift`, `NoteEditorView.swift`) — lower priority, not individually mocked up, lean on the tokens + patterns from steps 1–4.

**Out of scope:** 1Cash, 1Fit, 1Life, 1Parcel, 1Pet, 1Track. Do not edit anything outside `/Volumes/ExtraStorage/XcodeProject/1Day`.

## 3. Reference mockups (attached)

`mockups/` has 9 standalone, dependency-free HTML files — open directly in a browser, no server needed. Static visual references (plain HTML/CSS), not code to port literally.

| File | What it shows | Relevant to this task? |
|---|---|---|
| `mockups/1day-today.html` | 1Day's Today screen in Swiss Ledger (overdue / today / notes grouping) | **Yes — primary reference** |
| `mockups/settings-shared.html` | Settings screen (shown as a 1Cash instance — same structure applies, swap content per §4/§5) | **Yes — primary reference for structure**, not literal content |
| `mockups/aichat-shared.html` | AI Chat: bubbles + one structured confirmation card (shown with a 1Cash transaction — 1Day's equivalent is a parsed task/note) | **Yes — primary reference for structure**, not literal content |
| `mockups/1cash-ledger.html`, `1fit-closet.html`, `1life-dashboard.html`, `1parcel-parcels.html`, `1pet-today.html`, `1track-subscriptions.html` | The other 6 apps' flagship screens | Context only. **Not part of this task.** |

The accent color in these exports is already resolved to a literal `#C4321F` — see §5, it's not finalized.

## 4. Current state — what's already real in the code

Confirmed directly from `1Day/1Day/Extensions.swift`:

```swift
enum FamilyUI {
    // pageBackground: light #F4F1EB (warm parchment) / dark #161410 (warm near-black)
    // panelBackground: light white / dark #1F1D1A
    // panelMutedBackground: light #F0EDE7 / dark #2A2724
    // panelBorder: black 14% (light) / white 12% (dark)
    // divider: black 10% (light) / white 8% (dark)
    static let accent = Color(hex: "1e4ed8")       // blue
    static let accentDeep = Color(hex: "173a98")   // darker blue — not present in 1Cash/1Life/1Track's copy, 1Day-specific addition, check what it's used for (likely a pressed/emphasis state) before deciding its Swiss Ledger equivalent
    static let success = Color(hex: "2f7a63")
    static let warning = Color.orange
    static let danger = Color.red
    static let subtleText = Color(.systemGray)
    static let panelCornerRadius: CGFloat = 12
    static let controlCornerRadius: CGFloat = 10
    static let badgeCornerRadius: CGFloat = 6
    static let iconBoxSize: CGFloat = 34
}
```

Same `FamilyTypography` (all `design: .rounded`) and `AppSpacing` present. Unlike 1Cash/1Life/1Track, **no separate legacy `AppCornerRadius` enum was found** in this file — worth a quick project-wide search before assuming radii are only ever set via `FamilyUI.panelCornerRadius`/`controlCornerRadius`.

**Known components** (confirmed present in `1Day/1Day/Components/`): `SystemPanel.swift` (also contains `FamilyListIconBox` and the shared `FamilyTaskRow` used by both Today and Plan), `PrimaryButton.swift`, `AppSettingsRow.swift`, `AppEmptyStateView.swift`, `AppErrorBanner.swift`, `SectionHeader.swift`, `UserAvatarView.swift`, `SystemTextField.swift`.

**Status-tag vocabulary — not explicitly documented for 1Day.** The mockup uses `OVERDUE` / `OPEN` / `SCHEDULED` / `DONE` / `DRAFT` (for notes) as reasonable guesses. `FamilyTaskRow` already renders a priority field and an overdue badge per the July 2026 alignment doc — **check its actual current visual treatment and the real `Task` model's field names before finalizing tag strings**, use those rather than the mockup's guesses if they differ. If task priority is currently color-coded (high/medium/low), treat those as small-scale semantic colors — same restrained, muted, label-only treatment as `danger`/`warning`/`success` get elsewhere in this direction, not a reason to introduce new accent hues.

## 5. Target design tokens — Swiss Ledger

Same family-wide tokens as every other app's pass (kept identical across all 7 handoffs on purpose):

| Token | Light | Notes |
|---|---|---|
| Page / paper background | `#FAFAF7` | replaces `#F4F1EB` |
| Ink (primary text, borders, rules) | `#0B0B0A` | replaces near-black `.primary` |
| Ink, soft (secondary text) | `#6E6E68` | |
| Ink, faint (tertiary / inactive tab labels) | `#9C9B90` | |
| Hairline, regular | `rgba(11,11,10,0.14)` | panel/section borders |
| Hairline, subtle | `rgba(11,11,10,0.10)` | row dividers |
| Hairline, strong | `rgba(11,11,10,0.16)` | tab bar top border |
| **Accent (single signal color)** | `#C4321F` | **open decision, same as every app — see below** |
| Corner radius, panels | `0–4pt` | down from 12pt |
| Corner radius, controls/tags | `0–2pt` | down from 10pt; tags are rectangles, not capsules |
| Borders vs. shadows | hairline `1px` borders, **no** drop shadows | |
| Numerals | tabular/monospaced digits wherever they appear (`.monospacedDigit()`) | task counts, dates |
| Type | a grotesk, not `design: .rounded` | see open decision below |
| Status tags | outlined rectangle, uppercase, ~8.5–9pt, tracked | replaces filled/toned status badges |

**Dark mode — not yet designed**, same gap as every app in this family: near-black paper, near-white ink, white-alpha hairlines, brightened accent — follow the existing `UIColor { traitCollection in ... }` dynamic-provider pattern already in `Extensions.swift`.

**Two open decisions, same as every app in this family — don't decide unilaterally, confirm or ask:**

1. **Accent color** — mockups default to `#C4321F` (print red); alternates considered were `#0B0B0A` (ink only), `#1E4ED8` (family's existing blue), `#8A6A1F` (muted gold). Not finalized.
2. **Typeface** — mockups use Archivo (web-only) for preview purposes. For SwiftUI: either drop `design: .rounded` and use plain system San Francisco (lower risk, recommended default), or bundle a real grotesk like Archivo (OFL, embeddable, more distinctive, adds app size + a loading step).

## 6. Suggested implementation order

1. Confirm the two open decisions in §5 (or ask before assuming).
2. Update the token layer only (`Extensions.swift`) — because Today/Plan already share `FamilyTaskRow` and most screens already route through `FamilyUI`/`SystemPanel` (see §2), this step should cascade through most of the app.
3. Update the status-tag styling used by `FamilyTaskRow`/`FamilyListIconBox` to the outlined-rectangle treatment.
4. Verify Today and Plan against `mockups/1day-today.html` — since they share a row component, fixing it once should fix both; confirm rather than assume.
5. Checkpoint / review before continuing.
6. Settings, then AI Chat confirmation card, then Notes if there's runway.

## 7. Definition of done for this pass

- [ ] Project still builds and runs (iOS 17+ target as currently configured).
- [ ] No changes to `Models/`, `ViewModels/`, `Services/` — unless a file is *purely* a hardcoded color/style constant with no logic.
- [ ] Tab bar order, tab contents, and navigation flow are structurally identical to before.
- [ ] Every existing user-facing string, gesture, and button action still does exactly what it did before.
- [ ] Task counts and any dates line up on tabular figures where stacked.
- [ ] Status tags are outlined, not filled; no rounded pill shapes remain in the touched screens.
- [ ] Dark mode still works (draft values acceptable pending review) — don't regress to light-only.
- [ ] Existing tests (`1DayTests` if present) still pass unchanged.
- [ ] A couple of real-app screenshots compared against the matching `mockups/*.html`.

## 8. Git

**No git repository exists yet at `/Volumes/ExtraStorage/XcodeProject/1Day`.** Before making any changes: `git init`, then commit the current state as-is (e.g. `chore: baseline before Swiss Ledger visual pass`), so this pass becomes a reviewable, revertable diff instead of starting from nothing. No remote — don't add one or push without asking.

## 9. If you're continuing in Claude Code specifically

No design-exploration skills needed (`taste`, `design`) — the direction is already specified above, this is implementation against a spec. Running `code-review` on the diff before calling this done is reasonable given the size of the change. On another platform: whatever this project's normal lint/build/test checks are, plus a manual diff read against the "definition of done" list.

## 10. Optional extra reference (only if this session can reach claude.ai)

- 5-direction comparison this was chosen from: `https://claude.ai/code/artifact/aa0d9c88-22c0-42d5-8d4e-937702b035a8`
- Full 9-screen canvas (live accent-color swatch per screen): `https://claude.ai/code/artifact/7d9055b8-7eff-45ad-b5bf-58e01e16ad60`
