# Family Food — rodinný stravovací plánovač

Kolaborativní plánování jídelníčku pro celou rodinu: návrhy jídel na kalendáři, hlasování,
diskuze, potvrzení a (ve fázi 2) AI generovaný nákupní seznam.

Kompletní zadání: [zadani-rodinny-jidelnicek-claude-code.md](zadani-rodinny-jidelnicek-claude-code.md)

## Struktura repozitáře

```
backend/   Node.js 22 + Fastify 5 + TypeScript + Prisma + PostgreSQL — REST API
app/       Flutter (Dart) + Riverpod — mobilní aplikace (Android + iOS)
```

## Stav vývoje

| Fáze | Obsah | Stav |
|---|---|---|
| 1 (MVP) | registrace, rodina, pozvánky, kalendář, návrhy, hlasy, komentáře, galerie | hotovo |
| 2 | AI nákupní seznam, nastavení šablony | hotovo |
| 2 | push notifikace | plánováno |
| 3 | předplatné (RevenueCat), Open Food Facts, web | plánováno |

---

## Lokální vývojové prostředí

Vše je nainstalované na disku `D:` (mimo `C:`, kvůli místu).

| Nástroj | Umístění |
|---|---|
| Flutter SDK 3.44.8 | `D:\dev\flutter` |
| Android SDK | `D:\dev\android-sdk` |
| Gradle cache | `D:\dev\gradle` |
| PostgreSQL 17.6 (portable) | `D:\dev\pgsql`, data v `D:\dev\pgdata` |
| Pub cache | `D:\dev\pub-cache` |

Nastavené uživatelské proměnné prostředí: `ANDROID_HOME`, `ANDROID_SDK_ROOT`,
`GRADLE_USER_HOME`, `PUB_CACHE`, `JAVA_HOME` (JDK 21 dodávané s Android Studiem), a `PATH`
rozšířený o `D:\dev\flutter\bin`, `D:\dev\android-sdk\platform-tools`
a `cmdline-tools\latest\bin`.

Po restartu počítače je potřeba nastartovat databázi ručně — neběží jako služba.

### Databáze — start a stop

```powershell
# start
D:\dev\pgsql\bin\pg_ctl.exe -D D:\dev\pgdata -l D:\dev\pgdata\server.log start

# stav
D:\dev\pgsql\bin\pg_isready.exe -p 5432

# stop
D:\dev\pgsql\bin\pg_ctl.exe -D D:\dev\pgdata stop
```

Databáze a role vytvořené pro projekt:

| Databáze | Účel |
|---|---|
| `family_food` | vývoj |
| `family_food_test` | automatické testy |

Role `familyfood` / heslo `familyfood` (jen lokálně — v produkci nahradit).

---

## Backend

```powershell
cd backend
npm install
copy .env.example .env      # a doplň hodnoty
npx prisma migrate dev      # vytvoří schéma
npm run seed                # naplní globální galerii jídel
npm run dev                 # http://localhost:3000
```

Skripty:

| Příkaz | Co dělá |
|---|---|
| `npm run dev` | vývojový server s hot reloadem (tsx watch) |
| `npm run build` / `npm start` | produkční build a spuštění |
| `npm run typecheck` | kontrola typů bez buildu |
| `npm test` | integrační testy proti `family_food_test` |
| `npm run prisma:studio` | GUI prohlížeč databáze |

### Přehled API

Base URL: `http://localhost:3000/api/v1`. Autentizace hlavičkou `Authorization: Bearer <accessToken>`.

**Auth** — `/auth`

| Metoda | Cesta | Popis |
|---|---|---|
| POST | `/register` | registrace, vrací uživatele + tokeny |
| POST | `/login` | přihlášení |
| POST | `/refresh` | obnovení tokenů (refresh token se rotuje) |
| POST | `/logout` | zneplatnění refresh tokenu |
| GET | `/me` | aktuální uživatel |

**Rodiny a pozvánky** — `/families`

