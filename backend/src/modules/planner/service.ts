import type { Prisma, PrismaClient, SlotType } from '@prisma/client';

import {
  addDays,
  assertWithinPlanningWindow,
  formatDateOnly,
  startOfIsoWeek,
} from '../../lib/dates.js';
import { badRequest, conflict, forbidden, notFound } from '../../lib/errors.js';

const proposalInclude = {
  proposedByUser: { select: { id: true, name: true, avatarUrl: true } },
  votes: { select: { userId: true } },
  _count: { select: { comments: true } },
} satisfies Prisma.MealProposalInclude;

type ProposalWithRelations = Prisma.MealProposalGetPayload<{ include: typeof proposalInclude }>;

function serializeProposal(proposal: ProposalWithRelations, currentUserId: string) {
  return {
    id: proposal.id,
    mealSlotId: proposal.mealSlotId,
    title: proposal.title,
    description: proposal.description,
    photoUrl: proposal.photoUrl,
    status: proposal.status,
    createdAt: proposal.createdAt.toISOString(),
    proposedBy: proposal.proposedByUser,
    voteCount: proposal.votes.length,
    votedByMe: proposal.votes.some((v) => v.userId === currentUserId),
    commentCount: proposal._count.comments,
  };
}

export class PlannerService {
  constructor(private readonly prisma: PrismaClient) {}

  // --- Šablona ----------------------------------------------------------

  async getTemplate(familyId: string) {
    const template = await this.prisma.mealTemplate.findUnique({
      where: { familyId },
      include: { slots: { orderBy: { sortOrder: 'asc' } } },
    });
    if (!template) throw notFound('TEMPLATE_NOT_FOUND', 'Šablona rodiny nenalezena.');

    return {
      id: template.id,
      slots: template.slots.map((s) => ({
        id: s.id,
        slotType: s.slotType,
        enabled: s.enabled,
        customLabel: s.customLabel,
        sortOrder: s.sortOrder,
      })),
    };
  }

  /** Přepíše sloty šablony. Už existující MealSloty v kalendáři zůstávají. */
  async replaceTemplateSlots(
    familyId: string,
    slots: Array<{ slotType: SlotType; enabled: boolean; customLabel?: string | null }>,
  ) {
    const template = await this.prisma.mealTemplate.findUnique({ where: { familyId } });
    if (!template) throw notFound('TEMPLATE_NOT_FOUND', 'Šablona rodiny nenalezena.');

    const seen = new Set<string>();
    for (const slot of slots) {
      const key = `${slot.slotType}::${slot.customLabel ?? ''}`;
      if (seen.has(key)) {
        throw badRequest('DUPLICATE_SLOT', `Slot "${key}" je v šabloně uvedený vícekrát.`);
      }
      seen.add(key);
      if (slot.slotType === 'custom' && !slot.customLabel?.trim()) {
        throw badRequest('CUSTOM_LABEL_REQUIRED', 'Vlastní slot musí mít název.');
      }
    }

    await this.prisma.$transaction([
      this.prisma.mealTemplateSlotItem.deleteMany({ where: { templateId: template.id } }),
      this.prisma.mealTemplateSlotItem.createMany({
        data: slots.map((slot, index) => ({
          templateId: template.id,
          slotType: slot.slotType,
          enabled: slot.enabled,
          customLabel: slot.customLabel?.trim() || null,
          sortOrder: index,
        })),
      }),
    ]);

    return this.getTemplate(familyId);
  }

  // --- Kalendář ---------------------------------------------------------

  /**
   * Vytvoří ze šablony chybějící MealSloty pro daný den.
   * Vypnuté sloty se negenerují; už existující se díky skipDuplicates nepřepisují.
   */
  private async materializeDay(familyId: string, date: Date): Promise<void> {
    const template = await this.prisma.mealTemplate.findUnique({
      where: { familyId },
      include: { slots: { where: { enabled: true }, orderBy: { sortOrder: 'asc' } } },
    });
    if (!template || template.slots.length === 0) return;

    await this.prisma.mealSlot.createMany({
      data: template.slots.map((s) => ({
        familyId,
        date,
        slotType: s.slotType,
        customLabel: s.customLabel,
        sortOrder: s.sortOrder,
        isCustomSlot: false,
      })),
      skipDuplicates: true,
    });
  }

