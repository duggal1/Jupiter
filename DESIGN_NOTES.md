# Purge redesign — five-line brief (DESIGN.md §14)

1. **Surface:** a 960×620 dark window on `bg` (#0A0A0A): 220 sidebar + detail on one left edge,
   with one-line readout replacing the subtitle; titles are serif italic 28 with the pixel stop.
2. **One pixel move:** reclaimable space is a tick field (3×10 ticks, `Ramp.blue`, white head)
   in the sidebar header and per-row sizes as small tick strips — selecting a row fills its strip,
   cleaning drains it; scanning is the three wait-cells loop, never a bar or spinner.
3. **States:** waiting (wait cells), results (tick rows), empty (11-cell stop + one sentence),
   FDA notice (40pt `control` row + one accent action), cleaning (pixel sweep), cleaned (check burst),
   failed (Failed badge + Retry); hover/pressed/disabled/focus drawn for every control.
4. **Tokens:** `Tok` surfaces/text/accent (§1 exact sRGB), `Ramp.blue`, `AppType` roles only,
   4pt grid / page pad 32 / rows 32–44 / heights 24–32 / radii 16·12·8·6, motion per §10, no raw controls.
5. **Deleted:** NavigationSplitView, system toolbar, `Divider`, `ProgressView`, `Gauge`, checkbox `Toggle`,
   `.borderedProminent`, `Color.secondary/.accentColor`, every stroke/gradient/shadow/card-in-card,
   duplicate Cancel buttons, surprise Downloads prompt (now opt-in), rescan-all on selection.
