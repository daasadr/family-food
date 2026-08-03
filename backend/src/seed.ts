import { PrismaClient } from '@prisma/client';

const prisma = new PrismaClient();

/**
 * Globální předvytvořená galerie běžných jídel (familyId = null).
 * Bez značek výrobců — jen obecné názvy, jak požaduje zadání (sekce 5).
 *
 * Žije v src/, ne v prisma/, aby se zkompiloval do dist/ a šel spustit
 * v produkčním kontejneru, kde není tsx.
 *
 * POZOR: fotky jsou zatím zástupné (placehold.co). Před vydáním je nahraď
 * vlastními nebo licencovanými obrázky uloženými na R2/MinIO.
 */
const GLOBAL_MEALS: Array<{ title: string; category: string }> = [
  { title: 'Ovesná kaše s ovocem', category: 'snídaně' },
  { title: 'Míchaná vajíčka s pečivem', category: 'snídaně' },
  { title: 'Jogurt s müsli', category: 'snídaně' },
  { title: 'Palačinky', category: 'snídaně' },
  { title: 'Chleba s pomazánkou', category: 'snídaně' },

  { title: 'Svíčková na smetaně', category: 'oběd' },
  { title: 'Kuřecí řízek s bramborem', category: 'oběd' },
  { title: 'Rajská omáčka s knedlíkem', category: 'oběd' },
  { title: 'Guláš s knedlíkem', category: 'oběd' },
  { title: 'Špagety s rajčatovou omáčkou', category: 'oběd' },
  { title: 'Čočka na kyselo s vejcem', category: 'oběd' },
  { title: 'Pečené kuře se zeleninou', category: 'oběd' },
  { title: 'Losos s bramborovou kaší', category: 'oběd' },
  { title: 'Zeleninové rizoto', category: 'oběd' },
  { title: 'Bramborák', category: 'oběd' },
  { title: 'Kuskus se zeleninou', category: 'oběd' },
  { title: 'Dušená mrkev s bramborem', category: 'oběd' },

  { title: 'Bramborová polévka', category: 'polévka' },
  { title: 'Kuřecí vývar s nudlemi', category: 'polévka' },
  { title: 'Čočková polévka', category: 'polévka' },
  { title: 'Dýňová polévka', category: 'polévka' },

  { title: 'Zeleninový salát se sýrem', category: 'večeře' },
  { title: 'Toasty se šunkou a sýrem', category: 'večeře' },
  { title: 'Omeleta se zeleninou', category: 'večeře' },
  { title: 'Pizza', category: 'večeře' },
  { title: 'Sýrová bageta', category: 'večeře' },
  { title: 'Rybí prsty s bramborem', category: 'večeře' },

  { title: 'Ovoce', category: 'svačina' },
  { title: 'Tvarohový dezert', category: 'svačina' },
  { title: 'Ořechy a sušené ovoce', category: 'svačina' },
  { title: 'Zeleninové tyčinky s dipem', category: 'svačina' },
  { title: 'Domácí buchta', category: 'svačina' },
];

function placeholderPhoto(title: string): string {
  return `https://placehold.co/600x400/e8f0e3/2f4f2f?text=${encodeURIComponent(title)}`;
}

async function main() {
  let created = 0;

  for (const meal of GLOBAL_MEALS) {
    const existing = await prisma.mealGalleryItem.findFirst({
      where: { familyId: null, title: meal.title },
    });
    if (existing) continue;

    await prisma.mealGalleryItem.create({
      data: {
        familyId: null,
        title: meal.title,
        category: meal.category,
        photoUrl: placeholderPhoto(meal.title),
      },
    });
    created += 1;
  }

  console.log(
    `Seed hotov: ${created} nových položek globální galerie (celkem definováno ${GLOBAL_MEALS.length}).`,
  );
}

main()
  .catch((err) => {
    console.error(err);
    process.exit(1);
  })
  .finally(() => prisma.$disconnect());
