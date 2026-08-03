import type { FamilyRole, PrismaClient, User } from '@prisma/client';

import { env } from '../../config/env.js';
import { generateOpaqueToken, hashPassword, hashToken, verifyPassword } from '../../lib/crypto.js';
import { badRequest, conflict, unauthorized } from '../../lib/errors.js';


export interface TokenPair {
  accessToken: string;
  refreshToken: string;
}

/** Kolik dat rodiny zmizí se smazáním posledního člena. */
export interface FamilyDataSummary {
  proposals: number;
  comments: number;
  shoppingLists: number;
  galleryItems: number;
  plannedDays: number;
}

export interface DeletionPreview {
  /** True, když je uživatel poslední v rodině — pak mizí i rodina. */
  willDeleteFamily: boolean;
  familyName: string | null;
  memberCount: number;
  /** Komu připadne vlastnictví, pokud odchází poslední vlastník. */
  newOwnerName: string | null;
  /** Vyplněno jen když willDeleteFamily. */
  familyData: FamilyDataSummary | null;
}

export interface PublicUser {
  id: string;
  email: string;
  name: string;
  avatarUrl: string | null;
  familyId: string | null;
  role: FamilyRole;
}

export function toPublicUser(user: User): PublicUser {
  return {
    id: user.id,
    email: user.email,
    name: user.name,
    avatarUrl: user.avatarUrl,
    familyId: user.familyId,
    role: user.role,
  };
}

function refreshExpiry(): Date {
  return new Date(Date.now() + env.REFRESH_TOKEN_TTL_DAYS * 86_400_000);
}

export class AuthService {
  constructor(
    private readonly prisma: PrismaClient,
    private readonly signAccessToken: (payload: {
      sub: string;
      familyId: string | null;
      role: FamilyRole;
    }) => string,
  ) {}

  private async issueTokens(user: User): Promise<TokenPair> {
    const refreshToken = generateOpaqueToken();

    await this.prisma.refreshToken.create({
      data: {
        userId: user.id,
        tokenHash: hashToken(refreshToken),
        expiresAt: refreshExpiry(),
      },
    });

    const accessToken = this.signAccessToken({
      sub: user.id,
      familyId: user.familyId,
      role: user.role,
    });

    return { accessToken, refreshToken };
  }

  /** Vydá novou dvojici tokenů — používá se i po změně členství v rodině. */
  async issueTokensForUserId(userId: string): Promise<TokenPair> {
    const user = await this.prisma.user.findUniqueOrThrow({ where: { id: userId } });
    return this.issueTokens(user);
  }

  async register(input: {
    email: string;
    password: string;
    name: string;
  }): Promise<{ user: PublicUser; tokens: TokenPair }> {
    const email = input.email.trim().toLowerCase();

    const existing = await this.prisma.user.findUnique({ where: { email } });
    if (existing) {
      throw conflict('EMAIL_TAKEN', 'Účet s tímto e-mailem už existuje.');
    }

    const user = await this.prisma.user.create({
      data: {
        email,
        name: input.name.trim(),
        passwordHash: await hashPassword(input.password),
      },
    });

    return { user: toPublicUser(user), tokens: await this.issueTokens(user) };
  }

  async login(input: {
    email: string;
    password: string;
  }): Promise<{ user: PublicUser; tokens: TokenPair }> {
    const email = input.email.trim().toLowerCase();
    const user = await this.prisma.user.findUnique({ where: { email } });

    // Stejná chyba pro neexistující účet i špatné heslo — neprozrazuje,
    // které e-maily jsou registrované.
    const invalid = unauthorized('INVALID_CREDENTIALS', 'Nesprávný e-mail nebo heslo.');
    if (!user) {
      // Ověření naprázdno, aby odpověď trvala podobně dlouho jako u existujícího účtu.
      await verifyPassword(
        '$argon2id$v=19$m=19456,t=2,p=1$c29tZXNhbHR2YWx1ZQ$0000000000000000000000000000000000000000000',
        input.password,
      );
      throw invalid;
    }

    if (!(await verifyPassword(user.passwordHash, input.password))) {
      throw invalid;
    }

    return { user: toPublicUser(user), tokens: await this.issueTokens(user) };
  }

  /** Rotace: starý refresh token se zneplatní, vydá se nová dvojice. */
  async refresh(refreshToken: string): Promise<{ user: PublicUser; tokens: TokenPair }> {
    const stored = await this.prisma.refreshToken.findUnique({
      where: { tokenHash: hashToken(refreshToken) },
      include: { user: true },
    });

    if (!stored || stored.revokedAt || stored.expiresAt < new Date()) {
      throw unauthorized('INVALID_REFRESH_TOKEN', 'Relace vypršela, přihlas se prosím znovu.');
    }

    await this.prisma.refreshToken.update({
      where: { id: stored.id },
      data: { revokedAt: new Date() },
    });

    return {
      user: toPublicUser(stored.user),
      tokens: await this.issueTokens(stored.user),
    };
  }

