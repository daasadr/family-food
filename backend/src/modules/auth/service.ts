import type { FamilyRole, PrismaClient, User } from '@prisma/client';

import { env } from '../../config/env.js';
import { generateOpaqueToken, hashPassword, hashToken, verifyPassword } from '../../lib/crypto.js';
import { conflict, unauthorized } from '../../lib/errors.js';

export interface TokenPair {
  accessToken: string;
  refreshToken: string;
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
}
