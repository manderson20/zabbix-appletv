# Zabbix Widget Coverage Audit — tvOS Dashboard Renderer

> **Re-audit refresh (2026-07-19):** every row below was re-verified against the current
> resolver code. The original audit (see git history) is preserved in intent, but many of its
> gaps have since been closed by the config-fidelity campaign — the shared `scopedGroupIDs`
> (nested-aware), `tagFilters`/`tagEvalType`, `timePeriod`, aggregation engine, and value-map-aware
> item fetch now reach far more widgets than the first pass recorded. Ratings, gap counts, and
> headlines are updated to reflect reality; strikethrough marks work that has landed.

## 1. Executive summary

Coverage is broad and, since the original audit, materially deeper. Every widget renders
*something*, and the count of widgets whose worst realistic-config behavior is **wrong-data** has
dropped from 25/26 to **5/26**, with the other 21 down to **missing-detail** (renders correctly
but ignores a display or layout knob). The improvement came almost entirely from the cross-cutting
helpers the original audit predicted would each fix a class of widgets:

- **Host-group scoping** (positive `groupids`, nested-subgroup expansion, `exclude_groupids`) is now
  applied via a shared `scopedGroupIDs` helper across Problems, Problems by severity, Problem hosts,
  Top triggers, Top hosts, Host availability, and the navigators — no longer "dropped everywhere."
- **Tag filtering** (`tags`/`evaltype`) is now wired into **every** widget that has a tag filter —
  the problem/trigger family, Top hosts, the host navigator, the item-search path (Data overview,
  Honeycomb, Item navigator), Web monitoring (`httptest.get`), and Geomap (marker severity). This
  cross-cutting gap is fully closed.
- **Aggregation over a window** (`aggregate_function` + `time_period`) is implemented for Item value,
  Top hosts, and Pie chart via a shared engine. **Still missing** the per-dataset `aggregate_function`
  in Graph (svg) — though its `approximation` (min/avg/max trend backfill) is now honored.
- **Value maps** now come through the item-search path (`selectValueMap` added), so Data overview,
  Honeycomb, Item navigator, and Item history render labels, not raw codes.
- **Indexed-field reads** were corrected: Item history (`columns.N.itemid`), Honeycomb / Item
  navigator (`items.N`), Host navigator (`hosts.N`), SLA report (`slaid.0`) all read the real fields
  now instead of scalar/non-existent names.
- **Resolver signatures** were standardized to receive the widget: Problem hosts and Action log now
  do (and honor their scope/`show_lines`). **Map navigation tree still does not.**

The genuine strengths are unchanged: everything fetches under the session token, so server-side
permissions hold and nothing leaks. The wrong-data set is down to 5 and is now concentrated in a
handful of genuinely-unbuilt features — the navtree hierarchy (Map navigation tree), svggraph
per-dataset aggregation/`timeshift`, Action log's fixed window & content filters, and the
Data-overview / Honeycomb row caps — rather than a systemic scope/filter drop. The scope, tag, aggregation, value-map, status-derivation, and time-period themes the original
audit opened with are all closed.

## 2. Coverage matrix

Sorted by worst impact (wrong-data first; renders-nothing / entirely-wrong-content near the top,
cosmetic-leaning last).

