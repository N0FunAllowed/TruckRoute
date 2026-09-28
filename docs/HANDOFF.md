# TruckRoute — session handoff

Verified live against GitHub and the local checkout on **2026-09-28**.

## What this is

An iOS app (SwiftUI + SwiftData + MapKit, iOS 17+) for a one-truck operation: enter the week's loads, get them ordered into a route with real drive times and arrival times, and see what each load actually pays per mile. Built from scratch in this repo with the owner, one request at a time.

**"Dead simple" is the owner's stated goal** and has decided several scope calls. Invoicing, IFTA, ELD/hours-of-service, multi-driver, accounts and backend sync are deliberately excluded — see README "Scope". Don't add them unasked.

## Four things that will bite you immediately

**1. The repo was renamed: `HelloWorld` → `TruckRoute`.**
- The local working dir is still `/home/user/HelloWorld`. That's fine — leave it.
- The git remote URL reverts to the old `HelloWorld` URL when the session re-provisions. GitHub redirects, so it's cosmetic.
- **The GitHub MCP tools are scoped by repo name** and reject `TruckRoute` with "Access denied: repository not configured for this session". Fix: `add_repo` with owner `N0FunAllowed`, repo `TruckRoute`. Don't re-clone; the existing checkout is a valid clone of the renamed repo.

**2. There is no Xcode in this environment. You cannot build or run tests locally.**
CI on a macOS runner (Xcode 16.4, iOS 18.5 simulator) is the *only* verification that exists. Workflow: push, wait ~4–11 min, read the runs. Every push produces **two** runs on the same SHA (push event + pull_request event) — check both. This has caught real bugs inspection missed. Don't claim anything compiles or passes until CI says so.

