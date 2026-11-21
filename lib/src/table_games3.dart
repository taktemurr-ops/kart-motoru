import 'package:studio_core/core/rng.dart';
import 'package:studio_core/core/strings.dart';

import 'cards.dart';
import 'table_engine.dart';
import 'table_games2.dart' show rankName;

// ======================================================================
// Cribbage

int cribValue(KCard c) => rankOf(c) > 10 ? 10 : rankOf(c);

/// Bir elin (+ açılan kart) puanı: 15'ler, çiftler, seriler, renk, "nobs".
int cribHandScore(List<KCard> hand, KCard starter, {bool crib = false}) {
  final all = [...hand, starter];
  var pts = 0;
  // 15'ler
  final n = all.length;
  for (var mask = 1; mask < (1 << n); mask++) {
    var sum = 0;
    for (var i = 0; i < n; i++) {
      if ((mask >> i) & 1 == 1) sum += cribValue(all[i]);
    }
    if (sum == 15) pts += 2;
  }
  // Çiftler
  for (var i = 0; i < n; i++) {
    for (var j = i + 1; j < n; j++) {
      if (rankOf(all[i]) == rankOf(all[j])) pts += 2;
    }
  }
  // Seriler (en uzun, çarpanlarıyla)
  final counts = List.filled(15, 0);
  for (final c in all) {
    counts[rankOf(c)]++;
  }
  var r = 1;
  var runPts = 0;
  while (r <= 13) {
    if (counts[r] == 0) {
      r++;
      continue;
    }
    var len = 0, mult = 1;
    while (r + len <= 13 && counts[r + len] > 0) {
      mult *= counts[r + len];
      len++;
    }
    if (len >= 3) runPts += len * mult;
    r += len;
  }
  pts += runPts;
  // Renk
  final su = suitOf(hand.first);
  if (hand.every((c) => suitOf(c) == su)) {
    if (suitOf(starter) == su) {
      pts += 5;
    } else if (!crib) {
      pts += 4;
    }
  }
  // Nobs
  if (hand.any((c) => rankOf(c) == 11 && suitOf(c) == suitOf(starter))) pts += 1;
  return pts;
}

/// Cribbage: iki kişi, altışar kart. Her oyuncu iki kartı dağıtanın "krib"ine
/// verir. Sonra sırayla kart açılır; toplam 31'i geçemez: 15 ve 31 2 puan,
/// çiftler ve seriler puan getirir. En sonda eller (ve dağıtanın krib'i)
/// açılan kartla birlikte sayılır. Çok puan toplayan kazanır.
class CribbageRules extends TableRules {
  const CribbageRules();

  // piles: 0 deste, 1 krib (kapalı), 2 açılan kart, 3 sayı dizisi, 4 oynananlar, 5/6 gösterilecek eller
  // vars: 0 aşama (0 krib, 1 sayma, 2 bitti), 1 toplam, 2 son kart atan, 3 dağıtan, 4 "go" sayısı
  static const _cribLabel = [
    'Krib', 'Crib', 'Crib', 'Cuna', 'Crib', 'المهد', 'کریب', 'קריב', 'کریب', 'Криб', 'Криб', 'Krib', 'Krib', 'Crib', 'Krib', 'Κριμπ',
    'Culla', 'Crib', 'Crib', 'Krubba', 'Krybbe', 'Krybbe', 'Krippa', 'クリブ', '크립', '奖牌堆', 'क्रिब', 'ক্রিব', 'Crib', 'Crib', 'คริบ', 'Crib', 'Crib',
  ];
  static const _starterLabel = [
    'Açılan', 'Starter', 'Startkarte', 'Carta de corte', 'Carte de départ', 'بطاقة البداية', 'کارت شروع', 'קלף פתיחה', 'آغاز کارڈ', 'Стартовая',
    'Стартова', 'Karta startowa', 'Startovní', 'Carte de start', 'Kezdőlap', 'Αρχικό', 'Carta di partenza', 'Carta inicial', 'Startkaart',
    'Startkort', 'Startkort', 'Startkort', 'Aloituskortti', 'スターター', '스타터', '起始牌', 'आरंभ पत्ता', 'শুরুর তাস', 'Kartu awal', 'Kad permulaan',
    'ไพ่เริ่ม', 'Lá mở', 'Panimulang baraha',
  ];
  static const _countLabel = [
    'Sayı', 'Count', 'Zählung', 'Cuenta', 'Compte', 'العد', 'شمارش', 'ספירה', 'گنتی', 'Счёт', 'Рахунок', 'Licznik', 'Počet', 'Numărătoare',
    'Számolás', 'Μέτρημα', 'Conteggio', 'Contagem', 'Telling', 'Räkning', 'Optælling', 'Telling', 'Laskenta', 'カウント', '카운트', '计数',
    'गिनती', 'গণনা', 'Hitungan', 'Kiraan', 'นับ', 'Đếm', 'Bilang',
  ];

