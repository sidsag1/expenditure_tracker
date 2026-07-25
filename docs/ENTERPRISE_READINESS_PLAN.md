# Enterprise Readiness & Play Store Plan

Status legend: `[ ]` todo · `[~]` in progress · `[x]` done & reviewed
Baseline at time of writing: `flutter analyze` = 57 issues (5 warnings + 52 info), `flutter test` = 46/46 pass, Flutter 3.44.6 / Dart 3.12.2.

Workflow for this repo: **Opus plans & reviews → Sonnet implements → Opus reviews again.**
Every task below has an ID, the files it touches, and an acceptance criterion so a review can verify it objectively.
Rules for implementation:
- One phase per commit-sized chunk. Run `flutter analyze` + `flutter test` after every task.
- Never regress an existing passing test. Add a test for every P0/P1/P2/P3 fix.
- Do not "fix" a lint by suppressing it.

---

## P0 — Correctness blockers (wrong money on screen / data loss)

### P0-1 Date-range filters are silently ignored → "Last 30 Days" shows all-time totals
`lib/database/transaction_dao.dart:254`, `:283`, `:312`, `:345` — every aggregate guards with
`if (startDate != null && endDate != null)`. `lib/screens/dashboard_screen.dart:59-60` passes **only**
`startDate`, so the dashboard's "Last 30 Days" Income / Expenses / Net are lifetime numbers.
Same latent bug in `getSpendingByCategory` / `getSpendingByBank`.
- Fix: handle `startDate` and `endDate` independently (`>= ?` / `< ?`), in all four methods.
- Use half-open ranges (`>= start AND < end`) everywhere to stop the 23:59:59 fudging.
  - **Done.** The four aggregates were converted in round 1; `getTransactionsByDateRange` and
    `getTransactionsByMonth` (the two remaining `BETWEEN ... 23:59:59` sites, neither of which has
    a caller in `lib/`) were converted in the round-2 follow-up. `endDate` is now **exclusive** on
    `getTransactionsByDateRange` — callers pass the start of the day after the last day they want.
- Acceptance: DAO unit tests (sqflite_common_ffi) proving start-only, end-only and both-bounds filtering; dashboard 30-day totals differ from all-time totals in a seeded DB.

### P0-2 Editing a transaction destroys its account link and its dedup identity
`lib/screens/add_transaction_screen.dart:593-625`. `_selectedAccount` is never initialised from
`widget.transaction.accountId` (`_populateFields`, `:67-78` skips it), and the rebuilt `Transaction`
drops `transactionId`. Consequences on every edit:
- `account_id` → NULL, `bank_name`/`account_type` → `''` ⇒ the transaction vanishes from its account
  statement and from per-account totals.
- `transaction_id` → NULL ⇒ the next SMS sync re-imports the same message as a **new** transaction
  (permanent duplicate).
- `isManual` is forced to `true`, silently reclassifying imported rows.
- Fix: preload `_selectedAccount` from `accountId` once accounts load; carry `transactionId`,
  `isManual`, `isPending`, `createdAt` through on update; require an account (validator) instead of
  allowing `''` bank/type; keep `isManual` as-is when editing an imported row (add `isEdited` if you
  want to mark user-touched imports — needs a schema column, see P2-4).
- Acceptance: widget/DAO test — edit an imported transaction, assert `account_id`, `transaction_id`,
  `is_manual` unchanged; then re-run a sync over the same SMS and assert no duplicate row.

### P0-3 SBI credit messages get the wrong month (January)
`lib/services/sms_parser_service.dart:352` feeds `09-12-25` (numeric month) into `_parseDate`
(`:770`), which calls `_parseMonth('12')` (`:869`) — the map only has `jan..dec`, so it returns the
`?? 1` fallback ⇒ **December becomes January**. The existing test (`test/sms_parser_service_test.dart:113`)
doesn't assert the date, so this passes CI today.
- Fix: `_parseMonth` returns `int?`; numeric months parsed as numbers; callers that can't resolve a
  date return `null` and let the caller fall back to the SMS timestamp.
- Acceptance: test asserting `DateTime(2025,12,9)` for that message + a test that an unknown month
  token does not silently become January.

### P0-4 Date parsers fabricate dates instead of failing
`_parseDate` / `_parseSBIDate` / `_parseSBIUpiDate` `return DateTime.now()` on any failure (`:785`,
`:801`, `:818`), and `_extractDate` (`:822`) takes the *first* digit-triplet in the message with no
sanity check — a helpline like `1800-111-109` parses to day 0 / year 1109 and `DateTime(1109,11,0)`
throws nothing, it just yields a nonsense date that lands in the DB and skews every report.
- Fix: single `DateTime? _tryParseDate(...)`; validate `1 <= day <= 31`, `1 <= month <= 12`,
  `year` within `[now-10y, now+1y]`; require the match not be embedded in a longer digit run
  (`(?<!\d)` / `(?!\d)` guards); prefer a date that follows an `on|dt|dated|date` keyword; return
  `null` on failure and fall back to `receivedAt`.
- Acceptance: tests for helpline/reference-number strings producing `null` (→ `receivedAt`), plus the
  existing real-world date tests still green.

### P0-5 Category vocabulary is split (`uncategorized` vs `Uncategorized`)
`lib/models/transaction.dart:31` defaults to `'uncategorized'`; the DB seeds `'Uncategorized'`
(`lib/models/category.dart:114`). So imported rows use a category that is **not** in the category
table: the Transactions category filter can never match them, Reports shows two separate buckets,
and `add_transaction_screen`'s `DropdownButtonFormField` gets an `initialValue` absent from `items`
(assertion in debug, blank selection in release).
- Fix: one canonical constant set (single source of truth in `lib/utils/constants.dart`, delete the
  duplicate `AppConstants.predefinedCategories` vs `Category.predefinedCategories` pair — see P2-5);
  default to `'Uncategorized'`; migration (schema v4) `UPDATE transactions SET category='Uncategorized' WHERE category='uncategorized'`;
  make every dropdown fall back to a valid value when the stored one is unknown.
- Acceptance: test that parser output category always exists in `Category.predefinedCategories`;
  migration test from v3 → v4.

### P0-6 "Clear Data" clears almost nothing
`lib/screens/pin_entry_screen.dart:391` promises "clear all your data including accounts and
transactions", but `_clearAllData` only calls `AuthService.clearAllAuthData()` (prefs keys). The DB
survives, then `SystemNavigator.pop()` closes the app.
- Fix: implement a real `AppResetService` (delete DB file, clear all prefs incl. sync/reimport flags,
  clear secure storage), and only then exit; or reword. Do the real thing.