**3. The repo's `CLAUDE.md` says Claude is a reviewer, not an implementer.**
It arrived via an unrelated merge (PR #3, an "AI dev router") partway through, and declares a planner → Codex → reviewer stack with `never_auto_merge: true`. The app code on PR #9 predates it and was written directly by Claude at the owner's explicit direction; the conflict is flagged in the PR body. **Practical upshot: do not merge anything.** The owner asked once, I declined with the reason, and they accepted. Human-approved merges only.

**4. Xcode project quirks**
- Uses `PBXFileSystemSynchronizedRootGroup`, so **new `.swift` files under `TruckRoute/` and `TruckRouteTests/` are picked up automatically** — no `project.pbxproj` editing.
- Swift 5 language mode (not 6), so strict-concurrency errors aren't in play. That also means `@MainActor` violations fail silently rather than at compile time — see the SE-0338 bug below.
- A new stored property on a SwiftData `@Model` needs an **inline default on the property itself** (not just in `init`), or lightweight migration of existing rows breaks.

## Where things stand

**Branch:** `claude/trucking-app-routing-prompt-5ckvae` · **PR #9** · head `1227d8a` · base `master` at `2c70673`
**CI:** green on both runs for `1227d8a` — **44 tests, 0 failures**, `** TEST SUCCEEDED **`, no Swift compiler warnings
**Mergeability:** GitHub reports `blocked` — that's the review requirement, *not* a conflict; `master` hasn't moved since the PR opened.

PR #9 is the whole app. It has now had **two independent reviews**, and the fixes from the second one are merged into its branch via PR #10 (merged 2026-09-28). What it is still waiting on:

1. **A review of the PR #10 fixes.** The Claude session that reviewed #9 also wrote those fixes, so the review requirement is not met by its author. This is explicitly flagged in #10's body.
2. **Simulator/device QA.** Still never done — see below.
3. **Six open decisions** the second review deliberately left to the owner (below).

### Review history

- [Review 5201662045](https://github.com/N0FunAllowed/TruckRoute/pull/9#pullrequestreview-5201662045) (2026-09-14, against `2660ad3`) — two scheduling blockers: the past-midnight day reset, and an unmeasured leg scheduled as zero travel time. Both fixed in `caaf0d2`.
- [Review 5331164661](https://github.com/N0FunAllowed/TruckRoute/pull/9#pullrequestreview-5331164661) (2026-09-27, against `caaf0d2`) — a fresh Claude session that read every Swift file on the branch. Confirmed the first review's blockers fixed, and found eight more issues. All eight are fixed on the branch now via PR #10. Note its own caveat: same model family as the author, so a human or different-model pass still adds something.

### What PR #10 fixed (6 commits, 12 new tests, 32 → 44)

- **High — a new day still reset to 08:00 even when the previous day's work ran past it** (`eabe5ad`). `caaf0d2` fixed this *within* a day but not at a day boundary: a drop-off window opening Tuesday 14:00 kept the truck there, yet Tuesday's first pickup still scheduled from 08:00 — the truck in two places, and a pickup it will miss reported on time. Now `clock = max(dayStart, clock)`. Because a stop can now be scheduled on a later day than the one it's listed under, the route row shows the weekday when the two differ.
- **High — editing an existing load couldn't change its pickup or drop-off** (`272e2f1`). `loadExisting` ran from `onAppear`, which re-fires when a pushed view pops, so returning from `PlacePicker` reloaded the stored load over the new pick and every other unsaved edit. New loads were unaffected, which made it easy to miss. Found by reading, from documented SwiftUI behaviour — not reproduced on a simulator.
- **Medium — the rate was corrupted on save in comma-decimal locales** (`272e2f1`). Pre-filled in the locale's format, read back by keeping only digits and `.`, so with the region set to Germany $2,400 saved as **$2.40** on any save. New `MoneyInput` owns both directions; round-trip tests cover en_US/de_DE/fr_FR. Non-numeric text now blocks Save.
- **Medium — a load's $/mi was overstated when a leg was unmeasured** (`aab324e`). `?? 0` counted a missing leg as zero miles, so a $1,000 load whose loaded leg failed showed **$100/mi** in green. Now nil unless both legs measured; the math moved into a testable `PlannedRoute.assignLoadMiles()`.
- **Medium — SwiftData `Place` written off the main thread** (`0afbfc0`). Under SE-0338 a plain `async` method runs on the generic executor even when a `@MainActor` caller awaits it, so the resolver read and wrote `Place.latitude/longitude` from a background thread — a latent race that would surface only as an occasional crash. The resolving methods are now `@MainActor`.
- **Low** — `isDelivered` got its inline migration default; "Check this address" no longer applies a lookup result if the text changed meanwhile; the PDF route sheet now prints the load reference.

### Six open decisions from the second review — not changed, deliberately

1. **Same-day ordering ignores pickup times.** Nearest-neighbor will take a 14:00 pickup near the yard before an 08:00 pickup further out, wait six hours, then run the 08:00 load that evening; it's only flagged if that load has a window close. Now that the scheduler knows windows, a cheap fix is "earliest-open first, nearest-neighbor among loads already open when the truck is free." Left alone as an algorithm and product call for the planning role under `config/router.json`.
2. **The unknown-schedule question is now visibly asymmetric.** After fix 1, a *known* overrun carries into the next day, but an *unknown* one is still assumed to finish by 08:00. The reviewer would keep the recovery — propagating would let one unmeasured Monday leg blank the whole week, and both the unknown stop and the missing leg are already flagged — but it deserves a deliberate yes. Pinned by `testANewOperatingDayRecoversFromAnEarlierMissingLeg`, which the code comment points at.
3. **The route goes stale silently.** After loads are edited, delivered or deleted, the Route tab keeps the old plan with nothing saying so. A "loads changed since this was planned" line next to Replan would cover it.
4. **The delete buttons inside the Load and Place edit forms skip the confirmation** the list swipe has. The Place one also bypasses the home-base and "N loads use this address" warnings.
5. **MapKit throttling.** Directions allows roughly 50 requests a minute; a 25-load week is about 51 legs. The 1-second retry can't outlast a per-minute window. It fails visibly (unmeasured-leg warnings) rather than silently. The `drivingRoute` comment claims requests are spaced out, but only retries are.
6. **The map doesn't re-fit on Replan**, because `Map(initialPosition:)` only applies on first appearance.

Nits: the PDF's "Generated" time is captured when the Route view renders, not when you share; turning on a window or deadline defaults it to *now*, which any future load shows as an error until changed.

### Other open PRs and issues

| PR | What | State |
|---|---|---|
| **#9** | The app itself | Green at `1227d8a`; needs a review of the #10 fixes + QA |
| **#6** | `feature/load-expenses` — per-load cost/profit (issue #5, built by Codex) | Open, off `master`, **conflicts with #9** |
| **#8** | `infra/use-shared-ai-workflows` | Open, untouched |

**PR #6 was reviewed separately on its own PR.** It has the same money-parsing bug on six fields, no tests despite issue #5 requiring them, and a cost/profit summary that doesn't add up. Its merge with #9 is something **git reports as clean in `PlannedRoute.swift` but that won't compile** — both sides append parameters to `RouteStop`'s initializer right after `loadRate` (#6 adds `loadCost`; #9 adds `windowStart` / `deadline` / `serviceDurationMinutes`) and both edit the same regions of `Load.swift`, `RoutePlanner.swift`, `LoadFormView.swift`, `LoadListView.swift`, `RouteView.swift`. The reviewer's recommendation: **merge #9 first, then rework #6 on top** — a deliberate reconciliation keeping both the cost and scheduling fields as named, defaulted parameters, not a drive-by conflict resolution.

**Open issues:** #5 (per-load operating costs — what PR #6 implements) and #7 (automate Claude review for PRs; flagged high-risk in its own description, wires GitHub events to an external API, wants a security review before enabling).

## What's in the app

- **`Place`** — address book. Apple Maps autocomplete confirms an address is real before saving; the confirmed coordinate is cached on the place and cleared when the address is edited.
- **`Load`** — pickup/drop-off chosen from the address book, pickup date + optional window close, optional delivery window and/or deadline, on-site service time, rate (via `MoneyInput`), reference, notes, delivered flag. The form blocks self-contradicting schedules and non-numeric rates.
- **`RoutePlanner`** (`@MainActor @Observable`) — groups loads by pickup day, orders each day nearest-neighbor from the yard, measures each leg with MapKit (one retry against throttling), closes the loop with a return-to-yard deadhead leg, then hands the stops to the scheduler.
- **`RouteScheduler`** — pure, synchronous, no MapKit or network. Arrival/departure per stop from travel time, windows and service duration; a day starts at the later of 08:00 and the previous day's last departure; early arrival waits; past-deadline stops flagged. The piece worth testing directly and the one that's had the most bugs.
- **`LoadCoordinateResolver`** — `@MainActor`; resolves coordinates from a place's *current* address, geocoder injected for tests.
- **`RoutePDFRenderer` + `RouteShareDocument`** — paginated route-sheet PDF via `UIGraphicsPDFRenderer`, shared through `ShareLink` with a timestamped, collision-proof filename.
- **Money** — rate per mile/km over *all* miles (loaded + empty), nil for a load with an unmeasured leg, deadhead surfaced explicitly and dashed on the map, miles/km toggle in Settings driving both distances and rate labels.

**Tests (44, all without MapKit or network):** `RouteSchedulerTests` 16 (pinned to a fixed UTC calendar and base date so absolute-time assertions can't flake on DST or a midnight rollover), `PlannedRouteTests` 14, `LoadCoordinateResolverTests` 6, `MoneyInputTests` 5 (locale round trips), `FormatTests` 3.

## Things worth knowing, not just facts

- **The scheduler is where the bugs live.** Five real ones so far: travel time skipped on a day's first stop (`if`/`else if`); the operating day derived from a mutable clock, which broke past midnight; the inverse facet of that, where a genuine new day failed to reset; an unmeasured MapKit leg treated as zero travel time, so stops read "on time" when arrival was unknown; and a new day resetting to 08:00 even when the previous day's work ran past it. Not one was caught by casually reading the code — two by CI, three by review passes that went looking. Treat changes there with suspicion and add tests.
- **Reading found what CI never could.** The `onAppear` data loss, the off-main-actor SwiftData write and the address-lookup race were all found by reading, and none of them has a test. CI proves compilation and math; it cannot see a SwiftUI lifecycle bug or a data race.
- **Nothing has ever been run on a simulator or device. Not once.** This is the single biggest gap and the highest-value next step. When it happens, the reviews specifically want: edit an existing load and change its drop-off; set the region to Germany and re-save a load that has a rate; plan a week where a drop-off opens the day after its pickup.
- The regression tests are confirmed by CI to *pass* against the fixes. That they *fail* against the old code was established by reading the old logic, not by running it.

## Conventions

- Commit messages explain *why*, often several sentences, and end with the Co-Authored-By and Claude-Session trailers the harness specifies.
- Push only to `claude/trucking-app-routing-prompt-5ckvae`. Don't open PRs unless asked. **Don't merge.** Surface risky or irreversible things before doing them.
- **The branch moves between sessions.** PR #10 was merged into it by another session while this doc was being written. Fetch before assuming a head SHA, and rebase rather than force-push.
- The owner values honesty about what's verified vs. assumed and has responded well to flagged uncertainty — that's why the caveats above are phrased the way they are.

## Likely next steps, in order

1. **Simulator/device QA of PR #9** — needs a Mac with Xcode, which this environment is not. The three scenarios above are the priority.
2. **An independent review of the PR #10 fixes**, by a human or a different model. Its author wrote both the review and the fixes.
3. **Work the six open decisions** above, at least items 1 and 2, which are product calls rather than bugs.
4. **Merge #9, then rework #6 on top** — note the merge that git calls clean but that won't compile.
5. Issue #7 (automated Claude review workflow) is unstarted and wants a security review first.