  @override
  List<PileView> get pileViews => const [
        PileView('Deste', 'Stock', faceUp: false),
        PileView('Krib', 'Crib', faceUp: false, labels: _cribLabel),
        PileView('Açılan', 'Starter', labels: _starterLabel),
        PileView('Sayı', 'Count', spread: true, labels: _countLabel),
      ];

  @override
  Set<int> get hiddenPiles => const {0, 1};

  @override
  TableState deal(List<KCard> shuffled, int dealer) {
    final deck = List.of(shuffled);
    final hands = [<KCard>[], <KCard>[]];
    for (var r = 0; r < 6; r++) {
      hands[0].add(deck.removeLast());
      hands[1].add(deck.removeLast());
    }
    for (final h in hands) {
      h.sort((a, b) => rankOf(a).compareTo(rankOf(b)));
    }
    final s = TableState(seats: 2, hands: hands, piles: [deck, [], [], [], [], [], []], turn: 1 - dealer % 2);
    s.vars[3] = dealer % 2;
    return s;
  }

  int dealer(TableState s) => s.vars[3];

  bool _canPlay(TableState s, int p) => s.hands[p].any((c) => s.vars[1] + cribValue(c) <= 31);

  @override
  List<TAction> legalActions(TableState s) {
    final h = s.hands[s.turn];
    if (s.vars[0] == 0) {
      return [
        for (var i = 0; i < h.length; i++)
          for (var j = i + 1; j < h.length; j++) TAction(1, [h[i], h[j]]),
      ];
    }
    final plays = [for (final c in h) if (s.vars[1] + cribValue(c) <= 31) TAction(0, [c])];
    return plays.isEmpty ? const [TAction(2)] : plays;
  }

  int _pegPoints(List<KCard> seq, int count) {
    var pts = 0;
    if (count == 15 || count == 31) pts += 2;
    // Çift/üçlü/dörtlü
    var same = 1;
    for (var i = seq.length - 2; i >= 0 && rankOf(seq[i]) == rankOf(seq.last); i--) {
      same++;
    }
    pts += const [0, 0, 2, 6, 12][same.clamp(0, 4)];
    // Seri (son k kart)
    for (var k = seq.length; k >= 3; k--) {
      final tail = [for (final c in seq.sublist(seq.length - k)) rankOf(c)]..sort();
      var ok = true;
      for (var i = 1; i < tail.length; i++) {
        if (tail[i] != tail[i - 1] + 1) ok = false;
      }
      if (ok) {
        pts += k;
        break;
      }
    }
    return pts;
  }

  @override
  void apply(TableState s, TAction a) {
    final p = s.turn;
    s.lastSeat = p;
    s.last = a;
    if (s.vars[0] == 0) {
      for (final c in a.cards) {
        s.hands[p].remove(c);
      }
      s.piles[1].addAll(a.cards);
      if (s.piles[1].length == 4) {
        final st = s.piles[0].removeLast();
        s.piles[2].add(st);
        if (rankOf(st) == 11) s.scores[dealer(s)] += 2;
        s.vars[0] = 1;
        s.turn = 1 - dealer(s);
      } else {
        s.turn = 1 - p;
      }
      return;
    }
    if (a.kind == 2) {
      // Go: rakip de oynayamıyorsa son kart atan 1 puan alır, sayı sıfırlanır
      s.vars[4]++;
      final o = 1 - p;
      if (!_canPlay(s, o)) {
        if (s.vars[1] != 31 && s.vars[2] >= 0) s.scores[s.vars[2]] += 1;
        _resetCount(s);
        s.turn = s.hands[p].isNotEmpty ? p : o;
      } else {
        s.turn = o;
      }
    } else {
      final c = a.cards.first;
      s.hands[p].remove(c);
      s.piles[3].add(c);
      s.piles[4].add(c);
      s.piles[5 + p].add(c);
      s.vars[1] += cribValue(c);
      s.vars[2] = p;
      s.scores[p] += _pegPoints(s.piles[3], s.vars[1]);
      if (s.vars[1] == 31) {
        _resetCount(s);
        s.turn = s.hands[1 - p].isNotEmpty ? 1 - p : p;
      } else {
        s.turn = s.hands[1 - p].isNotEmpty ? 1 - p : p;
      }
    }
    if (s.hands.every((h) => h.isEmpty)) {
      if (s.vars[1] > 0 && s.vars[1] != 31) s.scores[s.vars[2]] += 1;
      _show(s);
    }
  }