| Widget | Support | Worst impact | # gaps | Headline gap |
|---|---|---|---|---|
| Map navigation tree | rendered-only | wrong-data | 6 | Resolver takes no `widget`; ignores entire `navtree`, lists every map on the server |
| SLA report | partial | missing-detail | 2 | Computes achieved SLI per service (`sla.getsli`) vs target with pass/fail color; shows only the latest period, and `serviceid` field name assumed (unverified live) |
| Web monitoring | partial | missing-detail | 1 | Status (`web.test.fail`) + full scope (`groupids`/`hostids`/tags/`exclude_groupids`) honored; only the 15-row view cap remains |
| Top triggers | partial | missing-detail | 1 | Now ranks by problem-event frequency over `time_period` with a count column; only acknowledgement filtering remains |
| Graph (svggraph) | partial | wrong-data | 7 | Per-dataset aggregation/`timeshift`/`axisy` ignored — `approximation` (min/avg/max trend backfill) now honored |
| Graph (classic) | partial | missing-detail | 1 | Pie/exploded-pie graphs render as a pie and Simple-graph (`itemid`) mode is supported; stacked graphs draw as overlaid lines (data correct, visual stacking pending) |
| Honeycomb | partial | wrong-data | 3 | Hardcoded 60-cell cap; units/label templates dropped — `items.N` + value maps + item-tag filter + threshold cell coloring now applied |
| Item navigator | partial | missing-detail | 2 | `group_by` flattened; `show_lines` default 100 — `items.N` + value maps + item-tag filter now applied |
| Data overview | partial | wrong-data | 3 | Arbitrary 100-item cap; hosts×items matrix flattened — `tags` + value maps now applied |
| Geomap | partial | missing-detail | 1 | Marker severity scoped to the widget's tag + severity filter; only `default_view` initial center/zoom (cosmetic) remains |
| Problems | partial | missing-detail | 1 | `groupids`/tags/suppression/acknowledgement all honored; only `show_lines` default (20 vs 25) remains |
| Problems by severity | partial | missing-detail | 1 | `groupids`/tags/`ext_ack` acknowledgement now honored; only `show_type=GROUPS` (collapsed to a flat tally) remains |
| Action log | partial | wrong-data | 4 | Hardcoded 7-day window; content filters (recipients/severities/statuses) ignored — now receives widget + honors `show_lines` |
| System information | partial | missing-detail | 1 | `info_type=1` shows HA nodes and `isRunning` is derived from them (`hanode.get`); standalone still uses the API-success proxy for running |
| Clock | partial | missing-detail | 1 | `time_type=host` (via `system.localtime` offset) and `tzone_timezone` now honored; server-time mode still falls back to local |
| Map | full | missing-detail | 1 | Trigger + host-group elements now colored by their real severity; only submap (map-type) elements — needing recursive child-map rollup — stay OK |
| Item value | partial | missing-detail | 4 | units/`units_show`/`decimal_places`/`description` overrides ignored — aggregation + `thresholds` alert color now honored |
| Gauge | partial | missing-detail | 8 | `description`/`units`/`units_show`/`decimal_places` overrides ignored (value + threshold arc correct) |
| Pie chart | partial | missing-detail | 5 | Pattern datasets expand correctly + per-dataset aggregation honored; still missing merge/center-total, units, value maps |
| Host availability | partial | missing-detail | 3 | Ignores maintenance, active-check availability (`active_available`), and layout — `groupids` + multi-interface classification now correct |
| Host navigator | partial | missing-detail | 2 | `group_by` flattened; `show_lines` default 100 — `hosts.N`/`status`/host-tags now honored |
| Problem hosts | partial | missing-detail | 2 | Per-severity-column layout + explicit host scoping missing — now receives widget; groups(nested)/tags/severity/suppression/exclude all applied |
| Top hosts | partial | missing-detail | 3 | Ranking + per-column aggregation honored; still missing tag/maintenance scope, exact-item match, units/thresholds |
| Trigger overview | partial | missing-detail | 3 | `show`(Any→OK cells)/tags/nested-scope honored; still missing `show_suppressed` and Recent-vs-Problems recency |
| Item history | partial | missing-detail | 2 | Reads `columns.N.itemid`/`show_lines`/value maps/`time_period`; still missing trend backfill + per-column thresholds |
| Discovery status | full | missing-detail | 1 | Filters to enabled rules, sorted by name; only a no-permission/empty distinction remains |

## 3. Prioritized fix list

### Tier 1 — Wrong data (app disagrees with Zabbix; erodes trust on a wall display)

**Landed since the original audit:**

