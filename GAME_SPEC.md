# Idle Data Center Tycoon — Build Spec

**Codename:** `rackline`
**Store title (ASO):** Idle Data Center Tycoon
**Engine:** Godot 4.6 (GDScript)
**Target:** Android first, iOS second
**Owner:** solo developer, evenings/weekends
**Spec version:** 1.0

---

## 0. How to use this file with Claude Code

1. Put this file at the repo root as `GAME_SPEC.md`.
2. Create a `CLAUDE.md` that says: *"Read GAME_SPEC.md before any task. Do not add features not listed in §9 Scope Lock. Do not change balance constants in §5 without being asked."*
3. Work milestone by milestone (§10). One milestone per session. Do not let the agent jump ahead.
4. After every milestone, run the acceptance checks listed for it before starting the next.

---

## 1. Why this game (decision rationale)

| Criterion | Why this concept wins |
|---|---|
| Art burden | Near zero. UI panels, icons, numbers. No character art, no animation rigs. |
| Skill match | Idle games are spreadsheet design. Systems, formulas, balance curves — the same muscle as engineering calc workbooks. |
| Language match | GDScript reads like Python. No C#, no C++. |
| Differentiation | Every idle clone is farms/mines/bakeries. Nobody is shipping a data center idle built by someone who actually engineers MEP for data centers. Power/cooling/PUE mechanics are authentic, not decorative. |
| Distribution | r/incremental_games is a real, free launch channel with a documented history of five-figure and six-figure solo launches. TikTok secondary. |
| Ceiling | Lower than a hybrid-casual puzzle hit. Accepted trade: much higher probability of *something*, much lower probability of nothing. |

**Reality check, stated once:** ~62% of new mobile titles earn nothing. This concept improves your odds; it does not make them good. Build it to be cheap and fast, not perfect. The plan is a catalog, not a lottery ticket.

---

## 2. Core fantasy

You start with one rack in a rented closet and end up running a hyperscale campus. The fun is not "number goes up" alone — it is **the constraint triangle**: every rack you add consumes power and dumps heat. Add racks without power and cooling, and racks throttle or trip. The player is constantly rebalancing IT load against electrical capacity and cooling capacity, chasing a better PUE and more nines of uptime.

That constraint loop is what makes this game different from every other idle. Do not dilute it.

---

## 3. Core loop

```
Buy/upgrade IT capacity  →  power draw + heat rise
        ↓
Power & cooling headroom shrinks
        ↓
Buy electrical + mechanical capacity to restore headroom
        ↓
Efficiency upgrades lower PUE  →  more profit per rack
        ↓
Revenue accumulates (online + offline)
        ↓
Site Sale (prestige)  →  Tech Tokens  →  permanent multipliers  →  next site tier
```

Session shape: 60–120 second active sessions, 4–8 times a day, plus offline collection.

---

## 4. Systems

### 4.1 Resources

| Resource | Symbol | Role |
|---|---|---|
| Cash | `$` | Soft currency. Buys and upgrades everything. |
| Compute | `TFLOPs` | Produced by racks. Converted to Cash by contracts. |
| Power capacity | `kW` | Supplied by electrical units. Consumed by IT + mechanical. |
| Cooling capacity | `kW-th` | Supplied by mechanical units. Must exceed heat load. |
| Tech Tokens | `TT` | Prestige currency earned through Site Sales and spent in the tech tree. Optional packs supplement progress but never gate content. |

### 4.2 Derived metrics (shown in a persistent top bar)

```
IT_load_kW      = sum(rack.power_draw)
Mech_load_kW    = sum(cooling_unit.power_draw)
Total_load_kW   = IT_load_kW + Mech_load_kW + losses
PUE             = Total_load_kW / IT_load_kW          # target: drive from 2.0 toward 1.10
Heat_load_kWth  = IT_load_kW * 1.0                    # 1:1, keep it simple
Reliability     = min(sum(equipment + tech uptime bonuses), 0.999%)
Power_penalty   = (1 - throttle) * 10%
Cooling_penalty = (1 - clamp(cooling_capacity / heat_load, 0, 1)) * 8%
Trip_penalty    = tripped_IT_ratio * 15%
Uptime          = clamp(99% + Reliability - Power_penalty - Cooling_penalty - Trip_penalty, 50%, 99.999%)
Revenue_per_sec = Compute_rate * contract_rate * uptime_mult * tech_mult
```