  void _resetCount(TableState s) {
    s.vars[1] = 0;
    s.vars[4] = 0;
    s.piles[3].clear();
  }

  void _show(TableState s) {
    final st = s.piles[2].first;
    final d = dealer(s);
    for (var p = 0; p < 2; p++) {
      s.scores[p] += cribHandScore(s.piles[5 + p], st);
    }
    s.scores[d] += cribHandScore(s.piles[1], st, crib: true);
    s.vars[0] = 2;
    s.over = true;
  }

  @override
  String actionLabel(TAction a, String lang) => switch (a.kind) {
        1 => '${Strings.pick(_cribLabel, lang)}: ${a.cards.map((c) => rankName(rankOf(c), lang)).join(' ')}',
        2 => 'Go',
        _ => rankName(rankOf(a.cards.first), lang),
      };

  @override
  TAction quick(TableState s, SeededRandom r) {
    final l = legalActions(s);
    if (s.vars[0] == 0) {
      final h = s.hands[s.turn];
      var best = l.first;
      var bv = -1 << 20;
      for (final a in l) {
        final keep = [...h]..removeWhere(a.cards.contains);
        var v = 0;
        // Ortalama açılan kart yerine birkaç tipik kart
        for (final st in const [5, 10, 1]) {
          v += cribHandScore(keep, makeCard(st, (suitOf(keep.first) + 1) % 4, 1));
        }
        final mine = s.turn == dealer(s);
        final give = cribHandScore([...a.cards, ...a.cards], makeCard(13, 0, 1)) ~/ 2;
        v = v * 2 + (mine ? give : -give) + r.nextInt(2);
        if (v > bv) {
          bv = v;
          best = a;
        }
      }
      return best;
    }
    if (l.first.kind == 2) return l.first;
    var best = l.first;
    var bv = -1 << 20;
    for (final a in l) {
      final c = a.cards.first;
      final cnt = s.vars[1] + cribValue(c);
      var v = _pegPoints([...s.piles[3], c], cnt) * 10 - cribValue(c);
      if (cnt == 5 || cnt == 21) v -= 6;
      if (v > bv) {
        bv = v;
        best = a;
      }
    }
    return best;
  }

  @override
  String status(TableState s, String lang) =>
      '${Strings.tx(lang, 'Puan', 'Points')}: ${s.scores[0]} · ${s.scores[1]}  ·  ${Strings.pick(_countLabel, lang)}: ${s.vars[1]}';
}

// ======================================================================
// Durak

/// Durak: iki kişi, 36 kart (6–As); destenin altındaki kartın rengi koz.
/// Saldıran bir kart açar, savunan aynı renkten büyükle ya da kozla keser
/// veya kartları alır. Saldıran masadaki sayılardan kart ekleyebilir. Deste
/// bitince elini ilk bitiren kazanır; kartları elinde kalan "durak"tır.
class DurakRules extends TableRules {
  const DurakRules();

  @override
  List<KCard> deck() => buildDeck(ranks: const [1, 6, 7, 8, 9, 10, 11, 12, 13]);