  async getDay(familyId: string, userId: string, date: Date) {
    assertWithinPlanningWindow(date);
    await this.materializeDay(familyId, date);

    const slots = await this.prisma.mealSlot.findMany({
      where: { familyId, date },
      orderBy: [{ sortOrder: 'asc' }, { createdAt: 'asc' }],
      include: { proposals: { include: proposalInclude, orderBy: { createdAt: 'asc' } } },
    });

    return {
      date: formatDateOnly(date),
      slots: slots.map((slot) => ({
        id: slot.id,
        slotType: slot.slotType,
        customLabel: slot.customLabel,
        isCustomSlot: slot.isCustomSlot,
        sortOrder: slot.sortOrder,
        proposals: slot.proposals.map((p) => serializeProposal(p, userId)),
      })),
    };
  }

  /** Týdenní přehled — jen počty pro indikátory na domovské obrazovce. */
  async getWeek(familyId: string, weekStart: Date) {
    const start = startOfIsoWeek(weekStart);
    const end = addDays(start, 6);
    assertWithinPlanningWindow(end);

    for (let i = 0; i < 7; i++) {
      await this.materializeDay(familyId, addDays(start, i));
    }

    const slots = await this.prisma.mealSlot.findMany({
      where: { familyId, date: { gte: start, lte: end } },
      include: { proposals: { select: { status: true } } },
    });

    const byDate = new Map<
      string,
      { slotCount: number; proposedCount: number; confirmedCount: number }
    >();
    for (let i = 0; i < 7; i++) {
      byDate.set(formatDateOnly(addDays(start, i)), {
        slotCount: 0,
        proposedCount: 0,
        confirmedCount: 0,
      });
    }

    for (const slot of slots) {
      const key = formatDateOnly(slot.date);
      const entry = byDate.get(key);
      if (!entry) continue;
      entry.slotCount += 1;
      if (slot.proposals.some((p) => p.status === 'confirmed' || p.status === 'locked')) {
        entry.confirmedCount += 1;
      } else if (slot.proposals.length > 0) {
        entry.proposedCount += 1;
      }
    }

    return {
      weekStart: formatDateOnly(start),
      weekEnd: formatDateOnly(end),
      days: [...byDate.entries()].map(([date, counts]) => ({ date, ...counts })),
    };
  }

  /** Mimořádný slot mimo šablonu (např. oslava). */
  async createCustomSlot(
    familyId: string,
    date: Date,
    input: { slotType: SlotType; customLabel: string },
  ) {
    assertWithinPlanningWindow(date);

    const label = input.customLabel.trim();
    if (!label) throw badRequest('CUSTOM_LABEL_REQUIRED', 'Mimořádný slot musí mít název.');

    const existing = await this.prisma.mealSlot.findFirst({
      where: { familyId, date, slotType: input.slotType, customLabel: label },
    });
    if (existing) throw conflict('SLOT_EXISTS', 'Takový slot už v tomto dni existuje.');

    const maxOrder = await this.prisma.mealSlot.aggregate({
      where: { familyId, date },
      _max: { sortOrder: true },
    });

    const slot = await this.prisma.mealSlot.create({
      data: {
        familyId,
        date,
        slotType: input.slotType,
        customLabel: label,
        isCustomSlot: true,
        sortOrder: (maxOrder._max.sortOrder ?? 0) + 1,
      },
    });

    return {
      id: slot.id,
      slotType: slot.slotType,
      customLabel: slot.customLabel,
      isCustomSlot: slot.isCustomSlot,
      sortOrder: slot.sortOrder,
      proposals: [],
    };
  }

