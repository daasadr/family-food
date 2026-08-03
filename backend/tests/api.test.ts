import type { FastifyInstance } from 'fastify';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';

import { buildServer } from '../src/server.js';

/**
 * Integrační test proti skutečné testovací databázi.
 * Před během nastav DATABASE_URL na family_food_test (viz vitest.config.ts).
 */
let app: FastifyInstance;

const unique = () => Math.random().toString(36).slice(2, 10);

async function registerUser(name: string) {
  const email = `${unique()}@test.local`;
  const res = await app.inject({
    method: 'POST',
    url: '/api/v1/auth/register',
    payload: { email, password: 'heslo12345', name },
  });
  expect(res.statusCode).toBe(201);
  const body = res.json();
  return { email, ...body } as {
    email: string;
    user: { id: string };
    tokens: { accessToken: string; refreshToken: string };
  };
}

const auth = (token: string) => ({ authorization: `Bearer ${token}` });

/** Registruje uživatele a rovnou mu založí rodinu; vrací čerstvé tokeny. */
async function registerWithFamily(name = 'Vlastník') {
  const registered = await registerUser(name);
  const familyName = `Rodina ${unique()}`;
  const created = await app.inject({
    method: 'POST',
    url: '/api/v1/families',
    headers: auth(registered.tokens.accessToken),
    payload: { name: familyName },
  });
  expect(created.statusCode).toBe(201);
  return {
    email: registered.email,
    familyName,
    token: created.json().tokens.accessToken as string,
    familyId: created.json().family.id as string,
  };
}

/** Datum v budoucnu uvnitř povoleného tříměsíčního okna. */
function futureDate(offsetDays = 7): string {
  return new Date(Date.now() + offsetDays * 86_400_000).toISOString().slice(0, 10);
}

beforeAll(async () => {
  app = await buildServer();
  await app.ready();
});

afterAll(async () => {
  await app.close();
});

describe('health', () => {
  it('odpoví ok', async () => {
    const res = await app.inject({ method: 'GET', url: '/health' });
    expect(res.statusCode).toBe(200);
    expect(res.json().status).toBe('ok');
  });
});

describe('auth', () => {
  it('registruje, přihlásí a obnoví token', async () => {
    const registered = await registerUser('Tester');

    const login = await app.inject({
      method: 'POST',
      url: '/api/v1/auth/login',
      payload: { email: registered.email, password: 'heslo12345' },
    });
    expect(login.statusCode).toBe(200);

    const refresh = await app.inject({
      method: 'POST',
      url: '/api/v1/auth/refresh',
      payload: { refreshToken: login.json().tokens.refreshToken },
    });
    expect(refresh.statusCode).toBe(200);

    // Rotace: použitý refresh token už podruhé neprojde.
    const reuse = await app.inject({
      method: 'POST',
      url: '/api/v1/auth/refresh',
      payload: { refreshToken: login.json().tokens.refreshToken },
    });
    expect(reuse.statusCode).toBe(401);
  });

  it('odmítne špatné heslo', async () => {
    const registered = await registerUser('Tester');
    const res = await app.inject({
      method: 'POST',
      url: '/api/v1/auth/login',
      payload: { email: registered.email, password: 'spatneheslo' },
    });
    expect(res.statusCode).toBe(401);
    expect(res.json().error).toBe('INVALID_CREDENTIALS');
  });

  it('odmítne duplicitní e-mail', async () => {
    const registered = await registerUser('Tester');
    const res = await app.inject({
      method: 'POST',
      url: '/api/v1/auth/register',
      payload: { email: registered.email, password: 'heslo12345', name: 'Druhy' },
    });
    expect(res.statusCode).toBe(409);
  });
});

