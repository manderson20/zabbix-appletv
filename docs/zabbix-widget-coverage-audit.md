# Zabbix Widget Coverage Audit — tvOS Dashboard Renderer

## 1. Executive summary

Across all 26 audited widgets, coverage is broad but shallow: every widget renders *something*, yet 25 of 26 carry a **wrong-data** severity — meaning that for at least one realistic configuration the Apple TV disagrees with what Zabbix itself displays. Only the classic **Map** widget reaches "full" support, and even it mis-colors non-host elements; only **Gauge** escapes with a mere missing-detail rating. The failures cluster into a handful of systemic themes rather than 26 unique bugs: (a) **filter/scope fields are silently dropped** — positive host-group scoping (`groupids`), tag filtering (`tags`/`evaltype`), maintenance/suppression, and acknowledgement are ignored across most problem- and host-oriented widgets, so the app routinely shows a *superset* of what the widget was scoped to; (b) **aggregation over a time window is unimplemented** — `aggregate_function` + `time_period` are ignored in Item value, Pie chart, Graph (svg), and Top hosts, which all fall back to the instantaneous last value; (c) **several resolvers read the wrong or a non-existent field** (Item history, Honeycomb, Item navigator, Host navigator, SLA report), or don't receive the widget at all (Problem hosts, Action log, Map navigation tree), so their primary selector never applies — Item history renders nothing; (d) **value maps and units are dropped** wherever items are fetched through the "search" parameter path instead of the "get" path. The single highest-leverage observation is that most of these are **shared-helper problems**: a common group-scope helper, a tag-filter builder, a real `time_period` resolver, a unified aggregation engine, and a value-map-aware item fetch would each fix 4–12 widgets at once. The app's genuine strengths — permission-safe fetches (everything runs under the session token), and the existing history+trend-backfill machinery — are real assets that are simply not wired into every widget that needs them.

## 2. Coverage matrix

Sorted by worst impact (wrong-data first; renders-nothing / entirely-wrong-content at the top of the wrong-data band, cosmetic-leaning last).

| Widget | Support | Worst impact | # gaps | Headline gap |
|---|---|---|---|---|
| Item history | unsupported | wrong-data | 6 | Reads non-existent `itemids`; real items live at `columns.N.itemid` → renders nothing |
| Map navigation tree | rendered-only | wrong-data | 6 | Ignores entire `navtree`; lists every map on the server, not the configured tree |
| SLA report | rendered-only | wrong-data | 5 | Shows static target SLO via `sla.get`, never the computed SLI (`sla.getsli`) |
| Action log | rendered-only | wrong-data | 6 | Hardcoded 7-day window; all four content filters + statuses ignored |
| Problem hosts | rendered-only | wrong-data | 7 | Resolver takes no `widget`; all group/host/tag/severity scoping impossible |
| Honeycomb | partial | wrong-data | 7 | Item selector reads bogus `itempatterns.N.itemname`; thresholds/coloring absent |
| Item navigator | partial | wrong-data | 5 | Reads field `item`; Zabbix stores `items.N` → pattern never applied, lists all items |
| Host navigator | partial | wrong-data | 7 | Reads non-existent `hostids` (real field `hosts`); `status` hardcoded enabled-only |
| Top triggers | partial | wrong-data | 5 | Wrong metric — current problems by severity, not event-frequency over `time_period` |
| Top hosts | partial | missing-detail | 3 | Ranking (`order`/`column`/`show_lines`) + per-column `aggregate_function` over `time_period` now honored; still missing tag/maintenance scope, exact-item match, units/thresholds |
| Trigger overview | partial | wrong-data | 6 | `show` hardcoded to PROBLEM-only; no OK/green cells, ignores `show_suppressed` |
| Item value | partial | wrong-data | 6 | `aggregate_function`+`time_period` and `thresholds` ignored → wrong number, no alert color |
| Pie chart | partial | wrong-data | 8 | Aggregation ignored + pattern datasets collapsed to one slice → wrong proportions |
| Graph (svggraph) | partial | wrong-data | 8 | Per-dataset aggregation/`timeshift`/`approximation`/`axisy` all ignored |
| Graph (classic) | partial | wrong-data | 7 | Graph type (stacked/pie) lost; Simple-graph mode (`itemid`) unsupported |
| Data overview | partial | wrong-data | 5 | `tags` ignored + value maps dropped + 100-item arbitrary cap |
| Host availability | partial | wrong-data | 6 | `groupids` ignored (whole server counted); maintenance inverted; classification bug |
| Problems | partial | wrong-data | 7 | Only `exclude_groupids` honored; positive `groupids`, tags, ack all dropped |
| Problems by severity | partial | wrong-data | 5 | `groupids`/tags/`ext_ack` ignored → inflated counts; `show_type` groups view collapsed |
| Web monitoring | partial | wrong-data | 5 | Ok/Failed/Unknown status not derived; `exclude_groupids`/tags ignored |
| System information | partial | wrong-data | 4 | `info_type` ignored (HA mode wrong); `isRunning` hardcoded true |
| Discovery status | partial | wrong-data | 3 | No `status=active` filter → lists disabled discovery rules |
| Geomap | partial | wrong-data | 3 | Marker severity uses server-wide problems, ignores widget `tags` filter |
| Clock | partial | wrong-data | 4 | `time_type=host`/`tzone_timezone` ignored → shows device local time, wrong |
| Map | full | wrong-data | 5 | Non-host elements (submap/group/trigger) always colored OK/green |
| Gauge | partial | missing-detail | 8 | `description`/`units`/`units_show`/`decimal_places` overrides ignored |

