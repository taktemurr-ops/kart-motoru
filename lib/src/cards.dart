import 'package:studio_core/core/rng.dart';

/// Kart: tek bir tamsayı. id = deste * 52 + renk * 13 + (değer - 1).
/// Değer 1 (As) … 13 (Papaz). Renk sırası: 0 maça, 1 kupa, 2 karo, 3 sinek.
typedef Card = int;

int rankOf(Card c) => c % 13 + 1;
int suitOf(Card c) => (c ~/ 13) % 4;
int deckOf(Card c) => c ~/ 52;
bool isRed(Card c) => suitOf(c) == 1 || suitOf(c) == 2;
Card makeCard(int rank, int suit, [int deck = 0]) => deck * 52 + suit * 13 + (rank - 1);

const kSpades = 0, kHearts = 1, kDiamonds = 2, kClubs = 3;

/// Kartın kısa adı (çizimde köşe yazısı).
String rankLabel(int rank) => switch (rank) {
      1 => 'A',
      11 => 'J',
      12 => 'Q',
      13 => 'K',
      _ => '$rank',
    };

/// Deste kurucu. [suits] ile tek renkli (Spider) desteler, [ranks] ile kısa
/// desteler (32, 36, 40, 48 kartlık) kurulur.
List<Card> buildDeck({int decks = 1, List<int> suits = const [0, 1, 2, 3], List<int>? ranks}) {
  final rs = ranks ?? [for (var r = 1; r <= 13; r++) r];
  final out = <Card>[];
  // Az renkli destelerde 52 kart tamamlanır: aynı renk birkaç kez tekrar eder.
  final perDeck = 4 ~/ suits.length;
  var d = 0;
  for (var k = 0; k < decks; k++) {
    for (var rep = 0; rep < perDeck; rep++) {
      for (final s in suits) {
        for (final r in rs) {
          out.add(makeCard(r, s, d));
        }
      }
      d++;
    }
  }
  return out;
}

void shuffleCards(List<Card> cards, SeededRandom r) {
  for (var i = cards.length - 1; i > 0; i--) {
    final j = r.nextInt(i + 1);
    final t = cards[i];
    cards[i] = cards[j];
    cards[j] = t;
  }
}