  async logout(refreshToken: string): Promise<void> {
    await this.prisma.refreshToken.updateMany({
      where: { tokenHash: hashToken(refreshToken), revokedAt: null },
      data: { revokedAt: new Date() },
    });
  }

  async me(userId: string): Promise<PublicUser> {
    const user = await this.prisma.user.findUniqueOrThrow({ where: { id: userId } });
    return toPublicUser(user);
  }

  /**
   * Co se stane při smazání účtu. Klient si to vyžádá dřív, než ukáže
   * potvrzovací dialog — u posledního člena rodiny je totiž potřeba
   * varovat, že mizí celá rodina, a vyžádat si opsání jejího názvu.
   */
  async deletionPreview(userId: string): Promise<DeletionPreview> {
    const user = await this.prisma.user.findUniqueOrThrow({ where: { id: userId } });

    if (!user.familyId) {
      return {
        willDeleteFamily: false,
        familyName: null,
        memberCount: 0,
        newOwnerName: null,
        familyData: null,
      };
    }

    const familyId = user.familyId;
    const family = await this.prisma.family.findUniqueOrThrow({ where: { id: familyId } });

    const others = await this.prisma.user.findMany({
      where: { familyId, id: { not: userId } },
      orderBy: { createdAt: 'asc' },
      select: { id: true, name: true, role: true },
    });

    if (others.length > 0) {
      // Rodina zůstává. Pokud odchází poslední vlastník, převezme roli
      // nejdéle přítomný člen — právo na výmaz nesmí uvíznout na tom,
      // že uživatel zapomněl předat vlastnictví.
      const someoneElseOwns = others.some((m) => m.role === 'owner');
      return {
        willDeleteFamily: false,
        familyName: family.name,
        memberCount: others.length + 1,
        newOwnerName:
          user.role === 'owner' && !someoneElseOwns ? (others[0]?.name ?? null) : null,
        familyData: null,
      };
    }

    // Poslední člen — s účtem odchází i celá rodina. Spočítáme, o co přijde,
    // aby varování nebylo obecné, ale konkrétní.
    const [proposals, comments, shoppingLists, galleryItems, plannedDays] = await Promise.all([
      this.prisma.mealProposal.count({ where: { mealSlot: { familyId } } }),
      this.prisma.comment.count({ where: { proposal: { mealSlot: { familyId } } } }),
      this.prisma.shoppingList.count({ where: { familyId } }),
      this.prisma.mealGalleryItem.count({ where: { familyId } }),
      this.prisma.mealSlot
        .findMany({ where: { familyId }, distinct: ['date'], select: { date: true } })
        .then((rows) => rows.length),
    ]);

    return {
      willDeleteFamily: true,
      familyName: family.name,
      memberCount: 1,
      newOwnerName: null,
      familyData: { proposals, comments, shoppingLists, galleryItems, plannedDays },
    };
  }

  /**
   * Smazání účtu na žádost uživatele (GDPR, vyžadují i oba obchody).
   *
   * Kaskády v schématu odstraní tokeny, návrhy, hlasy i komentáře.
   *
   * Rodina se maže jen s posledním členem, a to až po opsání jejího názvu —
   * bez toho by jedno chybné ťuknutí smazalo celou historii jídelníčku.
   * Když v rodině někdo zůstává, data zůstávají jemu.
   */
  async deleteAccount(userId: string, confirmFamilyName?: string): Promise<void> {
    const user = await this.prisma.user.findUniqueOrThrow({ where: { id: userId } });

    if (!user.familyId) {
      await this.prisma.user.delete({ where: { id: userId } });
      return;
    }

    const familyId = user.familyId;
    const others = await this.prisma.user.findMany({
      where: { familyId, id: { not: userId } },
      orderBy: { createdAt: 'asc' },
      select: { id: true, role: true },
    });

    if (others.length === 0) {
      const family = await this.prisma.family.findUniqueOrThrow({ where: { id: familyId } });

      const typed = confirmFamilyName?.trim() ?? '';
      if (typed.toLocaleLowerCase('cs') !== family.name.trim().toLocaleLowerCase('cs')) {
        throw badRequest(
          'FAMILY_NAME_MISMATCH',
          `Jsi poslední člen rodiny, takže se smaže i celá rodina a její jídelníček. `
            + `Pro potvrzení opiš přesně její název: „${family.name}".`,
        );
      }

      // Smazání rodiny kaskádou odnese sloty, návrhy, seznamy i galerii.
      await this.prisma.$transaction([
        this.prisma.user.delete({ where: { id: userId } }),
        this.prisma.family.delete({ where: { id: familyId } }),
      ]);
      return;
    }

    const promoteId =
      user.role === 'owner' && !others.some((m) => m.role === 'owner')
        ? others[0]?.id
        : undefined;

    await this.prisma.$transaction([
      ...(promoteId
        ? [this.prisma.user.update({ where: { id: promoteId }, data: { role: 'owner' } })]
        : []),
      this.prisma.user.delete({ where: { id: userId } }),
    ]);
  }
}
