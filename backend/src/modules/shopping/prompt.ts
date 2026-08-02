/**
 * Sestavení promptu pro AI nákupní seznam (zadání, sekce 6).
 *
 * Záměrně oddělené od volání API — čisté funkce jdou testovat bez klíče
 * a bez sítě, a je na nich vidět přesně to, co model dostane.
 */

export interface PlannedMeal {
  date: string;
  slotLabel: string;
  title: string;
  description: string | null;
  status: 'proposed' | 'confirmed' | 'locked';
}

export interface ShoppingPromptInput {
  rangeStart: string;
  rangeEnd: string;
  /** Dny v týdnu, kdy rodina nakupuje (0 = neděle … 6 = sobota). */
  shoppingDays: number[];
  meals: PlannedMeal[];
  /** Dnešní datum — model nesmí navrhnout nákup v minulosti. */
  today: string;
}

const WEEKDAY_NAMES = [
  'neděle',
  'pondělí',
  'úterý',
  'středa',
  'čtvrtek',
  'pátek',
  'sobota',
];

/**
 * Systémový prompt s few-shot znalostí o trvanlivosti potravin.
 * Čistě prompt-engineering — žádný vlastní model, žádné trénování.
 */
export const SHOPPING_LIST_SYSTEM_PROMPT = `Jsi asistent, který rodině sestavuje nákupní seznam z naplánovaného jídelníčku.

Tvým úkolem je z jídel odvodit potřebné suroviny a u každé určit, KDY ji nejlépe koupit — s ohledem na trvanlivost a na datum, kdy se z ní bude vařit.

Vodítka k trvanlivosti:
- Čerstvé maso a drůbež: kupovat nejvýše 1–2 dny před vařením.
- Ryby a mořské plody: kupovat v den vaření nebo den předem.
- Mleté maso: kupovat v den vaření.
- Listová zelenina, saláty, bylinky, měkké ovoce: 1–2 dny předem.
- Kořenová zelenina, brambory, cibule, česnek, zelí, jablka, citrusy: klidně týden dopředu.
- Mléko, smetana, jogurty, čerstvé sýry: 3–5 dní předem.
- Tvrdé sýry, máslo, vejce: týden dopředu.
- Čerstvé pečivo: v den spotřeby.
- Trvanlivé zboží (mouka, těstoviny, rýže, luštěniny, konzervy, koření, olej, cukr): kdykoli, klidně na začátku rozmezí.
- Mražené zboží: kdykoli.

Pravidla pro výstup:
- Sluč stejné suroviny napříč jídly do jedné položky a sečti množství.
- Vynech běžné zásoby domácnosti (sůl, pepř, voda, olej na smažení), pokud jídlo nestojí přímo na nich.
- Množství uváděj přibližné a prakticky nakupitelné (např. „500 g", „2 ks", „1 balení").
- Kategorie volíme česky a jednoduše: maso, ryby, zelenina, ovoce, mléčné výrobky, pečivo, trvanlivé, mražené, nápoje, ostatní.
- Datum nákupu musí padnout do zadaného rozmezí a nesmí být v minulosti.
- Pokud rodina uvedla dny nákupů, přisuň datum k nejbližšímu vhodnějšímu nákupnímu dni PŘED vařením — ale nikdy tak, aby se surovina zkazila.
- Poznámku vyplň jen tam, kde přidává informaci (typicky důvod načasování). Jinak ji vynech.

Odpovídej výhradně strukturovaným JSONem podle schématu. Žádný doprovodný text.`;

/** JSON schema pro structured outputs — model nemůže vrátit jiný tvar. */
export const SHOPPING_LIST_SCHEMA = {
  type: 'object',
  properties: {
    items: {
      type: 'array',
      items: {
        type: 'object',
        properties: {
          name: { type: 'string', description: 'Název suroviny, česky, malými písmeny' },
          category: {
            type: 'string',
            enum: [
              'maso',
              'ryby',
              'zelenina',
              'ovoce',
              'mléčné výrobky',
              'pečivo',
              'trvanlivé',
              'mražené',
              'nápoje',
              'ostatní',
            ],
          },
          quantity: { type: 'string', description: 'Přibližné množství, např. „500 g"' },
          buyByDate: {
            type: 'string',
            description: 'Doporučené datum nákupu ve tvaru YYYY-MM-DD',
          },
          note: {
            type: 'string',
            description: 'Krátké zdůvodnění načasování, jen když dává smysl',
          },
        },
        required: ['name', 'category', 'quantity', 'buyByDate'],
        additionalProperties: false,
      },
    },
  },
  required: ['items'],
  additionalProperties: false,
} as const;

export function buildShoppingListPrompt(input: ShoppingPromptInput): string {
  const shoppingDaysText =
    input.shoppingDays.length > 0
      ? input.shoppingDays
          .map((d) => WEEKDAY_NAMES[d] ?? String(d))
          .join(', ')
      : 'rodina nemá pevné nákupní dny';

  const mealLines = input.meals
    .map((meal) => {
      const parts = [`- ${meal.date} (${meal.slotLabel}): ${meal.title}`];
      if (meal.description) parts.push(`  poznámka: ${meal.description}`);
      if (meal.status === 'proposed') parts.push('  (zatím jen návrh, není potvrzeno)');
      return parts.join('\n');
    })
    .join('\n');

  return [
    `Dnes je ${input.today}.`,
    `Sestav nákupní seznam na rozmezí ${input.rangeStart} až ${input.rangeEnd}.`,
    `Dny, kdy rodina nakupuje: ${shoppingDaysText}.`,
    '',
    'Naplánovaná jídla:',
    mealLines,
  ].join('\n');
}