## 3. Prioritized fix list

### Tier 1 — Wrong data (app disagrees with Zabbix; erodes trust on a wall display)

- **Item history — item selector reads the wrong field.** Read columns via `indexedFieldGroups(prefix:"columns")` and use each group's `itemid`; the widget currently reads `itemids` and renders nothing for every real 7.0 widget.
- **Honeycomb — item pattern reads bogus `itempatterns.N.itemname`.** Read the real `items.N` pattern array (`CWidgetFieldPatternSelectItem`) and pass it to `item.get` search; today an unfiltered fetch returns all server items, first 60 shown.
- **Item navigator — reads field `item` instead of `items.N`.** Same class of bug; switch to the indexed `items` pattern array so scoping actually applies.
- **Host navigator — reads non-existent `hostids`; real field is `hosts` (name patterns).** Read `hosts.N` patterns and stop hardcoding `filter{status:0}` — honor the `status` field (Any/Enabled/Disabled).
- **SLA report — mis-keyed `slaid` + wrong API.** Read `slaid` with the indexed helper (`firstIndexedValue`, as every other reference field does), and compute the report with `sla.getsli(serviceids, periods)` instead of returning the static target from `sla.get`.
- **Problem hosts / Action log / Map navigation tree — resolvers don't receive the widget.** Change the resolver signatures to accept `ZabbixWidget` so any field can be read at all; then apply group/host/tag scope (problemhosts), `time_period`+filters (actionlog), and the authored `navtree` (navtree).
- **Positive `groupids` scoping dropped.** Apply it in Problems, Problems by severity, Problem hosts, Top triggers, Host availability (the `problem.get`/`host.get` param structs need a `groupids` key where missing). This is the most common cause of inflated counts/extra rows.
- **Tag filtering (`tags`+`evaltype`) unimplemented everywhere.** Add a shared tag-param builder and apply to Problems, Problems by severity, Problem hosts, Trigger overview, Top triggers, Top hosts, Data overview, Honeycomb, Web, Geomap, Host/Item navigator.
- **Aggregation over a window ignored.** Item value, Pie chart, Graph (svg), Top hosts must compute `aggregate_function` over `time_period` (via history/trends) instead of showing `lastvalue`.
- **Top triggers — wrong metric.** Rank by problem-event count over `time_period` (`event.get` grouped by `objectid`, ordered by count DESC) and surface the count column; currently sorts current problems by severity.
- ~~**Top hosts — ranking unimplemented.** Honor `column` (order-by), `order` (Top/Bottom N), and `show_lines` instead of default hostid order capped at 25.~~ **Done** — ranks up to 50 candidate hosts by the configured column (Top/Bottom N), limited to `show_lines` (default 10); per-column `aggregate_function` computed over `time_period`.
- **Trigger overview — only PROBLEM state fetched.** Honor `show` (Recent/Problems/Any) so OK/green cells render, and apply `show_suppressed`.
- **Item value — thresholds ignored.** Read `thresholds` (the gauge resolver already does) so the value-driven background alert color fires.
- **Host availability — `maintenance` inverted + multi-interface classification bug.** Add the `maintenance_status` filter (default excludes maintenance) and fix `{available,unknown}`/`{unavailable,unknown}` categorization to match Zabbix's unknown/mixed rules.
- **Acknowledgement filtering dropped.** Problems (`acknowledgement_status`) and Problems by severity (`ext_ack`) over-count acknowledged problems.
- **Value maps dropped on the "search" fetch path.** Data overview, Top hosts, Honeycomb, Item navigator, Item history show raw numeric codes; request `selectValueMap` and apply `mappedText`.
- **Discovery — no `status=active` filter.** Add it so disabled discovery rules stop appearing.
- **System information — `isRunning` hardcoded true + `info_type` ignored.** The HA-nodes mode shows a version string; and "running" can display while the server is down.
- **Graph (classic) — graph type lost + Simple-graph unsupported.** Fetch `graphtype` and render stacked/pie correctly; implement `source_type=1`/`itemid`.
- **Web monitoring — scenario status not derived.** Fetch each scenario's status items to render Ok/Failed/Unknown; also apply `exclude_groupids`.
- **Map — non-host elements always OK.** Compute status for submap/host-group/trigger elements, not just hosts, so red child maps don't render green.
- **Clock — `time_type=host` and `tzone_timezone` ignored.** Fetch the item's `lastclock` for host-time mode and honor the configured timezone instead of device local time.
- **Geomap — marker severity ignores widget `tags`.** Scope `maxSeverityByHostID` to the configured tag filter.