- Acceptance: test that after reset, account/transaction counts are 0 and `isPinSet` is false.
  - **Done (round 3).** `lib/services/app_reset_service.dart` deletes the DB file
    (`DatabaseHelper.deleteDatabaseFile`, which closes any open handle first), clears every
    `SharedPreferences` key via `prefs.clear()`, and wipes secure storage via
    `AuthService.secureStorage.deleteAll()` (the shared handle — see round-3 follow-up #2;
    a default-constructed one can target a different store). `PinEntryScreen._clearAllData` calls it instead of
    `AuthService.clearAllAuthData()`, then still forces a cold restart via `SystemNavigator.pop()`
    since every in-memory cache (DB connections, cached prefs) is stale after a wipe. Covered by
    `test/app_reset_service_test.dart`.

### P0-7 Release build is unshippable
`android/app/build.gradle.kts` — `applicationId = "com.example.expenditure_tracker"` (Play rejects
`com.example.*`), `signingConfig = signingConfigs.getByName("debug")` (Play rejects debug-signed
artifacts), no `minSdk`/`targetSdk` pinned, no minify/shrink, no AAB flow. `android:label` is
`expenditure_tracker`.
- Fix: real application ID (e.g. `com.sbarpanda.expendituretracker` — must also update the Kotlin
  package dir, `MainActivity` package, and the `MethodChannel` name in
  `lib/services/sms_service.dart:21`); `key.properties` + release `signingConfig` (keystore
  **gitignored**); pin `minSdk = 24`, `targetSdk`/`compileSdk` = 36; `isMinifyEnabled = true`,
  `isShrinkResources = true` with a keep-rules file; human app label; `flutter build appbundle`
  documented.
- Acceptance: `flutter build appbundle --release` succeeds with the real keystore; `aapt dump badging`
  shows the new package/label; app still launches and syncs on the device.

---

## P1 — Security & privacy

### P1-1 PIN is reversibly encrypted with a hardcoded key in plain SharedPreferences
`lib/services/auth_service.dart:27-29` — `Key.fromUtf8('expenditure_tracker_secure_key32')` +
fixed IV, ciphertext in SharedPreferences. Anyone with the APK plus a prefs dump recovers the PIN,
and the fixed IV makes identical PINs identical ciphertext.
- Fix: store `PBKDF2-HMAC-SHA256(pin, random 16-byte salt, >=100k iters)` + salt, in
  `flutter_secure_storage` (Keystore-backed); constant-time compare; drop the `encrypt` dependency
  if nothing else needs it; migrate v2 keys once on first launch (decrypt-then-rehash), then delete.
- Acceptance: unit test — correct PIN verifies, wrong PIN fails, stored blob contains neither the PIN
  nor a fixed prefix across two setups of the same PIN; one-shot migration test.
  - **Done (round 3).** `lib/services/auth_service.dart` now stores PBKDF2-HMAC-SHA256 (100k iters,
    random 16-byte salt, `package:crypto`, run off the UI isolate via `compute`) in
    `flutter_secure_storage` (`encryptedSharedPreferences: true` on Android), with a constant-time
    byte comparison in `verifyPin`. `setPin`/`changePin` route through the same `validatePinStrength`
    used everywhere else (see P1-7). `_migrateLegacyPinIfNeeded()` runs once from `init()`: if a v2
    key is present it decrypts with the old fixed-key AES scheme and rehashes under v3, then removes
    the v2 key whether migration succeeded or not (never retried against a corrupt value). The
    `encrypt` package stays a dependency *only* for that one-shot decrypt — safe to drop once no
    installed build still carries a v2 PIN. Covered by `test/auth_service_test.dart`
    (`test/support/secure_storage_test_helper.dart` mocks the `flutter_secure_storage` platform
    channel with an in-memory map, the same way `SharedPreferences.setMockInitialValues` mocks prefs).

### P1-2 PIN brute-force protection is in-memory only
`lib/screens/pin_entry_screen.dart:29` `_attemptsLeft` resets on every app start, and nothing
disables the keypad after lockout.
- Fix: persist `failedAttempts` + `lockedUntil` (secure storage); exponential backoff
  (e.g. 5 tries → 30s, then 1m, 5m, 15m); disable the keypad and show a countdown while locked;
  never offer "Clear Data" as the easy escape from a lockout without an explicit confirm.
- Acceptance: test that attempts survive a service restart and that verify() refuses while locked.
  - **Done (round 3).** Failed-attempt count, lock-expiry timestamp and a lockout "stage" (for
    escalating backoff) are persisted in secure storage rather than instance fields, so they survive
    process death. `AppConstants.lockoutBackoff` = `[30s, 1m, 5m, 15m]`, indexed by stage and clamped
    at the last entry; a successful `verifyPin` resets all three. `verifyPin` checks `isLockedOut()`
    first and returns `false` without touching the attempt counter while locked — so a locked-out user
    mashing the correct PIN can't attempts-race their way out early. `PinEntryScreen` polls
    `getLockRemaining()` on a 1s `Timer` to disable the keypad and show a countdown, and no longer
    resets its own attempt counter locally. "Forgot PIN?" is still reachable during a lockout, but
    only through the existing explicit confirm dialog (`_showResetPinDialog`), same as P0-6 — not a
    bare-tap escape. Covered by `test/auth_service_test.dart`'s `lockout` group.

### P1-3 The privacy claim in-app is false
`lib/screens/sms_permission_screen.dart:401` states "All financial information stays **encrypted** on
your phone". The SQLite DB is plaintext.
- Fix: either encrypt at rest (`sqflite_sqlcipher`, key in secure storage — preferred for an app
  holding bank data) or change the copy to what's true ("stored locally on your device, protected by
  your device lock and app PIN"). Do not ship the false claim.
- Acceptance: if encrypting — DB file bytes contain no plaintext merchant strings; if rewording — no
  "encrypted" claim remains anywhere in UI or README.

### P1-4 Over-broad and Play-hostile permissions
`android/app/src/main/AndroidManifest.xml:4-17` declares `READ_SMS`, `RECEIVE_SMS`, **`SEND_SMS`**,
`INTERNET`, `ACCESS_NETWORK_STATE`, `READ/WRITE_EXTERNAL_STORAGE`, `READ_PHONE_STATE`. Only
`READ_SMS` is actually used. `SEND_SMS` on a finance app is an instant compliance red flag, and the
app has no network code at all.
- Fix: delete everything except `READ_SMS`. Add `android:allowBackup="false"` and
  `dataExtractionRules`/`fullBackupContent` so the PIN + DB can't be pulled via backup.