- ~~**Web monitoring — scenario status not derived.**~~ **Done** — Ok/Failed/Unknown derived from each scenario's `web.test.fail[<name>]` item (fetched with `webitems: true`); `exclude_groupids` + tags scope still pending.
- ~~**Top triggers — wrong metric.**~~ **Done** — ranks by problem-event count over `time_period` (`event.get` grouped by trigger, busiest-first) with a count column, replacing the current-problems-by-severity list.
- ~~**Acknowledgement filtering dropped.**~~ **Done** — Problems (`acknowledgement_status`) and Problems by severity (`ext_ack`) map to `problem.get`'s `acknowledged` filter, so "unacknowledged only" no longer counts acked problems.
- ~~**Clock — `time_type=host` / `tzone_timezone` ignored.**~~ **Done** — host time is derived from the host's `system.localtime` item (reported-minus-collected offset) and the configured timezone is applied to both faces; server-time mode still falls back to local.
- ~~**System information — `isRunning` hardcoded true + `info_type` ignored.**~~ **Done** — `info_type=1` lists HA nodes via `hanode.get`, and `isRunning` is inferred from an active node; standalone servers (no HA nodes) keep the API-success proxy.
- ~~**Web monitoring — `exclude_groupids` + tags dropped.**~~ **Done** — tags filter `httptest.get` server-side and `exclude_groupids` drops scenarios whose host is in an excluded group (client-side), so the widget's full scope is honored.
- ~~**Map — non-host elements always OK.**~~ **Done** — trigger elements take the worst severity of their referenced triggers and host-group elements the worst across the group's hosts; only submap elements (needing a recursive child-map rollup) stay OK.
- ~~**Graph (classic) — graph type lost + Simple-graph unsupported.**~~ **Done** — pie/exploded-pie graphs (`graphtype` 2/3) render as a pie of each item's latest value, and Simple-graph mode (`itemid`, no `graphid`) plots the single item; stacked graphs (type 1) still draw as overlaid lines (correct data, visual stacking pending).
- ~~**Item value — thresholds ignored.**~~ **Done** — reads `thresholds.N` (shared `thresholdColorHex` helper) so a value crossing a band repaints the background with its alert color.
- ~~**Honeycomb — thresholds/cell coloring absent.**~~ **Done** — each cell is tinted by the threshold band its reading meets (same `thresholdColorHex` helper).
- ~~**Geomap — marker severity ignores widget `tags`.**~~ **Done** — `maxSeverityByHostID` now takes the widget's tag + severity filter, so a marker's color reflects only the problems the widget shows.
- ~~**Tag filtering on the item-search path.**~~ **Done** — `ZabbixItemSearchParameters` now carries `tags`/`evaltype` (forwarded to `item.get`); Data overview, Honeycomb, and Item navigator apply the widget's item-tag filter.
- ~~**Item history — item selector reads the wrong field.**~~ **Done** — reads `columns.N.itemid`, honors `show_lines` (default 25), applies value maps, bounds to `time_period`.
- ~~**Positive `groupids` scoping dropped.**~~ **Done** — a shared `scopedGroupIDs` (nested-aware) is applied in Problems, Problems by severity, Problem hosts, Top triggers, Top hosts, Host availability, and the navigators; the `problem.get`/`host.get` param structs carry `groupids`.
- ~~**Tag filtering (`tags`+`evaltype`) unimplemented everywhere.**~~ **Done** — a shared `tagFilters`/`tagEvalType` builder is wired into every widget with a tag filter: Problems, Problems by severity, Problem hosts, Trigger overview, Top triggers, Top hosts, Host navigator, the item-search path (Data overview, Honeycomb, Item navigator), Web monitoring, and Geomap.
- ~~**Aggregation over a window ignored.**~~ **Mostly done** — Item value, Top hosts, and Pie chart compute `aggregate_function` over `time_period`. Graph (svg) now honors `approximation` for its trend backfill; only its per-dataset `aggregate_function` remains.
- ~~**Top hosts — ranking unimplemented.**~~ **Done** — ranks up to 50 candidate hosts by the configured column (Top/Bottom N), limited to `show_lines`; per-column aggregation over `time_period`.
- ~~**Trigger overview — only PROBLEM state fetched.**~~ **Done** — `show: Any` fetches all triggers and renders OK cells green; tags + nested scope applied.
- ~~**Discovery — no `status=active` filter.**~~ **Done** — filters to `status: 0`, sorted by name.
- ~~**Problem hosts — resolver doesn't receive the widget.**~~ **Done** — now accepts `ZabbixWidget`; severity/groups(nested)/tags/suppression/exclude all applied.
- ~~**Action log — resolver doesn't receive the widget.**~~ **Partly done** — now accepts `ZabbixWidget` and honors `show_lines`; the 7-day window and content filters remain.
- ~~**Host availability — multi-interface classification bug.**~~ **Done** — available/unavailable/mixed/unknown categorization matches Zabbix; `groupids` scoping applied.
- ~~**Host navigator / Item navigator / Honeycomb — indexed-field reads.**~~ **Done** — read `hosts.N` / `items.N`; Host navigator honors `status` (Any/Enabled/Disabled).
- ~~**Value maps dropped on the "search" fetch path.**~~ **Done** — `ZabbixItemSearchParameters` requests `selectValueMap`; Data overview / Honeycomb / Item navigator / Item history apply `mappedText`.
- ~~**SLA report — mis-keyed `slaid`.**~~ **Done** — read with `firstIndexedValue`; no longer returns every SLA on the server.
- ~~**SLA report — wrong API.**~~ **Done** — computes achieved SLI per service via `sla.getsli` (latest period), labels rows via `service.get`, and colors each pass/fail against the target SLO. Only the latest period is shown; multi-period history is a follow-up.

