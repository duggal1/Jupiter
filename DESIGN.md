# Purge — Design record (read before writing any UI)

> Superseded. The build now follows the Superflow `DESIGN.md` spec
> (tokens, AppType, pixels, components) — see `DESIGN_NOTES.md` for the
> five-line brief. This file is the earlier Tokens draft, kept for history.

## 1. Structure (before pixels)

**Purpose.** Find and remove the junk macOS hides from Storage settings, measured in
allocated bytes (st_blocks × 512), safe by default, deleted via Trash.

**Primary thing.** *How much can I reclaim, and what is it?*
One number dominates: **total selected reclaimable bytes** (largest type on screen).
Everything else supports that decision: the category breakdown underneath.

**Hierarchy.**
1. Reclaimable total + selected breakdown (footer, always visible once scanned).
2. Categories sorted descending by allocated size (sidebar).
3. Items inside a category (detail + expandable sidebar rows).
4. Status lines: scanning / needs-FDA / deleted, quiet caption weight.

**Layout.** `NavigationSplitView`: sidebar (strip + categories, DisclosureGroups) /
detail (selected category header + item list + FDA banner slot). No dashboard cards.
Footer bar (selection summary + Clean) lives in detail column, above the toolbar.
Toolbar holds: Scan/Rescan, Select-safe / Clear only. No settings.

**State machine (all states designed).**
- notScanned: sidebar shows empty caption "Not scanned yet"; detail shows prompt + Scan button.
- scanning: strip fills progressively left→right as categories land; per-category rows
  show `ProgressView` + "Scanning…"; a Cancel appears; partial results stay usable.
- results: sorted categories, expandable, selectable; footer shows selected total.
- needsFDA: banner in detail (one sentence + System Settings deep link); protected
  categories show "Requires Full Disk Access" instead of items; rest still works.
- deleting: items animate out one-by-one as Trash confirms; footer shows progress.
- cleaned: footer shows "Freed X" + "Failed Y" (if any); scanned totals refresh.
- error: inline caption on the failing row; global errors surface in footer.

**Copy.** Short, verb-led, no marketing voice. "Scan", "Clean X", "Select safe",
"Move to Trash", "Open System Settings".

## 2. Tokens (decided once, used everywhere)

- Spacing: 4, 8, 12, 16, 20, 24, 32 (8pt grid). Group spacing (24) > intra-group (8).
- Radius: system only (8 rows / 6 controls). Strip: 3pt tall, corner 1.5.
- Type: system. Reclaimable total 26 semibold tabular. Row title 13 semibold.
  Item name 13 regular. Detail/caption 11 regular secondary. Safety badge 11 medium.
  All byte counts `.monospacedDigit()` + fixed layout (no jitter).
- Color: dark mode only (`colorScheme = .dark` locked). System materials/backgrounds.
  **One accent**: `Color.accentColor` (macOS blue #0A84FF) for selection + Clean + strip.
  Everything else system primary/secondary/separator. No gradients, no custom palette.
- Controls: 28pt native `Toggle(.checkbox)` / `Button(.borderedProminent)`, SF Symbols.
  No custom heights, no icon tiles, no pills-as-decoration.

## 3. The one novel idea

**The strip is the disk.** A single 3pt strip at the top of the sidebar is divided
proportionally to each category's allocated bytes — it *is* the junk, to scale.
During scan it fills left→right as real categories land. Selected bytes are the accent
fill; unselected bytes are neutral gray; **selecting an item drains the strip in place**
(the surface moves, so removing junk is visible at a glance). The footer mirrors the
same drain with the matching number. No card, no bar-in-a-box: the strip itself
progresses, drains, and reads instantly. Reduced-motion users get the same end state
instantly and read it completely without animation.

Everything else is stock-native on purpose (List, Toggle, ProgressView, Gauge-free):
the strip is the only custom surface, and it earns its place by encoding the one
quantity the whole app exists to show.

## 4. Motion (from the start, reduced-motion safe)

- Strip fill/drain: `.animation(.easeOut(duration: 0.3))`, skipped with
  `accessibilityReduceMotion`.
- Sidebar row insertion on scan land: `.animation(.default)` move+opacity, skipped
  under reduced motion.
- Cleaning: items fade+move out as Trash confirms (state change → movement).
- No springs, no loops, no shimmer. Numbers roll via tabular fixed-width (no slide).
