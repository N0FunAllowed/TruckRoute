# TruckRoute — session handoff

Verified live against GitHub and the local checkout on **2026-10-05**.

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

**Branch:** `claude/trucking-app-routing-prompt-5ckvae` · **PR #9** · base `master`
**CI:** **53 tests, 0 failures**, plus a Release build for arm64 device
**Default branch is `master`, not `main`** — worth knowing before anyone goes looking for it.

PR #9 is the whole app. It has had **two independent reviews**; the second one's fixes landed via PR #10 (merged into this branch 2026-09-28), and five of the six decisions it left open were closed on 2026-10-05 in the TestFlight-readiness round. What it is still waiting on:

1. **An independent review of the PR #10 fixes and the 2026-10-05 round.** Neither has had one. The session that reviewed #9 also wrote the #10 fixes.
2. **Simulator/device QA.** Still never done — see below. This is the one that matters.
3. **One open design decision**, the unknown-schedule asymmetry (below).

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

### The second review's six decisions — five closed on 2026-10-05

1. **Same-day ordering ignored pickup times** — closed. Nearest-neighbor took a 14:00 pickup near the yard before an 08:00 pickup further out, idled six hours, then ran the 08:00 load that evening. Ordering now lives in `RouteOrdering`, pure and testable alongside `RouteScheduler`: earlier opening first, distance breaking ties among pickups opening in the same hour. The hour rounding is deliberate and is the part to argue with — the review wanted "nearest-neighbor among loads already open when the truck is free", which needs travel times the ordering step doesn't have yet.
2. **The route went stale silently** — closed. The Route tab compares a fingerprint of the loads and yard against what was planned, says so, and offers Replan, while keeping the old plan on screen.
3. **The delete buttons inside the edit forms skipped confirmation** — closed. Both confirm now, and the address form shows the same home-base and "N loads use this" warning; that warning moved onto `Place` so the two call sites can't drift.
4. **The map didn't re-fit on Replan** — closed. The camera is `@State`, re-fitted when the stop list changes identity rather than on every update (measuring republishes once per leg).
5. **MapKit throttling** — closed, and it changes how planning feels. `drivingRoute` only ever slept between *retries* despite a comment claiming otherwise, so a 25-load week's 51 legs ran straight into the roughly-50-a-minute ceiling and legs went silently unmeasured. Paced 1.25s apart now, which makes planning a big week take about a minute.

The nits went with them: the PDF is stamped when it's exported rather than when the Route tab last redrew, and turning on a window or deadline seeds from the pickup instead of *now* (which on any future load was before the pickup, so the form opened onto a validation error).

**Still open — the one that is a judgement call, not a bug:**

6. **The unknown-schedule question is asymmetric.** A *known* overrun carries into the next day, but an *unknown* one is still assumed to finish by 08:00. Keeping the recovery is defensible — propagating would let one unmeasured Monday leg blank the whole week, and both the unknown stop and the missing leg are already flagged — but it deserves a deliberate yes. Pinned by `testANewOperatingDayRecoversFromAnEarlierMissingLeg`, which the code comment points at.

### Shipping

`docs/TESTFLIGHT.md` is the runbook. What was wrong before 2026-10-05, none of it visible from a simulator build: the bundle ID was `com.example.TruckRoute`, which Apple will not let you register; there was no asset catalog at all, so no app icon, which App Store Connect rejects; and export compliance was unanswered, so TestFlight would ask on every build. All three are fixed. The one thing that can't be set from this side is `DEVELOPMENT_TEAM`.

CI now also builds Release for arm64 device, not just Debug for a simulator — an archive can fail where a simulator build succeeds.

### Other open PRs and issues

| PR | What | State |
|---|---|---|
| **#9** | The app itself | Green; needs a review of the #10 and 2026-10-05 rounds, and QA |
| **#6** | `feature/load-expenses` — per-load cost/profit (issue #5, built by Codex) | Open, off `master`, **conflicts with #9** |
| **#8** | `infra/use-shared-ai-workflows` | Open, untouched |

**PR #6 was reviewed separately on its own PR.** It has the same money-parsing bug on six fields, no tests despite issue #5 requiring them, and a cost/profit summary that doesn't add up. Its merge with #9 is something **git reports as clean in `PlannedRoute.swift` but that won't compile** — both sides append parameters to `RouteStop`'s initializer right after `loadRate` (#6 adds `loadCost`; #9 adds `windowStart` / `deadline` / `serviceDurationMinutes`) and both edit the same regions of `Load.swift`, `RoutePlanner.swift`, `LoadFormView.swift`, `LoadListView.swift`, `RouteView.swift`. The reviewer's recommendation: **merge #9 first, then rework #6 on top** — a deliberate reconciliation keeping both the cost and scheduling fields as named, defaulted parameters, not a drive-by conflict resolution.