**Still open:**

- **Map navigation tree — resolver doesn't receive the widget.** Change the signature to accept
  `ZabbixWidget`, then render the authored `navtree` hierarchy instead of listing every server map.
- **Host availability — `maintenance` not honored.** Add the `maintenance_status` filter (default
  excludes maintenance); also fetch `active_available` for active-check availability.
- **Graph (svggraph) — per-dataset aggregation/`timeshift`/`axisy`.** Reuse the aggregation engine
  for `aggregate_function`; apply `timeshift` to the window and honor left/right `axisy`.
  (`approximation` min/avg/max trend backfill is now done.)

### Tier 2 — Missing configured detail (renders, but ignores a knob)

- **`show_lines` / row caps.** ~~Item history~~ (done, 25), ~~Top hosts~~ (done, 10), ~~Action log~~
  (done, 25) fixed. Host nav / Item nav read `show_lines` but default 100; Honeycomb hardcodes
  `prefix(60)` and Data overview `prefix(100)` — these two are **safety caps with no corresponding
  Zabbix field**, left as-is. Problems default 20 vs 25; Top triggers 20 vs 10 — minor.
- **Grouping/tree structure flattened.** `group_by` (Host/Item navigator), `show_type=GROUPS`
  (Problems by severity), per-severity columns (Problem hosts), hosts×items matrix (Data overview),
  and the `navtree` hierarchy are all rendered as flat lists.
- **`time_period.to` and non-relative expressions.** ~~Item history~~ (done). Classic/svg graphs and
  Action log still always end at `now()` and drop `now/d`/absolute windows.
- **Units + decimal formatting.** `units`/`units_show` overrides and `decimal_places` ignored in Item
  value, Gauge, Honeycomb, Top hosts, Pie chart — raw `lastvalue` string shown.
- **Label/description templates.** `description`/`primary_label`/`secondary_label` macro templates
  ignored (Gauge, Item value, Honeycomb).
- **Pie chart merge + center total.** `merge`/`merge_percent` and the `total_show`/center-value
  block unimplemented.
- **Display styles.** `display` (bar/indicators), per-column `thresholds`/`base_color` (Top hosts,
  Item history), svg draw `type`/`stacked`/`fill`/`axisy`, problem overlays and percentile lines.
- **`only_totals`, `maintenance`, `hide_empty_groups`, `show`/`show_tags`/`show_opdata`** knobs
  ignored across the problem/availability widgets.

### Tier 3 — Cosmetic / nice-to-have

- All color/bold/size/position fields (Clock, Item value, Gauge, Honeycomb) — the native tvOS
  typography intentionally overrides these.
- Matrix orientation: `style`/`layout` (Trigger overview, Data overview, Problems by severity, Host
  availability).
- `show_legend`/`legend_*` (classic + svg graphs, Pie), `show_timeline`, `highlight_row`,
  `draw_type` doughnut-vs-pie, `default_view` initial map center/zoom (Geomap), `tzone_format`
  (Clock), SLO trailing-zero trimming.
- Discovery: a no-permission/empty-state distinction.

## 4. Cross-cutting patterns (where a shared helper fixes many widgets)

These were the leverage points, and most have now been built. Status is marked inline.

- **Host-group scoping helper (positive + exclude + nested).** ✅ **Built** — `scopedGroupIDs`
  expands nested subgroups and is applied across the problem/host family; `exclude_groupids` is
  honored via `problemsExcludingGroups` in Problems, Problems by severity, and Problem hosts, and
  client-side in Web monitoring (drops scenarios whose host is in an excluded group).
- **Tag-filter builder (`tags` + `evaltype`).** ✅ **Built** — `tagFilters`/`tagEvalType` wired into
  the problem/trigger family, Top hosts, Host navigator, and the item-search path
  (`ZabbixItemSearchParameters` now forwards `tags` to `item.get`; Data overview / Honeycomb / Item
  navigator scoped), Web monitoring (`httptest.get`), and Geomap (marker severity). No widget with a
  tag filter is left tag-unfiltered.