**Failure states (this is the tension):**
- `Power_capacity < Total_load_kW` → racks throttle: production scales by `capacity / load`.
- `Cooling_capacity < Heat_load_kWth` → thermal alarm; after 30s, racks start tripping offline one by one until load fits.
- Both are recoverable by buying capacity. No permanent loss. Never punish the player into quitting.

### 4.3 Unit catalog (v1 — 15 units)

**IT (produces Compute, consumes Power, produces Heat)**
1. `Rack — 1U Server Shelf` — entry unit
2. `Rack — Blade Chassis` — 4x compute, 3x power
3. `Rack — GPU Pod` — 20x compute, 12x power, 2x heat coefficient
4. `Rack — Edge Microcluster` — efficient post-GPU compute tier
5. `Rack — AI Superpod` — campus-scale compute with high heat output

**Electrical (supplies Power capacity)**
6. `PDU` — cheap, small kW
7. `UPS + Transformer` — medium kW, +0.025% uptime each
8. `Diesel Generator` — large kW, +0.015% uptime each, small ongoing fuel cost
9. `Modular Substation` — dense medium-voltage capacity
10. `Grid Battery Farm` — top-tier capacity without fuel burn

**Mechanical (supplies Cooling capacity, consumes Power)**
11. `CRAC Unit` — cheap, poor efficiency (high kW draw per kW-th)
12. `Chilled Water Plant` — medium, better efficiency
13. `Free Cooling Economizer` — expensive, near-zero draw, capacity varies with the site's climate modifier
14. `In-Row Cooling Array` — efficient close-coupled cooling
15. `Immersion Cooling Plant` — top-tier high-density cooling

Advanced equipment is never hard-locked by prestige. Its high cash price creates a soft gate. The first two Electrical, Mechanical, and Compute research nodes each reduce their matching Facility equipment costs by 15%, allowing the 12 TT earned from the first Site Sale to make one category 30% cheaper immediately.

### 4.4 Site tiers (prestige ladder — 5 tiers, v1 ships all 5)

| Tier | Name | Climate modifier (economizer effectiveness) | Unlock cost |
|---|---|---|---|
| 1 | Rented Closet | 0.2 | start |
| 2 | Colo Suite | 0.4, 1.25x contract rate | 5 TT |
| 3 | Purpose-Built Facility | 0.6, 1.75x contract rate | 30 TT |
| 4 | Nordic Campus | 1.0, 2.5x contract rate | 120 TT |
| 5 | Hyperscale Region | 0.8, 10x base contract rate | 500 TT |

### 4.5 Tech tree (20 nodes, v1)

Four branches, 5 nodes each. Costs in TT. Effects are permanent and persist through Site Sale.

- **Electrical:** higher-voltage distribution, DC busway, lithium UPS, on-site solar, grid arbitrage
- **Mechanical:** hot-aisle containment, raised setpoint, liquid-to-chip, immersion, waste-heat recovery
- **Compute:** denser packing, better schedulers, custom silicon, overclock profiles, dark-fiber peering
- **Ops:** automated remediation, N+1 redundancy, predictive maintenance, staffed NOC, SLA renegotiation

Each node: `cost_tt`, `effect_type`, `effect_value`. Store as data, not code (§7).

### 4.6 Random events (5 types, one every 6–12 min of active play)

| Event | Effect | Player options |
|---|---|---|
| Heat wave | Cooling capacity −30% for 3 min | Ride it out / rewarded ad: instant fix |
| Grid sag | Power capacity −25% for 2 min | Ride it out / rewarded ad: instant fix |
| Coolant leak | One mechanical unit offline until repaired | Pay cash / rewarded ad: free repair |
| Traffic spike | Compute demand +100% for 2 min — free upside | — |
| Audit passed | +1 hour of offline accrual | — |

Two of five are pure gifts. Keep it that way; events must not feel like a tax.

---

## 5. Balance math (do not change without an explicit instruction)

