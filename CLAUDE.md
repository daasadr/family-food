# Poznámky pro Claude Code

Kontext, který není zřejmý z kódu ani z historie gitu.

## Prostředí

Všechny vývojové nástroje jsou na disku `D:`, protože `C:` je téměř plný.
Nikdy neinstaluj nic velkého na `C:`.

| Nástroj | Cesta | Proměnná prostředí |
|---|---|---|
| Flutter SDK 3.44.8 | `D:\dev\flutter` | v `PATH` |
| Android SDK | `D:\dev\android-sdk` | `ANDROID_HOME`, `ANDROID_SDK_ROOT` |
| Gradle cache | `D:\dev\gradle` | `GRADLE_USER_HOME` |
| Pub cache | `D:\dev\pub-cache` | `PUB_CACHE` |
| PostgreSQL 17.6 | `D:\dev\pgsql`, data `D:\dev\pgdata` | — |
| JDK 21 | JBR z Android Studia na `C:` | `JAVA_HOME` |

Na `D:` zbývá jen několik GB volných — před většími operacemi zkontroluj místo.
`JAVA_HOME` na úrovni systému ukazuje na odinstalovaný Adoptium JDK; přebíjí ho
uživatelská proměnná mířící na JBR z Android Studia.

Databáze neběží jako služba — po restartu počítače ji je potřeba nastartovat:

```powershell
D:\dev\pgsql\bin\pg_ctl.exe -D D:\dev\pgdata -l D:\dev\pgdata\server.log start
```

## Konvence

- **Uživatelské texty jsou česky** — chybové hlášky z API, popisky v UI, komentáře.
  Kód (identifikátory, názvy endpointů, klíče v JSON) je anglicky.
- **Chyby z API** mají stabilní kód (`error`) a českou zprávu (`message`).
  Klient rozlišuje případy podle kódu, nikdy podle textu.
- **Riverpod bez code-genu** — žádný `build_runner`, `riverpod_generator`
  ani `freezed`. Providery i `fromJson` se píší ručně.
- Tokeny a kódy pozvánek se v databázi ukládají **jen jako hash**.

## Na co si dát pozor

- Access token nese `familyId`. Každý endpoint, který mění členství v rodině
  (založení, přijetí pozvánky, odchod), proto **vrací i nové tokeny** — klient
  je musí uložit, jinak by 15 minut pracoval se starým `familyId`.
- Sloty dne se materializují ze šablony až při otevření dne (`GET /planner/days/:date`).
  Vypnutí slotu v šabloně neodstraní už vytvořené sloty v kalendáři.
- `POST` bez těla musí posílat aspoň `{}` — Fastify odmítá prázdné tělo
  s hlavičkou `content-type: application/json`. Řešeno v `ApiClient.post`.
- **Stahování velkých balíků přes Javu** (sdkmanager, AGP) se na tomto stroji
  zasekává na 0 B, i když je stejná URL přes `Invoke-WebRequest` dostupná. Když
  build stojí na „Preparing Install …", není to pomalá síť — stáhni balík ručně
  a rozbal ho na správné místo. Takhle byl nainstalovaný NDK 28.2.13676358
  (`https://dl.google.com/android/repository/android-ndk-r28c-windows.zip`
  → `D:\dev\android-sdk\ndk\28.2.13676358`).
- `path_provider_android` je v `dependency_overrides` držený na **2.2.17**. Od
  verze 2.3 táhne balíček `jni` s nativním kódem, jehož kompilace spotřebuje
  ~3 GB navíc — na to tu není místo. Vlastní nativní kód nemáme, starší
  implementace dělá totéž.
- `flutter_secure_storage` je držený na řadě **9.x**; 10.x přidává další nativní
  závislosti bez přínosu pro naše použití.
- Android build zabere ~1,5 GB v `app/build/`. Po `flutter build apk` je dobré
  `flutter clean`, pokud se místo tenčí.

## Testy

```powershell
cd backend; npm test                    # 13 integračních testů (family_food_test)
cd app; flutter test                    # 8 unit testů, bez závislosti na backendu
cd app; flutter test test_integration   # 6 testů proti běžícímu backendu na :3000
```

Integrační testy aplikace leží mimo `test/`, aby je běžné `flutter test` (a CI bez
backendu) nespouštělo. Ověřují, že modely sedí na skutečné odpovědi backendu —
spouštěj je po každé změně tvaru API.