| Metoda | Cesta | Popis |
|---|---|---|
| POST | `/` | založení rodiny (zakladatel = owner) |
| GET | `/me` | detail rodiny včetně členů |
| PATCH | `/me` | název, dny nákupů (jen owner) |
| POST | `/me/leave` | odchod z rodiny |
| POST | `/me/transfer-ownership` | předání vlastnictví |
| POST | `/me/invites` | vytvoření pozvánky — kód se vrací jen jednou |
| GET | `/me/invites` | seznam pozvánek |
| DELETE | `/me/invites/:id` | zrušení pozvánky |
| POST | `/invites/accept` | přijetí pozvánky kódem |

Endpointy, které mění členství v rodině, vracejí i **nové tokeny** — access token nese
`familyId`, takže po vstupu do rodiny je potřeba ho vyměnit.

**Plánovač** — `/planner`

| Metoda | Cesta | Popis |
|---|---|---|
| GET | `/template` | šablona slotů rodiny |
| PUT | `/template` | přepsání slotů (zapnutí/vypnutí, vlastní názvy) |
| GET | `/week?start=YYYY-MM-DD` | týdenní přehled s počty pro indikátory |
| GET | `/days/:date` | detail dne — sloty se generují ze šablony při otevření |
| POST | `/days/:date/slots` | mimořádný slot mimo šablonu (oslava apod.) |
| DELETE | `/slots/:slotId` | smazání mimořádného slotu |
| POST | `/slots/:slotId/proposals` | návrh jídla |
| GET/PATCH/DELETE | `/proposals/:id` | detail, úprava, smazání návrhu |
| POST | `/proposals/:id/confirm` | potvrzení návrhu → uzamkne slot |
| POST | `/proposals/:id/unlock` | odemknutí zpět k úpravě |
| POST/DELETE | `/proposals/:id/vote` | hlasování |
| GET/POST | `/proposals/:id/comments` | diskuzní vlákno |
| DELETE | `/comments/:id` | smazání vlastního komentáře |

## Nasazení

Produkce běží na sdíleném serveru, kde reverse proxy a HTTPS spravuje
samostatné serverové okno. Postup, porty a text k předání jsou
v [deploy/README.md](deploy/README.md).

Stručně: `docker compose` spustí PostgreSQL a API; API poslouchá na
`127.0.0.1:3004` a servíruje jak REST API (`/api/v1/…`), tak úvodní stránku
a zásady ochrany osobních údajů (`/privacy`). Databáze se na hosta
nepublikuje.

Release build aplikace míří na `https://api.familyfood-ai.eu/api/v1`
i bez `--dart-define` — aby se omylem nevydala verze ukazující na localhost.

**Nákupní seznam** — `/shopping-lists`

| Metoda | Cesta | Popis |
|---|---|---|
| POST | `/generate` | AI sestaví seznam z jídel v rozmezí (max 10× za hodinu) |
| GET | `/` | přehled seznamů s počtem odškrtnutých položek |
| GET/DELETE | `/:id` | detail a smazání seznamu |
| POST | `/:id/items` | přidání vlastní položky |
| PATCH/DELETE | `/items/:itemId` | odškrtnutí, úprava, smazání položky |

Generování vyžaduje `ANTHROPIC_API_KEY`. Bez klíče vrací `409 AI_NOT_CONFIGURED` —
zbytek API funguje normálně.

**Galerie** — `/gallery`

| Metoda | Cesta | Popis |
|---|---|---|
| GET | `/?scope=all\|global\|family` | globální i rodinná galerie, filtr `category`, `search` |
| POST | `/` | přidání do rodinné galerie |
| DELETE | `/:id` | smazání z rodinné galerie (globální je jen ke čtení) |

### Doménová pravidla vynucovaná backendem