```gdscript
# Cost scaling — classic idle geometric curve
cost(n) = base_cost * pow(cost_growth, n)      # cost_growth in [1.07, 1.15]
# IT units use 1.12, electrical 1.09, mechanical 1.10

# Production
compute_rate = sum(unit.base_compute * unit.count) * tech_compute_mult
throttle     = clamp(power_capacity / total_load_kW, 0.0, 1.0)
balance_mult = 1.72  # Constant; revenue never decays as lifetime revenue rises
revenue_per_sec = compute_rate * throttle * contract_rate * uptime_mult * site_mult * balance_mult

# Active play — RUN JOB
manual_job_reward = max(1.0, revenue_per_sec * 0.25)
manual_job_charges = 5 maximum, regenerating 4 per second
# Sustained active play adds roughly 100% income and targets a 10–15 min first Site Sale.

# Cash-based JOB OPS upgrades reset on Site Sale:
# Contract Optimizer: +5% job value/level (5 levels)
# Queue Expansion: +2 stored jobs/level (4 levels)
# Dispatch Firmware: +5% recharge speed/level (4 levels)
# Even fully upgraded sustained clicking is capped at 2.5x total income.

# Offline earnings
offline_seconds = clamp(now - last_seen, 0, offline_cap)
offline_cap     = 7200                      # 2 hours default
                + 7200 if remove_ads_owned  # 4 hours total
offline_rate    = 0.50
                + up to 0.25 from PUE       # PUE 2.0 → 1.0
                + up to 0.15 from uptime    # UP 99.0% → 99.999%
offline_rate    = clamp(offline_rate, 0.50, 0.90)
offline_revenue = revenue_per_sec * offline_seconds * offline_rate
# Rewarded ad on the return screen: multiply collected amount by 2

# Prestige (Site Sale)
tokens_earned = floor(12 * pow(lifetime_revenue_this_site / 1e6, 0.5))
# Requires lifetime_revenue_this_site >= 1e6 before the button unlocks

# Tech multipliers stack multiplicatively within a branch, additively across branches
```

**Pacing targets — tune until these hold:**
- First Site Sale reachable in **20–30 minutes** of total play, targeting **25 minutes**.
- Each subsequent site tier: **1.5x–2x** the previous time-to-prestige.
- Full tech tree: **25–40 hours**. That is the content ceiling for v1.

---

## 6. Monetization

**Never:** energy timers, forced interstitials mid-decision, pay-to-progress walls, loot boxes.

### 6.1 Rewarded video (primary revenue — AdMob)
| Placement | Reward | Cap |
|---|---|---|
| Return screen | 2x offline collection | 1 per return |
| Boost button (always visible) | 2x revenue, 4 min | 6/day |
| Event card | Instant fix / free repair | per event |
| Site Sale screen | +25% Tech Tokens from this sale | 1 per sale |

### 6.2 Interstitial (secondary)
Shown **only** on the Site Sale transition. Hard cap: 1 per 3 minutes, max 8/day. Never during a purchase or an event.

### 6.3 IAP
| SKU | Price | Contents |
|---|---|---|
| `remove_ads` | $2.99 | No interstitials, rewarded stays optional, offline cap 2h → 4h |
| `starter_pack` | $4.99 | 10 TT + 2x revenue for 24h, offered once, after first Site Sale only |
| `tt_small` / `tt_large` | $4.99 / $19.99 | Tech Tokens |

Target mix: roughly 55% ads / 45% IAP.

### 6.4 Targets to judge the game against
- D1 retention **>30%** — below 20% after two iterations, kill the concept, keep the codebase.
- D7 **>12%**, D30 **>5%**
- ARPDAU **>$0.05** at launch, **>$0.15** after ad-placement tuning
- Payer conversion **>1.5%**

---

## 7. Architecture

```
rackline/
├── project.godot
├── CLAUDE.md
├── GAME_SPEC.md
├── data/                    # ALL balance data lives here as JSON. No magic numbers in code.
│   ├── units.json
│   ├── tech_tree.json
│   ├── sites.json
│   ├── events.json
│   └── balance.json             # Cross-system pacing constants
├── scripts/
│   ├── autoload/
│   │   ├── GameState.gd     # single source of truth, holds the save dict
│   │   ├── Economy.gd       # all formulas from §5, pure functions, no UI
│   │   ├── SaveManager.gd   # save/load, offline calc, schema migration
│   │   ├── Ads.gd           # AdMob wrapper, no-ops in editor
│   │   └── Analytics.gd     # GameAnalytics wrapper, no-ops in editor
│   ├── ui/
│   └── systems/
├── scenes/
│   ├── Main.tscn
│   ├── ui/ (TopBar, UnitList, JobOps, TechTree, SiteSale, EventCard, ReturnScreen)
└── tests/
    └── test_economy.gd      # GUT tests for every formula in §5
```

