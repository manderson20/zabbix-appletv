# Hiding hosts from the Apple TV dashboard with Zabbix permissions

This is the runbook for **Option 2**: instead of relying on a dashboard widget's
`exclude_groupids` filter, hide unwanted hosts (Apple TVs, test gear, anything you
don't want on the wall) by locking down the **Zabbix account the app logs in with**.

Tested against **Zabbix 7.0**.

---

## Why do it this way

The Apple TV app has **no access control of its own**. It shows exactly what its
Zabbix account is *permitted* to see, because every screen is built from that
account's own API responses, which Zabbix permission-filters server-side.

That has one important consequence, and it's the whole reason this document exists:

- A widget's **`exclude_groupids`** is only a *display* filter. Zabbix's web UI can
  apply it even for groups the account can't read (an exclusion only ever hides
  rows, so it's "permission-safe"). **The app cannot reproduce that**, because the
  API won't reveal the membership of groups the account can't read. So a widget that
  excludes a group the account can't see will over-count in the app.
- **Permissions**, on the other hand, are honored automatically and everywhere. If
  the account genuinely can't see a host, `problem.get` never returns it, and the
  app never shows it — on *every* widget, with no special handling.

So for an unattended wall display, hide by permission. It's more secure and it stays
correct as your groups change.

> Rule of thumb: **"exclude on the widget" needs the account to be able to *read* the
> group. "Hide by permission" needs the account to *not* be able to read it.** For a
> kiosk, the second is what you want.

---

## How Zabbix combines permissions (the one rule that matters)

Permissions are granted to **user groups**, not individual users. Each user group
sets a level per host group:

| Level | Meaning |
|-------|---------|
| **Read-write** | See and modify |
| **Read** | See only |
| **Deny** | Explicitly blocked |

When a host is in several groups with different levels, Zabbix combines them like so:

- **Read-write** beats **Read**.
- **Deny beats everything.** ← this is the lever we use.

That last line is critical: if an Apple TV is in both `Apple TVs` **and** some group
the wall display *does* show (e.g. `Discovered hosts`), a plain "no permission" on
`Apple TVs` is **not** enough — it stays visible via the other group. You must set
**Deny** on `Apple TVs` so it wins.

---

## Setup

### Step 1 — Put the hosts to hide in a dedicated group

Everything you want off the wall should live in one (or a few) host group(s) you
control, e.g. `Wall Display – Hidden` (or reuse an existing `Apple TVs` group).

- **Data collection → Host groups → Create host group**, or edit each host
  (**Data collection → Hosts →** *host* **→ Host groups**) and add it to the group.
- If you use nested groups (e.g. `Wall Display/Hidden`), note the "apply to
  subgroups" option in Step 3.

Keeping "hidden" membership in a single group is what makes this robust: as long as
new Apple TVs land in that group, they're hidden automatically.

### Step 2 — Create a read-only user group for the app

**Users → User groups → Create user group**

- **Name:** `Apple TV Dashboard (read-only)`
- **Host permissions** tab → add entries:
  - **Read** on the group(s) you *do* want shown. Tip: you can grant Read on a
    top-level parent group and, when adding it, tick **"Include subgroups"** so all
    children inherit it — fewer entries to maintain.
  - **Deny** on `Wall Display – Hidden` (and any other group to hide).
  - If the hidden group is nested, also tick **"Include subgroups"** on the Deny entry.
- Leave frontend access at default; the app only needs the API (controlled by the
  role in Step 3).

> Because Deny beats Read, any host in the hidden group is invisible to this user
> group even if it's also in a group you granted Read.

### Step 3 — Create the dedicated app user

**Users → Users → Create user**

- **Username / password:** a fresh, strong credential used *only* by the Apple TVs.
  Don't reuse your admin login.
- **Groups:** add **only** `Apple TV Dashboard (read-only)`. (Membership in any other
  group could grant extra visibility.)
- **Role:** assign a role that has **API access** enabled. The built-in **`User`**
  role works. (Optional hardening in the last section restricts it to read-only API
  methods.)

### Step 4 — Point the app at the new account

On each Apple TV: open the app → **Server Configuration** → enter the new
**username** and **password** (same server URL) → **Save**. The dashboard reconnects
and now reflects the locked-down account.

### Step 5 — (Optional) drop the widget `exclude_groupids`

Once hosts are hidden by permission, the widgets' `exclude_groupids = 27, 40` is
redundant. You can leave it (harmless) or remove it from the dashboard's **Problems**
and **Problems by severity** widgets to keep the config honest.

### Step 6 — Verify

The fastest check that doesn't involve the TV:

1. Log into the Zabbix **web UI as the new app account** (an incognito window helps).
2. Go to **Monitoring → Problems**. The hidden hosts should **not** appear, and the
   total should drop to the intended number.
3. The Apple TV app, using the same account, will match automatically — the
   "Problems by severity" totals included.

If Monitoring → Problems for the new account already excludes the hosts, you're done;
the app cannot show anything that view doesn't.

---

## Keeping it correct as things change

- **New Apple TVs / test hosts:** make sure they get added to the hidden group. If
  they're auto-discovered, point the discovery action / host prototype at the hidden
  group so they land there from the start.
- **Nested groups:** if you organize hidden hosts under a parent (`Wall Display/…`),
  a Super Admin can set **"Apply permissions to all subgroups"** on the host group so
  new subgroups inherit the Deny.
- **This is separate from maintenance/suppression.** Putting a host in maintenance
  hides its problems temporarily; this permission setup hides the host from this
  account permanently. Both can be in play at once.

---

## Optional hardening (recommended for a kiosk)

A wall display should be able to *read* and nothing else.

- **Restrict the role to read-only API:** **Users → User roles → Create user role**
  (User type) → under **API**, set **"Allowed methods"** and use a `*.get` pattern
  (e.g. allow only methods ending in `.get`), or explicitly deny write methods.
  Assign this role to the app user instead of the stock `User` role.
- **No frontend needed:** you can disable frontend (GUI) access for the app's user
  group and keep only API access, so the credential can't be used to log into the web
  UI at all.
- **Rotate the credential** if it's ever entered on a shared/again-imaged device.

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|--------|--------------|-----|
| Hidden host still shows in the app | It's in a group the account has **Read** on, and the hidden group is only "no permission", not **Deny** | Set the hidden group to **Deny** (Deny overrides Read) |
| App shows *nothing* / can't connect | The account has no **Read** anywhere, or the role lacks **API** access | Grant Read on the shown groups; ensure the role has API enabled |
| Counts still differ from an admin's web view | You're comparing against a *different* (more privileged) account | Compare **Monitoring → Problems** logged in as the *app's* account — that's the app's ground truth |
| A whole subgroup of hosts leaked | Permissions weren't applied to nested subgroups | Re-add the group with **"Include subgroups"**, or enable subgroup inheritance on the host group |

---

*Context: the app mirrors its Zabbix account 1:1 and delegates all access control to
Zabbix. Hiding by permission is therefore the durable, secure way to curate the wall
display — the app follows whatever that account is allowed to see.*