- **Suppression + maintenance handling.** ◐ **Partly** — `show_suppressed` honored in Problems,
  Problems by severity, Problem hosts; Trigger overview still can't (trigger.get lacks the filter).
  `maintenance` still ignored in Host availability, Honeycomb, Top hosts, Web, Host navigator.
- **Real `time_period` resolver.** ✅ **Built** — `timePeriod` returns `(from,to)` and is used by the
  aggregation widgets and Item history. Classic/svg graphs and Action log still don't apply `.to`;
  the dashboard-level foreign-reference default is still unresolved.
- **Unified aggregation engine.** ✅ **Built** — `aggregate`/`aggregatedValue` used by Item value,
  Top hosts, Pie chart. Graph (svg)'s per-dataset `aggregate_function` not yet wired in (its
  `approximation` trend selection is).
- **History-vs-trends reuse.** ◐ **Partly** — svggraph/classic graph backfill history from trends
  (peak-preserving); svggraph now honors `approximation` (min/avg/max), classic still uses `avg`.
  Item history honors `time_period` but not
  `columns.N.history` / trend backfill for short-retention items.
- **Value-map-aware item fetch.** ✅ **Built** — `ZabbixItemSearchParameters` now requests
  `selectValueMap`; `mappedItemValue` applies `mappedText` on the search path.
- **`value_type` correctness.** Handled for history table selection; still unused for formatting
  (`decimal_places`); text/log items silently dropped.
- **Pattern expansion for hosts/items.** ◐ **Partly** — Pie chart and svggraph expand multi-item
  patterns; host patterns still resolve via exact-technical-name `hostsByName`, so visible-name /
  wildcard host patterns match nothing.
- **Field-serialization discipline.** ✅ **Resolved for the known cases** — `columns.N.itemid`,
  `items.N`, `hosts.N`, `slaid.0` all read with indexed helpers now. A lint/test enforcing this
  convention would prevent regressions.
- **Pass the widget to every resolver.** ◐ **Partly** — Problem hosts, Action log, Discovery now
  receive it. **Map navigation tree still does not.**
- **Ranking + grouping models.** Top hosts ranking built; Top triggers frequency ranking and the
  grouping/tree widgets (navigators `group_by`, Problems-by-severity groups, Problem hosts severity
  columns, Data overview matrix, navtree hierarchy) still share missing "nest-by-attribute"
  primitives.

## 5. Data-robustness summary

- **Under-filtering, narrowing.** Every widget still fetches under the session token, so no leaks.
  The scope gap has shrunk further: group scoping and tag filtering (including the item-search path
  and Web) are now applied — including Geomap's marker severity. No widget shows a broader set than
  its own filter intends; the scope-fidelity gap the original audit opened with is closed.
- **Hard caps + arbitrary ordering.** Data overview `prefix(100)` and Honeycomb `prefix(60)` are
  intentional safety caps (no Zabbix field). Item history, Action log, and Top hosts now bound by
  the configured count. `problem.get limit:5000` remains a coarse ceiling for very busy servers.
- **History retention vs trends.** svg/classic backfill from trends but hardcode `avg`; Item value /
  Pie chart consult history only for aggregation, not display. Short-retention items remain the
  practical failure mode for the graph widgets.
- **Value maps + units + precision.** Value maps now render on the search path. Units overrides and
  `decimal_places` are still ignored broadly, so numeric presentation can drift even when the value
  is right.
- **State/enum modeling gaps.** Action log doesn't model status `2` (Failed) → failed alerts
  mislabeled as sent; Host availability can't represent active-check availability (`active_available`
  never fetched); multi-host triggers are attributed to `hosts.first` only. (System info's
  `isRunning` is now derived from HA node status where available.)
- **Stale-value semantics.** Widgets keyed on `lastvalue` (Item value non-aggregated, Honeycomb,
  navigators) keep showing a stale last sample for items that stopped reporting.
- **Not applicable (correctly).** History/trends, value maps, `value_type`, and aggregation don't
  apply to the event/topology/metadata widgets (Problems family, Trigger overview, Host availability,
  Discovery, Map/Geomap/navtree, System info, SLA, Web) — their concerns are filtering/status
  derivation, not item-value fidelity.