**Hard rules for the agent:**
1. `Economy.gd` must be pure: takes state, returns numbers, touches no nodes. This is what makes it testable and what lets you rebalance without breaking the game.
2. All balance values load from `data/*.json`. A balance change must never require a code change.
3. Use `float` for all currency. Above ~1e15, format via a magnitude table (K, M, B, T, Qa, Qi…). Write the formatter early; every screen needs it.
4. Tick at 10 Hz for economy, not per-frame. UI updates at 4 Hz.
5. Save every 30s, on every purchase, and on `NOTIFICATION_APPLICATION_PAUSED`.
6. Save file carries a `schema_version`. Write the migration path before shipping v1.

---

## 8. UI (6 screens, nothing more)

1. **Facility** (home) — top bar metrics, a clickable pixel-art data center that changes with the selected site and runs the active-play job, three tabs (IT / Electrical / Mechanical), buy buttons with cost and effect delta, boost button
2. **Job Ops** — three cash-based active-clicking upgrades, current tap reward, queue capacity, and recharge rate
3. **Tech Tree** — 4 branches, node cards, TT balance
4. **Site Sale** — projected TT, what carries over, confirm
5. **Return Screen** — offline earnings, 2x ad button
6. **Settings** — sound, remove-ads, restore purchases, privacy policy link, credits

Visual direction: retro pixel-art terminal aesthetic (chosen 2026-08-17, supersedes the earlier flat dark-NOC direction). Blocky, hard-edged panels and buttons (no rounded corners, no anti-aliasing), a small fixed retro palette, and a chunky pixel font. Procedurally-generated pixel icons only — no sourced/hand-drawn art assets, keeping the zero-art-burden premise from §1 intact. One accent color for "healthy," one for "at capacity," one for "alarm," carried over unchanged from the previous palette. Every number that changes must animate — that is the dopamine, and it is free.

---

## 9. Scope lock

**In v1:** everything in §4 exactly as listed — 9 units, 5 sites, 20 tech nodes, 5 events, 6 screens.

**Explicitly out of v1 (do not build, do not "prepare for"):** multiplayer, leaderboards, cloud save, daily quests, seasonal events, achievements, a tutorial beyond 3 tooltips, localization beyond English + Turkish, iOS-specific features, custom shaders, sound design beyond 6 UI sounds and one ambient loop.

If a feature is not in §4, the answer is no. Ship, then decide from data.

---

## 10. Milestones

| # | Milestone | Deliverable | Acceptance check | Est. (solo, evenings) |
|---|---|---|---|---|
| M0 | Setup | Godot 4.6 project, git repo, Android export template, `data/*.json` stubs, GUT installed | `godot --headless --export-debug Android build.apk` succeeds and runs on a phone | 2–3 h |
| M1 | Economy core | `Economy.gd` + `test_economy.gd`, no UI | All §5 formulas pass unit tests; a headless sim of 2 h of play produces sane numbers | 8–12 h |
| M2 | Playable loop | Facility screen, 9 units, buy/upgrade, throttle + thermal trip, save/load, offline | You can play 45 min and hit a real power/cooling crunch that you must solve | 15–20 h |
| M3 | Meta | Site Sale, tech tree, 5 sites, 20 nodes, events | First prestige reachable in 20–30 min; tech tree fully navigable | 15–20 h |
| M4 | Monetize + ship | AdMob, IAP, GameAnalytics, 5 UI sounds, store listing, privacy policy | Test ads serve; test purchase completes; analytics events land in dashboard | 15–20 h |

**Total: ~60–75 hours → roughly 8–10 weeks at 8 h/week.**

Then: Google Play closed testing — **14 consecutive days, 12+ testers**, mandatory for new personal developer accounts. Start recruiting testers during M3, not after M4.

---

## 11. Launch checklist

1. Play Console personal account ($25), W-8BEN filed, GVK 20/B exemption certificate obtained, dedicated TL bank account
2. Closed test running with 12 testers on day 1 of M4
3. Store listing: keyword-rich title, 6 screenshots (each showing a metric under stress, not a static menu), 30 s preview video
4. Launch post on r/incremental_games — a real dev post, not an ad. That subreddit is the single highest-value free channel for this genre.
5. 3 TikToks: "I engineer real data centers, so I made a game about it" / a thermal alarm cascade / PUE dropping from 2.0 to 1.1

---

## 12. Go / no-go, 30 days after launch

| Signal | Action |
|---|---|
| D1 >30% and D7 >12% | Keep going: add content, then test small paid UA |
| D1 20–30% | Two iteration cycles on the first-session experience. Then re-measure. |
| D1 <20% after iteration | Stop. Keep `Economy.gd`, the save system, the ad wrapper, and the formatter. Reskin into the next concept in a fraction of the time. |

The reusable engine is the real asset. This game is the first payload it carries.
