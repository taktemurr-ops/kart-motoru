// Oyun testi (5. tur) kural denetimi: piyasadaki kurallarla karşılaştırılan
// zorunlu hamleler.
import 'package:flutter_test/flutter_test.dart';
import 'package:kart_motoru/kart_motoru.dart';

TrickState _state(TrickRules r, List<List<KCard>> hands, {int trump = -1, int contract = 0}) {
  final s = TrickState(seats: 4, hands: hands, kitty: <KCard>[], dealer: 3, trump: trump);
  s
    ..phase = TrickPhase.play
    ..contract = contract
    ..leader = 0
    ..turn = 0;
  return s;
}

void main() {
  group('Batak', () {
    const r = BatakRules();
    test('renge uy ve yükselt; renk yoksa koz, mümkünse kozu geç', () {
      final s = _state(r, [
        [makeCard(10, kSpades)],
        [makeCard(3, kSpades), makeCard(12, kSpades), makeCard(2, kHearts)],
        [makeCard(5, kDiamonds), makeCard(4, kHearts), makeCard(11, kHearts)],
        [makeCard(9, kClubs)],
      ], trump: kHearts);
      s.extra = 1; // koz açıldı
      r.play(s, 0, makeCard(10, kSpades));
      // Elinde daha büyük maça var: yalnız onu oynayabilir.
      expect(r.legalPlays(s, 1), [makeCard(12, kSpades)]);
      r.play(s, 1, makeCard(12, kSpades));
      // Maçası yok: koz atmak zorunlu (karo atamaz).
      expect(r.legalPlays(s, 2).toSet(), {makeCard(4, kHearts), makeCard(11, kHearts)});
    });

    test('koz açılmadan kozla çıkılmaz', () {
      final s = _state(r, [
        [makeCard(1, kHearts), makeCard(5, kClubs)],
        [makeCard(2, kClubs)],
        [makeCard(3, kClubs)],
        [makeCard(4, kClubs)],
      ], trump: kHearts);
      expect(r.legalPlays(s, 0), [makeCard(5, kClubs)]);
    });
  });

  group('King', () {
    const r = KingRules();
    test('kız almaz: büyük kart düştüyse elindeki kızı vermek zorunlu', () {
      final s = _state(r, [
        [makeCard(13, kSpades)],
        [makeCard(12, kSpades), makeCard(3, kSpades)],
        [makeCard(2, kClubs)],
        [makeCard(2, kDiamonds)],
      ], contract: 3);
      r.play(s, 0, makeCard(13, kSpades));
      expect(r.legalPlays(s, 1), [makeCard(12, kSpades)]);
    });

    test('rıfkı: as düştüyse kupa papazı verilir; renk yoksa ceza kartı atılır', () {
      final s = _state(r, [
        [makeCard(1, kHearts), makeCard(4, kClubs)],
        [makeCard(13, kHearts), makeCard(5, kHearts)],
        [makeCard(13, kSpades), makeCard(6, kClubs)],
        [makeCard(2, kDiamonds), makeCard(7, kClubs)],
      ], contract: 5);
      s.extra = 1;
      r.play(s, 0, makeCard(1, kHearts));
      expect(r.legalPlays(s, 1), [makeCard(13, kHearts)]);
      r.play(s, 1, makeCard(13, kHearts));
      r.play(s, 2, makeCard(13, kSpades));
      r.play(s, 3, makeCard(2, kDiamonds));
      // Rıfkı alındı: el erken biter.
      expect(s.phase, TrickPhase.over);
      expect(r.handScores(s)[0], -320);
    });
  });
}