describe('smazání účtu (GDPR)', () => {
  /** Přizve druhého člena do rodiny a vrátí jeho token. */
  async function addMember(ownerToken: string) {
    const invite = await app.inject({
      method: 'POST',
      url: '/api/v1/families/me/invites',
      headers: auth(ownerToken),
      payload: {},
    });
    const member = await app.inject({
      method: 'POST',
      url: '/api/v1/auth/register',
      payload: { email: `${unique()}@test.local`, password: 'heslo12345', name: 'Člen' },
    });
    const joined = await app.inject({
      method: 'POST',
      url: '/api/v1/families/invites/accept',
      headers: auth(member.json().tokens.accessToken),
      payload: { code: invite.json().code },
    });
    expect(joined.statusCode).toBe(200);
    return joined.json().tokens.accessToken as string;
  }

  it('náhled varuje posledního člena, že mizí celá rodina', async () => {
    const { token, familyName } = await registerWithFamily();

    const res = await app.inject({
      method: 'GET',
      url: '/api/v1/auth/me/deletion-preview',
      headers: auth(token),
    });

    expect(res.statusCode).toBe(200);
    expect(res.json().willDeleteFamily).toBe(true);
    expect(res.json().familyName).toBe(familyName);
    // Přehled toho, o co přijde — varování má být konkrétní, ne obecné.
    expect(res.json().familyData).not.toBeNull();
    expect(res.json().familyData.plannedDays).toBeGreaterThanOrEqual(0);
  });

  it('bez opsání názvu rodiny se poslednímu členovi nic nesmaže', async () => {
    const { token, email } = await registerWithFamily();

    const res = await app.inject({
      method: 'DELETE',
      url: '/api/v1/auth/me',
      headers: auth(token),
      payload: {},
    });

    expect(res.statusCode).toBe(400);
    expect(res.json().error).toBe('FAMILY_NAME_MISMATCH');

    // Účet pořád existuje.
    const login = await app.inject({
      method: 'POST',
      url: '/api/v1/auth/login',
      payload: { email, password: 'heslo12345' },
    });
    expect(login.statusCode).toBe(200);
  });

  it('špatně opsaný název rodinu neodstraní', async () => {
    const { token } = await registerWithFamily();

    const res = await app.inject({
      method: 'DELETE',
      url: '/api/v1/auth/me',
      headers: auth(token),
      payload: { confirmFamilyName: 'Nějaká úplně jiná rodina' },
    });

    expect(res.statusCode).toBe(400);
    expect(res.json().error).toBe('FAMILY_NAME_MISMATCH');
  });

  it('se správně opsaným názvem smaže účet i celou rodinu', async () => {
    const { token, email, familyName } = await registerWithFamily();

    const res = await app.inject({
      method: 'DELETE',
      url: '/api/v1/auth/me',
      headers: auth(token),
      payload: { confirmFamilyName: familyName },
    });
    expect(res.statusCode).toBe(204);

    const login = await app.inject({
      method: 'POST',
      url: '/api/v1/auth/login',
      payload: { email, password: 'heslo12345' },
    });
    expect(login.statusCode).toBe(401);
  });

  it('název rodiny se porovnává bez ohledu na velikost písmen a mezery', async () => {
    const { token, familyName } = await registerWithFamily();

    const res = await app.inject({
      method: 'DELETE',
      url: '/api/v1/auth/me',
      headers: auth(token),
      payload: { confirmFamilyName: `  ${familyName.toUpperCase()}  ` },
    });

    expect(res.statusCode).toBe(204);
  });

  it('člen v rodině s ostatními se smaže bez opisování a rodina zůstane', async () => {
    const owner = await registerWithFamily();
    const memberToken = await addMember(owner.token);

    // Náhled členovi rodinu nemaže, takže potvrzení nepožaduje.
    const preview = await app.inject({
      method: 'GET',
      url: '/api/v1/auth/me/deletion-preview',
      headers: auth(memberToken),
    });
    expect(preview.json().willDeleteFamily).toBe(false);
    expect(preview.json().memberCount).toBe(2);

    const res = await app.inject({
      method: 'DELETE',
      url: '/api/v1/auth/me',
      headers: auth(memberToken),
    });
    expect(res.statusCode).toBe(204);

    const family = await app.inject({
      method: 'GET',
      url: '/api/v1/families/me',
      headers: auth(owner.token),
    });
    expect(family.statusCode).toBe(200);
    expect(family.json().members).toHaveLength(1);
  });

  it('odchod posledního vlastníka předá rodinu dalšímu členovi', async () => {
    const owner = await registerWithFamily();
    const memberToken = await addMember(owner.token);

    // Náhled vlastníkovi řekne, kdo rodinu převezme.
    const preview = await app.inject({
      method: 'GET',
      url: '/api/v1/auth/me/deletion-preview',
      headers: auth(owner.token),
    });
    expect(preview.json().willDeleteFamily).toBe(false);
    expect(preview.json().newOwnerName).toBe('Člen');

    // Právo na výmaz nesmí uvíznout na nepředaném vlastnictví.
    const res = await app.inject({
      method: 'DELETE',
      url: '/api/v1/auth/me',
      headers: auth(owner.token),
    });
    expect(res.statusCode).toBe(204);

    const family = await app.inject({
      method: 'GET',
      url: '/api/v1/families/me',
      headers: auth(memberToken),
    });
    expect(family.statusCode).toBe(200);
    expect(family.json().members).toHaveLength(1);
    expect(family.json().members[0].role).toBe('owner');
  });

  it('smazáním posledního člena zmizí i data rodiny', async () => {
    const { token, familyName } = await registerWithFamily();

    // Vytvoříme jídlo, ať je co mazat.
    const date = futureDate();
    const day = await app.inject({
      method: 'GET',
      url: `/api/v1/planner/days/${date}`,
      headers: auth(token),
    });
    const slot = day.json().slots[0];
    await app.inject({
      method: 'POST',
      url: `/api/v1/planner/slots/${slot.id}/proposals`,
      headers: auth(token),
      payload: { title: 'Guláš' },
    });

    const preview = await app.inject({
      method: 'GET',
      url: '/api/v1/auth/me/deletion-preview',
      headers: auth(token),
    });
    expect(preview.json().familyData.proposals).toBe(1);

    const res = await app.inject({
      method: 'DELETE',
      url: '/api/v1/auth/me',
      headers: auth(token),
      payload: { confirmFamilyName: familyName },
    });
    expect(res.statusCode).toBe(204);

    // Slot i návrh odešly kaskádou s rodinou — token už stejně neplatí,
    // takže se ověří přes prázdný dotaz na plánovač.
    const orphaned = await app.inject({
      method: 'GET',
      url: `/api/v1/planner/days/${date}`,
      headers: auth(token),
    });
    expect(orphaned.statusCode).toBe(401);
  });
});

