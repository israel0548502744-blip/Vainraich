# אינטגרציות חיצוניות — מחקר ותכנון

> סטטוס: **מחקר (שלב 0)**. **אף אינטגרציה לא מומשה ולא נבדקה.** כל מה שכתוב כאן הוא ממצאי מחקר ותכנון בלבד.
> תאריך מחקר: 02/11/2026. יש לאמת מול הגורמים לפני חתימה/מימוש.

## 1. בנקאות פתוחה בישראל — רקע רגולטורי

ממצאים:
- בנק ישראל אימץ את **הוראה 368** ואת תקן **Berlin Group NextGenPSD2 XS2A** כתקן הבנקאות הפתוחה בישראל.
- **חוק שירות מידע פיננסי** קובע שגוף המקבל מידע פיננסי של לקוחות חייב **רישיון "נותן שירות מידע פיננסי"** מרשות ניירות ערך (ISA). מספר החברות המורשות קטן (פורסם על ה-7 בסדר הגודל הזה).
- ב-07/06/2026 פרסמה רשות ני"ע הוראה לחברות תשלום על יישום התקן; חוק ההסדרים 2026 **דחה** את מועד תחילת חובות הבנקאות הפתוחה לחברות תשלום (רלוונטי ל-Bit ולחברות כרטיסים מסוימות).
- פורטל המפתחים של בנק הפועלים מציין במפורש: *"Service providers with an Israeli PSD2 license may use Bank Hapoalim's APIs"*.

**מסקנה:** אדם פרטי **אינו יכול** להתחבר ישירות ל-API של הבנקים לצורך קריאת נתוניו בתוך אפליקציה. הנתיבים האפשריים:
1. שימוש בספק מורשה (aggregator) שמחזיק ברישיון ומציע שירות ללקוחות עסקיים.
2. קבלת רישיון עצמאי (תהליך רגולטורי ארוך ויקר — לא מתאים לאפליקציה אישית).
3. ייבוא ידני של קבצי CSV/Excel שהמשתמש מוריד מאתר הבנק — **חוקי, זמין מיד, ללא צד שלישי**.

### נתיב שנדחה: סקרייפרים עם סיסמת בנק
ספריות קוד פתוח (למשל israeli-bank-scrapers) מתחברות לאתר הבנק עם שם משתמש וסיסמה. **נדחה**: מחייב שמירת סיסמאות בנק (סותר כלל 14), עוקף את מנגנון ההסכמה הרגולטורי, ועלול להפר תנאי שימוש של הבנקים.

## 2. Feezback — ספק מועמד ראשי

מקור: https://docs.feezback.cloud/docs/introduction-to-open-banking-data

| נושא | ממצא |
|---|---|
| מהות | אגרגטור בנקאות פתוחה ישראלי; API אחד לבנקים ולחברות כרטיסים; מושך נתונים **רק דרך ה-API הרשמי** של כל מוסד |
| בנקים | לאומי/Pepper, הפועלים, דיסקונט/מרכנתיל, מזרחי, קבוצת הבינלאומי, יהב |
| כרטיסי אשראי | כאל, ישראכרט, מקס, אמריקן אקספרס |
| נתונים | חשבונות, יתרות, תנועות; חשבונות עו"ש, כרטיסים, חיסכון, הלוואות, ני"ע; עד 3 שנים היסטוריה |
| תהליך הסכמה | השרת שלנו יוצר בקשת הסכמה חתומה → המשתמש מאשר במסך Feezback → מאשר באפליקציית הבנק → Feezback מודיע לשרת (הסכמה ניתנה / משיכה ראשונה הושלמה / הסכמה בוטלה) |
| זהות | הסכמה קשורה לת.ז. אחת; ההתחברות לבנק חייבת להתאים לת.ז. |
| דרישת רישיון | לפי התיעוד: **רק ארגונים בעלי רישיון לשירותי מידע פיננסי מקבלים נתונים פיננסיים מלאים**; ארגון ללא רישיון יכול לקבל דירוג אשראי בלבד |
| Sandbox | לא מתועד בפומבי |
| תמחור | לא מפורסם — דורש פנייה למכירות |
| Endpoints | `/tpp/v1/...`, `userId` בפורמט `{sub}@{tpp_id}` |