### Tier 2 — Missing configured detail (renders, but ignores a knob)

- **`show_lines` / row caps ignored or wrong-defaulted.** Item history (hardcoded 5), Top hosts / Host nav / Item nav (hardcoded 100), Data overview (100), Honeycomb (60), Action log (50), Problems (default 20 vs Zabbix 25), Top triggers (20 vs 10) — read `show_lines` with the correct per-widget default.
- **Grouping/tree structure flattened.** `group_by` (Host/Item navigator), `show_type=GROUPS` (Problems by severity), per-severity columns (Problem hosts), hosts×items matrix (Data overview), and the `navtree` hierarchy are all rendered as flat lists.
- **`time_period.to` and non-relative expressions ignored.** Classic/svg graphs, Item history, Action log always end at `now()` and drop `now/d`/absolute windows.
- **Units + decimal formatting.** `units`/`units_show` overrides and `decimal_places` ignored in Item value, Gauge, Honeycomb, Top hosts, Pie chart — raw `lastvalue` string shown.
- **Label/description templates.** `description`/`primary_label`/`secondary_label` macro templates ignored (Gauge, Item value, Honeycomb) — only the literal item/host name is shown.
- **Pie chart merge + center total.** `merge`/`merge_percent` and the whole `total_show`/center-value block unimplemented.
- **Display styles.** `display` (bar/indicators), per-column `thresholds`/`base_color` (Top hosts, Item history), svg draw `type`/`stacked`/`fill`/`axisy`, problem overlays and percentile lines all dropped.
- **`only_totals`, `maintenance`, `hide_empty_groups`, `show`/`show_tags`/`show_opdata`** knobs ignored across the problem/availability widgets.