describe('veřejné stránky', () => {
  it('zásady ochrany údajů jsou dostupné bez přihlášení', async () => {
    const res = await app.inject({ method: 'GET', url: '/privacy' });

    expect(res.statusCode).toBe(200);
    expect(res.headers['content-type']).toContain('text/html');
    expect(res.body).toContain('Zásady ochrany osobních údajů');
  });

  it('statické soubory nestíní API ani health', async () => {
    expect((await app.inject({ method: 'GET', url: '/health' })).statusCode).toBe(200);

    const api = await app.inject({ method: 'GET', url: '/api/v1/auth/me' });
    // Bez tokenu 401 — kdyby trasu přebral statický server, vrátil by 404.
    expect(api.statusCode).toBe(401);
  });
});

describe('rodina a pozvánky', () => {
  it('založí rodinu, pozve druhého člena a ten se připojí', async () => {
    const owner = await registerUser('Vlastník');

    const created = await app.inject({
      method: 'POST',
      url: '/api/v1/families',
      headers: auth(owner.tokens.accessToken),
      payload: { name: 'Novákovi' },
    });
    expect(created.statusCode).toBe(201);
    const ownerToken = created.json().tokens.accessToken;
    expect(created.json().family.members).toHaveLength(1);

    const invite = await app.inject({
      method: 'POST',
      url: '/api/v1/families/me/invites',
      headers: auth(ownerToken),
      payload: {},
    });
    expect(invite.statusCode).toBe(201);
    const code = invite.json().code as string;

    const member = await registerUser('Člen');
    const accepted = await app.inject({
      method: 'POST',
      url: '/api/v1/families/invites/accept',
      headers: auth(member.tokens.accessToken),
      payload: { code },
    });
    expect(accepted.statusCode).toBe(200);
    expect(accepted.json().family.members).toHaveLength(2);

    // Stejný kód nelze použít podruhé.
    const third = await registerUser('Třetí');
    const reuse = await app.inject({
      method: 'POST',
      url: '/api/v1/families/invites/accept',
      headers: auth(third.tokens.accessToken),
      payload: { code },
    });
    expect(reuse.statusCode).toBe(404);
  });

  it('bez rodiny nepustí do plánovače', async () => {
    const user = await registerUser('Bez rodiny');
    const res = await app.inject({
      method: 'GET',
      url: '/api/v1/planner/week?start=2026-08-03',
      headers: auth(user.tokens.accessToken),
    });
    expect(res.statusCode).toBe(403);
    expect(res.json().error).toBe('NO_FAMILY');
  });
});

