# Zadání pro Claude Code: Rodinný stravovací plánovač (pracovní název)

Tento dokument slouží jako kompletní brief pro Claude Code. Obsahuje (A) instrukce k instalaci
vývojového prostředí na disk D:, a (B) podrobnou specifikaci aplikace k implementaci.

---

## ČÁST A — Instalace vývojového prostředí (Windows, vše na disk D:)

**Cíl:** Flutter SDK, Android SDK, a související nástroje nainstalovat na `D:\dev\...`, ne na C:,
kvůli místu na disku. Postupuj krok po kroku, po každém kroku ověř výsledek.

### A1. Příprava adresářové struktury

```powershell
mkdir D:\dev
mkdir D:\dev\flutter
mkdir D:\dev\android-sdk
```

### A2. Stažení a instalace Flutter SDK

1. Zkontroluj, že je nainstalovaný Git (`git --version`). Pokud ne, nainstaluj Git for Windows.
2. Nejjednodušší cesta je naklonovat Flutter SDK přímo z GitHubu do `D:\dev\flutter` (umožní to
   snadné budoucí `flutter upgrade`):

```powershell
git clone https://github.com/flutter/flutter.git -b stable D:\dev\flutter
```

   Alternativně lze stáhnout aktuální stabilní `.zip` balíček z oficiální adresy
   `https://docs.flutter.dev/install` (sekce "Manual install") a rozbalit ho do `D:\dev\flutter`.
   **Nikdy needávej Flutter do `C:\Program Files`** — oprávnění tam dělají problémy s `flutter upgrade`.
   Cesta k adresáři by neměla obsahovat mezery ani diakritiku.

3. Přidej Flutter do PATH (jen pro aktuálního uživatele, netřeba admin práva):

```powershell
[Environment]::SetEnvironmentVariable("Path", $env:Path + ";D:\dev\flutter\bin", "User")
```

   Po tomto kroku restartuj terminál (a VS Code), aby se PATH načetl znovu.

4. Ověření:

```powershell
flutter --version
flutter doctor
```

### A3. Android toolchain (na D:)

1. Nainstaluj Android Studio (instalátor sám nabídne, kam uložit SDK — zvol `D:\dev\android-sdk`
   namísto výchozí cesty na C:).
2. Po instalaci nastav proměnnou prostředí, aby `flutter doctor` i další nástroje věděly, kde SDK
   hledat:

```powershell
[Environment]::SetEnvironmentVariable("ANDROID_HOME", "D:\dev\android-sdk", "User")
[Environment]::SetEnvironmentVariable("ANDROID_SDK_ROOT", "D:\dev\android-sdk", "User")
```

3. V Android Studiu: Settings → Plugins → doinstaluj Flutter plugin (Dart se doinstaluje automaticky).
4. Spusť znovu `flutter doctor -v` a vyřeš všechny `[X]` položky, které ukáže (typicky přijetí
   licencí: `flutter doctor --android-licenses`).

### A4. VS Code

1. Nainstaluj rozšíření **Flutter** a **Dart** ve VS Code (obsahuje i debugger, hot reload apod.).
2. `Ctrl+Shift+P` → "Flutter: New Project" — pokud VS Code požádá o cestu k SDK, ukaž na
   `D:\dev\flutter`.

### A5. Poznámka k iOS

Buildy pro iOS (Xcode, Simulator, App Store submission) vyžadují macOS. Na Windows lze psát
veškerý Dart/Flutter kód a testovat na Androidu i webu, ale finální iOS build a nahrání do App
Store bude nutné dělat buď na Macu (fyzickém nebo cloudovém, např. Codemagic/Ionic Appflow/
GitHub Actions s macOS runnerem), nebo přes CI/CD službu specializovanou na Flutter (Codemagic má
štědrý free tier a umí i App Store Connect submission bez vlastního Macu).

### A6. Rychlá kontrola, že vše funguje

```powershell
cd D:\dev
flutter create test_app
cd test_app
flutter run
```