- Acceptance: manifest diff; app still reads the inbox.
  - **Done (round 3).** Manifest now declares only `READ_SMS` (confirmed against
    `MainActivity.readInbox`, a plain `ContentResolver` query with no send/receive/network/storage/
    phone-state code anywhere in `lib/`). Added `android:allowBackup="false"` plus
    `android:dataExtractionRules="@xml/data_extraction_rules"` (API 31+ cloud-backup *and*
    device-transfer exclusion — device-transfer isn't gated by `allowBackup`) and
    `android:fullBackupContent="@xml/backup_rules"` (pre-31 fallback, inert today but kept in case
    backup is ever re-enabled), both excluding `sharedpref` and `database` domains.

### P1-5 Play Store restricted-permission risk (**highest release risk — decide before building**)
`READ_SMS`/`RECEIVE_SMS` are Play *restricted* permissions: they require a Permissions Declaration and
are only granted for a short list of approved use cases. "Read bank SMS to track expenses" is not on
that list, so a `READ_SMS` submission is likely to be rejected or removed later. Verify the current
policy in Play Console before committing to a path. Options, in the order I'd pursue them:
1. **Notification-based import** (`NotificationListenerService` on bank notifications) — no restricted
   permission, same text, requires an explicit user opt-in in system settings. This is what most
   surviving Indian expense trackers moved to.
2. Manual entry + user-initiated import (share-sheet / paste an SMS) — always allowed.
3. Submit the SMS declaration anyway and keep 1+2 as the fallback build.
- Fix (structural, do this regardless): put a `TransactionSourceAdapter` interface between the parser
  and the inbox reader so SMS / notification / manual sources are interchangeable and the parser is
  reused untouched.
- Acceptance: `SMSParserService` has no dependency on the SMS channel; a second source can be added
  without touching the parser; a build flag selects the enabled source(s).

### P1-6 No app-level lock lifecycle, no screenshot protection
Once past `/pin_entry` the app never re-locks — background/resume, task switcher and screenshots all
expose balances. `local_auth` and `isBiometricEnabled` exist but no screen ever enables biometrics
(`AuthService.autoLogin` is dead code).
- Fix: `AppLifecycleListener` that re-locks after N seconds in background; `FLAG_SECURE` on the
  Android window (at minimum while locked / on request); a Settings screen switch for biometric
  unlock wired to `authenticateWithBiometric()`.
- Acceptance: manual device check + a test for the lock-timeout state machine.

### P1-7 PIN length rules disagree in three places
`AuthService.setPin` 4–8 (`:95`), `PinSetupScreen` caps at 6 (`:252`), `PinEntryScreen` renders 6 dots
and only auto-submits at 6 (`:259`, `:270`), `AppConstants` says 4–8 (`:68`),
`validatePinStrength` is never called.
- Fix: one constant (recommend exactly 6 for a keypad UI, or a length picker); render dots from that
  constant; call `validatePinStrength` in setup.
- Acceptance: test that a 4-digit PIN either works end-to-end or is rejected at setup — no third state.
  - **Done (round 3).** Went with exactly 6 digits, fixed: `AppConstants.pinLength` is the single
    source of truth (replacing the old `minPinLength`/`maxPinLength` pair), used by the dot renderer
    and input caps in both `PinSetupScreen` and `PinEntryScreen`, by `AuthService.validatePinStrength`
    (now `pin.length != pinLength` instead of a 4–8 range), and by `PinSetupScreen._onSubmit`, which
    now calls `validatePinStrength` instead of its own inline `length < 4` check. A 4-digit PIN is
    rejected at setup with an explicit error; there's no path where it's accepted. Covered by
    `test/auth_service_test.dart`'s `rejects a PIN of the wrong length` case.

---

## P2 — Data model & accounting correctness

### P2-1 Balances never move
`accounts.current_balance` is whatever the user typed at creation; no transaction or SMS ever updates
it, so the dashboard's "Total Balance" is permanently stale — while the SMS bodies literally carry
`Avl bal Rs.X` / `Available Balance is Rs. X` / `Avl Limit: INR X`.
- Fix: parse the trailing balance/limit out of the message, store it on the transaction
  (`balance_after`, schema v4) and update `accounts.current_balance` when the parsed message is newer
  than `accounts.updated_at`; show "as of <date>" next to the balance. Manual transactions adjust the
  balance too (debit −, credit +), with an "adjust balance" toggle.
- Acceptance: parser tests extracting available balance for ICICI/Kotak/SBI/HDFC formats; DAO test
  that a newer message wins and an older one doesn't.
  - **Done (round 4).** `SMSParserService._extractBalance` matches the four documented formats
    (bank-agnostic — applied to every parsed transaction regardless of which bank branch produced it)
    and sets `Transaction.balanceAfter`. `AccountDAO.updateBalanceIfNewer(accountId, balance, asOf)`
    compares `asOf` (the transaction's date, not wall-clock time) against `accounts.updated_at` and
    only writes when not older, so `updated_at` doubles as a "balance as of" date even when the whole
    inbox is rescanned out of chronological order. `SMSParserService.saveTransaction` calls it after
    every successful insert. `add_transaction_screen.dart` gained an "Adjust account balance"
    checkbox (add-only, not shown while editing — applying it again on an edit would double-count with
    no way to know whether the original entry already adjusted the balance) that moves the account
    balance by ± the amount via `AccountDAO.updateAccountBalance`. "as of `<date>`" now renders next to
    the balance on the dashboard's account cards and the account detail screen. Covered by
    `sms_parser_service_test.dart`'s "balance/limit extraction" group, `account_dao_test.dart`'s
    `updateBalanceIfNewer` group, and the balance-propagation group in the new
    `sms_parser_service_persistence_test.dart`.

### P2-2 Transfers are double-counted as expenses
A credit-card bill payment produces a debit on the bank account **and** a credit on the card; a
self-transfer produces two rows. `getTotalExpenses` sums every `debit`, so "Total Expenses" is
inflated. `transactionType` even documents a `'transfer'` value that nothing ever writes.
- Fix: detect internal transfers (same amount, opposite direction, ≤2 days apart, both accounts
  registered; plus explicit patterns like "credit card payment received", "BBPS", "card ending X
  credited"); mark both rows `is_transfer = 1` (schema v4) and exclude them from income/expense
  aggregates while still showing them in statements.
- Acceptance: test with a CC-payment pair asserting expenses exclude it; regression test that a real
  merchant debit is never classified as a transfer.
  - **Done (round 4).** Two detection paths, both landing on `Transaction.isTransfer`:
    `SMSParserService._isTransferPattern` matches the explicit phrase family ("credit card payment
    received", "payment received towards your card", "bharat bill payment system"/"bbps", "credited to
    your card") directly on the raw message, for the case where the other leg isn't a tracked account
    (e.g. paid from an external bank). `TransactionDAO.findOffsettingTransaction` looks for an
    opposite-direction, same-amount row on a *different* registered account within a 2-day window, for
    the case where both legs are tracked (a bank→card bill payment, or a self-transfer). Both legs get
    marked via `markTransferPair`; `saveTransaction` always attempts the offsetting-match step — even
    when the current leg is already pattern-flagged — because whichever leg saves *first* has no
    counterpart yet, so this is what retroactively marks it once the second leg arrives, regardless of
    which one carried the explicit pattern. `getTotalExpenses`/`getTotalIncome`/`getSpendingByCategory`/
    `getSpendingByBank`/`getDailySpending` all gained `is_transfer = 0`; `reports_screen.dart`'s
    in-memory totals (it doesn't use those DAO aggregates) got the same exclusion. Covered by
    `transaction_dao_test.dart`'s transfer and aggregate-exclusion groups,
    `sms_parser_service_test.dart`'s "transfer detection" group, and the transfer-detection group in
    `sms_parser_service_persistence_test.dart` (including both same-account-never-matches and
    insertion-order regression cases).

### P2-3 Duplicate suppression can silently drop real transactions
`TransactionDAO.hasSimilarTransaction` (`:34`) treats *any* same-account / same-type / same-amount /
same-day row as a duplicate whenever either row lacks a reference number. Two ₹50 coffees on the same
card in one day ⇒ the second is discarded with no trace.
- Fix: require a stronger signal — matching reference number, or matching normalised merchant, or an
  explicit "confirmation pair" pattern; otherwise import and flag as `possible_duplicate` for user
  review. Also fold the two one-time cleanup hacks (`_reimportFlagKey`,
  `deleteUnlinkedAutoTransactions` running on *every* sync, `sms_service.dart:123-130`) into a real
  versioned migration.
- Acceptance: test that two identical-amount same-day debits with different refs both persist; test
  that a genuine bank double-SMS still collapses to one.
  - **Done (round 4).** `hasSimilarTransaction` was replaced with
    `TransactionDAO.findDuplicateMatch`, returning a `DuplicateMatch` tri-state instead of a bool:
    `confirmed` (matching reference number, matching normalised merchant, or both candidate rows are
    already `is_transfer`-flagged bill-payment confirmations, which carry no ref/merchant on either
    side) drops the new row; `ambiguous` (a same-account/type/amount/day row exists but shares none of
    those signals — the exact coffee-shop scenario) still imports it but sets
    `Transaction.needsReview = true`; `none` imports normally. The UI surface for `needs_review` is
    P3-3's job in round 5 — this round only makes sure the data is captured instead of the row being
    silently dropped. The `_reimportFlagKey` SharedPreferences flag and the every-sync
    `deleteUnlinkedAutoTransactions()` call are gone from `sms_service.dart`; both are now a one-time
    `DELETE FROM transactions WHERE is_manual = 0 AND account_id IS NULL` inside the v5 migration,
    which is inherently one-shot per install rather than needing a hand-rolled "have I done this
    already" flag. Covered by `transaction_dao_test.dart`'s `findDuplicateMatch` group and the
    duplicate-handling group in `sms_parser_service_persistence_test.dart`.

### P2-4 / P2-5 Schema & model hygiene
- Schema v4 migration carrying: `balance_after`, `is_transfer`, `needs_review`, `source`
  (`sms|notification|manual`), `raw_message_hash`; index on `transaction_id`; `PRAGMA foreign_keys = ON`
  via `onConfigure` (today `ON DELETE SET NULL` at `database_helper.dart:83` never fires).
- Cache the open-DB `Future` in `DatabaseHelper` (`:16-20`) — two concurrent first calls can open twice.
- Delete the duplicated category source of truth: `AppConstants.predefinedCategories` +
  `main._initializeCategories()` (`lib/main.dart:130`) re-seed what `_createDatabase` already seeded.
- `Transaction.fromMap` (`:63`) is unchecked `dynamic` casts — `amount: map['amount']` throws on an
  `int` column value (SQLite returns `int` for `50.0` stored as `50`). Make it defensive
  (`(map['amount'] as num).toDouble()`), same for `Account.fromMap:53`.
- `Transaction`/`Account`/`Category` `operator ==` compares only `id`, so two unsaved objects
  (`id == null`) are "equal" — this is what a dropdown uses for `Account` identity. Compare all
  fields or use identity.
- Acceptance: migration test v1→v4 and v3→v4 on a seeded fixture DB; a `fromMap` test with int-typed
  amount/balance columns.
  - **Done (round 4).** Schema bumped to v5; the migration lives in `DatabaseHelper._upgradeDatabase`'s
    `if (oldVersion < 5)` block (five `ALTER TABLE ADD COLUMN`s, a `source` backfill from `is_manual`,
    the `idx_transactions_transaction_id` index, and the P2-3 unlinked-row cleanup described above).
    `onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON')` is wired into `openDatabase`, so the
    existing `ON DELETE SET NULL` now actually fires. `DatabaseHelper.database` caches the in-flight
    open `Future` (`_openingFuture`), not just the resolved `Database`, so two callers racing the
    getter before the first open completes both await the same open instead of a second one racing
    sqflite's single-open-per-path lock; `close()` was updated to drain a pending open rather than
    leaving it to land after `close()` returns. `main.dart`'s `_initializeCategories()` (and its
    `CategoryDAO`/`Category` imports) is deleted — `DatabaseHelper._createDatabase` already seeds on
    first create, so it was a pure duplicate of P2-5's already-fixed single source of truth.
    `Transaction.fromMap`/`Account.fromMap` were already defensive (`(map[...] as num?)?.toDouble()`)
    from earlier work; the P2-4 gap that remained was `operator ==`, now comparing every field on
    `Transaction`, `Account` and `Category` (with a matching `hashCode` via `Object.hash`) instead of
    just `id`. Covered by `database_migration_test.dart`'s new "v4 -> v5" group (new columns, index,
    `source` backfill, unlinked-row deletion, manual-with-no-account rows surviving) and
    `models_test.dart`'s per-model "equality compares every field, not just id" tests (including the
    `id == null` case, built via the constructor directly since `copyWith(id: null)` can't null out a
    field per Dart's `??` semantics).

---

## P3 — Parser robustness (accuracy of the core feature)

### P3-1 Promo/OTP filter has dangerous false positives
`_isNonTransactionalMessage` (`sms_parser_service.dart:541`) rejects on substrings including
`'offer'`, `'due on'`, `'click here'`, `'know more'`, `'do not share'`. Real transaction alerts
routinely end with "Do not share your OTP/CVV" or carry a "know more" link ⇒ **real spends silently
dropped**.
- Fix: two-stage classification. First test for a strong transaction signature (amount + verb +
  account/card token + date). If present, only a narrow OTP/loan-ad denylist can veto it. Keep the
  broad markers for messages with no strong signature. Add a debug-only counter of skipped messages.
- Acceptance: tests for a debit alert containing "Do not share" (must parse) and for the existing
  promo corpus (must still be rejected).

### P3-2 Merchant extraction truncates on the letters "on"
`_extractMerchant` (`:877`) uses `(?:\.|on|$)` — an unanchored literal, so `MONITOR` → `M`,
`ONLINE` → `` etc. Also matches the *first* `at|to|from` anywhere in the message, including inside
the fraud-helpline footer.
- Fix: `\b(?:on|dated)\b` word boundaries, stop at `;`/`.`/`Ref`/`UPI`/`Avl`/`Not you`, normalise
  (strip `PYU*`, `UPI/`, trailing card digits, collapse whitespace, title-case), and keep a
  `merchantNormalised` for grouping/categorisation.
- Acceptance: table-driven test over the real merchant strings in
  `SMSService.getTestSMSMessages()` (`sms_service.dart:223`) plus the `MONITOR` regression.

### P3-3 Account matching is loose in both directions
`_findRegisteredAccount` (`:475`): with no digits in the message it attaches to
`bankAccounts.first` (arbitrary when the user has two accounts at one bank); with digits it accepts a
2-digit suffix match (`_extractAccountDigits` allows `\d{2,8}`), so `18` from a helpline can bind to
an account. And when nothing matches, the transaction is **dropped with no user-visible trace**.
- Fix: require ≥3 matching digits; prefer the longest match; when ambiguous or unmatched, import with
  `needs_review = 1` and surface a "Needs review / unmatched" list where the user assigns the account.
  Never silently discard money.
- Acceptance: tests for ambiguous 2-account cases and for the unmatched → needs_review path.

### P3-4 Parser coverage & structure
Only ICICI/Kotak/SBI have dedicated parsers; everything else falls to a keyword-based generic parser
that decides credit-vs-debit by `contains('credited'|'received'|...)` (`:391`) — "not credited",
"refund received", "payment received towards your card" all mis-sign. HDFC — the most common Indian
bank in the sender map — has **no** dedicated parser.
- Fix: restructure into a rule table (`BankRule { senderPatterns, List<Pattern> patterns, extractors }`)
  loaded from one place; add HDFC + Axis rules; sign determination from the matched pattern, not from
  bag-of-words; treat `refund|reversed|failed|declined` explicitly.
- Acceptance: the whole `getTestSMSMessages()` corpus (move it into `test/fixtures/`) parses to
  expected type/amount/date/merchant; add fixtures for HDFC/Axis.

### P3-5 Parser hygiene
`print` in production (`:79`, `:451`, `:782`, `:799`, `:816` and `add_transaction_screen.dart:63`),
3 unused imports, unused `accountNumber` local (`:115`), deprecated `Uuid.NAMESPACE_URL` (`:752`),
dead stubs `smsStream`/`listenToNewSMS`/`stopListening` (`sms_service.dart:181-195`), and
`getTestSMSMessages()` shipping the owner's real transaction data inside the app binary.
- Fix: a tiny `AppLogger` (debug-only), delete dead code, move the corpus to test fixtures.
- Acceptance: `flutter analyze` clean (0 warnings, 0 info) and no `print` in `lib/`.

---

## P4 — Performance & responsiveness

### P4-1 Full-inbox re-parse on every dashboard load, on the UI isolate
`dashboard_screen.dart:48` calls `SMSService().syncMessages()` on every load/refresh;
`syncMessages` (`sms_service.dart:132`) always reads the **entire** inbox (`since` unused), then per
message runs regex parsing plus 2–3 awaited SQLite queries. With a few thousand SMS that's tens of
thousands of round-trips before the first frame of data — visible multi-second stall, and it also
re-runs `deleteUnlinkedAutoTransactions()` every single time.
- Fix: (a) incremental sync by default (`since = lastSyncTime`) with an explicit "full re-scan" action;
  (b) filter senders in Kotlin (`MainActivity.readInbox`) instead of shipping the whole inbox over the
  channel; (c) stream/paginate the cursor rather than materialising one giant `List<Map>` (current
  code is an OOM/ANR risk on a large inbox); (d) run parsing in an isolate (`compute`) and batch
  inserts in one transaction; (e) trigger sync from a user action / app-resume, not from build.
- Acceptance: measured cold-dashboard time with a 5k-message inbox before/after; no dropped frames in
  DevTools timeline during sync; unchanged import results.

### P4-2 Screen-level query patterns
- `reports_screen.dart:61` loads **all** transactions then filters in Dart; use SQL aggregates
  (`getSpendingByCategory` etc. already exist and are unused).
- `transactions_screen.dart:466` `_debouncedSearch` isn't a debounce — it schedules one delayed load
  *per keystroke*, and overlapping `_loadTransactions()` results can land out of order. Use a real
  `Timer` (cancel previous) + a request sequence guard.
- `transactions_screen.dart:63` loads every transaction and filters in memory; push filters to SQL and
  paginate (`AppConstants.defaultPageSize` exists and is unused).
- `reports_screen.dart:408` fixed-height `Container` with a nested unbounded `ListView` of every
  transaction.
- Acceptance: typing 10 characters issues 1 query; transactions list scrolls a 5k-row DB smoothly.

---

## P5 — UX, navigation & missing features

### P5-1 Reports screen is unreachable and Dashboard is orphaned after setup
`/reports` is registered (`main.dart:120`) but **nothing navigates to it**. First-run flow ends at
`/accounts` (`main.dart:82-86`), and no screen navigates to `/dashboard` — a new user only sees the
dashboard after killing and relaunching the app. `theme.dart:245` even themes a bottom nav that
doesn't exist.
- Fix: a `HomeShell` with a persistent bottom navigation bar (Dashboard · Transactions · Reports ·
  Accounts · Settings) as the single post-auth destination; onboarding ends there.
- Acceptance: every screen reachable in ≤2 taps from launch; navigation widget test.

### P5-2 Account editing is a stub
`account_detail_screen.dart:536` — "Account editing functionality will be implemented in future
updates." So a typo'd account number, a changed balance, or adding a debit card later is impossible,
and a wrong account number means SMS never matches (silently, per P3-3).
- Fix: reuse `AddAccountScreen` in edit mode (`AccountDAO.updateAccount` already exists).
- Acceptance: edit an account's number/cards/balance and see subsequent SMS match.

### P5-3 No Settings screen
Nothing exposes: change PIN (`AuthService.changePin` is dead code), biometric toggle, lock timeout,
full re-scan of SMS, export CSV/JSON, delete all data, privacy policy, version/licences
(`showLicensePage` is a Play expectation).
- Acceptance: each of the above works from Settings; `changePin`/`setBiometricEnabled` are reachable.

### P5-4 fl_chart is a dependency with zero charts
`pubspec.yaml` ships `fl_chart` (and `go_router`, entirely unused) while `reports_screen.dart` draws
percentages with `LinearProgressIndicator`, and the README claims "Visual charts".
- Fix: either add a category pie + monthly-trend bar chart with `fl_chart`, or drop both deps.
  Recommend: add the two charts (it's the headline feature of the Reports tab), drop `go_router`.
- Acceptance: charts render with seeded data and with empty data; `flutter pub deps` has no unused
  direct dependency.

### P5-5 Sync is invisible
No last-sync time, no "N new transactions imported", no error surfaced when permission was revoked
(`dashboard_screen.dart:49` swallows everything), no visibility into skipped/unmatched messages.
- Acceptance: dashboard shows "Last synced <time> · N imported · M need review", with a tappable
  needs-review list.

### P5-6 UI robustness & accessibility
Colors hardcoded per screen (`Color(0xFF0f0f23)` etc.) instead of the theme that already defines them;
fixed font sizes overflow at large text scale; keypad keys are bare `GestureDetector`s (no ink, no
semantics label, tap target below 48dp in some layouts); `withOpacity` deprecated in 26 places;
`RadioListTile.groupValue`/`onChanged` and `DropdownButtonFormField.value` deprecated.
- Fix: route all colors through `AppTheme`/`ColorScheme`; `Semantics` labels + `InkWell` on the
  keypad; test at 200% text scale and 320dp width; migrate the deprecated APIs (`withValues`,
  `RadioGroup`, `initialValue`).
- Acceptance: `flutter analyze` reports 0 deprecations; screens render without overflow at
  `textScaleFactor 2.0` on a 320×640 canvas (golden/widget tests).
- **Pulled forward into round 2** (both were hard blockers for writing any screen test, so they
  could not wait): in `add_transaction_screen.dart` the `ListTile`/`RadioListTile` instances sat
  inside bare `Container`s and asserted on every build ("background color or ink splashes may be
  invisible"), and the `DropdownMenuItem` `Expanded` threw an unbounded-width layout assertion.
  Fixed with a shared `_buildSurface()` `Material` and `isExpanded: true`. **The same
  `Container` + `ListTile` pattern still needs auditing on the other screens.**

### P5-7 Error presentation leaks internals
Every screen surfaces `e.toString()` (`'Failed to load dashboard data: ${e.toString()}'`, etc.).
- Fix: user-facing message + debug-only detail; log via `AppLogger`.

---

## P6 — Store readiness

- **P6-1** App identity: real `applicationId` (P0-7), human label, adaptive launcher icon +
  monochrome variant (`flutter_launcher_icons`), branded splash (`flutter_native_splash`) — currently
  the default Flutter icon and a lowercase package label.
- **P6-2** Privacy policy URL (mandatory for a Play listing, doubly so with SMS access) + in-app link
  + Play Data Safety form answers that match reality ("no data collected, no data shared, processed
  on device").
- **P6-3** Store listing assets: title/short/full description, 2–8 screenshots per form factor,
  512×512 icon, 1024×500 feature graphic, content rating questionnaire, target-audience declaration.
- **P6-4** Compliance: target API level ≥ current Play requirement, 64-bit/AAB, `READ_SMS`
  declaration (P1-5), data-deletion path (P0-6/P5-3) — Play now requires an in-app account/data
  deletion route.
- **P6-5** Drop unused platform targets (`ios/`, `macos/`, `linux/`, `windows/`, `web/`) or make the
  SMS channel degrade gracefully — `getInboxMessages` throws `MissingPluginException` off Android
  today.
- **P6-6** README is inaccurate: claims 100% complete, "Local data encryption", "Visual charts",
  "real-time balance calculations" — none of which is true. Rewrite honestly; keep the design doc
  separate from the status claim.

---

## P7 — Tests, tooling, CI

- **P7-1** No DAO/migration tests at all (the riskiest code). Add `sqflite_common_ffi` and cover
  every DAO method, plus v1→v4 migrations on fixture DBs.
  - Migration fixtures must reproduce the *whole* historical schema, not just the tables a given
    migration touches. `_upgradeDatabase` only ALTERs and UPDATEs — it never CREATEs — so a fixture
    missing `categories` (or the five v1 indexes) produces a post-upgrade schema that cannot exist in
    production, hides every category-related migration bug, and makes the next
    `CategoryDAO`/`clearAllData()` assertion fail with `no such table: categories` as if it were a
    production defect.
  - Adding `sqflite_common_ffi` makes the native-assets prebuild run for **the entire suite**, so on
    Windows it breaks every test file, not just the DB-backed ones. See the README's Windows
    one-time setup; `scripts/setup-windows-flutter-sdk.ps1` now persists the fix rather than
    needing to be dot-sourced per shell.
- **P7-2** No screen tests. Add widget tests for pin entry/lockout, add-transaction edit round-trip,
  navigation shell, empty/error states. `test/widget_test.dart` currently only asserts the root widget
  is a `Widget`.
  - Started: `test/add_transaction_screen_test.dart` covers the RadioGroup toggle in both
    directions, the Material/ink invariant, the merchant field's conditional visibility, and the
    no-accounts save guard. Screens doing DB I/O in `initState` must pump inside
    `tester.runAsync()` — under the default fake clock the real sqflite I/O never completes.
  - Still to do: pin entry/lockout, edit round-trip, navigation shell.
- **P7-3** Parser corpus: move `getTestSMSMessages()` out of `lib/` into `test/fixtures/` and make it a
  table-driven expectation file per bank.
- **P7-4** Tighten `analysis_options.yaml`: `strict-casts`, `strict-raw-types`, `avoid_print`,
  `prefer_const_constructors`, `always_declare_return_types`, and `errors: unused_import: error`.
  Then get to 0 issues. **`require_trailing_commas` is intentionally excluded**: it is a no-op on
  Dart 3.12.2 (verified — a multiline argument list with no trailing comma produces zero
  diagnostics), so listing it would misrepresent what is enforced. Enforce trailing commas as
  formatting instead, via `dart format --set-exit-if-changed .` in CI (P7-5). Note that this needs
  a one-time `dart format` pass first — the repo has never been formatted (33 of 37 files under
  `lib/` + `test/` currently change), so the gate must land as its own commit or it will fail on
  day one and bury every subsequent diff in reflow noise.
- **P7-5** GitHub Actions: `flutter analyze` + `flutter test --coverage` + `flutter build appbundle`
  on PR; coverage floor. Secrets for the keystore.
- **P7-6** Optional: crash reporting (Sentry/Crashlytics) with an explicit opt-in — weigh against the
  "nothing leaves your device" promise; if added, update the Data Safety form.

---

## Round 2 review follow-ups (all resolved)

Seven items came out of the round 1 + 2 review. All are closed; the notes below record the
*reasoning*, since several are easy to undo by accident.

| # | Item | Resolution |
|---|---|---|
| 1 | `flutter test` broken in any shell without the SDK junction (**high**) | `scripts/setup-windows-flutter-sdk.ps1` now persists User-scope `PATH`/`FLUTTER_ROOT` (run once, ever; `-Revert` undoes it, `-SessionOnly` skips persistence). Documented in the README together with the `flutter_tester` / `sqlite3.dll` lock and its `Stop-Process` fix. |
| 2 | Migration fixtures omitted `categories` + the 5 indexes | All three fixtures now build the full historical schema and seed `categories` from `Category.predefinedCategories`; new assertions prove the table, its seeded rows, a user's custom category and the indexes all survive v1→v4. See P7-1. |
| 3 | `DatabaseHelper.close()` opened the DB in order to close it | `close()` reads the `_database` field directly and returns early when null, so it neither creates a stray file nor resurrects one on a second call. Covered by `test/database_helper_test.dart`. |
| 4 | `require_trailing_commas` declared but inert | Removed, with a comment explaining why. See P7-4. |
| 5 | Four tests asserted almost nothing | PK-conflict test now forces a real collision via `Account.toMap()`'s `id` and asserts the survivor is untouched; `updatedAt` test seeds a stale timestamp so a strict `isAfter` can fail; date-range test places rows exactly on both bounds; `searchCategories` test renamed (SQLite `LIKE` **is** ASCII-case-insensitive) and now probes all three casings plus a mid-string match. |
| 6 | Half-open ranges unfinished; test temp dirs never cleaned | Ranges: see P0-1. Temp dirs: `disposeTestDatabase()` in `test/support/db_test_helper.dart` removes the per-isolate temp directory; every DB-backed test file calls it from `tearDownAll`. |
| 7 | Add Transaction screen threw 6 ink-splash assertions on build | Fixed via `_buildSurface()`; fixing it exposed a second, pre-existing layout crash (`Expanded` inside `DropdownMenuItem` with unbounded width) fixed with `isExpanded: true`. Both would also misbehave on device. See P5-6. |

Two behaviour changes from round 2 flagged for awareness, both left as-is:
`(raw ?? const [])` in `sms_service` makes a null platform response read as "empty inbox" rather
than throwing; and `AppLogger` is debug-only, so the `_loadData` catch is silent in release
(empty dropdowns, no message) — **P5-7 must fix that**, not just prettify error text.

---

## Round 3 review follow-ups (all resolved)

Round 3 landed correct in substance — PBKDF2 is textbook-correct (verified against RFC 2898: `U1 =
PRF(P, S||INT(i))`, `T = U1 ⊕ … ⊕ Uc`, exactly `c` PRF calls), the v2 decrypt reproduces the old
`Key.fromUtf8`/`IV.fromUtf8`/`decrypt64` pair byte-for-byte (checked against `git show HEAD`), the
manifest trim is safe (`permission_handler`'s `getManifestNames` filters the SMS group by what the
manifest actually declares, so `Permission.sms` still resolves to `READ_SMS`; `INTERNET` survives in
`src/debug` + `src/profile` so hot reload is unaffected), and `flutter analyze` is at 0 issues.
Seven review findings, all fixed:

| # | Item | Resolution |
|---|---|---|
| 1 | **A migrated 4-digit PIN was unenterable — data lockout (high)** | v2 accepted 4–8 digits (`git show HEAD:.../auth_service.dart:95`); v3's keypad can only ever submit exactly 6. Migrating such a PIN forward left `isPinSet == true` with no input that could ever verify it — the only escape being "Forgot PIN?", i.e. **wiping the user's accounts and transactions**. `_migrateLegacyPinIfNeeded` now migrates only if `validatePinStrength` passes; otherwise it drops the legacy key, `isPinSet` reports false, the splash routes to PIN setup, and the database is untouched. Regression test `a v2 PIN of the wrong length is dropped, not carried over` (verified to fail without the guard). |
| 2 | `AppResetService` cleared a *differently configured* secure store | It constructed a bare `FlutterSecureStorage()` while `AuthService` used `AndroidOptions(encryptedSharedPreferences: true)`. The Android plugin resolves its backing store from each call's options and `ensureInitialized` carries a `TODO` saying mixed usage is broken — so the one operation that must not fail silently (Clear Data) could leave the PIN hash behind. `AuthService.secureStorage` is now the single shared handle both go through. |
| 3 | PIN storage was three keys = a torn write away from permanent lockout | `_storePin` wrote salt, hash and iterations as three separate secure-storage commits. A kill between the first two during a **PIN change** leaves a new salt paired with the old hash: set, unverifiable, unrecoverable. Collapsed to one atomic record, `expenditure_tracker_pin_v3` = `"<iterations>:<b64 salt>:<b64 hash>"` (base64 never contains `:`). Test asserts exactly one `pin` key exists. |
| 4 | `clearAllAuthData()`'s doc comment claimed AppResetService used it | It doesn't — `resetAll()` wipes prefs and secure storage wholesale. Comment corrected; the method is kept (dead, like `changePin`/`clearPin`) for the Settings work in P5-3. |
| 5 | `setState` after dispose on both PIN screens | PBKDF2 made `setPin`/`verifyPin` ~300 ms, turning a theoretical window into a real one: the `catch`/`finally` blocks in `_onSubmit` (both screens) and the `Future.delayed(300ms, _onSubmit)` auto-submit had no `mounted` guard. All guarded. |
| 6 | Silent `catch (e) { return false; }` in the auth path | A secure-storage fault was indistinguishable from a wrong PIN, with nothing logged. `setPin`, `verifyPin`, the malformed/invalid-record branches, and both screens' handlers now log via `AppLogger`. (Release-mode silence is still P5-7's problem.) |
| 7 | A lockout gated `verifyPin` only | `autoLogin()` would have handed back an escape hatch the moment P5-3 wires up the biometric toggle. It now returns false while locked. |

Also removed from `AppConstants`: `pinKey`/`biometricKey`/`isFirstLaunchKey` (dead, and misleading now
that the PIN lives in secure storage rather than prefs) and `databaseName`/`databaseVersion` (dead
duplicates of `DatabaseHelper`'s, which had already drifted — this file still claimed version 1
against a v4 schema). `hasSeenOnboardingKey`/`lastSyncTimeKey` are also unused but their literals
*are* used in `main.dart`/`splash_screen.dart`; wiring those up belongs with P5-1's navigation work.

Two things noted and deliberately left:

- A device clock moved backwards can extend a lockout arbitrarily (and forwards can end one early).
  Standard for any local-clock lockout; the escape is "Forgot PIN?", which is a wipe.
- `SystemNavigator.pop()` after a reset finishes the activity but need not kill the process, so
  Android may restore the task with stale in-memory state. Only a real fix once P5-1 gives the app a
  single post-auth shell that can be rebuilt in place.

---

## Round 4 review follow-ups (all resolved)

Two review findings, both fixed:

| # | Item | Resolution |
|---|---|---|
| 1 | `_isTransferPattern`'s bare `'bbps'`/`'bharat bill payment system'` substring match had no credit-card-context requirement (**high** — silently drops real expenses from every total) | BBPS is also the rail Indian banks use for ordinary third-party bill payments (electricity, gas, DTH) debited straight from a bank account — a genuine expense, not an internal transfer between the user's own accounts. The bare substring match flagged those the same as a credit-card bill payment. A BBPS mention now only counts as a transfer when the message also reads as a payment *received* on a *card* (`lower.contains('card') && lower.contains('received')`), matching the same "money landing back on the card" semantic as the other four explicit markers, which are checked first and unconditionally. Regression test: a non-card BBPS utility-bill debit, in `sms_parser_service_test.dart`'s "transfer detection" group. |
| 2 | The v5 migration silently narrowed the pre-existing "clean re-import after a parser fix" behavior instead of preserving it, contradicting the round's own resolution note (**medium-high** — historical bad data becomes permanent on any real install) | Pre-round-4, `SMSService`'s `_reimportFlagKey` hack did two things: delete *every* auto-imported row once (so the next full-inbox rescan could reinsert everything through the current parser) and delete only *unlinked* auto-imported rows on every sync. The v5 migration only replicated the second, narrower behavior (`WHERE is_manual = 0 AND account_id IS NULL`), leaving `TransactionDAO.deleteAutoImportedTransactions()` as dead code with no caller anywhere in `lib/`. Any row already imported under a parser bug that predates v5 (P0-3's December -> January bug, P0-4's fabricated dates) would have stayed wrong forever, since `saveTransaction`'s duplicate check is keyed on a deterministic hash of the raw SMS and would keep matching the same stale row on every rescan. The migration's delete is now unconditional on `is_manual = 0` (linked or not), so every SMS-imported row is wiped once on any pre-v5 upgrade and reinstated by the next sync's unconditional full-inbox rescan; manual entries are untouched regardless of whether they have an account. The now-pointless `source = 'sms'` backfill (nothing `is_manual = 0` survives the delete that follows it) was removed rather than left as dead code — every surviving row is manual and already defaults to `source = 'manual'` from the `ALTER TABLE ... DEFAULT`. Covered by `database_migration_test.dart`'s updated v4 -> v5 group. |

Two smaller findings from the same review pass were noted but left as-is (neither is a correctness bug):

- `DatabaseHelper.close()` has a narrow race — if a third caller hits the `database` getter in the window after `close()` nulls `_openingFuture` but before the original in-flight open resolves, it starts a second concurrent `openDatabase()` call. `close()` essentially never overlaps the very first open in practice (app reset is the only caller, and it runs long after startup), so left unguarded rather than adding speculative complexity.
- The "Adjust account balance" toggle on Add Transaction computes its delta against the account balance loaded when the screen opened, and `updateAccountBalance` stamps `updated_at` with wall-clock time rather than the transaction's own date, so a back-dated manual adjustment can outrank a genuinely newer but earlier-dated SMS balance update. Documented here rather than fixed — a real fix needs `updateAccountBalance` to go through the same as-of comparison as `updateBalanceIfNewer`, which is more naturally a P5-3 (Settings/manual-entry polish) task than a bugfix.

---

## Suggested execution order

| Round | Tasks | Why |
|---|---|---|
| 1 | P0-1, P0-3, P0-4, P0-5, P0-2 | Wrong numbers and data loss first |
| 2 | P7-1, P7-4 (test harness + lints) | Everything after this needs a safety net |
| 3 ✅ | P1-1, P1-2, P1-4, P1-7, P0-6 | Security core |
| 4 ✅ | P2-4/P2-5 (schema v5 + model hygiene), P2-1, P2-2, P2-3 | Accounting correctness on the new schema |
| 5 | P3-1, P3-2, P3-3, P3-4, P3-5 | Parser accuracy, with fixtures from round 2 |
| 6 | P4-1, P4-2 | Performance, once behaviour is pinned by tests |
| 7 | P5-1, P5-2, P5-3, P5-4, P5-5, P5-6, P5-7, P1-3, P1-6 | UX + the honest privacy story |
| 8 | P0-7, P6-*, P7-5 | Release engineering and the store submission |

**Decide P1-5 (SMS restricted permission) before round 8** — it can change the product, not just the
code. Everything in rounds 1–7 is worth doing on either path.
