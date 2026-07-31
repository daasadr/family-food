import type { PrismaClient, SlotType } from '@prisma/client';

import { env } from '../../config/env.js';
import { generateInviteCode, hashToken } from '../../lib/crypto.js';
import { badRequest, conflict, forbidden, notFound } from '../../lib/errors.js';

/** Výchozí šablona ze zadání: snídaně, oběd, večeře, 2 svačiny. */
export const DEFAULT_TEMPLATE_SLOTS: Array<{ slotType: SlotType; sortOrder: number }> = [
  { slotType: 'breakfast', sortOrder: 0 },
  { slotType: 'snack1', sortOrder: 1 },
  { slotType: 'lunch', sortOrder: 2 },
  { slotType: 'snack2', sortOrder: 3 },
  { slotType: 'dinner', sortOrder: 4 },
];

export class FamilyService {
  constructor(private readonly prisma: PrismaClient) {}

  /** Založí rodinu, zakladatel se stane ownerem. Zároveň vznikne výchozí šablona. */
  async createFamily(userId: string, name: string) {
    const user = await this.prisma.user.findUniqueOrThrow({ where: { id: userId } });
    if (user.familyId) {
      throw conflict(
        'ALREADY_IN_FAMILY',
        'Už jsi členem rodiny. Nejdřív z ní odejdi, než založíš novou.',
      );
    }

    return this.prisma.$transaction(async (tx) => {
      const family = await tx.family.create({
        data: {
          name: name.trim(),
          mealTemplate: {
            create: {
              slots: { createMany: { data: DEFAULT_TEMPLATE_SLOTS } },
            },
          },
        },
      });

      await tx.user.update({
        where: { id: userId },
        data: { familyId: family.id, role: 'owner' },
      });

      return family;
    });
  }

  async getFamily(familyId: string) {
    const family = await this.prisma.family.findUnique({
      where: { id: familyId },
      include: {
        users: {
          select: { id: true, name: true, email: true, avatarUrl: true, role: true },
          orderBy: { createdAt: 'asc' },
        },
      },
    });
    if (!family) throw notFound('FAMILY_NOT_FOUND', 'Rodina nenalezena.');

    return {
      id: family.id,
      name: family.name,
      subscriptionTier: family.subscriptionTier,
      shoppingDays: family.shoppingDays,
      createdAt: family.createdAt.toISOString(),
      members: family.users,
    };
  }

  async updateFamily(
    familyId: string,
    userRole: string,
    input: { name?: string; shoppingDays?: number[] },
  ) {
    if (userRole !== 'owner') {
      throw forbidden('OWNER_ONLY', 'Upravit nastavení rodiny může jen její vlastník.');
    }
    if (input.shoppingDays?.some((d) => d < 0 || d > 6)) {
      throw badRequest('INVALID_SHOPPING_DAYS', 'Dny nákupu musí být čísla 0–6 (0 = neděle).');
    }

    await this.prisma.family.update({
      where: { id: familyId },
      data: {
        ...(input.name !== undefined ? { name: input.name.trim() } : {}),
        ...(input.shoppingDays !== undefined
          ? { shoppingDays: [...new Set(input.shoppingDays)].sort() }
          : {}),
      },
    });

    return this.getFamily(familyId);
  }

  /** Odchod z rodiny. Poslední owner musí nejdřív předat vlastnictví. */
  async leaveFamily(userId: string, familyId: string, role: string) {
    if (role === 'owner') {
      const otherOwners = await this.prisma.user.count({
        where: { familyId, role: 'owner', id: { not: userId } },
      });
      if (otherOwners === 0) {
        const otherMembers = await this.prisma.user.count({
          where: { familyId, id: { not: userId } },
        });
        if (otherMembers > 0) {
          throw conflict(
            'LAST_OWNER',
            'Jsi poslední vlastník rodiny. Nejdřív předej vlastnictví jinému členovi.',
          );
        }
      }
    }

    await this.prisma.user.update({
      where: { id: userId },
      data: { familyId: null, role: 'member' },
    });
  }

  async transferOwnership(familyId: string, actorRole: string, targetUserId: string) {
    if (actorRole !== 'owner') {
      throw forbidden('OWNER_ONLY', 'Předat vlastnictví může jen vlastník rodiny.');
    }
    const target = await this.prisma.user.findFirst({
      where: { id: targetUserId, familyId },
    });
    if (!target) throw notFound('MEMBER_NOT_FOUND', 'Tento uživatel není členem rodiny.');

    await this.prisma.user.update({ where: { id: targetUserId }, data: { role: 'owner' } });
    return this.getFamily(familyId);
  }

  // --- Pozvánky ---------------------------------------------------------

  async createInvite(familyId: string, email?: string) {
    const code = generateInviteCode();
    const expiresAt = new Date(Date.now() + env.INVITE_TTL_DAYS * 86_400_000);

    const invite = await this.prisma.invite.create({
      data: {
        familyId,
        tokenHash: hashToken(code),
        email: email?.trim().toLowerCase() ?? null,
        expiresAt,
      },
    });

    // Plaintext kód se vrací jen tady — v DB je uložený jen jeho hash.
    return {
      id: invite.id,
      code,
      email: invite.email,
      expiresAt: invite.expiresAt.toISOString(),
      status: invite.status,
    };
  }

  async listInvites(familyId: string) {
    const invites = await this.prisma.invite.findMany({
      where: { familyId },
      orderBy: { createdAt: 'desc' },
    });
    return invites.map((i) => ({
      id: i.id,
      email: i.email,
      status: i.expiresAt < new Date() && i.status === 'pending' ? 'expired' : i.status,
      expiresAt: i.expiresAt.toISOString(),
      createdAt: i.createdAt.toISOString(),
    }));
  }

  async revokeInvite(familyId: string, inviteId: string) {
    const invite = await this.prisma.invite.findFirst({ where: { id: inviteId, familyId } });
    if (!invite) throw notFound('INVITE_NOT_FOUND', 'Pozvánka nenalezena.');
    await this.prisma.invite.update({ where: { id: inviteId }, data: { status: 'revoked' } });
  }

  /** Přijetí pozvánky — vrací id rodiny, volající poté vydá nové tokeny. */
  async acceptInvite(userId: string, code: string): Promise<string> {
    const user = await this.prisma.user.findUniqueOrThrow({ where: { id: userId } });
    if (user.familyId) {
      throw conflict('ALREADY_IN_FAMILY', 'Už jsi členem rodiny.');
    }

    const invite = await this.prisma.invite.findUnique({
      where: { tokenHash: hashToken(code.trim().toUpperCase()) },
    });

    if (!invite || invite.status !== 'pending') {
      throw notFound('INVITE_INVALID', 'Pozvánka neexistuje nebo už byla použita.');
    }
    if (invite.expiresAt < new Date()) {
      await this.prisma.invite.update({ where: { id: invite.id }, data: { status: 'expired' } });
      throw badRequest('INVITE_EXPIRED', 'Platnost pozvánky vypršela.');
    }
    if (invite.email && invite.email !== user.email) {
      throw forbidden('INVITE_EMAIL_MISMATCH', 'Tato pozvánka je určena pro jiný e-mail.');
    }

    await this.prisma.$transaction([
      this.prisma.user.update({
        where: { id: userId },
        data: { familyId: invite.familyId, role: 'member' },
      }),
      this.prisma.invite.update({ where: { id: invite.id }, data: { status: 'accepted' } }),
    ]);

    return invite.familyId;
  }
}
