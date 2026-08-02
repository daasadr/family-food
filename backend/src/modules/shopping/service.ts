import type { PrismaClient, SlotType } from '@prisma/client';

import { formatDateOnly, todayUtc } from '../../lib/dates.js';
import { badRequest, conflict, notFound } from '../../lib/errors.js';
import type { ShoppingListGenerator } from './ai.js';
import type { PlannedMeal } from './prompt.js';

/** Stejné popisky slotů jako v aplikaci — model tím lépe chápe kontext jídla. */
const SLOT_LABELS: Record<SlotType, string> = {
  breakfast: 'snídaně',
  lunch: 'oběd',
  dinner: 'večeře',
  snack1: 'dopolední svačina',
  snack2: 'odpolední svačina',
  custom: 'mimořádné jídlo',
};

const MAX_RANGE_DAYS = 31;

export class ShoppingService {
  constructor(
    private readonly prisma: PrismaClient,
    private readonly generator: ShoppingListGenerator | null,
  ) {}

  private async loadListOfFamily(familyId: string, listId: string) {
    const list = await this.prisma.shoppingList.findFirst({
      where: { id: listId, familyId },
    });
    if (!list) throw notFound('SHOPPING_LIST_NOT_FOUND', 'Nákupní seznam nenalezen.');
    return list;
  }

  private serializeList(list: {
    id: string;
    rangeStart: Date;
    rangeEnd: Date;
    generatedAt: Date;
    generatedByAI: boolean;
    items?: Array<{
      id: string;
      name: string;
      category: string | null;
      quantity: string | null;
      buyByDate: Date | null;
      note: string | null;
      isChecked: boolean;
    }>;
  }) {
    return {
      id: list.id,
      rangeStart: formatDateOnly(list.rangeStart),
      rangeEnd: formatDateOnly(list.rangeEnd),
      generatedAt: list.generatedAt.toISOString(),
      generatedByAI: list.generatedByAI,
      items: (list.items ?? []).map((item) => ({
        id: item.id,
        name: item.name,
        category: item.category,
        quantity: item.quantity,
        buyByDate: item.buyByDate ? formatDateOnly(item.buyByDate) : null,
        note: item.note,
        isChecked: item.isChecked,
      })),
    };
  }

  /**
   * Posbírá naplánovaná jídla v rozmezí a nechá AI sestavit nákupní seznam
   * (zadání 4.6). Výchozí je jen potvrzená jídla — návrhy se ještě mohou změnit.
   */
  async generate(
    familyId: string,
    input: { rangeStart: Date; rangeEnd: Date; includeProposed: boolean },
  ) {
    if (!this.generator) {
      throw conflict(
        'AI_NOT_CONFIGURED',
        'Generování nákupního seznamu není nastavené — chybí klíč k AI službě.',
      );
    }

    if (input.rangeEnd < input.rangeStart) {
      throw badRequest('INVALID_RANGE', 'Konec rozmezí je dřív než jeho začátek.');
    }

    const days = Math.round(
      (input.rangeEnd.getTime() - input.rangeStart.getTime()) / 86_400_000,
    );
    if (days > MAX_RANGE_DAYS) {
      throw badRequest(
        'RANGE_TOO_LONG',
        `Nákupní seznam lze vygenerovat nejvýše na ${MAX_RANGE_DAYS} dní.`,
      );
    }

    const family = await this.prisma.family.findUniqueOrThrow({ where: { id: familyId } });

    const slots = await this.prisma.mealSlot.findMany({
      where: { familyId, date: { gte: input.rangeStart, lte: input.rangeEnd } },
      orderBy: [{ date: 'asc' }, { sortOrder: 'asc' }],
      include: {
        proposals: {
          where: input.includeProposed
            ? {}
            : { status: { in: ['confirmed', 'locked'] } },
          orderBy: { createdAt: 'asc' },
        },
      },
    });

    const meals: PlannedMeal[] = [];
    for (const slot of slots) {
      // U slotu s potvrzeným jídlem bereme jen to potvrzené — ostatní návrhy
      // už neplatí, i když se generuje "včetně návrhů".
      const confirmed = slot.proposals.find(
        (p) => p.status === 'confirmed' || p.status === 'locked',
      );
      const relevant = confirmed ? [confirmed] : slot.proposals;

      for (const proposal of relevant) {
        meals.push({
          date: formatDateOnly(slot.date),
          slotLabel: slot.customLabel || SLOT_LABELS[slot.slotType],
          title: proposal.title,
          description: proposal.description,
          status: proposal.status,
        });
      }
    }

    if (meals.length === 0) {
      throw badRequest(
        'NO_MEALS_PLANNED',
        input.includeProposed
          ? 'V tomto rozmezí nejsou naplánovaná žádná jídla.'
          : 'V tomto rozmezí není žádné potvrzené jídlo. Zkus zahrnout i návrhy.',
      );
    }

    const generated = await this.generator.generate({
      rangeStart: formatDateOnly(input.rangeStart),
      rangeEnd: formatDateOnly(input.rangeEnd),
      shoppingDays: family.shoppingDays,
      today: formatDateOnly(todayUtc()),
      meals,
    });

    const list = await this.prisma.shoppingList.create({
      data: {
        familyId,
        rangeStart: input.rangeStart,
        rangeEnd: input.rangeEnd,
        generatedByAI: true,
        items: {
          createMany: {
            data: generated.map((item) => ({
              name: item.name,
              category: item.category,
              quantity: item.quantity,
              buyByDate: item.buyByDate,
              note: item.note,
            })),
          },
        },
      },
      include: { items: { orderBy: [{ buyByDate: 'asc' }, { name: 'asc' }] } },
    });

    return this.serializeList(list);
  }