### Tier 3 — Cosmetic / nice-to-have

- All color/bold/size/position fields (Clock, Item value, Gauge, Honeycomb) — the native tvOS typography intentionally overrides these.
- Matrix orientation: `style`/`layout` (Trigger overview, Data overview, Problems by severity, Host availability).
- `show_legend`/`legend_*` (classic + svg graphs, Pie), `show_timeline`, `highlight_row`, `draw_type` doughnut-vs-pie, `default_view` initial map center/zoom (Geomap), `tzone_format` (Clock), SLO trailing-zero trimming.
- Discovery: alphabetical sort by rule name and a no-permission/empty-state message.

## 4. Cross-cutting patterns (where a shared helper fixes many widgets)

These are the leverage points. Each is one helper that corrects a whole class of widgets rather than a per-widget patch — the key to making the renderer generically config-faithful.

- **Host-group scoping helper (positive + exclude + nested).** `groupids` is applied in some widgets and ignored in Problems, Problems by severity, Problem hosts, Top triggers, Host availability; `exclude_groupids` is honored in Problems/Problems-by-severity (`problemsExcludingGroups`) but *not* in Problem hosts or Web despite the helper existing. Zabbix group scoping also includes **nested subgroups** (`Group/*`), which exact-match logic misses. **One `scopeToGroups(include:exclude:)` helper — plus adding `groupids` to the `problem.get`/`host.get`/`httptest.get` param structs — corrects ~8 widgets.**
- **Tag-filter builder (`tags` + `evaltype`).** Not implemented in a single widget. A shared builder that emits the `tags`/`evaltype` params (and, where the API can't, a client-side And/Or evaluator) fixes ~12 widgets that currently show a tag-unfiltered superset.
- **Suppression + maintenance handling.** `show_suppressed` is done well in Problems/Problems-by-severity but hardcoded or ignored in Trigger overview, Problem hosts, Honeycomb, Top hosts, Host availability, Web, Host navigator; the analogous `maintenance` toggle is ignored (and effectively inverted) in Host availability, Honeycomb, Top hosts, Web, Host navigator. **A shared "problem/host visibility" helper carrying suppressed + maintenance defaults unifies these.**
- **Real `time_period` resolver.** `historyWindowSeconds` only parses `time_period.from` as `now-<N><unit>` and drops `.to`, aligned expressions (`now/d`), and — critically — the **dashboard-level foreign-reference** default used by Graph/Top triggers/Action log/Item history/SLA report. **One resolver that returns `(from,to)` and resolves the dashboard reference** fixes the X-axis window and ranking window across all time-based widgets.
- **Unified aggregation engine.** `aggregate_function`+`time_period` (and svg's `aggregate_interval`/`grouping`, pie's `dataset_aggregation`) are ignored in Item value, Pie chart, Graph (svg), Top hosts. **One "aggregate item(s) over window with function F from history/trends" routine** — reusing the existing `recentPoints`/trend-backfill machinery — corrects all of them.
- **History-vs-trends reuse.** The repo already backfills history from trends for svggraph/classic graph (commit `1d518f3`) with peak-preserving bucketing. Item history hardcodes `history.get` (ignoring `columns.N.history` and retention), and Item/Pie fetch no history at all. **Wire the existing helper into those widgets and honor the per-dataset `approximation` (min/avg/max)** instead of hardcoding `value_avg`.
- **Value-map-aware item fetch.** The correctness split is structural: `ZabbixItemGetParameters` requests `selectValueMap` (Item, Gauge — correct) while `ZabbixItemSearchParameters` does not (Data overview, Top hosts, Honeycomb, Item navigator, Item history — raw numbers). **Add `selectValueMap` to the search params and apply `mappedText` in one place.**
- **`value_type` correctness.** Handled for history-based widgets (table selection) but unused where it matters for formatting (`decimal_places`, aggregation numeric-awareness); text/log items are silently dropped. Fold into the aggregation/formatting helper.
- **Pattern expansion for hosts/items.** Pie chart, svggraph, Top hosts, Honeycomb resolve host patterns via exact-technical-name `hostsByName`, so wildcard/visible-name patterns (`Linux *`, `*`) match nothing. **A shared wildcard pattern-expander (host.get name search + item.get `searchWildcardsEnabled`) that returns one series/slice per matched item** fixes both the "resolves nothing" and the "collapsed to one slice" failures.
- **Field-serialization discipline.** Multiple resolvers read scalar/singular names for indexed fields: `itemids` vs `columns.N.itemid` (Item history), `itempatterns.N.itemname` vs `items.N` (Honeycomb), `item` vs `items.N` (Item navigator), `hostids` vs `hosts.N` (Host navigator), flat `slaid` vs `slaid.0` (SLA report). **A convention (and a lint/test) that pattern-select and multiselect/reference fields are always read with the indexed helpers** would have caught all five.
- **Pass the widget to every resolver.** `resolveProblemHosts`, `resolveActionLog`, `resolveMapNavigationTree`, `resolveDiscoveryStatus` take only `(serverBaseURL:authToken:)`, structurally guaranteeing zero field support. **Standardize every resolver signature to accept `ZabbixWidget`.**
- **Ranking + grouping models.** Two ranking widgets (Top triggers, Top hosts) and several grouping/tree widgets (Host/Item navigator `group_by`, Problems-by-severity groups, Problem hosts severity columns, Data overview matrix, navtree hierarchy) share missing "order/limit-by-value" and "nest-by-attribute" primitives that could be modeled once.
- **`show_lines` default reader.** Centralize reading `show_lines` with the correct default so no widget hardcodes `prefix(5/50/60/100)` or a wrong 20.

## 5. Data-robustness summary

- **Under-filtering, not over-exposure.** Every widget fetches under the session auth token, so Zabbix server-side permissions hold and no hidden host/problem/map leaks — this is a genuine strength. The robustness gap is the inverse: widget-level scope (groups/hosts/tags/ack/maintenance/name) is applied inconsistently, so the app shows a *broader* set than the widget's own config intends.
- **Hard caps + arbitrary ordering.** Fixed limits truncate and reorder nondeterministically: Item history `limit:5`, Action log `50`, Data overview `prefix(100)`, Honeycomb `prefix(60)`, Trigger overview `limit:100`, Top hosts `prefix(25)`, plus `problem.get limit:5000` (undercounts on very busy servers). Several truncate in `itemid`/`eventid` order — not the sort Zabbix would apply — so the first N rows can be entirely different rows.
- **History retention vs trends.** The trend-backfill logic exists but isn't universal: Item history shows empty where Zabbix resolves from trends; Item value / Pie chart never consult history at all; svg backfill hardcodes `avg` regardless of `approximation`. Short-retention items are the practical failure mode.
- **Value maps + units + precision.** Mapped items render as raw codes on the search-param path; units overrides and `decimal_places` are ignored broadly, so numeric presentation drifts from Zabbix even when the underlying value is right.
- **State/enum modeling gaps.** Action log doesn't model status `2` (Failed) → failed alerts mislabeled as sent; Host availability mis-classifies multi-interface hosts and can't represent active-check availability (`active_available` never fetched); System info hardcodes `isRunning=true`; multi-host triggers are attributed to `hosts.first` only, skewing per-host problem counts.
- **Stale-value semantics.** Widgets keyed on `lastvalue` (Item, Pie, Honeycomb, navigators) keep showing a stale last sample for items that stopped reporting, whereas a period-aggregated Zabbix view over an empty window would show nothing/zero.
- **Not applicable (correctly).** History/trends, value maps, `value_type`, and aggregation genuinely don't apply to the event/topology/metadata widgets (Problems family, Trigger overview, Host availability, Discovery, Map/Geomap/navtree, System info, SLA, Web) — their robustness concerns are all filtering/status-derivation, not item-value fidelity.