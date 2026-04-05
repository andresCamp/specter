# Live Change Visualization — Product Spec

## Purpose

Spectr watches the open file on disk. When something external modifies it — an agent, a script, another editor — Spectr shows the change beautifully. Scroll position stays stable, changed content animates in, and a review bar lets you navigate, keep, or undo changes.

This is the feature people demo. Terminal on the left, Spectr on the right, agent writes to the file, the doc evolves in real time.

### The Analogy

Think of how a Google Doc shows collaborator edits appearing in real time — you see text materialize, you know where changes happened, you stay oriented. Spectr does this for local files, but instead of a cursor you see the finished result fade in.

Where it sits in the pipeline:

  [External write to .md file] → [THIS SYSTEM] → [Animated update + review bar]

## Inputs

- A file-system event indicating the open `.md` file has been modified externally
- The previous document content (held in memory)
- The new document content (read from disk)

## Interaction Model

The user has Spectr open beside their terminal. An agent (or any process) modifies the file on disk.

1. **The document updates without disrupting the user.** Scroll position stays exactly where it was. No jump, no flash, no reload.

2. **Changed regions animate.** Affected lines blur briefly, then the new content fades in. Insertions grow into place. Deletions collapse out. The document feels alive.

3. **A change review bar appears.** A floating pill at the bottom of the viewport — compact, like Cursor's find/replace bar. Shows the current change index and total: `1/3` with prev/next arrows (▲▼) to jump between changes. Two actions: "Undo all" (revert every change) and "Keep all" (accept every change).

4. **Each changed region has a gutter marker.** A small icon in the right gutter marks every change. Clicking it opens a popover showing the diff for that specific change — old content vs new content — with three actions: keep, undo, edit.

5. **Scrollbar markers show change locations.** Small colored dots appear in the right scrollbar track at the vertical position of each change — like VS Code's overview ruler. Click a dot to jump directly to that change. Gives an instant birds-eye view of where in the document changes occurred.

6. **The user works through changes or ignores them.** They can navigate change-by-change, accept/revert individually, or bulk-accept. They can also just keep working — changes stay marked until acted upon.

## The Flow

### 1. Detection

The file system watcher fires when the `.md` file is saved externally. Spectr reads the new content from disk.

### 2. Diffing

Spectr diffs the previous content against the new content at the line level. It identifies changed regions — insertions, deletions, and modifications — and maps them to document positions.

### 3. Debounce

Rapid writes (agents often save multiple times in quick succession) are batched. Spectr waits for a short debounce window after the last write before applying changes. If new writes arrive during animation, they queue and merge.

### 4. Scroll Anchor

Before applying changes, Spectr records the viewport anchor — the line at the center of the visible area. After the content update, Spectr restores the viewport so the anchor line remains in the same position. Content above and below shifts; the user's view stays fixed.

### 5. Animation

Changed regions animate in sequence:
- **Modified lines:** Content blurs (gaussian, ~200ms), then the new text fades in (~300ms)
- **Inserted lines:** Lines grow from zero height with a fade-in (~300ms)
- **Deleted lines:** Lines collapse to zero height with a fade-out (~200ms)

All animations use ease-out timing. They should feel smooth and natural, not flashy.

### 6. Change Markers

After animation completes, each changed region gets:
- A subtle background tint (using `--trim-color` at low opacity) to indicate "unreviewed"
- A small gutter icon on the right edge
- A colored dot in the scrollbar track at the corresponding vertical position

The review bar appears at the bottom.

### 7. Review

The user navigates changes via the review bar or by clicking gutter icons directly.

**Per-change actions (popover):**
- **Keep** — Accept the change. Marker and tint disappear. Content becomes normal.
- **Undo** — Revert to previous content at this location. The old content fades back in.
- **Edit** — Dismiss the popover and place the cursor in the changed region for manual editing. The change marker remains until the user explicitly keeps or undoes.

**Bulk actions (review bar):**
- **Keep all** — Accept every remaining change. All markers clear.
- **Undo all** — Revert every remaining change. All changed regions restore to previous content.

### 8. Completion

When all changes are reviewed (individually or via bulk action), the review bar disappears. The document returns to its normal state.

If the user closes the file with unreviewed changes, the current content (including unreviewed changes) is what's on disk — no prompt, no data loss. Change markers are session-only.

## Behavioral Rules

**DO:**
- Keep scroll position stable — this is the most important behavior
- Debounce rapid writes — never animate partial states
- Make animations subtle and fast — the content is the star, not the transition
- Show the review bar only when there are unreviewed changes
- Let the user ignore changes entirely — no forced review

**DON'T:**
- Don't scroll to the first change automatically — the user may be reading something else
- Don't play sound effects or show system notifications
- Don't persist change markers across sessions — if you close and reopen, it's a clean slate
- Don't block editing while changes are animating — the user can always type
- Don't animate if the user is actively editing the same region — apply silently

## Edge Cases

| Scenario | Expected Behavior |
|----------|-------------------|
| User is editing when external change arrives | Apply non-conflicting changes normally. For regions the user is actively editing, skip animation and merge silently. |
| External change modifies 100+ lines | Same behavior, but consider batching animation to avoid overwhelming the viewport. Only animate changes visible in the viewport; off-screen changes apply instantly. |
| File is deleted externally | Not this system's concern — handled by FileDocument's existing behavior. |
| File is replaced entirely (completely different content) | Treat as a bulk change. Animate visible changes, apply the rest. Review bar shows total count. |
| Multiple rapid external writes | Debounce. Accumulate changes, diff once, animate once. |
| User clicks "Undo" on a change, then an external write modifies the same region again | The new external write takes precedence. A new change marker appears for that region. |
| No actual content change (file touched but identical) | No-op. No animation, no review bar. |

## Connections

| System | Relationship | What Flows |
|--------|--------------|------------|
| Document Model (SpectrDocument) | Receives from | Previous content for diffing |
| Editor Bundle (CodeMirror 6) | Feeds into | Animations, scroll anchoring, gutter markers, review bar UI |
| App Shell (SpectrApp) | Receives from | File system events via FileDocument |

## Open Questions

- [ ] Exact debounce window duration — 300ms? 500ms? Needs testing with real agent workflows.
- [ ] Animation values (blur radius, fade duration) — spec'd above as starting points, needs visual tuning.
- [ ] Should the review bar auto-dismiss after a timeout if the user doesn't interact? Or persist until explicitly resolved?
- [ ] Gutter icon design — what SF Symbol? How prominent?
- [ ] Does "Undo" save to disk immediately, or batch until the user explicitly saves?