  async listLists(familyId: string) {
    const lists = await this.prisma.shoppingList.findMany({
      where: { familyId },
      orderBy: { generatedAt: 'desc' },
      take: 50,
      include: { items: { select: { isChecked: true } } },
    });

    return lists.map((list) => ({
      id: list.id,
      rangeStart: formatDateOnly(list.rangeStart),
      rangeEnd: formatDateOnly(list.rangeEnd),
      generatedAt: list.generatedAt.toISOString(),
      generatedByAI: list.generatedByAI,
      itemCount: list.items.length,
      checkedCount: list.items.filter((i) => i.isChecked).length,
    }));
  }

  async getList(familyId: string, listId: string) {
    await this.loadListOfFamily(familyId, listId);
    const list = await this.prisma.shoppingList.findUniqueOrThrow({
      where: { id: listId },
      include: { items: { orderBy: [{ buyByDate: 'asc' }, { name: 'asc' }] } },
    });
    return this.serializeList(list);
  }

  async deleteList(familyId: string, listId: string) {
    await this.loadListOfFamily(familyId, listId);
    await this.prisma.shoppingList.delete({ where: { id: listId } });
  }

  async addItem(
    familyId: string,
    listId: string,
    input: { name: string; category?: string; quantity?: string; buyByDate?: Date; note?: string },
  ) {
    await this.loadListOfFamily(familyId, listId);

    const item = await this.prisma.shoppingListItem.create({
      data: {
        shoppingListId: listId,
        name: input.name.trim(),
        category: input.category?.trim() || null,
        quantity: input.quantity?.trim() || null,
        buyByDate: input.buyByDate ?? null,
        note: input.note?.trim() || null,
      },
    });

    return {
      id: item.id,
      name: item.name,
      category: item.category,
      quantity: item.quantity,
      buyByDate: item.buyByDate ? formatDateOnly(item.buyByDate) : null,
      note: item.note,
      isChecked: item.isChecked,
    };
  }

  async updateItem(
    familyId: string,
    itemId: string,
    input: {
      name?: string;
      category?: string | null;
      quantity?: string | null;
      buyByDate?: Date | null;
      note?: string | null;
      isChecked?: boolean;
    },
  ) {
    const item = await this.prisma.shoppingListItem.findFirst({
      where: { id: itemId, shoppingList: { familyId } },
    });
    if (!item) throw notFound('SHOPPING_ITEM_NOT_FOUND', 'Položka nákupního seznamu nenalezena.');

    const updated = await this.prisma.shoppingListItem.update({
      where: { id: itemId },
      data: {
        ...(input.name !== undefined ? { name: input.name.trim() } : {}),
        ...(input.category !== undefined ? { category: input.category?.trim() || null } : {}),
        ...(input.quantity !== undefined ? { quantity: input.quantity?.trim() || null } : {}),
        ...(input.buyByDate !== undefined ? { buyByDate: input.buyByDate } : {}),
        ...(input.note !== undefined ? { note: input.note?.trim() || null } : {}),
        ...(input.isChecked !== undefined ? { isChecked: input.isChecked } : {}),
      },
    });

    return {
      id: updated.id,
      name: updated.name,
      category: updated.category,
      quantity: updated.quantity,
      buyByDate: updated.buyByDate ? formatDateOnly(updated.buyByDate) : null,
      note: updated.note,
      isChecked: updated.isChecked,
    };
  }

  async deleteItem(familyId: string, itemId: string) {
    const item = await this.prisma.shoppingListItem.findFirst({
      where: { id: itemId, shoppingList: { familyId } },
    });
    if (!item) throw notFound('SHOPPING_ITEM_NOT_FOUND', 'Položka nákupního seznamu nenalezena.');
    await this.prisma.shoppingListItem.delete({ where: { id: itemId } });
  }
}