**Open issues:** #5 (per-load operating costs — what PR #6 implements) and #7 (automate Claude review for PRs; flagged high-risk in its own description, wires GitHub events to an external API, wants a security review before enabling).

## What's in the app

- **`Place`** — address book. Apple Maps autocomplete confirms an address is real before saving; the confirmed coordinate is cached on the place and cleared when the address is edited.
- **`Load`** — pickup/drop-off chosen from the address book, pickup date + optional window close, optional delivery window and/or deadline, on-site service time, rate (via `MoneyInput`), reference, notes, delivered flag. The form blocks self-contradicting schedules and non-numeric rates.
- **`RoutePlanner`** (`@MainActor @Observable`) — groups loads by pickup day, hands each day to `RouteOrdering`, measures each leg with MapKit (paced 1.25s apart, one retry), closes the loop with a return-to-yard deadhead leg, then hands the stops to the scheduler. Also publishes `plannedSignature`, the fingerprint the Route tab uses to notice it has gone stale.
- **`RouteOrdering`** — pure, synchronous, no MapKit. Decides what order a day's loads are worked in: earlier opening first, distance breaking ties within the hour.
- **`RouteScheduler`** — pure, synchronous, no MapKit or network. Arrival/departure per stop from travel time, windows and service duration; a day starts at the later of 08:00 and the previous day's last departure; early arrival waits; past-deadline stops flagged. The piece worth testing directly and the one that's had the most bugs.
- **`LoadCoordinateResolver`** — `@MainActor`; resolves coordinates from a place's *current* address, geocoder injected for tests.
- **`RoutePDFRenderer` + `RouteShareDocument`** — paginated route-sheet PDF via `UIGraphicsPDFRenderer`, shared through `ShareLink` with a timestamped, collision-proof filename.
- **Money** — rate per mile/km over *all* miles (loaded + empty), nil for a load with an unmeasured leg, deadhead surfaced explicitly and dashed on the map, miles/km toggle in Settings driving both distances and rate labels.

**Tests (53, all without MapKit or network):** `RouteSchedulerTests` 16 (pinned to a fixed UTC calendar and base date so absolute-time assertions can't flake on DST or a midnight rollover), `PlannedRouteTests` 14, `RouteOrderingTests` 9 (same fixed calendar), `LoadCoordinateResolverTests` 6, `MoneyInputTests` 5 (locale round trips), `FormatTests` 3.

## Things worth knowing, not just facts

- **The scheduler is where the bugs live.** Five real ones so far: travel time skipped on a day's first stop (`if`/`else if`); the operating day derived from a mutable clock, which broke past midnight; the inverse facet of that, where a genuine new day failed to reset; an unmeasured MapKit leg treated as zero travel time, so stops read "on time" when arrival was unknown; and a new day resetting to 08:00 even when the previous day's work ran past it. Not one was caught by casually reading the code — two by CI, three by review passes that went looking. Treat changes there with suspicion and add tests.
- **Reading found what CI never could.** The `onAppear` data loss, the off-main-actor SwiftData write and the address-lookup race were all found by reading, and none of them has a test. CI proves compilation and math; it cannot see a SwiftUI lifecycle bug or a data race.
- **Nothing has ever been run on a simulator or device. Not once.** This is the single biggest gap and the highest-value next step. `docs/TESTFLIGHT.md` lists the six things to drive first, each one a bug fixed by reading rather than by running — so each is unconfirmed in exactly the way a human driving the app would confirm.
- The regression tests are confirmed by CI to *pass* against the fixes. That they *fail* against the old code was established by reading the old logic, not by running it.

## Conventions

- Commit messages explain *why*, often several sentences, and end with the Co-Authored-By and Claude-Session trailers the harness specifies.
- Push only to `claude/trucking-app-routing-prompt-5ckvae`. Don't open PRs unless asked. Surface risky or irreversible things before doing them. The repo's `CLAUDE.md` and `config/router.json` (`never_auto_merge: true`) say merges are the owner's call — when one happens it's because they asked for it in so many words.
- **The branch moves between sessions.** PR #10 was merged into it by another session while this doc was being written. Fetch before assuming a head SHA, and rebase rather than force-push.
- The owner values honesty about what's verified vs. assumed and has responded well to flagged uncertainty — that's why the caveats above are phrased the way they are.

## Likely next steps, in order

1. **Run it.** Simulator or device, following `docs/TESTFLIGHT.md`'s list. Needs a Mac with Xcode, which this environment is not. Everything else is downstream of this.
2. **An independent review** of the PR #10 fixes and the 2026-10-05 round, by a human or a different model. Neither has had one.
3. **Decide the unknown-schedule asymmetry** — the one open design question.
4. **Rework #6 on top of `master`** once #9 is in — note the merge that git calls clean but that won't compile.
5. Issue #7 (automated Claude review workflow) is unstarted and wants a security review first.