**חסם מרכזי:** לא ברור אם Feezback יכולה לשמש "מטריית רישיון" עבור אפליקציה של גורם לא מורשה. **נדרשת פנייה** ל-Feezback עם השאלות בסעיף 7.

## 3. ספקים/פורטלים נוספים שנבדקו

| גורם | ממצא |
|---|---|
| בנק הפועלים — poalimdev.co.il | פורטל מפתחים עם sandbox; פרודקשן רק לבעלי רישיון PSD2 ישראלי |
| הבינלאומי (FIBI) — פורטל dev | API לגישת TPP: פרטי חשבון, יתרות, תנועות; sandbox קיים |
| בנק ישראל — מסמכי יישום Berlin Group | מסמכי תקן (כולל כרטיסים) — רלוונטיים לבניית adapter תקני |

אפשר להירשם ל-sandbox של בנקים כדי לפתח adapter תקני, אבל **אין לזה ערך בפרודקשן בלי רישיון**. לכן העדיפות: ספק אחד מורשה.

## 4. Bit

מקור: https://open-banking.bitpay.co.il/

- קיים **פורטל מפתחים של Bit** (סטטוס "Live", דף Sandbox ו-Availability; מאוחסן על תשתית Salt Edge — `bit-hapoalim.saltedge.com`).
- התוכן הפומבי לא פירט את ה-endpoints. דף ה-sandbox החזיר 404 בזמן הבדיקה.
- לפי המסגרת הרגולטורית — גישה רק ל-TPP מורשה, וחובות הבנקאות הפתוחה לחברות תשלום **נדחו** בחוק ההסדרים 2026.
- **אין ראיה לקיום API ציבורי לקריאת היסטוריית Bit של אדם פרטי.**

**החלטה:** Bit ימומש כ:
1. **הזנה ידנית** — חשבון מסוג `bit`, תנועות ידניות.
2. **התאמה לתנועות בנק** — תנועות בנק שתיאורן מכיל "BIT"/"ביט" מוצעות להתאמה לתנועת Bit ידנית (`matched_transaction_id`), כך שאין ספירה כפולה.
3. **ייבוא CSV** — אם המשתמש יכול לייצא היסטוריה מהאפליקציה/מהבנק.
4. אם בעתיד ספק מורשה יחשוף נתוני Bit — ייכנס כ-adapter נוסף.

## 5. Apple Calendar (EventKit)

- iOS 17+: `requestFullAccessToEvents()` לקריאה/ייבוא; `requestWriteOnlyAccessToEvents()` אם המשתמש רוצה רק ייצוא.
- `Info.plist`: `NSCalendarsFullAccessUsageDescription`, `NSCalendarsWriteOnlyAccessUsageDescription` — טקסט בעברית שמסביר בדיוק מה ייעשה.
- זרימה: הגדרות → "חיבור ליומן Apple" → הסבר → בקשת הרשאה → בחירת יומנים → בחירת כיוון (ייבוא / ייצוא / שניהם).
- ייבוא: אירוע מיובא **ללא** הכנסה צפויה; המשתמש מוסיף סכום ידנית. נשמר `ek_event_identifier` לסנכרון חוזר.
- ייצוא: אירועי האפליקציה נכתבים ליומן ייעודי ("כספים") שהאפליקציה יוצרת.
- אין גישה ליומן ללא הרשאה; ביטול הרשאה מטופל בחן.
- **בדיקה:** רק בסימולטור/מכשיר (לא בסביבת Linux).

## 6. שכבת ה-Provider (ארכיטקטורה)

```swift
// iOS — לא מדבר עם הספק ישירות, רק עם Edge Functions שלנו
protocol BankingIntegrationService {
    func availableProviders() async throws -> [ProviderInfo]
    func startConnection(provider: ProviderID) async throws -> URL      // URL למסך הסכמה של הספק
    func connections() async throws -> [IntegrationConnection]
    func triggerSync(connectionID: UUID) async throws -> SyncLog
    func revoke(connectionID: UUID) async throws
}
```

```ts
// Edge Functions (Deno) — סודות הספק רק כאן
interface BankingProviderAdapter {
  id: 'feezback' | 'csv' | string
  createConsent(userId: string, scopes: Scope[]): Promise<{ redirectUrl: string; consentId: string }>
  handleWebhook(req: Request): Promise<ConsentEvent>        // אימות חתימה חובה
  fetchAccounts(consentId: string): Promise<ProviderAccount[]>
  fetchTransactions(consentId: string, accountRef: string, from: Date, to: Date): Promise<ProviderTransaction[]>
  revoke(consentId: string): Promise<void>
}
```

