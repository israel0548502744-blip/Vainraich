# ארכיטקטורה

> סטטוס: **אושר ע״י המשתמש (02/11/2026)** עם שינויים: מקומי-תחילה, ייבוא מסמכים עם AI, ספקי AI חינמיים. ראו §12.

## 1. תמונה כללית

```
┌──────────────────────── iPhone (SwiftUI, iOS 17+) ────────────────────────┐
│  Features (Home · Calendar · Transactions · Debts · Accounts · Reports ·   │
│            Settings · Onboarding)                                          │
│      │ ViewModels (@Observable, @MainActor)                                │
│      ▼                                                                     │
│  FinanceCore (Swift Package טהור: מודלים, חישובים, תחזית, חוזרות)          │
│      ▲                                                                     │
│  DataLayer: Repository protocols ──► SupabaseRepository | DemoRepository   │
│      │            + מטמון מקומי (SwiftData) לעבודה לא מקוונת – שלב מאוחר   │
│  Platform: EventKitService · NotificationService · Export (CSV/PDF)        │
│  DesignSystem (Swift Package: צבעים, טיפוגרפיה, רכיבים, פורמט ₪/תאריך)     │
└──────────────┬─────────────────────────────────────────────────────────────┘
               │ HTTPS (supabase-swift), JWT של המשתמש בלבד, anon key ציבורי
┌──────────────▼──────────────────── Supabase ──────────────────────────────┐
│ Auth (Sign in with Apple + אימייל/OTP)                                     │
│ PostgreSQL: טבלאות + RLS (user_id = auth.uid()) + Views + RPC + Triggers   │
│ audit_log (טריגרים) · pg_cron (חוזרות/תזכורות)                              │
│ Edge Functions (Deno): banking-connect, banking-sync, webhooks, csv-import │
│ Vault / Function secrets: מפתחות ספקים — לעולם לא בלקוח                     │
└──────────────┬─────────────────────────────────────────────────────────────┘
               │ mTLS / OAuth של הספק
     ספק בנקאות פתוחה מורשה (למשל Feezback)  ·  (Bit דרך ספק מורשה, אם יתאפשר)
```

## 2. סטאק טכנולוגי מומלץ

| שכבה | טכנולוגיה | הערות |
|---|---|---|
| UI | SwiftUI, Swift 6 (strict concurrency), iOS 17+ | `@Observable`, `NavigationStack`, `TabView` |
| גרפים | Swift Charts | אינטראקטיבי (`chartXSelection`), נגיש |
| יומן | EventKit (`requestFullAccessToEvents` / `requestWriteOnlyAccessToEvents`) | הרשאה מפורשת ובחירת כיוון ייבוא/ייצוא |
| התראות | UserNotifications (מקומי) → APNs בהמשך | |
| Backend client | `supabase-swift` (SPM) | |
| מטמון מקומי | SwiftData (שלב מאוחר) | לא חובה ל-MVP |
| מאגר נתונים | PostgreSQL 15+ ב-Supabase | `NUMERIC(14,2)` |
| פונקציות שרת | Supabase Edge Functions (TypeScript/Deno) | סודות בצד שרת בלבד |
| יצירת פרויקט | XcodeGen | `project.yml` במאגר |
| בדיקות | XCTest / Swift Testing; pgTAP או SQL tests ל-RLS; snapshot tests ל-UI | |
| CI | GitHub Actions (`macos-15`) לבנייה ובדיקות; Linux לבדיקות FinanceCore ו-SQL | |
| לינט | SwiftLint, SwiftFormat | |

### למה לא React Native / Flutter?
הדרישה מעדיפה נייטיב, ו-EventKit, Swift Charts, נגישות ו-RTL מקבלים את החוויה הטובה ביותר ב-SwiftUI. החיסרון: פיתוח UI מחייב macOS. אם אין למשתמש גישה ל-Mac/CI — זו נקודת החלטה (ראו §11).

## 3. מבנה המאגר המוצע

```
/ios
  project.yml                 # XcodeGen
  App/                        # @main, ניתוב, הזרקת תלויות
  Features/<Feature>/         # Views + ViewModels
  Packages/
    FinanceCore/              # Swift Package טהור — נבדק גם על Linux
    DesignSystem/
    DataLayer/
  Resources/ (he.lproj, Assets, Localizable.xcstrings)
  Tests/ (UnitTests, SnapshotTests, UITests)
/supabase
  migrations/                 # SQL ממוספר
  functions/                  # Edge Functions
  tests/                      # בדיקות RLS ובידוד
  seed_demo.sql               # דמו — רק לסביבת demo
/docs (אופציונלי)
PROJECT_PLAN.md ARCHITECTURE.md DATABASE_SCHEMA.md API_INTEGRATIONS.md CHANGELOG.md TODO.md
```