  static const _attackLabel = [
    'Saldırı', 'Attack', 'Angriff', 'Ataque', 'Attaque', 'الهجوم', 'حمله', 'התקפה', 'حملہ', 'Атака', 'Атака', 'Atak', 'Útok', 'Atac', 'Támadás',
    'Επίθεση', 'Attacco', 'Ataque', 'Aanval', 'Anfall', 'Angreb', 'Angrep', 'Hyökkäys', '攻撃', '공격', '进攻', 'हमला', 'আক্রমণ', 'Serangan',
    'Serangan', 'บุก', 'Tấn công', 'Atake',
  ];
  static const _defenseLabel = [
    'Savunma', 'Defence', 'Verteidigung', 'Defensa', 'Défense', 'الدفاع', 'دفاع', 'הגנה', 'دفاع', 'Защита', 'Захист', 'Obrona', 'Obrana',
    'Apărare', 'Védekezés', 'Άμυνα', 'Difesa', 'Defesa', 'Verdediging', 'Försvar', 'Forsvar', 'Forsvar', 'Puolustus', '防御', '수비', '防守',
    'बचाव', 'প্রতিরক্ষা', 'Pertahanan', 'Pertahanan', 'รับ', 'Phòng thủ', 'Depensa',
  ];
  static const _take = [
    'Al', 'Take', 'Nehmen', 'Tomar', 'Prendre', 'خذ', 'بردار', 'קח', 'لیں', 'Беру', 'Беру', 'Biorę', 'Beru', 'Iau', 'Felveszem', 'Παίρνω',
    'Prendo', 'Pego', 'Pak', 'Tar', 'Tager', 'Tar', 'Otan', '引き取る', '가져가기', '收牌', 'लें', 'নিন', 'Ambil', 'Ambil', 'รับไพ่', 'Nhận', 'Kunin',
  ];
  static const _done = [
    'Bitti', 'Done', 'Fertig', 'Hecho', 'Terminé', 'انتهى', 'تمام', 'סיימתי', 'ختم', 'Бито', 'Відбій', 'Koniec', 'Hotovo', 'Gata', 'Kész',
    'Τέλος', 'Fatto', 'Pronto', 'Klaar', 'Klar', 'Færdig', 'Ferdig', 'Valmis', '終わり', '끝', '完成', 'हो गया', 'শেষ', 'Selesai', 'Selesai',
    'เสร็จ', 'Xong', 'Tapos',
  ];

  // piles: 0 deste (kapalı), 1 koz kartı, 2 saldırı, 3 savunma, 4 çıkan
  // vars: 0 saldıran, 1 koz rengi
  @override
  List<PileView> get pileViews => const [
        PileView('Deste', 'Stock', faceUp: false),
        PileView('Koz', 'Trump'),
        PileView('Saldırı', 'Attack', spread: true, labels: _attackLabel),
        PileView('Savunma', 'Defence', spread: true, labels: _defenseLabel),
      ];

  int _pow(KCard c) => rankOf(c) == 1 ? 14 : rankOf(c);

  @override
  TableState deal(List<KCard> shuffled, int dealer) {
    final deck = List.of(shuffled);
    final trumpCard = deck.removeAt(0);
    final hands = [<KCard>[], <KCard>[]];
    for (var r = 0; r < 6; r++) {
      hands[0].add(deck.removeLast());
      hands[1].add(deck.removeLast());
    }
    final s = TableState(seats: 2, hands: hands, piles: [deck, [trumpCard], [], [], []], turn: (dealer + 1) % 2);
    s.vars[1] = suitOf(trumpCard);
    // En küçük kozu olan saldırır
    var att = s.turn, best = 99;
    for (var p = 0; p < 2; p++) {
      for (final c in hands[p]) {
        if (suitOf(c) == s.vars[1] && _pow(c) < best) {
          best = _pow(c);
          att = p;
        }
      }
    }
    s.vars[0] = att;
    s.turn = att;
    for (final h in hands) {
      _sort(s, h);
    }
    return s;
  }

  void _sort(TableState s, List<KCard> h) =>
      h.sort((a, b) => ((suitOf(a) == s.vars[1] ? 100 : 0) + _pow(a)).compareTo((suitOf(b) == s.vars[1] ? 100 : 0) + _pow(b)));

  bool beatsCard(TableState s, KCard d, KCard a) {
    if (suitOf(d) == suitOf(a)) return _pow(d) > _pow(a);
    return suitOf(d) == s.vars[1];
  }