  async deleteSlot(familyId: string, slotId: string) {
    const slot = await this.prisma.mealSlot.findFirst({
      where: { id: slotId, familyId },
      include: { proposals: { select: { status: true } } },
    });
    if (!slot) throw notFound('SLOT_NOT_FOUND', 'Slot nenalezen.');
    if (!slot.isCustomSlot) {
      throw badRequest(
        'NOT_CUSTOM_SLOT',
        'Smazat lze jen mimořádný slot. Slot ze šablony vypni v nastavení šablony.',
      );
    }
    if (slot.proposals.some((p) => p.status !== 'proposed')) {
      throw conflict('SLOT_LOCKED', 'Slot obsahuje potvrzené jídlo — nejdřív ho odemkni.');
    }

    await this.prisma.mealSlot.delete({ where: { id: slotId } });
  }

  // --- Návrhy jídel -----------------------------------------------------

  private async loadSlotOfFamily(familyId: string, slotId: string) {
    const slot = await this.prisma.mealSlot.findFirst({ where: { id: slotId, familyId } });
    if (!slot) throw notFound('SLOT_NOT_FOUND', 'Slot nenalezen.');
    return slot;
  }

  private async loadProposalOfFamily(familyId: string, proposalId: string) {
    const proposal = await this.prisma.mealProposal.findFirst({
      where: { id: proposalId, mealSlot: { familyId } },
      include: proposalInclude,
    });
    if (!proposal) throw notFound('PROPOSAL_NOT_FOUND', 'Návrh jídla nenalezen.');
    return proposal;
  }

  async createProposal(
    familyId: string,
    userId: string,
    slotId: string,
    input: { title: string; description?: string; photoUrl?: string },
  ) {
    const slot = await this.loadSlotOfFamily(familyId, slotId);
    assertWithinPlanningWindow(slot.date);

    const locked = await this.prisma.mealProposal.findFirst({
      where: { mealSlotId: slotId, status: { in: ['confirmed', 'locked'] } },
    });
    if (locked) {
      throw conflict(
        'SLOT_LOCKED',
        'V tomto slotu je už potvrzené jídlo. Nejdřív ho odemkni k úpravě.',
      );
    }

    const proposal = await this.prisma.mealProposal.create({
      data: {
        mealSlotId: slotId,
        proposedByUserId: userId,
        title: input.title.trim(),
        description: input.description?.trim() || null,
        photoUrl: input.photoUrl?.trim() || null,
      },
      include: proposalInclude,
    });

    return serializeProposal(proposal, userId);
  }

  async getProposal(familyId: string, userId: string, proposalId: string) {
    const proposal = await this.loadProposalOfFamily(familyId, proposalId);
    return serializeProposal(proposal, userId);
  }

  async updateProposal(
    familyId: string,
    userId: string,
    proposalId: string,
    input: { title?: string; description?: string | null; photoUrl?: string | null },
  ) {
    const proposal = await this.loadProposalOfFamily(familyId, proposalId);

    // Pravidlo ze zadání: potvrzený/uzamčený návrh nelze editovat bez odemknutí.
    if (proposal.status !== 'proposed') {
      throw conflict(
        'PROPOSAL_LOCKED',
        'Potvrzený návrh nelze upravit. Nejdřív ho odemkni k úpravě.',
      );
    }
    if (proposal.proposedByUserId !== userId) {
      throw forbidden('NOT_PROPOSAL_AUTHOR', 'Upravit návrh může jen ten, kdo ho vytvořil.');
    }

    const updated = await this.prisma.mealProposal.update({
      where: { id: proposalId },
      data: {
        ...(input.title !== undefined ? { title: input.title.trim() } : {}),
        ...(input.description !== undefined ? { description: input.description?.trim() || null } : {}),
        ...(input.photoUrl !== undefined ? { photoUrl: input.photoUrl?.trim() || null } : {}),
      },
      include: proposalInclude,
    });

    return serializeProposal(updated, userId);
  }