## 4. מודל חשבונאי (הליבה)

### 4.1 סוגי תנועות
| kind | השפעה על יתרה | נספר בדוחות הכנסה/הוצאה? |
|---|---|---|
| `income` | +amount לחשבון | כן — הכנסה |
| `expense` | −amount מהחשבון | כן — הוצאה |
| `transfer` | −amount מחשבון מקור, +amount לחשבון יעד | **לא** |
| `adjustment` | ±amount (עדכון יתרה ידני / התאמה לבנק) | לא (מוצג בנפרד) |

`amount` תמיד חיובי; הכיוון נקבע לפי `kind`. כך אין בלבול סימנים.

### 4.2 יתרת חשבון
```
balance(account) = opening_balance + Σ effect(t)  for t in transactions where status = 'completed'
```
תנועות `pending` לא משנות יתרה ממשית — הן נכנסות לתחזית בלבד. `cancelled` לא משפיעות על כלום.

### 4.3 כרטיס אשראי (תרחיש C)
- חשבון מסוג `credit_card`. היתרה שלו בדרך כלל **שלילית** = חוב.
- רכישה ב-₪300: `expense` על חשבון האשראי → הוצאות +300, יתרת כרטיס −300 (התחייבות 300).
- תשלום החשבון: `transfer` מהבנק לכרטיס ₪300 → בנק −300, כרטיס 0. **אין הוצאה נוספת.**
- ייבוא שורת "חיוב ויזה" מהבנק מסווג אוטומטית כ-`transfer` (ע"פ כלל התאמה), לא כהוצאה.
- התחייבות אשראי = `Σ max(0, −balance)` לחשבונות credit_card פעילים.
- תאריך חיוב חודשי (`billing_day`) של הכרטיס משמש בתחזית: ביום החיוב יוצא מהבנק המקושר סכום החוב הצפוי.

### 4.4 קטגוריות כסף בדשבורד
| מושג | הגדרה |
|---|---|
| **כסף ממשי (זמין)** | Σ יתרות של חשבונות פעילים עם `include_in_available = true` (בנק, מזומן, Bit; חיסכון — לפי בחירה, ברירת מחדל לא) |
| **התחייבויות** | חוב אשראי + Σ יתרת `payables` פתוחים |
| **כסף צפוי** | תנועות `pending` עתידיות מסוג income + הכנסות צפויות מאירועים לא משולמים + מופעי חוזרות עתידיים |
| **חובות אליי (receivables)** | Σ `remaining` של receivables פתוחים |
| **יתרה חזויה** | ממשי + הכנסות צפויות − הוצאות צפויות (בטווח) |

תרחיש A: 5,000 + 500 + 200 = **5,700** ממשי; 5,700 + 1,500 − 700 = **6,500** חזוי. ✅

### 4.5 חובות (תרחיש B)
- `receivables.original_amount = 2000`; תשלום ₪500 נרשם כ-`debt_payments` **ובמקביל** נוצרת תנועת `income` completed בחשבון שבו התקבל הכסף, המקושרת לתשלום.
- `remaining = original − Σ payments` (מחושב, לא נשמר כשדה ניתן לעריכה) → 1,500.
- היתרה הממשית גדלה רק בזכות תנועת ה-income — כלומר רק כשהתשלום נרשם בפועל.
- סטטוס: `open` → `partially_paid` → `paid` (נגזר אוטומטית), `written_off` / `cancelled` ידני.

### 4.6 חוזרות (תרחיש D)
- `recurring_transactions` מגדיר כלל (RRULE מוגבל: daily/weekly/monthly/yearly/custom interval, יום בחודש, תאריך סיום).
- התחזית **מחשבת מופעים וירטואליים** ואינה שומרת אותם.
- כשמופע מתממש — נוצרת תנועה עם `recurring_id` + `occurrence_date`; אילוץ `UNIQUE(recurring_id, occurrence_date)` מונע כפילות.
- מופע שכבר יש לו תנועה (בכל סטטוס פרט ל-cancelled שסומן "דלג") לא נספר שוב בתחזית.

### 4.7 אירועים (תרחיש E)
- `events.expected_income` / `expected_expense` נכנסים לתחזית כ"משוער" כל עוד `payment_status ≠ paid`.
- לעולם לא נכנסים ליתרה הממשית.
- **כלל דה-דופליקציה:** אם לאירוע יש receivable מקושר — התחזית סופרת את ה-receivable (remaining) ולא את `expected_income` של האירוע. אם לאירוע יש תנועות מקושרות completed — הצפוי מצטמצם בסכומן.
- אירוע מיומן Apple לא יוצר הכנסה אוטומטית — המשתמש מסמן ידנית.

### 4.8 מנוע התחזית
קלט: יתרות ממשיות, תנועות pending, מופעי חוזרות, אירועים, receivables/payables עם `due_date`, חיובי אשראי צפויים.
פלט: סדרה יומית `{date, confirmedBalance, projectedBalance, items[]}` כאשר כל item מסומן `confidence: confirmed | expected | estimated`:
- **confirmed** — תנועות pending שהוזנו עם סכום ותאריך, חיוב אשראי ידוע.
- **expected** — חוזרות, אירועים עם סכום מוסכם.
- **estimated** — receivables (תלוי בצד שלישי), אירועים ללא סכום סופי.
המשתמש יכול לבחור אם לכלול receivables בתחזית (ברירת מחדל: כן, מוצגים בנפרד). אזהרה כאשר `projectedBalance < 0` בתאריך כלשהו בטווח, עם התאריך הראשון.
המנוע חי ב-`FinanceCore` (Swift), ופונקציה מקבילה ב-SQL (`rpc_forecast`) לשימוש בהתראות שרת — שתיהן נבדקות מול אותם תרחישים.

## 5. שכבת הנתונים

- `protocol AccountsRepository`, `TransactionsRepository`, ... — מימושים: `SupabaseRepository` (אמיתי), `DemoRepository` (in-memory, מוצג רק במצב הדגמה עם באנר).
- סכומים: ה-API מחזיר Views עם `amount::text`; הלקוח ממיר ל-`Decimal(string:)`. כתיבה דרך RPC שמקבל `text`/`numeric`. **אסור** `Double` בכל נתיב כספי.
- פעולות מרובות-רשומות (תשלום חוב + תנועת הכנסה, העברה) מתבצעות ב-**RPC טרנזקציוני אחד** בשרת, לא בשתי קריאות מהלקוח.

## 6. אבטחה

- RLS מופעל על **כל** טבלה פרטית; מדיניות `user_id = auth.uid()` ל-select/insert/update/delete; `user_id` ברירת מחדל `auth.uid()` ולא ניתן לשינוי (טריגר).
- מפתחות זרים בין טבלאות נבדקים גם לבעלות (טריגר/בדיקה ב-RPC שהחשבון המקושר שייך לאותו משתמש) — מונע הפניה לרשומה של משתמש אחר.
- ה-iOS מחזיק רק `SUPABASE_URL` + `anon key` (ציבוריים בהגדרתם). `service_role` ומפתחות ספקים — רק ב-Edge Functions secrets.
- לא נשמרות סיסמאות בנק. חיבור בנק = הסכמה (consent) אצל הספק המורשה; נשמר רק מזהה consent ו-tokens מוצפנים בצד שרת (Vault).
- סשן: tokens ב-Keychain (ברירת המחדל של supabase-swift עם Keychain storage); נעילה ב-Face ID אופציונלית באפליקציה.
- `audit_log`: טריגרים על insert/update/delete בטבלאות כספיות (old/new JSON, user, זמן).
- ולידציה: אילוצי CHECK ב-DB (סכום > 0, תאריכים, enums) + ולידציה בלקוח.
- גיבויים: Supabase PITR (בתוכנית Pro) / גיבוי יומי; ייצוא CSV מלא למשתמש.
- פרטיות: מחיקת חשבון מלאה (cascade) — דרישת App Store.

## 7. לוקליזציה ועיצוב

- `he` כשפת פיתוח, `layoutDirection = .rightToLeft` טבעי מהמערכת; בדיקה גם עם `.environment(\.layoutDirection, .rightToLeft)` ב-Previews.
- פורמט: `Decimal.FormatStyle.Currency(code: "ILS", locale: he_IL)`, תאריכים `dd/MM/yyyy`, לוח שנה גרגוריאני, שבוע מתחיל ביום ראשון.
- מספרים ב-LTR בתוך טקסט RTL (Unicode isolates) כדי ש"−₪1,500" לא יתהפך.
- Dynamic Type, VoiceOver labels בעברית, ניגודיות AA, מצב כהה/בהיר.
- שפה עיצובית: רקע ניטרלי, כרטיסים עם עומק עדין, צבע מותג אחד, צבעים סמנטיים (ירוק=ממשי/הכנסה, ענבר=צפוי, אדום=התחייבות/שלילי, סגול=חובות אליי), גופן מערכת (SF Pro / SF Hebrew) עם ספרות טבלאיות (`.monospacedDigit()`).

## 8. ניווט

`TabView` עם 5 לשוניות: **בית · יומן · תנועות · חובות · עוד** ("עוד" מכיל חשבונות, דוחות, הגדרות) — כי iOS מציג עד 5 לשוניות בנוחות. כפתור "+" גלובלי להוספה מהירה (תנועה / אירוע / חוב / העברה).

## 9. אינטגרציות — ראו API_INTEGRATIONS.md

## 10. סיכונים טכניים

| # | סיכון | השפעה | מיטיגציה |
|---|---|---|---|
| R1 | אין macOS בסביבת הפיתוח | לא ניתן להריץ/לצלם UI כאן | FinanceCore טהור נבדק על Linux; CI עם macOS; Mac של המשתמש לבדיקה ידנית |
| R2 | Open Banking דורש רישיון ISA | אין סנכרון בנק אוטומטי ללא ספק מורשה | Provider abstraction; ייבוא CSV/Excel מהבנק כברירת מחדל; בירור מול Feezback |
| R3 | Bit ללא API ציבורי לפרטים | אין סנכרון Bit | הזנה ידנית + התאמה לתנועות בנק ("BIT" בתיאור) + CSV |
| R4 | איבוד דיוק Decimal ב-JSON | טעויות אגורות | העברה כמחרוזת; בדיקות round-trip |
| R5 | ספירה כפולה | מספרים שגויים | מודל transfer, כללי דה-דופליקציה, בדיקות תרחישים A–E + בדיקות property |
| R6 | RTL בגרפים/מספרים | תצוגה מבולבלת | Snapshot tests בעברית, בידוד LTR למספרים |
| R7 | אזורי זמן / תאריכים | מופעים ביום הלא נכון | תאריכים כספיים כ-`DATE` (ללא שעה), חישוב ב-`Asia/Jerusalem` |
| R8 | מטבע זר | סכימת סכומים במטבעות שונים | MVP: ILS בלבד בסיכומים; חשבונות במט"ח מוצגים בנפרד עד שיוגדר שער |
| R9 | עלויות Supabase / ספק | עלות חודשית | Free tier לפיתוח; Pro (~$25/חודש) לייצור עם גיבויים |
| R10 | עמידה בכללי App Store (פיננסי) | דחייה | מדיניות פרטיות, מחיקת חשבון, ללא ייעוץ פיננסי |

## 11. נקודות החלטה פתוחות (לאישור המשתמש)

1. אישור סטאק נייטיב SwiftUI + Supabase (מול חלופה חוצת-פלטפורמות אם אין גישה ל-Mac).
2. האם יש Mac / חשבון Apple Developer / מוכנות ל-CI בתשלום (דקות macOS ב-GitHub Actions)?
3. האם לכלול חיסכון ב"כסף זמין" כברירת מחדל? (מוצע: לא)
4. מטבע: ILS בלבד ב-MVP? (מוצע: כן)
5. Sign in with Apple + אימייל כספקי התחברות? (מוצע: כן)

## 12. עדכון 02/11/2026 — החלטות שאושרו

### 12.1 מקומי-תחילה
```
iPhone ── AppModel (@Observable) ── FinanceCore (חישובים) ── FinanceFileStore (JSON, FileProtection.complete)
   │                                   └─ DocumentAI (חילוץ ממסמכים)
   ├─ EventKit · UserNotifications · LocalAuthentication · VisionKit · ContactsUI · AppIntents
   └─ ספקי AI (HTTPS ישיר, מפתח של המשתמש מה-Keychain)
```
* כל הנתונים במסמך אחד (`FinanceData`) שנשמר אטומית ב-Application Support עם הצפנת iOS.
* סכומים נשמרים כמחרוזות (`"1234.50"`) — אין המרה דרך Double בשום שלב.
* גיבוי/שחזור: ייצוא קובץ JSON מלא דרך גיליון השיתוף (iCloud Drive/קבצים).
* Supabase (שלב 2) יתווסף כשכבת סנכרון אופציונלית מעל אותו מודל.

### 12.2 מבנה הקוד בפועל
```
ios/
  project.yml                      XcodeGen
  App/                             SwiftUI: AppModel, DesignSystem, Features/*, Services/*
  Packages/VainraichKit/
    Sources/FinanceCore/           LocalDate, Money, Models, Ledger, Recurrence, Debts, Forecast, Summary, Filtering, Persistence, DemoData
    Sources/DocumentAI/            ExtractionModels, ExtractionPrompt, Providers, RuleBasedParser, Redactor, ImportPlanner
    Tests/                         48 בדיקות (כולל תרחישים A–E)
.github/workflows/ios.yml          בדיקות Linux + בנייה ל-Simulator + צילומי מסך (macOS)
```

### 12.3 זרימת ייבוא מסמך
1. המשתמש בוחר חשבון יעד ומסמך (סריקה, תמונה, PDF, טקסט).
2. `DocumentPreprocessor` מתאים את הקלט ליכולות הספק: PDF ישיר / תמונות / טקסט (PDFKit או זיהוי טקסט Vision). במצב פרטיות: טקסט בלבד + `Redactor` (ת.ז., חשבונות, כרטיסים → 4 ספרות אחרונות).
3. הספק מחזיר JSON לפי סכמה קבועה (`ExtractionPrompt`); הפענוח סלחני — שורה פגומה נזרקת, לא כל המסמך.
4. `ImportPlanner`: ממפה לתנועות, מסווג חיוב כרטיס כ**העברה** (מונע ספירה כפולה), מזהה כפילויות (מזהה חיצוני, סכום+תאריך±1, ביט±3 ימים), מנחש קטגוריה, משווה יתרות.
5. מסך בדיקה: המשתמש מאשר/עורך/מבטל כל שורה ובוחר אם להתאים יתרה (תנועת `adjustment` — לא הכנסה ולא הוצאה).

### 12.4 התאמת אירועים להכנסות (`EventMatcher`)
* מועמדים: אירוע עם הכנסה צפויה, או ששמו כולל "אירוע"/מילות אירוע בתשלום, ושהמשתמש לא סימן "לא בתשלום".
* הכנסות מועמדות: לא מקושרות לאירוע, לא תשלום חוב, לא מבוטלות, בחלון של 14 יום לפני עד 45 יום אחרי.
* ציון: סכום (עד 50), לקוח (35/25), מילים משותפות (20), תזמון (10/5); סף 30. כל הכנסה מוצעת לאירוע אחד בלבד (הטוב ביותר).
* אישור משתמש בלבד. דחייה נשמרת ב-`rejectedTransactionIDs`; תשובה "בתשלום/לא" ב-`isIncomeEvent` (שדות אופציונליים — קבצים ישנים נטענים).
* אישור התאמה לאירוע עם חוב פתוח רושם גם `DebtPayment` על אותה תנועה — בלי ליצור כסף כפול.

### 12.6 גרסת Android (03/11/2026)
* `android/core` — מודול Kotlin/JVM טהור שמשכפל את `FinanceCore` + `DocumentAI` (אותם כללים, אותן בדיקות תרחישים). כסף: `BigDecimal` בסקאלה 2, נשמר כמחרוזת.
* `android/app` — Jetpack Compose, `AppViewModel` יחיד, ניווט מבוסס מחסנית, נתונים בקובץ JSON בתיקייה הפרטית של האפליקציה (`filesDir`, מוצפן בהצפנת המכשיר), מפתחות API ב-`EncryptedSharedPreferences`.
* שני הקודים נפרדים בכוונה (נייטיב בכל פלטפורמה). מקור האמת לכללים: בדיקות התרחישים — כל שינוי כלל צריך להיכנס לשתיהן.
* הבדל ידוע: באנדרואיד אין זיהוי טקסט עברי מתמונה בתוך המכשיר (ML Kit לא תומך בעברית) — צילומים נקראים דרך ספק AI; PDF דיגיטלי נקרא גם בלי AI (PDFBox).

### 12.5 החלטת אבטחה: מפתחות API
הכלל "אין מפתחות בלקוח" נועד לסודות *של האפליקציה*. כאן המפתח שייך למשתמש ומשמש רק אותו, ולכן נשמר ב-Keychain (`WhenUnlockedThisDeviceOnly`), לא בקבצים ולא בגיבויים. אם בעתיד תופעל האפליקציה לציבור עם מפתח משותף — הקריאות יעברו דרך Edge Function.
