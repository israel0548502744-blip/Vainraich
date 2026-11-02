# סכמת מסד הנתונים (PostgreSQL / Supabase)

> סטטוס: **תכנון** — המיגרציות ייכתבו בשלב 2 (`supabase/migrations/`).

## 1. עקרונות

- כל טבלה פרטית מכילה `user_id UUID NOT NULL DEFAULT auth.uid() REFERENCES auth.users ON DELETE CASCADE`.
- **RLS מופעל על כל טבלה**, עם מדיניות `user_id = auth.uid()` ל-SELECT/INSERT/UPDATE/DELETE.
- סכומים: `NUMERIC(14,2)` עם `CHECK (amount > 0)` היכן שרלוונטי. **אין** `real`/`double precision`.
- מטבע: `CHAR(3) DEFAULT 'ILS'` (ISO 4217).
- תאריכים כספיים: `DATE` (יום עסקה); חותמות זמן: `TIMESTAMPTZ`.
- כל טבלה: `id UUID PK DEFAULT gen_random_uuid()`, `created_at`, `updated_at` (טריגר `set_updated_at`).
- מחיקה רכה (`archived_at`) לחשבונות/אנשי קשר; מחיקה קשיחה לתנועות — עם תיעוד ב-`audit_log`.
- אילוצי בעלות חוצת-טבלאות: טריגר `assert_same_owner` מוודא שכל FK (account_id, contact_id וכו') מצביע לרשומה של אותו `user_id`.

## 2. Enums

```sql
account_type      : bank | cash | bit | credit_card | savings | other
transaction_kind  : income | expense | transfer | adjustment
transaction_status: pending | completed | cancelled
payment_method    : bank_transfer | credit_card | cash | bit | check | standing_order | other
recurrence_freq   : daily | weekly | monthly | yearly
event_pay_status  : none | unpaid | partially_paid | paid
debt_status       : open | partially_paid | paid | written_off | cancelled
integration_status: pending_consent | active | expired | revoked | error
sync_status       : started | succeeded | partial | failed
notification_kind : payment_due | debt_overdue | event_upcoming | recurring_due | sync_alert | negative_forecast
```

## 3. טבלאות

### profiles
| עמודה | טיפוס | הערות |
|---|---|---|
| id | uuid PK | = auth.users.id |
| display_name | text | |
| locale | text | default 'he-IL' |
| base_currency | char(3) | default 'ILS' |
| week_starts_on | smallint | default 0 (ראשון) |
| include_receivables_in_forecast | bool | default true |
| onboarding_completed_at | timestamptz | |
| created_at / updated_at | timestamptz | |

נוצר אוטומטית בטריגר על `auth.users` insert.

### accounts
| עמודה | טיפוס | הערות |
|---|---|---|
| id, user_id | uuid | |
| name | text NOT NULL | 1–60 תווים |
| type | account_type | |
| currency | char(3) | |
| institution_name | text | אופציונלי |
| opening_balance | numeric(14,2) | default 0; יכול להיות שלילי |
| opening_balance_date | date | |
| include_in_available | bool | default: true ל-bank/cash/bit, false לאחרים |
| credit_limit | numeric(14,2) | לכרטיס אשראי |
| billing_day | smallint 1–31 | יום חיוב לכרטיס |
| payment_account_id | uuid FK accounts | חשבון בנק שממנו משולם הכרטיס |
| is_active | bool | default true |
| last_synced_at | timestamptz | |
| external_ref | text | מזהה אצל ספק (לא מידע רגיש) |
| notes | text | |
| sort_order | int | |

היתרה הנוכחית **אינה נשמרת** — מחושבת ב-view `account_balances`:
```sql
opening_balance + Σ CASE
  WHEN kind='income'  AND account_id=a.id THEN amount
  WHEN kind='expense' AND account_id=a.id THEN -amount
  WHEN kind='transfer' AND account_id=a.id THEN -amount
  WHEN kind='transfer' AND counter_account_id=a.id THEN amount
  WHEN kind='adjustment' AND account_id=a.id THEN signed_amount
END  WHERE status='completed'
```
(`financial_snapshots` משמש לקיבוע היסטורי ולביצועים.)

### categories
| עמודה | טיפוס | הערות |
|---|---|---|
| id, user_id | uuid | `user_id NULL` = קטגוריית מערכת (קריאה לכולם, כתיבה לאף אחד) |
| name | text | |
| kind | 'income' \| 'expense' | |
| icon, color | text | SF Symbol / טוקן צבע |
| parent_id | uuid FK categories | תת-קטגוריה |
| is_archived | bool | |

UNIQUE(user_id, kind, name).

### contacts
| id, user_id, name, phone, email, notes, archived_at |
UNIQUE(user_id, name) לא חובה (שמות זהים מותרים).

### transactions
| עמודה | טיפוס | הערות |
|---|---|---|
| id, user_id | uuid | |
| kind | transaction_kind | |
| status | transaction_status | default 'completed' |
| amount | numeric(14,2) | `CHECK (amount > 0)` |
| adjustment_sign | smallint | ±1, רק ל-adjustment |
| currency | char(3) | חייב להתאים למטבע החשבון |
| account_id | uuid FK accounts NOT NULL | |
| counter_account_id | uuid FK accounts | **חובה** ל-transfer בלבד, `<> account_id` |
| category_id | uuid FK categories | אסור ב-transfer |
| contact_id | uuid FK contacts | |
| description | text NOT NULL | |
| txn_date | date NOT NULL | |
| payment_method | payment_method | |
| notes | text | |
| attachment_path | text | נתיב ב-Supabase Storage (bucket פרטי עם RLS) |
| event_id | uuid FK events | |
| recurring_id | uuid FK recurring_transactions | |
| occurrence_date | date | עם recurring_id |
| source | text | 'manual' \| 'import_csv' \| 'provider' |
| external_id | text | מזהה תנועה אצל הספק — לדה-דופליקציה בייבוא |
| matched_transaction_id | uuid | קישור התאמה (Bit ↔ בנק) |

אילוצים:
```sql
CHECK ((kind='transfer') = (counter_account_id IS NOT NULL))
CHECK (kind <> 'transfer' OR category_id IS NULL)
CHECK ((recurring_id IS NULL) = (occurrence_date IS NULL))
UNIQUE (recurring_id, occurrence_date)          -- תרחיש D: אין כפילות מופע
UNIQUE (user_id, account_id, external_id)       -- אין ייבוא כפול
```
אינדקסים: `(user_id, txn_date DESC)`, `(user_id, account_id, txn_date)`, `(user_id, category_id)`, `(user_id, status)`, GIN trigram על `description` לחיפוש.

### recurring_transactions
| עמודה | טיפוס | הערות |
|---|---|---|
| id, user_id | uuid | |
| kind | income \| expense \| transfer | |
| amount | numeric(14,2) > 0 | |
| account_id / counter_account_id / category_id / contact_id | | כמו transactions |
| description | text | |
| freq | recurrence_freq | |
| interval | smallint ≥ 1 | "כל N" — מכסה custom |
| by_month_day | smallint | למשל 10 לחודש; 31 → היום האחרון בחודש |
| by_weekday | smallint[] | לשבועי |
| start_date | date | |
| end_date | date | NULL = ללא סוף |
| max_occurrences | int | |
| auto_post | bool | default false — האם ליצור תנועה completed אוטומטית ביום המופע |
| is_active | bool | |
| last_materialized_date | date | |

### events
| עמודה | טיפוס | הערות |
|---|---|---|
| id, user_id | uuid | |
| title | text | |
| event_date | date | |
| start_time / end_time | time | אופציונלי, `end_time > start_time` |
| all_day | bool | |
| location | text | |
| contact_id | uuid FK contacts | |
| expected_income | numeric(14,2) ≥ 0 | NULL = אין הכנסה |
| expected_expense | numeric(14,2) ≥ 0 | |
| payment_status | event_pay_status | default 'none' |
| receivable_id | uuid FK receivables | אם הופק חוב מהאירוע |
| notes | text | |
| ek_event_identifier | text | מזהה EventKit (ייבוא/ייצוא) |
| ek_calendar_identifier | text | |

תנועות מקושרות: `transactions.event_id`.
אינדקס: `(user_id, event_date)`.

### receivables (כסף שחייבים לי)
| עמודה | טיפוס | הערות |
|---|---|---|
| id, user_id | uuid | |
| contact_id | uuid FK contacts NOT NULL | |
| title / reason | text | |
| original_amount | numeric(14,2) > 0 | |
| currency | char(3) | |
| issued_date | date | |
| due_date | date | |
| status | debt_status | **נגזר** בטריגר מסכום התשלומים (פרט ל-written_off/cancelled) |
| event_id | uuid FK events | |
| notes | text | |

View `receivable_balances`: `paid = Σ debt_payments.amount`, `remaining = original − paid`, `is_overdue = due_date < today AND remaining > 0`.

### payables (כסף שאני חייב)
מבנה זהה ל-receivables (contact, original_amount, due_date, status, event_id).

### debt_payments
| עמודה | טיפוס | הערות |
|---|---|---|
| id, user_id | uuid | |
| receivable_id | uuid FK | |
| payable_id | uuid FK | `CHECK (num_nonnulls(receivable_id, payable_id) = 1)` |
| amount | numeric(14,2) > 0 | |
| paid_date | date | |
| transaction_id | uuid FK transactions UNIQUE | התנועה בחשבון (income ל-receivable, expense ל-payable) |
| notes | text | |

טריגר: `Σ payments ≤ original_amount` (תשלום-יתר דורש אישור מפורש / יצירת חוב הפוך).
יצירה רק דרך RPC `record_debt_payment(debt_id, amount, date, account_id)` שיוצר באותה טרנזקציה את התנועה ואת התשלום.

### financial_snapshots
| id, user_id, snapshot_date DATE, available NUMERIC, liabilities NUMERIC, receivables NUMERIC, payables NUMERIC, details JSONB |
UNIQUE(user_id, snapshot_date). נוצר יומית ע"י pg_cron — לגרפי מגמה.

### integrations
| עמודה | טיפוס | הערות |
|---|---|---|
| id, user_id | uuid | |
| provider | text | 'feezback' \| 'csv' \| 'eventkit' ... |
| status | integration_status | |
| consent_id | text | מזהה הסכמה אצל הספק (לא סוד) |
| consent_expires_at | timestamptz | |
| scopes | text[] | |
| secret_ref | uuid | הפניה ל-Vault (tokens מוצפנים) — **לא נגיש ללקוח** (עמודה מוחרגת ב-view/grant) |
| last_sync_at | timestamptz | |

### synchronization_logs
| id, user_id, integration_id, started_at, finished_at, status sync_status, accounts_synced int, transactions_imported int, transactions_skipped int, error_code text, error_message text |

### notifications
| id, user_id, kind notification_kind, title, body, related_table text, related_id uuid, scheduled_for timestamptz, delivered_at, read_at, is_enabled bool |
+ `notification_preferences` (user_id, kind, enabled, lead_days, time_of_day).

### audit_log
| id bigserial, user_id, table_name, record_id, action ('INSERT'\|'UPDATE'\|'DELETE'), old_data jsonb, new_data jsonb, changed_at timestamptz |
RLS: SELECT בלבד לבעלים; INSERT רק מטריגר `SECURITY DEFINER`; אין UPDATE/DELETE.

## 4. RLS — תבנית

```sql
ALTER TABLE accounts ENABLE ROW LEVEL SECURITY;
ALTER TABLE accounts FORCE ROW LEVEL SECURITY;
CREATE POLICY accounts_select ON accounts FOR SELECT TO authenticated USING (user_id = (select auth.uid()));
CREATE POLICY accounts_insert ON accounts FOR INSERT TO authenticated WITH CHECK (user_id = (select auth.uid()));
CREATE POLICY accounts_update ON accounts FOR UPDATE TO authenticated USING (user_id = (select auth.uid())) WITH CHECK (user_id = (select auth.uid()));
CREATE POLICY accounts_delete ON accounts FOR DELETE TO authenticated USING (user_id = (select auth.uid()));
REVOKE ALL ON accounts FROM anon;
```
Views מוגדרים `WITH (security_invoker = true)` כדי ש-RLS יחול גם דרכם.

## 5. Views / RPC מתוכננים

| שם | תפקיד |
|---|---|
| `account_balances` | יתרה נוכחית לכל חשבון (סכומים כ-text לממשק) |
| `dashboard_summary(range)` | ממשי, התחייבויות, צפוי, חובות אליי, תזרים |
| `receivable_balances` / `payable_balances` | paid / remaining / overdue |
| `rpc_create_transfer` | העברה/תשלום אשראי אטומי |
| `rpc_record_debt_payment` | תשלום חוב + תנועה אטומי |
| `rpc_materialize_recurring(until)` | יצירת מופעים בלי כפילות (ON CONFLICT DO NOTHING) |
| `rpc_forecast(from, to)` | תחזית יומית — מקבילה ל-FinanceCore |
| `rpc_delete_my_account` | מחיקת כל נתוני המשתמש |

## 6. בדיקות מתוכננות (שלב 2–3)

- משתמש A לא רואה/מעדכן/מוחק רשומות של B בכל טבלה (כולל דרך views ו-RPC).
- A לא יכול ליצור תנועה עם `account_id` של B.
- anon לא קורא דבר.
- תרחישים A–E ברמת SQL ובמקביל ב-FinanceCore — אותן תוצאות.
- אילוצי UNIQUE מונעים כפילות מופע חוזר וייבוא כפול.