- נורמליזציה: `ProviderTransaction` → `transactions` עם `source='provider'`, `external_id`, ו-`ON CONFLICT DO NOTHING` על `(user_id, account_id, external_id)`.
- כללי סיווג: חיוב כרטיס מהבנק → `transfer` לחשבון האשראי המתאים (לא expense).
- כל הרצה נרשמת ב-`synchronization_logs`.
- **CsvImportAdapter** הוא הספק הראשון שימומש (שלב 7, ואפשר להקדים): מיפוי עמודות, תצוגה מקדימה, זיהוי כפילויות, תמיכה בפורמטים של הבנקים הגדולים (Excel/CSV, קידוד Windows-1255/UTF-8).
- במצב שאין ספק מוגדר — המסך מציג "חיבור בנק אוטומטי אינו זמין עדיין" ולא כפתור מזויף.

## 7. שאלות לפנייה ל-Feezback (ולספקים חלופיים)

1. האם ניתן להשתמש בשירות כאפליקציה ללא רישיון ISA עצמאי (למשל כ-agent/תחת רישיון שלכם)?
2. עלויות: הקמה, חודשי, לפי משתמש/הסכמה/קריאה.
3. האם יש sandbox עם בנקים מדומים? איך מקבלים גישה?
4. מנגנון אימות ל-API (client credentials? mTLS? מפתח חתימה לבקשות הסכמה?).
5. Webhooks — פורמט, חתימה, ניסיונות חוזרים.
6. תוקף הסכמה וחידוש (בדרך כלל 90 יום–שנה?).
7. תמיכה ב-Bit / בחברות תשלום.
8. דרישות אבטחה ופרטיות מהלקוח (DPA, אחסון בישראל וכו').

## 8. סטטוס

| אינטגרציה | סטטוס | חסם |
|---|---|---|
| ייבוא/ייצוא CSV | מתוכנן | אין |
| ייצוא PDF | מתוכנן | אין |
| EventKit | מתוכנן | בדיקה דורשת macOS/מכשיר |
| התראות מקומיות | מתוכנן | בדיקה דורשת macOS/מכשיר |
| Feezback / Open Banking | מחקר | חוזה + ייתכן רישיון ISA; תמחור לא ידוע |
| Bit | מחקר — אין API זמין לפרטים | רישיון TPP; דחיית חובות לחברות תשלום |
| APNs | מתוכנן לשלב 8 | Apple Developer Program |

## מקורות
- [בנק ישראל — בנקאות פתוחה](https://www.boi.org.il/roles/supervisionregulation/bank-sup/open-banking) (הדף חסם גישה אוטומטית בזמן המחקר)
- [בנק ישראל — הודעה על תקן בנקאות פתוחה](https://boi.org.il/en/communication-and-publications/press-releases/the-banking-supervision-department-is-leading-the-regulation-of-an-open-banking-standard-in-israel/)
- [Feezback — Introduction to Open Banking Data](https://docs.feezback.cloud/docs/introduction-to-open-banking-data)
- [Bank Hapoalim Developer Portal](https://poalimdev.co.il/)
- [Bit Developer Portal](https://open-banking.bitpay.co.il/)
- [FIBI — Getting started (sandbox)](https://devapi.test.fibi.co.il/fibi/sb/getting_started)
- [BOI Berlin Group XS2A implementation guide (cards)](https://boi.org.il/media/03dd2bib/boi-bg-xs2a-extended-service-ig-single-cards-v18.pdf)
- [Herzog — ISA directive for payment companies (06/2026)](https://herzoglaw.co.il/en/news-and-insights/israel-securities-authority-publishes-directive-for-payment-companies-regarding-the-implementation-of-an-open-banking-standard/)
- [Shibolet — Why Israel, and Why Now?](https://www.shibolet.com/en/why-israel-and-why-now/)
- [Barnea — Summa financial information service license](https://barlaw.co.il/insights_and_news/advising-summa-technologies-on-obtaining-financial-services-license)
- [The Paypers — ISA grants initial licenses](https://thepaypers.com/fintech/news/the-israel-securities-authority-grants-initial-licenses-to-fintechs)
