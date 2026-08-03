# Nasazení na sdílený server

Server `46.224.46.43` (Ubuntu, Docker, nginx 1.24.0) hostuje víc projektů.
Reverse proxy i HTTPS spravuje **samostatné serverové okno** — tenhle projekt
do `/etc/nginx` ani do cizích složek v `/opt` nesahá.

## Co se vlastně nasazuje

| | |
|---|---|
| Co běží | **Node.js REST API** (Fastify + TypeScript) + PostgreSQL |
| Co to není | Není to Dart backend ani Flutter web build |
| Aplikace | Flutter pro **Android a iOS** — instaluje se z obchodu, nehostuje se |
| Statické soubory | jen úvodní stránka a zásady ochrany údajů, servíruje je samo API |

Webová verze (Flutter Web) je až fáze 3 a zatím neexistuje. Až vznikne, přibude
druhý kontejner se statickými soubory a druhý port.

## Porty

| Služba | Vazba na hostu | Port v kontejneru |
|---|---|---|
| API + statické stránky | `127.0.0.1:3004` | 3000 |
| PostgreSQL | **nepublikováno** | 5432 (jen interní síť Composu) |

Porty 3000–3002 jsou obsazené jinými projekty, proto 3004. Nic neposlouchá na
veřejném rozhraní — ven se lze dostat jedině přes nginx.

## První nasazení

```bash
# 1. Klon do vlastní složky projektu
sudo mkdir -p /opt/familyfood && sudo chown "$USER" /opt/familyfood
git clone https://github.com/daasadr/family-food.git /opt/familyfood
cd /opt/familyfood/deploy

# 2. Konfigurace
cp .env.example .env
openssl rand -base64 24   # -> POSTGRES_PASSWORD
openssl rand -base64 48   # -> JWT_ACCESS_SECRET
openssl rand -base64 48   # -> JWT_REFRESH_SECRET
nano .env                 # doplň i ANTHROPIC_API_KEY

# 3. Start
docker compose --env-file .env up -d --build

# 4. Ověření
docker compose ps
curl -s http://127.0.0.1:3004/health
docker ps --format 'table {{.Names}}\t{{.Ports}}'
```

Migrace a naplnění globální galerie proběhnou automaticky při startu
kontejneru (`docker-entrypoint.sh`), není potřeba nic spouštět ručně.

## Co nahlásit serverovému oknu

> Projekt **familyfood** běží. Je to **Node.js REST API (Fastify)**, ne Dart
> backend a ne Flutter web — mobilní aplikace se instaluje z obchodu, hostuje
> se jen API.
>
> Poslouchá na **`127.0.0.1:3004`** (jeden port, HTTP). Databáze na hostu
> publikovaná není.
>
> Prosím o reverse proxy a certifikát pro:
> - `api.familyfood-ai.eu` → `http://127.0.0.1:3004`
> - `familyfood-ai.eu` a `www.familyfood-ai.eu` → `http://127.0.0.1:3004`
>   (na `/` je úvodní stránka, na `/privacy` zásady ochrany osobních údajů —
>   tu URL vyžadují Google Play i App Store)
>
> Pozn.: iOS aplikace odmítne komunikovat přes HTTP, takže certifikát pro
> `api.familyfood-ai.eu` je nutná podmínka vydání do App Store.
>
> Klient posílá hlavičku `Authorization: Bearer …` — je potřeba ji propustit.
> Odpovědi jsou JSON, největší požadavky jsou v řádu kilobajtů.

## Aktualizace

```bash
cd /opt/familyfood
git pull
cd deploy
docker compose --env-file .env up -d --build
```

### Nasazení z GitHubu

Workflow **Deploy** (`.github/workflows/deploy.yml`) udělá totéž přes SSH.
Spouští se ručně (Actions → Deploy → Run workflow, do pole napsat `nasadit`) —
na sdíleném serveru je automatické nasazení při každém pushi zbytečné riziko.

Potřebuje tajné hodnoty v Settings → Secrets → Actions:

| Secret | Hodnota |
|---|---|
| `VPS_HOST` | `46.224.46.43` |
| `VPS_USER` | uživatel, který vlastní `/opt/familyfood` |
| `VPS_SSH_KEY` | privátní klíč (celý, včetně hlaviček) |

## Zálohy

`backup.sh` udělá `pg_dump`, zkomprimuje ho a maže zálohy starší 30 dnů.

```bash
chmod +x /opt/familyfood/deploy/backup.sh
crontab -e
# 15 3 * * *  /opt/familyfood/deploy/backup.sh >> /var/log/familyfood-backup.log 2>&1
```

Obnovení ze zálohy:

```bash
gunzip -c backups/family_food_2026-08-02_0315.sql.gz \
  | docker compose exec -T db psql -U familyfood -d family_food
```

## Diagnostika

```bash
docker compose logs -f api          # log API
docker compose logs -f db           # log databáze
docker compose exec db psql -U familyfood -d family_food   # SQL konzole
docker compose restart api
```

Když API nenaběhne, bývá to nejčastěji chybějící nebo příliš krátký
`JWT_ACCESS_SECRET` (minimálně 16 znaků) — kontejner to zaloguje a skončí.