  @override
  List<TAction> legalActions(TableState s) {
    final p = s.turn;
    final h = s.hands[p];
    final att = s.vars[0], def = 1 - att;
    final attacks = s.piles[2], defs = s.piles[3];
    if (p == att) {
      if (attacks.isEmpty) return [for (final c in h) TAction(0, [c])];
      final ranks = {for (final c in [...attacks, ...defs]) rankOf(c)};
      final canAdd = attacks.length < 6 && (attacks.length - defs.length) < s.hands[def].length;
      return [
        if (canAdd)
          for (final c in h)
            if (ranks.contains(rankOf(c))) TAction(0, [c]),
        const TAction(2),
      ];
    }
    final target = attacks[defs.length];
    return [
      for (final c in h)
        if (beatsCard(s, c, target)) TAction(0, [c]),
      const TAction(3),
    ];
  }

  void _draw(TableState s, int first) {
    for (final p in [first, 1 - first]) {
      while (s.hands[p].length < 6) {
        if (s.piles[0].isNotEmpty) {
          s.hands[p].add(s.piles[0].removeLast());
        } else if (s.piles[1].isNotEmpty) {
          s.hands[p].add(s.piles[1].removeLast());
        } else {
          break;
        }
      }
      _sort(s, s.hands[p]);
    }
  }

  void _checkEnd(TableState s) {
    if (s.piles[0].isNotEmpty || s.piles[1].isNotEmpty) return;
    final e0 = s.hands[0].isEmpty, e1 = s.hands[1].isEmpty;
    if (e0 || e1) {
      s.over = true;
      s.scores[0] = e0 && !e1 ? 1 : (e1 && !e0 ? -1 : 0);
      s.scores[1] = -s.scores[0];
    }
  }

  @override
  void apply(TableState s, TAction a) {
    final p = s.turn;
    final att = s.vars[0], def = 1 - att;
    s.lastSeat = p;
    s.last = a;
    switch (a.kind) {
      case 0:
        s.hands[p].remove(a.cards.first);
        if (p == att) {
          s.piles[2].add(a.cards.first);
          s.turn = def;
        } else {
          s.piles[3].add(a.cards.first);
          s.turn = att;
        }
        // Savunanın kartı bitti ve her şey kesildiyse tur biter
        if (s.piles[2].length == s.piles[3].length && s.hands[def].isEmpty) {
          _endBeaten(s);
        }
      case 2:
        _endBeaten(s);
      case 3:
        s.hands[def].addAll([...s.piles[2], ...s.piles[3]]);
        s.piles[2].clear();
        s.piles[3].clear();
        _draw(s, att);
        s.turn = att;
    }
    _checkEnd(s);
  }

  void _endBeaten(TableState s) {
    final att = s.vars[0], def = 1 - att;
    s.piles[4].addAll([...s.piles[2], ...s.piles[3]]);
    s.piles[2].clear();
    s.piles[3].clear();
    _draw(s, att);
    s.vars[0] = def;
    s.turn = def;
  }

  @override
  String actionLabel(TAction a, String lang) => switch (a.kind) {
        2 => Strings.pick(_done, lang),
        3 => Strings.pick(_take, lang),
        _ => rankName(rankOf(a.cards.first), lang),
      };

  @override
  TAction quick(TableState s, SeededRandom r) {
    final l = legalActions(s);
    final cards = l.where((a) => a.kind == 0).toList()
      ..sort((a, b) {
        int k(KCard c) => (suitOf(c) == s.vars[1] ? 100 : 0) + _pow(c);
        return k(a.cards.first).compareTo(k(b.cards.first));
      });
    final p = s.turn;
    if (p == s.vars[0]) {
      if (s.piles[2].isEmpty) return cards.first;
      final cheap = cards.where((a) => suitOf(a.cards.first) != s.vars[1] && _pow(a.cards.first) < 11).toList();
      if (cheap.isNotEmpty && r.chance(0.8)) return cheap.first;
      return const TAction(2);
    }
    if (cards.isEmpty) return const TAction(3);
    final c = cards.first.cards.first;
    // Değerli kozu küçük karta harcama (deste varken)
    if (suitOf(c) == s.vars[1] && _pow(c) >= 12 && s.piles[0].length > 4 && r.chance(0.5)) return const TAction(3);
    return cards.first;
  }

  @override
  String status(TableState s, String lang) =>
      '${Strings.tx(lang, 'Koz', 'Trump')}: ${['♠', '♥', '♦', '♣'][s.vars[1]]}  ·  ${Strings.tx(lang, 'Deste', 'Stock')}: ${s.piles[0].length + s.piles[1].length}';
}