Pokud se objeví emulátor/zařízení se spuštěnou ukázkovou appkou, instalace je v pořádku a
`test_app` lze smazat.

---

## ČÁST B — Specifikace aplikace

## 1. Přehled a vize

Komerční mobilní aplikace (Android + iOS, později i web) pro **rodinné plánování stravování**.
Řeší běžný problém: co uvařit, aby to chutnalo všem, a jak podle toho nakoupit — kolaborativně,
na dálku, s předstihem.

Základní princip: uživatel si založí **rodinný stravovací profil**, pozve ostatní členy rodiny
(kteří si appku také nainstalují a připojí se), a rodina společně plánuje jídelníček na kalendáři
— navrhuje jídla, hlasuje, diskutuje, a jeden z členů dělá finální rozhodnutí. Aplikace k tomu
umí navrhnout nákupní seznam pomocí AI.

**Cílová platforma:** nativní mobilní aplikace ve Flutteru (Android + iOS, distribuce přes Google
Play a App Store). Webová verze je plánovaná jako druhá fáze (Flutter Web nebo samostatný
frontend napojený na stejné API — rozhodneme později).

**Monetizace:** předplatné (freemium model) — bude řešeno později přes RevenueCat, zatím
nespecifikováno detailně, ale datový model a backend by měly počítat s tím, že přibude koncept
"plánu"/"subscription tier" u rodinného profilu.

## 2. Technologický stack

| Vrstva | Technologie | Poznámka |
|---|---|---|
| Mobilní aplikace | **Flutter** (Dart), state management **Riverpod** | Android + iOS z jedné codebase |
| Backend API | **Node.js** (Fastify nebo Express) + TypeScript, REST API | Čisté API bez UI vrstvy — Flutter dělá celé UI |
| Databáze | **PostgreSQL** | |
| ORM | **Prisma** | typově bezpečné dotazy, migrace |
| Autentizace | JWT (access + refresh token), e-mail/heslo, později OAuth (Google/Apple sign-in — Apple to pro App Store vyžaduje, pokud nabízíš i jiné social login) | |
| Push notifikace | Firebase Cloud Messaging (Android) + APNs přes FCM (iOS) | |
| Ukládání fotek (jídla) | Cloudflare R2 nebo self-hosted MinIO na VPS | bez poplatků za egress u R2 |
| AI funkce (nákupní seznam, návrhy) | Anthropic API (Claude), structured JSON output | |
| Nasazení backendu | Docker Compose na VPS (Hetzner), reverse proxy Traefik/Caddy s automatickým TLS | navazuje na současný workflow |
| CI/CD | GitHub Actions — build & test na push, deploy backendu na VPS, build mobilních binárek (Codemagic doporučeno pro iOS) | |
| Verzování | GitHub, samostatné repo (nebo monorepo se složkami `/app` a `/backend`) | |

## 3. Datový model (návrh, Prisma schema — konceptuálně)

```
Family
  id, name, subscriptionTier, createdAt

User
  id, email, passwordHash, name, avatarUrl, familyId, role (owner/member), createdAt

Invite
  id, familyId, token, email, expiresAt, status (pending/accepted/expired)

MealTemplate
  id, familyId, slots: [ { type: breakfast|lunch|dinner|snack1|snack2, enabled: bool, customLabel? } ]
  -- výchozí šablona: snídaně, oběd, večeře, 2 svačiny; lze upravit nebo slot zcela vypnout

MealSlot
  id, familyId, date, slotType, isCustomSlot (bool)
  -- jedna instance slotu pro konkrétní den; generuje se ze šablony při otevření dne,
     nebo se vytvoří ad-hoc (např. slot na oslavu mimo šablonu)

MealProposal
  id, mealSlotId, proposedByUserId, title, description, photoUrl,
  status (proposed | confirmed | locked), createdAt

Vote
  id, proposalId, userId, createdAt  -- unikátní pár (proposalId, userId)

Comment
  id, proposalId, userId, text, createdAt

ShoppingList
  id, familyId, rangeStart, rangeEnd, generatedAt, generatedByAI (bool)

ShoppingListItem
  id, shoppingListId, name, category, quantity?, buyByDate, note, isChecked (bool)

MealGalleryItem
  id, familyId (nullable pro globální/předvytvořenou galerii), title, photoUrl, category
  -- předvytvořená galerie běžných jídel (bez značek výrobců, obecné fotky) + vlastní rodinná galerie
```