- Plánovat lze nejvýše `MAX_PLANNING_MONTHS_AHEAD` (výchozí 3) měsíce dopředu.
- Návrh se stavem `confirmed`/`locked` nelze editovat ani smazat, dokud ho někdo neodemkne.
- Ve slotu smí být potvrzené nejvýše jedno jídlo; dokud je potvrzené, nelze přidat další návrh.
- Navrhovat, hlasovat, komentovat i potvrzovat smí kterýkoli člen rodiny (owner i member).
- Upravit/smazat návrh smí jen jeho autor; komentář jen jeho autor.
- Pozvánky i refresh tokeny se v databázi ukládají jen jako hash.

### Chybové odpovědi

```json
{ "error": "SLOT_LOCKED", "message": "V tomto slotu je už potvrzené jídlo…" }
```

Klient rozlišuje případy podle stabilního `error` kódu, ne podle textu zprávy.

---

## Mobilní aplikace

```powershell
cd app
flutter pub get
flutter run                       # vybere připojené zařízení / emulátor
flutter run -d chrome             # rychlá zkouška v prohlížeči
flutter test                      # unit testy (nepotřebují backend)
flutter test test_integration     # testy proti běžícímu backendu na :3000
flutter analyze                   # statická analýza
```

**Backend musí běžet**, jinak se aplikace nepřihlásí. Adresa API se odvozuje automaticky:
Android emulátor `http://10.0.2.2:3000/api/v1`, jinak `http://localhost:3000/api/v1`.
Přepsat lze při spuštění:

```powershell
flutter run --dart-define=API_BASE_URL=https://api.example.com/api/v1
```

### Struktura

```
lib/
  main.dart                    kořen aplikace, lokalizace na cs_CZ
  src/
    router.dart                go_router + přesměrování podle stavu přihlášení
    core/
      api_client.dart          Dio, hlavička s tokenem, automatický refresh při 401
      api_service.dart         typované metody, jedna na endpoint
      token_storage.dart       tokeny v šifrovaném úložišti zařízení
      date_utils.dart          práce s daty a české formátování
      app_theme.dart           Material 3 téma, světlé i tmavé
    models/models.dart         datové modely + fromJson
    providers/providers.dart   Riverpod: auth, rodina, šablona, plánovač, galerie
    features/
      auth/                    přihlášení a registrace
      onboarding/              založení rodiny nebo přijetí pozvánky
      home/                    aktuální týden s indikátory naplněnosti
      calendar/                měsíční kalendář (3 měsíce dopředu)
      day/                     detail dne se sloty a návrhy
      proposal/                detail jídla s hlasy a diskuzí, formulář návrhu
      settings/                rodina, pozvánky, šablona slotů
    widgets/common.dart        sdílené stavy (chyba, prázdno, načítání)
```

Riverpod se používá **bez code-genu** — žádný `build_runner`, providery jsou psané ručně.

Ověřeno: `flutter analyze` bez nálezů, 8 unit testů, 6 integračních testů proti běžícímu
backendu, sestavení pro web i Android (`app-debug.apk`).

### Stav aplikace vs. zadání

Hotové obrazovky podle sekce 4 zadání: 4.1 onboarding, 4.2 týden + měsíční kalendář,
4.3 detail dne včetně mimořádných slotů, 4.4 detail jídla s hlasováním, diskuzí,
potvrzením a odemknutím, 4.5 nastavení šablony, 4.7 výběr z galerie při návrhu jídla.

Zbývá (fáze 2 a dál): nákupní seznam s AI (4.6), nahrávání vlastních fotek,
push notifikace, předplatné.

---

## Poznámky

- Fotky v předvytvořené galerii jsou zatím **zástupné** (placehold.co). Před vydáním je nahraď
  vlastními nebo licencovanými obrázky na Cloudflare R2 / MinIO.
- iOS build vyžaduje macOS — plánuje se přes Codemagic nebo GitHub Actions s macOS runnerem.
- Před nasazením do produkce vyměň `JWT_ACCESS_SECRET` a `JWT_REFRESH_SECRET` za dlouhé
  náhodné hodnoty a nastav skutečné heslo databáze.