  async deleteProposal(familyId: string, userId: string, proposalId: string) {
    const proposal = await this.loadProposalOfFamily(familyId, proposalId);
    if (proposal.status !== 'proposed') {
      throw conflict('PROPOSAL_LOCKED', 'Potvrzený návrh nelze smazat. Nejdřív ho odemkni.');
    }
    if (proposal.proposedByUserId !== userId) {
      throw forbidden('NOT_PROPOSAL_AUTHOR', 'Smazat návrh může jen ten, kdo ho vytvořil.');
    }
    await this.prisma.mealProposal.delete({ where: { id: proposalId } });
  }

  /** Potvrzení návrhu — dle zadání smí kdokoli z rodiny. Uzamkne slot. */
  async confirmProposal(familyId: string, userId: string, proposalId: string) {
    const proposal = await this.loadProposalOfFamily(familyId, proposalId);
    if (proposal.status !== 'proposed') {
      throw conflict('ALREADY_CONFIRMED', 'Tento návrh je už potvrzený.');
    }

    const other = await this.prisma.mealProposal.findFirst({
      where: {
        mealSlotId: proposal.mealSlotId,
        id: { not: proposalId },
        status: { in: ['confirmed', 'locked'] },
      },
    });
    if (other) {
      throw conflict(
        'SLOT_LOCKED',
        'V tomto slotu je už potvrzené jiné jídlo. Nejdřív ho odemkni.',
      );
    }

    const updated = await this.prisma.mealProposal.update({
      where: { id: proposalId },
      data: { status: 'confirmed' },
      include: proposalInclude,
    });

    return serializeProposal(updated, userId);
  }

  async unlockProposal(familyId: string, userId: string, proposalId: string) {
    const proposal = await this.loadProposalOfFamily(familyId, proposalId);
    if (proposal.status === 'proposed') {
      throw conflict('NOT_CONFIRMED', 'Tento návrh není potvrzený, není co odemykat.');
    }

    const updated = await this.prisma.mealProposal.update({
      where: { id: proposalId },
      data: { status: 'proposed' },
      include: proposalInclude,
    });

    return serializeProposal(updated, userId);
  }

  // --- Hlasy ------------------------------------------------------------

  async vote(familyId: string, userId: string, proposalId: string) {
    await this.loadProposalOfFamily(familyId, proposalId);
    await this.prisma.vote.upsert({
      where: { proposalId_userId: { proposalId, userId } },
      create: { proposalId, userId },
      update: {},
    });
    return this.getProposal(familyId, userId, proposalId);
  }

  async unvote(familyId: string, userId: string, proposalId: string) {
    await this.loadProposalOfFamily(familyId, proposalId);
    await this.prisma.vote.deleteMany({ where: { proposalId, userId } });
    return this.getProposal(familyId, userId, proposalId);
  }

  // --- Komentáře --------------------------------------------------------

  async listComments(familyId: string, proposalId: string) {
    await this.loadProposalOfFamily(familyId, proposalId);
    const comments = await this.prisma.comment.findMany({
      where: { proposalId },
      orderBy: { createdAt: 'asc' },
      include: { user: { select: { id: true, name: true, avatarUrl: true } } },
    });
    return comments.map((c) => ({
      id: c.id,
      text: c.text,
      createdAt: c.createdAt.toISOString(),
      author: c.user,
    }));
  }

  async addComment(familyId: string, userId: string, proposalId: string, text: string) {
    await this.loadProposalOfFamily(familyId, proposalId);
    const comment = await this.prisma.comment.create({
      data: { proposalId, userId, text: text.trim() },
      include: { user: { select: { id: true, name: true, avatarUrl: true } } },
    });
    return {
      id: comment.id,
      text: comment.text,
      createdAt: comment.createdAt.toISOString(),
      author: comment.user,
    };
  }

  async deleteComment(familyId: string, userId: string, commentId: string) {
    const comment = await this.prisma.comment.findFirst({
      where: { id: commentId, proposal: { mealSlot: { familyId } } },
    });
    if (!comment) throw notFound('COMMENT_NOT_FOUND', 'Komentář nenalezen.');
    if (comment.userId !== userId) {
      throw forbidden('NOT_COMMENT_AUTHOR', 'Smazat komentář může jen jeho autor.');
    }
    await this.prisma.comment.delete({ where: { id: commentId } });
  }
}