Klíčová pravidla, která musí backend vynucovat:
- Plánovat lze max. 3 měsíce dopředu (konfigurovatelný limit).
- `MealProposal` se stavem `confirmed`/`locked` nelze editovat, dokud ho vlastník/oprávněný
  člen znovu "odemkne" zpět na `proposed`.
- Hlasovat a navrhovat může kterýkoli člen rodiny se stavem `member` i `owner`.
- Potvrdit návrh (změnit na `confirmed`) může jen člen s příslušným oprávněním (zatím: kdokoli
  v rodině — v budoucnu možná omezit na roli "vaří/nakupuje", ale pro MVP nechat otevřené všem).

## 4. Uživatelské toky a obrazovky

### 4.1 Onboarding
- Registrace (e-mail/heslo, případně Google/Apple sign-in).
- Vytvoření rodinného profilu **nebo** přijetí pozvánky (deep link / kód pozvánky).
- Odeslání pozvánek ostatním členům rodiny (e-mail nebo sdílený odkaz/kód).

### 4.2 Domovská obrazovka — aktuální týden
- Po otevření appky se zobrazí **aktuální týden** (ne jen dnešek) — kvůli plánování je potřeba
  vidět, co je již naplánováno a kde jsou mezery.
- Každý den v týdnu má vizuální indikátory (malé značky/ikony), které ukazují, kolik slotů je
  již vyplněno/potvrzeno/jen navrženo.
- Tlačítko/odkaz "Zobrazit další dny" rozbalí měsíční kalendář, který lze přepínat až 2 měsíce
  dopředu (celkem 3 měsíce včetně aktuálního).

### 4.3 Detail dne
- Zobrazí sloty podle aktivní šablony (výchozí: snídaně, oběd, večeře, 2× svačina).
- Prázdný slot → tlačítko "Navrhnout jídlo".
- Vyplněný slot → zobrazí náhled navrženého/potvrzeného jídla, po kliknutí vede na detail jídla.
- Možnost přidat mimořádný slot mimo šablonu (např. pro oslavu).

### 4.4 Detail jídla (MealProposal)
- Název, popis, fotka (z vlastní galerie rodiny, z předvytvořené galerie, nebo nahraná nová).
- Seznam všech návrhů na daný slot (pokud jich je víc), u každého počet hlasů a tlačítko hlasovat.
- Diskuzní vlákno (komentáře) pod jídlem.
- Tlačítko "Potvrdit tento návrh" (dostupné komukoli v rodině) → uzamkne slot.
- Uzamčený slot: tlačítko "Odemknout k úpravě" (vrátí do editovatelného stavu).

### 4.5 Nastavení šablony
- Zapnutí/vypnutí jednotlivých slotů (snídaně/oběd/večeře/svačina 1/svačina 2).
- Přejmenování slotů, přidání vlastních.

### 4.6 Nákupní seznam (AI)
- Uživatel zvolí časové rozmezí (např. tento týden) → appka pošle na backend požadavek na
  vygenerování seznamu.
- Backend sesbírá potvrzené (případně i navržené, dle nastavení) jídla v daném rozmezí + info
  o tom, kdy rodina obvykle nakupuje (nastavení: dny nákupů).
- AI (Claude API) vrátí strukturovaný seznam položek rozdělených podle toho, **kdy je nejlepší
  je koupit** vzhledem k trvanlivosti a datu plánovaného jídla (např. maso na pátek se doporučí
  koupit až ve čtvrtek, ne v pondělí).