describe('plánovač', () => {
  async function setupFamily() {
    const owner = await registerUser('Vlastník');
    const created = await app.inject({
      method: 'POST',
      url: '/api/v1/families',
      headers: auth(owner.tokens.accessToken),
      payload: { name: 'Testovací rodina' },
    });
    const token = created.json().tokens.accessToken as string;

    const invite = await app.inject({
      method: 'POST',
      url: '/api/v1/families/me/invites',
      headers: auth(token),
      payload: {},
    });
    const member = await registerUser('Člen');
    const accepted = await app.inject({
      method: 'POST',
      url: '/api/v1/families/invites/accept',
      headers: auth(member.tokens.accessToken),
      payload: { code: invite.json().code },
    });

    return { ownerToken: token, memberToken: accepted.json().tokens.accessToken as string };
  }

  /** Datum v budoucnu, ale v povoleném okně (za týden). */
  const futureDate = () => {
    const d = new Date(Date.now() + 7 * 86_400_000);
    return d.toISOString().slice(0, 10);
  };

  it('vygeneruje sloty ze šablony při otevření dne', async () => {
    const { ownerToken } = await setupFamily();
    const res = await app.inject({
      method: 'GET',
      url: `/api/v1/planner/days/${futureDate()}`,
      headers: auth(ownerToken),
    });
    expect(res.statusCode).toBe(200);
    // Výchozí šablona: snídaně, 2 svačiny, oběd, večeře.
    expect(res.json().slots).toHaveLength(5);
    expect(res.json().slots.map((s: { slotType: string }) => s.slotType)).toEqual([
      'breakfast',
      'snack1',
      'lunch',
      'snack2',
      'dinner',
    ]);
  });

  it('projde celý tok: návrh → hlas → komentář → potvrzení → odemknutí', async () => {
    const { ownerToken, memberToken } = await setupFamily();
    const date = futureDate();

    const day = await app.inject({
      method: 'GET',
      url: `/api/v1/planner/days/${date}`,
      headers: auth(ownerToken),
    });
    const lunchSlot = day.json().slots.find((s: { slotType: string }) => s.slotType === 'lunch');

    const proposal = await app.inject({
      method: 'POST',
      url: `/api/v1/planner/slots/${lunchSlot.id}/proposals`,
      headers: auth(ownerToken),
      payload: { title: 'Svíčková', description: 'S houskovým knedlíkem' },
    });
    expect(proposal.statusCode).toBe(201);
    const proposalId = proposal.json().id as string;

    // Druhý člen hlasuje.
    const voted = await app.inject({
      method: 'POST',
      url: `/api/v1/planner/proposals/${proposalId}/vote`,
      headers: auth(memberToken),
    });
    expect(voted.statusCode).toBe(200);
    expect(voted.json().voteCount).toBe(1);
    expect(voted.json().votedByMe).toBe(true);

    // Opakovaný hlas nezdvojí počet.
    const votedAgain = await app.inject({
      method: 'POST',
      url: `/api/v1/planner/proposals/${proposalId}/vote`,
      headers: auth(memberToken),
    });
    expect(votedAgain.json().voteCount).toBe(1);

    const comment = await app.inject({
      method: 'POST',
      url: `/api/v1/planner/proposals/${proposalId}/comments`,
      headers: auth(memberToken),
      payload: { text: 'Super, dlouho jsme neměli!' },
    });
    expect(comment.statusCode).toBe(201);

    // Potvrdit smí kterýkoli člen rodiny (dle zadání).
    const confirmed = await app.inject({
      method: 'POST',
      url: `/api/v1/planner/proposals/${proposalId}/confirm`,
      headers: auth(memberToken),
    });
    expect(confirmed.statusCode).toBe(200);
    expect(confirmed.json().status).toBe('confirmed');

    // Potvrzený návrh nelze editovat.
    const edit = await app.inject({
      method: 'PATCH',
      url: `/api/v1/planner/proposals/${proposalId}`,
      headers: auth(ownerToken),
      payload: { title: 'Něco jiného' },
    });
    expect(edit.statusCode).toBe(409);
    expect(edit.json().error).toBe('PROPOSAL_LOCKED');

    // Do uzamčeného slotu nelze přidat další návrh.
    const blocked = await app.inject({
      method: 'POST',
      url: `/api/v1/planner/slots/${lunchSlot.id}/proposals`,
      headers: auth(memberToken),
      payload: { title: 'Guláš' },
    });
    expect(blocked.statusCode).toBe(409);

    const unlocked = await app.inject({
      method: 'POST',
      url: `/api/v1/planner/proposals/${proposalId}/unlock`,
      headers: auth(ownerToken),
    });
    expect(unlocked.statusCode).toBe(200);
    expect(unlocked.json().status).toBe('proposed');

    // Po odemknutí už editace projde.
    const editAgain = await app.inject({
      method: 'PATCH',
      url: `/api/v1/planner/proposals/${proposalId}`,
      headers: auth(ownerToken),
      payload: { title: 'Svíčková na smetaně' },
    });
    expect(editAgain.statusCode).toBe(200);
    expect(editAgain.json().title).toBe('Svíčková na smetaně');
  });

  it('odmítne plánování dál než 3 měsíce dopředu', async () => {
    const { ownerToken } = await setupFamily();
    const far = new Date(Date.now() + 200 * 86_400_000).toISOString().slice(0, 10);

    const res = await app.inject({
      method: 'GET',
      url: `/api/v1/planner/days/${far}`,
      headers: auth(ownerToken),
    });
    expect(res.statusCode).toBe(400);
    expect(res.json().error).toBe('BEYOND_PLANNING_WINDOW');
  });

  it('umí přidat mimořádný slot mimo šablonu', async () => {
    const { ownerToken } = await setupFamily();
    const date = futureDate();

    const res = await app.inject({
      method: 'POST',
      url: `/api/v1/planner/days/${date}/slots`,
      headers: auth(ownerToken),
      payload: { customLabel: 'Narozeninový dort' },
    });
    expect(res.statusCode).toBe(201);
    expect(res.json().isCustomSlot).toBe(true);

    const day = await app.inject({
      method: 'GET',
      url: `/api/v1/planner/days/${date}`,
      headers: auth(ownerToken),
    });
    expect(day.json().slots).toHaveLength(6);
  });

  it('týdenní přehled vrací 7 dní s počty', async () => {
    const { ownerToken } = await setupFamily();
    const res = await app.inject({
      method: 'GET',
      url: `/api/v1/planner/week?start=${futureDate()}`,
      headers: auth(ownerToken),
    });
    expect(res.statusCode).toBe(200);
    expect(res.json().days).toHaveLength(7);
    expect(res.json().days[0].slotCount).toBe(5);
  });

  it('úprava šablony se projeví v nově otevřených dnech', async () => {
    const { ownerToken } = await setupFamily();

    const updated = await app.inject({
      method: 'PUT',
      url: '/api/v1/planner/template',
      headers: auth(ownerToken),
      payload: {
        slots: [
          { slotType: 'breakfast', enabled: true },
          { slotType: 'lunch', enabled: true },
          { slotType: 'dinner', enabled: false },
        ],
      },
    });
    expect(updated.statusCode).toBe(200);
    expect(updated.json().slots).toHaveLength(3);

    const day = await app.inject({
      method: 'GET',
      url: `/api/v1/planner/days/${futureDate()}`,
      headers: auth(ownerToken),
    });
    // Vypnutá večeře se negeneruje.
    expect(day.json().slots.map((s: { slotType: string }) => s.slotType)).toEqual([
      'breakfast',
      'lunch',
    ]);
  });

  it('nepustí k cizí rodině', async () => {
    const a = await setupFamily();
    const b = await setupFamily();
    const date = futureDate();

    const day = await app.inject({
      method: 'GET',
      url: `/api/v1/planner/days/${date}`,
      headers: auth(a.ownerToken),
    });
    const slotId = day.json().slots[0].id;

    const res = await app.inject({
      method: 'POST',
      url: `/api/v1/planner/slots/${slotId}/proposals`,
      headers: auth(b.ownerToken),
      payload: { title: 'Cizí návrh' },
    });
    expect(res.statusCode).toBe(404);
  });
});