- Uživatel může položky odškrtávat, upravovat, mazat, přidávat vlastní.

### 4.7 Galerie jídel
- Předvytvořená galerie běžných jídel (bez konkrétních značek výrobců) pro rychlý výběr.
- Vlastní rodinná galerie — fotky uvařených jídel, které si rodina postupně vytváří.

## 5. Poznámka k databázi potravin/jídel

**Nebudovat vlastní databázi potravin po značkách** (jako Kalorické tabulky) — to je projekt na
roky. Pro MVP:
1. Volný textový vstup názvu jídla.
2. Vlastní + předvytvořená galerie (bez značek, obecné fotky běžných jídel).
3. Volitelně v pozdější fázi: napojení na **Open Food Facts** (otevřená, zdarma dostupná databáze
   potravin s čárovými kódy) pro vyhledávání konkrétních produktů při tvorbě nákupního seznamu.

## 6. AI nákupní seznam — technický přístup

- Žádný vlastní ML model, žádné trénování.
- Backend sestaví prompt s (a) seznamem plánovaných jídel a jejich daty, (b) informací o dnech
  nákupu, (c) instrukcí, aby model vrátil **pouze JSON** (bez preambule) ve tvaru:

```json
{
  "items": [
    { "name": "treska", "category": "ryby", "buyByDate": "2026-08-07", "note": "koupit až den před vařením kvůli trvanlivosti" }
  ]
}
```

- Systémový prompt bude obsahovat pár few-shot příkladů běžné trvanlivosti potravin (maso, ryby,
  pečivo, mléčné výrobky, trvanlivé zboží) — toto je čistě prompt-engineering úloha.

## 7. Nefunkční požadavky

- Nasazení backendu: Docker Compose na Hetzner VPS, reverse proxy s automatickým TLS.
- CI/CD: GitHub Actions — testy a build backendu při push do `main`, automatický deploy na VPS;
  mobilní build (Android APK/AAB, iOS IPA) přes Codemagic nebo GitHub Actions s macOS runnerem.
- Zálohování PostgreSQL databáze (denní dump na VPS, případně i mimo server).
- GDPR: appka bude zpracovávat osobní údaje (e-maily, jména, fotky) — je třeba zásady ochrany
  osobních údajů a možnost smazání účtu/dat na žádost uživatele (vyžaduje App Store i Google Play).

## 8. Navrhované fáze vývoje (MVP → rozšíření)

**Fáze 1 (MVP):**
- Registrace, rodinný profil, pozvánky.
- Kalendář týdne/měsíce, výchozí šablona slotů.
- Návrh jídla, hlasování, komentáře, potvrzení/odemknutí.
- Vlastní i předvytvořená galerie fotek.

**Fáze 2:**
- AI nákupní seznam.
- Push notifikace (nový návrh, nový komentář, blížící se nákup).
- Nastavení šablony (vlastní sloty).

**Fáze 3:**
- Předplatné (RevenueCat), rozlišení free/placený tier.
- Napojení na Open Food Facts.
- Webová verze.

---

## 9. Instrukce pro Claude Code — jak postupovat

1. Nejprve proveď kroky z ČÁSTI A (instalace Flutteru na D:) a ověř `flutter doctor`.
2. Založ dvě repozitáře (nebo monorepo se dvěma složkami): `backend/` (Node.js + Fastify +
   Prisma + PostgreSQL) a `app/` (Flutter).
3. Začni backendem: Prisma schema podle datového modelu výše, základní REST endpointy pro auth,
   rodiny, pozvánky, sloty, návrhy, hlasy, komentáře.
4. Poté Flutter appka: obrazovky podle sekce 4, napojené na API.
5. Postupuj po fázích podle sekce 8 — nesnaž se implementovat vše najednou.
6. Docker Compose a nasazení na VPS řeš až po funkčním MVP na lokálním prostředí.
