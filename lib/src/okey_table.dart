part of 'table_view.dart';

// Okey ailesinin (Okey, 101 Okey, Okey çeşitleri) masa ekranı: oyuncunun
// koltuğundan bakılan çuha masa, çevresinde üç rakip (avatar, ad, taş sayısı,
// sıra halkası), her oyuncunun köşesinde attığı taş, ortada deste ve
// gösterge, 101'de masaya açılan perler; altta iki katlı ıstaka (sürükle-
// bırak, seri/çift diz). Durum, yapay zekâ ve çevrimiçi koltuk mantığı
// [_TableViewState] ile ortaktır; burada yalnız görünüm ve dokunma var.

/// Taş masasının oyuna özgü görünümü: çuha, ahşap kenar, oda ve süs.
class _TileTheme {
  final List<Color> felt; // merkez, orta, kenar
  final List<Color> rim; // ahşap kenar (üst, alt)
  final List<Color> room; // masa çevresindeki zemin (üst, alt)
  final Color ink; // çuha süsü
  final int pattern; // 0 baklava, 1 halka, 2 yıldız köşeler
  final String mark; // çuhadaki silik yazı
  const _TileTheme(this.felt, this.rim, this.room, this.ink, this.pattern, this.mark);
}

_TileTheme _tileThemeFor(TableRules r) {
  const walnut = [Color(0xFF8A5631), Color(0xFF4A2814)];
  if (r is Okey101Rules) {
    // 101: bordo çuha, koyu ceviz; ortada silik "101".
    return const _TileTheme([Color(0xFF9E2C42), Color(0xFF761C2F), Color(0xFF47101C)], walnut,
        [Color(0xFF2A1218), Color(0xFF140709)], Color(0xFFFFD7A8), 0, '101');
  }
  if (r is OkeyRules) {
    if (r.partners) {
      // Eşli: lacivert çuha, açık meşe.
      return const _TileTheme([Color(0xFF2B5A9E), Color(0xFF1C3E74), Color(0xFF0F2347)],
          [Color(0xFFB98A55), Color(0xFF6B4520)], [Color(0xFF111A2E), Color(0xFF070C18)], Color(0xFFBFD8FF), 1, '');
    }
    if (r.doubling) {
      // Katlamalı: mor çuha, ×2 süsü.
      return const _TileTheme([Color(0xFF6E3A8E), Color(0xFF51286C), Color(0xFF2E1442)], walnut,
          [Color(0xFF1F1229), Color(0xFF0E0714)], Color(0xFFE7C8FF), 2, '×2');
    }
    if (r.players == 2) {
      // İki kişilik: zeytin yeşili çuha.
      return const _TileTheme([Color(0xFF6B7F2E), Color(0xFF4E5E1F), Color(0xFF2E3810)],
          [Color(0xFFA0703F), Color(0xFF5A3618)], [Color(0xFF1C2010), Color(0xFF0C0E06)], Color(0xFFF1F5C8), 1, '');
    }
  }
  // Klasik Okey: koyu yeşil çuha, ceviz kenar.
  return const _TileTheme([Color(0xFF23875F), Color(0xFF176446), Color(0xFF0B3D2A)], walnut,
      [Color(0xFF14231C), Color(0xFF07100C)], Color(0xFFCFF5E2), 0, '');
}

/// Koltuk renkleri (göreli: sen, sağ, karşı, sol).
const _seatInk = [Color(0xFF2EC4B6), Color(0xFFFFB627), Color(0xFFB388FF), Color(0xFFFF6B6B)];
const _gold = Color(0xFFFFD166);

class _FeltMotif extends CustomPainter {
  final _TileTheme t;
  _FeltMotif(this.t);

  @override
  bool shouldRepaint(covariant _FeltMotif o) => o.t != t;

  @override
  void paint(Canvas c, Size s) {
    final ink = Paint()
      ..color = t.ink.withValues(alpha: 0.07)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final o = Offset(s.width / 2, s.height / 2);
    switch (t.pattern) {
      case 1:
        for (var r = 40.0; r < s.longestSide; r += 34) {
          c.drawCircle(o, r, ink);
        }
      case 2:
        final step = 46.0;
        for (var x = step / 2; x < s.width; x += step) {
          for (var y = step / 2; y < s.height; y += step) {
            c.drawLine(Offset(x - 4, y), Offset(x + 4, y), ink);
            c.drawLine(Offset(x, y - 4), Offset(x, y + 4), ink);
          }
        }
      default:
        const step = 38.0;
        for (var d = -s.height; d < s.width; d += step) {
          c.drawLine(Offset(d, 0), Offset(d + s.height, s.height), ink);
          c.drawLine(Offset(d + s.height, 0), Offset(d, s.height), ink);
        }
    }
    // Merkezde ince çift halka (masanın ortası).
    final ring = Paint()
      ..color = t.ink.withValues(alpha: 0.12)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6;
    final rr = math.min(s.width, s.height) * 0.3;
    c.drawOval(Rect.fromCenter(center: o, width: rr * 2.4, height: rr * 1.6), ring);
    c.drawOval(Rect.fromCenter(center: o, width: rr * 2.4 - 10, height: rr * 1.6 - 10), ring);
    if (t.mark.isNotEmpty) {
      final tp = TextPainter(
        text: TextSpan(
            text: t.mark,
            style: TextStyle(
                fontSize: math.min(s.width, s.height) * 0.32,
                fontWeight: FontWeight.w900,
                color: t.ink.withValues(alpha: 0.08),
                letterSpacing: 4)),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(c, o - Offset(tp.width / 2, tp.height / 2));
    }
    final r = math.Random(5);
    final p = Paint()..color = Colors.white.withValues(alpha: 0.025);
    for (var i = 0; i < 220; i++) {
      c.drawCircle(Offset(r.nextDouble() * s.width, r.nextDouble() * s.height), 0.6 + r.nextDouble() * 0.9, p);
    }
  }
}

class _OkTileP extends CustomPainter {
  final KCard t;
  final bool up, hl, dim, joker;
  final CardStyle style;
  _OkTileP(this.t, this.up, this.style, this.hl, this.dim, this.joker);

  @override
  void paint(Canvas canvas, Size size) => paintTile(canvas, Offset.zero & size, t, kTileOkey,
      faceUp: up, backA: style.backA, backB: style.backB, highlight: hl, dim: dim, colorBlind: style.colorBlind, joker: joker);

  @override
  bool shouldRepaint(covariant _OkTileP o) =>
      o.t != t || o.up != up || o.hl != hl || o.dim != dim || o.joker != joker || o.style != style;
}

extension _OkeyTable on _TableViewState {
  OkeyRules get _ok => rules as OkeyRules;
  Okey101Rules? get _o101 => rules is Okey101Rules ? rules as Okey101Rules : null;
  int get _okKind => s.vars[1];
  String get _lang => ctx.lang;

  /// Koltuğun bana göre konumu: 0 ben, 1 sağ (sıradaki), 2 karşı, 3 sol.
  int _rel(int seat) => (seat - me + s.seats) % s.seats;

  bool _okJoker(KCard t) => okeyMeaning(t, _okKind) < 0;

  List<TAction> _okLegal() {
    if (!(_isLocal(s.turn) && s.turn == me && !s.over && !_busy && !_cover && !_summary)) return const [];
    final key = s.serialize();
    if (key != _legalKey) {
      _legalKey = key;
      _legalCache = rules.legalActions(s);
    }
    return _legalCache;
  }

  String _okName(int seat) {
    if (_multi && (ctx.passAndPlay || ctx.role(seat) != SeatRole.ai)) {
      if (seat == me && _match != null) return okt(_lang, 'you');
      return ctx.seatName(seat);
    }
    final k = _rel(seat);
    if (k == 0) return okt(_lang, 'you');
    if (s.seats == 2) return okt(_lang, 'across');
    if (rules.partnerships && k == 2) return okt(_lang, 'partner');
    return okt(_lang, k == 1 ? 'right' : (k == 2 ? 'across' : 'left'));
  }

  // ---- Istaka ----------------------------------------------------------------

  /// Istakayı eldeki taşlarla eşitler: çıkan taşların yuvası boşalır, gelen
  /// taş son taşın ardındaki ilk boş yuvaya konur.
  void _syncRack(int cols) {
    final hand = s.hands[me];
    if (_slotCols != cols || _slots.length != cols * 2 || _slotSeat != me) {
      _slotCols = cols;
      _slotSeat = me;
      _slots = List<KCard?>.filled(cols * 2, null);
      _okPlace(okeyArrange(hand, _okKind));
      return;
    }
    final have = hand.toSet();
    for (var i = 0; i < _slots.length; i++) {
      if (_slots[i] != null && !have.contains(_slots[i])) _slots[i] = null;
    }
    final placed = _slots.whereType<KCard>().toSet();
    for (final t in hand) {
      if (placed.contains(t)) continue;
      var last = -1;
      for (var i = 0; i < _slots.length; i++) {
        if (_slots[i] != null) last = i;
      }
      var at = -1;
      for (var i = last + 1; i < _slots.length; i++) {
        if (_slots[i] == null) {
          at = i;
          break;
        }
      }
      if (at < 0) at = _slots.indexOf(null);
      if (at < 0) break;
      _slots[at] = t;
      if (hand.length > 1 && s.turn == me) _fresh = t;
    }
  }

  /// Gruplar arada bir boşlukla, satıra sığmayan grup alt satıra; kalanlar
  /// sona. Sığmazsa boşluksuz dizilir.
  void _okPlace((List<List<KCard>>, List<KCard>) plan) {
    final cols = _slotCols;
    final total = cols * 2;
    final (groups, rest) = plan;
    final out = List<KCard?>.filled(total, null);
    var i = 0;
    var ok = true;
    for (final g in groups) {
      final row = i ~/ cols, col = i % cols;
      if (col + g.length > cols && row == 0 && g.length <= cols) i = cols;
      if (i + g.length > total) {
        ok = false;
        break;
      }
      for (final t in g) {
        out[i++] = t;
      }
      if (i % cols != 0) i++;
    }
    if (ok) {
      for (final t in rest) {
        while (i < total && out[i] != null) {
          i++;
        }
        if (i >= total) {
          ok = false;
          break;
        }
        out[i++] = t;
      }
    }
    if (!ok) {
      final all = [for (final g in groups) ...g, ...rest];
      for (var k = 0; k < total; k++) {
        out[k] = k < all.length ? all[k] : null;
      }
    }
    _slots = out;
  }

  void _okArrange(bool pairs) {
    if (_cover) return;
    _set(() {
      _okPlace(okeyArrange(s.hands[me], _okKind, pairs: pairs));
      _fresh = null;
    });
  }

  void _okMove(KCard t, int to) {
    final from = _slots.indexOf(t);
    if (from < 0 || from == to) return;
    _set(() {
      final o = _slots[to];
      _slots[to] = t;
      _slots[from] = o;
    });
  }

  void _okTap(KCard t) {
    if (_ended || _cover || _summary) return;
    _set(() {
      if (!_selected.remove(t)) _selected.add(t);
      if (_fresh == t) _fresh = null;
    });
  }

  // ---- Hamleler ----------------------------------------------------------------

  /// [tiles] ile aynı anlamdaki taşları kullanan yasal hamle (eş taşlardan
  /// hangisi seçilmiş olursa olsun).
  TAction? _okFind(List<TAction> legal, int kind, List<KCard> tiles, {int target = -1}) {
    final want = [for (final t in tiles) okeyMeaning(t, _okKind)]..sort();
    for (final a in legal) {
      if (a.kind != kind || a.cards.length != tiles.length) continue;
      if (target >= 0 && a.target != target) continue;
      final got = [for (final t in a.cards) okeyMeaning(t, _okKind)]..sort();
      var same = true;
      for (var i = 0; i < got.length; i++) {
        if (got[i] != want[i]) {
          same = false;
          break;
        }
      }
      if (same) return a;
    }
    return null;
  }

  /// Hamle seçilen taşın eşini kullanıyorsa ıstakada yerlerini değiştir:
  /// oyuncunun seçtiği yuvadaki taş gider.
  void _okSwapTwins(List<KCard> used, List<KCard> intended) {
    final free = used.where((t) => !intended.contains(t)).toList();
    for (final x in intended) {
      if (used.contains(x)) continue;
      final i = free.indexWhere((y) => okeyMeaning(y, _okKind) == okeyMeaning(x, _okKind));
      if (i < 0) continue;
      final y = free.removeAt(i);
      final a = _slots.indexOf(x), b = _slots.indexOf(y);
      if (a >= 0 && b >= 0) {
        _slots[a] = y;
        _slots[b] = x;
      }
    }
  }

  void _okAct(TAction a, [List<KCard>? intended]) {
    if (intended != null) _okSwapTwins(a.cards, intended);
    _fresh = null;
    _human(a);
  }

  Future<void> _okDiscard(KCard t) async {
    final legal = _okLegal();
    final fin = _okFind(legal, 9, [t]);
    if (fin != null) {
      _okAct(fin, [t]);
      return;
    }
    final d = _okFind(legal, 0, [t]);
    if (d == null) {
      ctx.sfx(Sfx.error);
      return;
    }
    final o = _o101;
    if (o != null && o.discardPenalty(s, t)) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (c) => StudioChrome(
          child: AlertDialog(
            content: Text(okt(_lang, _okJoker(t) ? 'warnOkey' : 'warnAdd')),
            actions: [
              TextButton(onPressed: () => Navigator.pop(c, false), child: Text(ctx.t('cancel'))),
              TextButton(onPressed: () => Navigator.pop(c, true), child: Text(okt(_lang, 'discardBtn'))),
            ],
          ),
        ),
      );
      if (ok != true || !mounted) return;
      final again = _okFind(_okLegal(), 0, [t]);
      if (again == null) return;
      _okAct(again, [t]);
      return;
    }
    _okAct(d, [t]);
  }

  /// 101: seçili taşlarla yeni per; seçim yoksa en büyük yasal per.
  TAction? _okLayAction(List<TAction> legal) {
    if (_selected.length >= 2) return _okFind(legal, 2, _selected.toList());
    if (_selected.isNotEmpty) return null;
    final lays = legal.where((a) => a.kind == 2).toList()..sort((a, b) => b.cards.length.compareTo(a.cards.length));
    return lays.isEmpty ? null : lays.first;
  }

  /// 101 açış durumu (benim elim): en iyi per toplamı ve çift sayısı.
  (int, int) _okOpenProgress() {
    final o = _o101!;
    final h = s.hands[me];
    final key = '$_okKind:${[...h]..sort()}';
    if (key != _progKey) {
      _progKey = key;
      _prog = (o.bestGroups(s, h).$2, o.pairsIn(s, h).length);
    }
    return _prog;
  }

  // ---- Parçalar ----------------------------------------------------------------

  Widget _okTile(KCard t, double w, {bool up = true, bool hl = false, bool dim = false}) => SizedBox(
        width: w,
        height: w * rules.tileAspect,
        child: CustomPaint(painter: _OkTileP(t, up, _style, hl, dim, up && _okJoker(t) && !isOkeyFalseJoker(t))),
      );

  Widget _okAvatar(int seat, double d) {
    final k = _rel(seat);
    final col = _seatInk[k % 4];
    final active = s.turn == seat && !s.over;
    final bot = seat != me && _isAi(seat);
    final local = _isLocal(seat);
    return SizedBox(
      width: d + 10,
      height: d + 10,
      child: Stack(alignment: Alignment.center, children: [
        if (active)
          SizedBox.expand(
            child: TweenAnimationBuilder<double>(
              key: ValueKey('ring$seat-${s.vars[0]}-${s.piles[0].length}-${s.piles[1].length}'),
              tween: Tween(begin: 0, end: 1),
              duration: local ? const Duration(seconds: 30) : Duration(milliseconds: ctx.reducedMotion ? 300 : 1300),
              builder: (_, v, __) => CircularProgressIndicator(
                value: 1 - v,
                strokeWidth: 3.5,
                color: _gold,
                backgroundColor: Colors.white24,
              ),
            ),
          ),
        Container(
          width: d,
          height: d,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(colors: [col, Color.lerp(col, Colors.black, 0.5)!]),
            border: Border.all(color: Colors.white.withValues(alpha: active ? 0.95 : 0.55), width: 2),
            boxShadow: [
              BoxShadow(color: (active ? _gold : Colors.black).withValues(alpha: active ? 0.55 : 0.4), blurRadius: active ? 12 : 6),
            ],
          ),
          child: Icon(bot ? Icons.smart_toy_rounded : Icons.person_rounded, color: Colors.white, size: d * 0.58),
        ),
      ]),
    );
  }

  Widget _okMiniBack() => SizedBox(
        width: 10,
        height: 14,
        child: CustomPaint(painter: _OkTileP(0, false, _style, false, false, false)),
      );

  Widget _okSeat(int seat, {double maxW = 120}) {
    final o = _o101;
    final opened = o != null && o.opened(s, seat);
    final n = s.hands[seat].length;
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxW),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        _okAvatar(seat, maxW < 90 ? 36 : 42),
        const SizedBox(height: 2),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.45),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _seatInk[_rel(seat) % 4].withValues(alpha: 0.8), width: 1.2),
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(_okName(seat),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 12.5)),
            Row(mainAxisSize: MainAxisSize.min, children: [
              _okMiniBack(),
              const SizedBox(width: 4),
              Text('$n', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 12)),
              if (o != null) ...[
                const SizedBox(width: 5),
                Icon(opened ? Icons.check_circle_rounded : Icons.lock_outline_rounded,
                    size: 13, color: opened ? const Color(0xFF7CF29C) : Colors.white60),
              ],
            ]),
          ]),
        ),
      ]),
    );
  }

  Widget _okCorner(int seat, double tw, List<TAction> legal, {bool takeSpot = false, bool mySpot = false}) {
    final t = seat < 0 ? -1 : _ok.lastDiscard(s, seat);
    final canTake = takeSpot && legal.any((a) => a.kind == 1 && a.target == 1);
    final discardPhase = s.vars[0] == 1 && legal.any((a) => a.kind == 0 || a.kind == 9);
    final canDrop = mySpot && discardPhase;
    final hinted = _hint != null && takeSpot && _hint!.kind == 1 && _hint!.target == 1;
    final glow = canTake || hinted || (canDrop && _selected.length == 1);
    final w = tw, h = tw * rules.tileAspect;
    final label = canTake || hinted ? kt(_lang, 'pick') : (canDrop ? okt(_lang, 'discardBtn') : '');
    Widget spot(bool over) => AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: w + 8,
          height: h + 8,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(9),
            color: Colors.black.withValues(alpha: over ? 0.35 : 0.18),
            border: Border.all(
                color: glow || over ? _gold : Colors.white.withValues(alpha: 0.22), width: glow || over ? 2.4 : 1.2),
            boxShadow: glow ? [BoxShadow(color: _gold.withValues(alpha: 0.45), blurRadius: 12)] : null,
          ),
          child: AnimatedSwitcher(
            duration: Duration(milliseconds: ctx.reducedMotion ? 0 : 260),
            transitionBuilder: (c, a) => ScaleTransition(scale: a, child: FadeTransition(opacity: a, child: c)),
            child: t < 0 ? SizedBox(key: ValueKey('e$seat'), width: w, height: h) : KeyedSubtree(key: ValueKey(t), child: _okTile(t, w)),
          ),
        );
    Widget body = Column(mainAxisSize: MainAxisSize.min, children: [
      if (mySpot || takeSpot)
        SizedBox(
          height: 15,
          width: w + 30,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(label, style: const TextStyle(color: _gold, fontSize: 11.5, fontWeight: FontWeight.w900)),
          ),
        ),
      if (mySpot)
        DragTarget<int>(
          onWillAcceptWithDetails: (_) => canDrop,
          onAcceptWithDetails: (d) => _okDiscard(d.data),
          builder: (c, cand, _) => spot(cand.isNotEmpty),
        )
      else
        spot(false),
    ]);
    if (canTake) {
      body = GestureDetector(onTap: () => _okAct(const TAction(1, [], 1)), child: body);
    } else if (canDrop) {
      body = GestureDetector(
        onTap: () {
          if (_selected.length == 1) _okDiscard(_selected.first);
        },
        child: body,
      );
    }
    return Semantics(label: label.isEmpty ? null : label, button: canTake || canDrop, child: body);
  }

  Widget _okCenter(double tw, List<TAction> legal) {
    final canDraw = legal.any((a) => a.kind == 1 && a.target == 0);
    final finish = rules is! Okey101Rules && legal.any((a) => a.kind == 9);
    final hinted = _hint != null && ((_hint!.kind == 1 && _hint!.target == 0) || _hint!.kind == 9);
    final glow = canDraw || finish || hinted;
    final stock = s.piles[0].length;
    final dw = tw;
    Widget deck(bool over) => Stack(clipBehavior: Clip.none, children: [
          for (var k = math.min(3, stock) - 1; k >= 0; k--)
            Transform.translate(offset: Offset(k * 2.0, -k * 2.0), child: _okTile(0, dw, up: false, hl: k == 0 && (glow || over))),
          if (stock == 0) SizedBox(width: dw, height: dw * rules.tileAspect, child: CustomPaint(painter: _SlotP())),
          Positioned(
            right: -8,
            bottom: -6,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(9),
                border: Border.all(color: Colors.white38),
              ),
              child: Text('$stock', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 11.5)),
            ),
          ),
        ]);
    Widget deckW = finish
        ? DragTarget<int>(
            onWillAcceptWithDetails: (d) => _okFind(legal, 9, [d.data]) != null,
            onAcceptWithDetails: (d) => _okDiscard(d.data),
            builder: (c, cand, _) => deck(cand.isNotEmpty),
          )
        : deck(false);
    if (canDraw) {
      deckW = GestureDetector(onTap: () => _okAct(const TAction(1, [], 0)), child: deckW);
    } else if (finish) {
      deckW = GestureDetector(
        onTap: () {
          if (_selected.length == 1) _okDiscard(_selected.first);
        },
        child: deckW,
      );
    }
    final ind = s.piles[2].isEmpty ? -1 : s.piles[2].last;
    final okeyFace = _okKind % 52; // okey taşının yüzü (gösterge +1)
    final small = (tw * 0.8).clamp(20.0, 48.0);
    return Row(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.end, children: [
      Column(mainAxisSize: MainAxisSize.min, children: [
        SizedBox(
          height: 15,
          width: dw + 40,
          child: glow
              ? FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(finish ? kt(_lang, 'finish') : kt(_lang, 'drawStock'),
                      style: const TextStyle(color: _gold, fontSize: 11.5, fontWeight: FontWeight.w900)),
                )
              : null,
        ),
        Semantics(button: canDraw, label: kt(_lang, 'drawStock'), child: deckW),
      ]),
      SizedBox(width: tw * 0.55 + 6),
      if (ind >= 0)
        Column(mainAxisSize: MainAxisSize.min, children: [
          Transform.rotate(angle: -0.12, child: _okTile(ind, small)),
          const SizedBox(height: 3),
          Text(Strings.pick(OkeyRules.indicatorLabels, _lang),
              style: const TextStyle(color: Colors.white70, fontSize: 10.5, fontWeight: FontWeight.w700)),
        ]),
      const SizedBox(width: 8),
      Column(mainAxisSize: MainAxisSize.min, children: [
        _okTile(okeyFace, small),
        const SizedBox(height: 3),
        const Text('OKEY', style: TextStyle(color: _gold, fontSize: 10.5, fontWeight: FontWeight.w900, letterSpacing: 1)),
      ]),
    ]);
  }

  Widget _okMelds(double mw, List<TAction> legal) {
    final o = _o101!;
    final ms = o.melds(s);
    if (ms.isEmpty) return const SizedBox.shrink();
    final idx = [for (var i = 0; i < ms.length; i++) i]
      ..sort((a, b) {
        final c = _rel(o.meldOwner(s, a)).compareTo(_rel(o.meldOwner(s, b)));
        return c != 0 ? c : a.compareTo(b);
      });
    final sel = _selected.length == 1 ? _selected.first : null;
    return Wrap(spacing: 6, runSpacing: 6, alignment: WrapAlignment.center, children: [
      for (final i in idx)
        () {
          final owner = o.meldOwner(s, i);
          final col = owner < 0 ? Colors.white54 : _seatInk[_rel(owner) % 4];
          final add = sel == null ? null : _okFind(legal, 3, [sel], target: i);
          final hinted = _hint != null && _hint!.kind == 3 && _hint!.target == i;
          final tiles = ms[i].length == 2 ? ms[i] : okeyMeldOrder(ms[i], _okKind);
          Widget box(bool over) => AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.fromLTRB(3, 2, 3, 3),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: over ? 0.4 : 0.22),
                  borderRadius: BorderRadius.circular(7),
                  border: Border.all(color: add != null || hinted || over ? _gold : col.withValues(alpha: 0.75), width: add != null || over ? 2.2 : 1.3),
                ),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Container(width: mw * 0.9, height: 3, decoration: BoxDecoration(color: col, borderRadius: BorderRadius.circular(2))),
                  const SizedBox(height: 2),
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    for (final t in tiles) Padding(padding: const EdgeInsets.symmetric(horizontal: 0.5), child: _okTile(t, mw)),
                  ]),
                ]),
              );
          return DragTarget<int>(
            onWillAcceptWithDetails: (d) => _okFind(legal, 3, [d.data], target: i) != null,
            onAcceptWithDetails: (d) {
              final a = _okFind(legal, 3, [d.data], target: i);
              if (a != null) _okAct(a, [d.data]);
            },
            builder: (c, cand, _) => GestureDetector(
              onTap: add == null ? null : () => _okAct(add, [sel!]),
              child: box(cand.isNotEmpty),
            ),
          );
        }(),
    ]);
  }

  Widget _okStatusText() {
    String text;
    if (s.over) {
      text = okt(_lang, 'handOver');
    } else if (_isLocal(s.turn) && s.turn == me && !_cover) {
      final o = _o101;
      text = s.vars[0] == 0 ? okt(_lang, 'draw') : (o != null && o.mustUse(s) >= 0 ? okt(_lang, 'use') : okt(_lang, 'discard'));
    } else {
      text = okt(_lang, 'turnOf', _okName(s.turn));
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.42), borderRadius: BorderRadius.circular(14)),
      child: Text(text,
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 12.5)),
    );
  }

  Widget _okTableArea(double tw, List<TAction> legal, bool wide) {
    final th = _tileThemeFor(rules);
    final n = s.seats;
    final ct = (tw * 1.0).clamp(26.0, 52.0);
    final mw = (tw * 0.74).clamp(17.0, 38.0);
    final sideW = wide ? 110.0 : 74.0;
    int seatAt(int k) => (me + k) % n;
    final top = n == 2 ? seatAt(1) : seatAt(2);
    final cornerW = ct + 8;
    Widget none() => SizedBox(width: cornerW);
    // Köşeler: sol üst karşının, sağ üst sağın, sol alt solun (alınacak), sağ alt benim.
    final tl = n == 4 ? _okCorner(seatAt(2), ct, legal) : none();
    final tr = n == 4 ? _okCorner(seatAt(1), ct, legal) : none();
    final bl = _okCorner(seatAt(n - 1), ct, legal, takeSpot: true);
    final br = _okCorner(me, ct, legal, mySpot: true);
    final centre = Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      _okCenter(tw.clamp(28.0, 54.0), legal),
      if (_o101 != null) ...[
        const SizedBox(height: 8),
        Flexible(child: SingleChildScrollView(child: _okMelds(mw, legal))),
      ],
    ]);
    return Container(
      margin: const EdgeInsets.fromLTRB(6, 2, 6, 4),
      padding: const EdgeInsets.all(7),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: th.rim),
        boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 14, offset: Offset(0, 6))],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(center: const Alignment(0, -0.1), radius: 1.05, colors: th.felt, stops: const [0, 0.62, 1]),
          ),
          child: CustomPaint(
            painter: _FeltMotif(th),
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: Column(children: [
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  tl,
                  Expanded(child: Center(child: _okSeat(top, maxW: wide ? 160 : 130))),
                  tr,
                ]),
                Expanded(
                  child: Row(children: [
                    if (n == 4) SizedBox(width: sideW, child: Center(child: _okSeat(seatAt(3), maxW: sideW))),
                    Expanded(child: centre),
                    if (n == 4) SizedBox(width: sideW, child: Center(child: _okSeat(seatAt(1), maxW: sideW))),
                  ]),
                ),
                Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  bl,
                  Expanded(child: Center(child: _okStatusText())),
                  br,
                ]),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  Widget _okRack(double tw, List<TAction> legal) {
    final cols = _slotCols;
    final th = tw * rules.tileAspect;
    final myTurn = legal.isNotEmpty;
    Widget slot(int i) {
      final t = _slots[i];
      return DragTarget<int>(
        onWillAcceptWithDetails: (d) => _slots.contains(d.data),
        onAcceptWithDetails: (d) => _okMove(d.data, i),
        builder: (c, cand, _) => SizedBox(
          width: tw + 2,
          height: th + 9,
          child: t == null
              ? (cand.isNotEmpty
                  ? Container(
                      margin: const EdgeInsets.only(top: 7),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(5),
                        border: Border.all(color: _gold, width: 1.5),
                      ),
                    )
                  : null)
              : () {
                  final sel = _selected.contains(t);
                  final hl = sel || t == _fresh || (_hint != null && _hint!.cards.contains(t));
                  final tile = _okTile(t, tw, hl: hl);
                  final hinted = _hint != null && _hint!.cards.contains(t);
                  return KeyedSubtree(
                    key: hinted ? ValueKey('ok-hint-t$t') : null,
                    child: Draggable<int>(
                    data: t,
                    feedback: Material(color: Colors.transparent, child: Transform.scale(scale: 1.15, child: _okTile(t, tw))),
                    childWhenDragging: Opacity(opacity: 0.25, child: Padding(padding: const EdgeInsets.only(top: 7), child: tile)),
                    child: GestureDetector(
                      onTap: () => _okTap(t),
                      child: AnimatedPadding(
                        duration: const Duration(milliseconds: 140),
                        padding: EdgeInsets.only(top: sel ? 0 : 7, left: 1, right: 1),
                        child: tile,
                      ),
                    ),
                  ),
                  );
                }(),
        ),
      );
    }

    Widget ledge() => Container(
          height: 5,
          margin: const EdgeInsets.symmetric(horizontal: 2),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(3),
            gradient: const LinearGradient(colors: [Color(0xFF5C3A20), Color(0xFF3B2312)], begin: Alignment.topCenter, end: Alignment.bottomCenter),
          ),
        );
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 4),
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 3),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        gradient: const LinearGradient(
            begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFFD09A66), Color(0xFF9A643B)]),
        border: Border.all(color: myTurn ? _gold.withValues(alpha: 0.8) : const Color(0xFF5C3A20), width: myTurn ? 2 : 1),
        boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 10, offset: Offset(0, 4))],
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Row(mainAxisSize: MainAxisSize.min, children: [for (var c = 0; c < cols; c++) slot(c)]),
        ledge(),
        Row(mainAxisSize: MainAxisSize.min, children: [for (var c = 0; c < cols; c++) slot(cols + c)]),
        ledge(),
      ]),
    );
  }

  Widget _okInfo(String text) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white24),
        ),
        child: Text(text, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13)),
      );

  Widget _okActions(List<TAction> legal) {
    final o = _o101;
    final items = <Widget>[
      StudioChoice(label: okt(_lang, 'runs'), icon: Icons.view_week_rounded, onPressed: _cover ? null : () => _okArrange(false)),
      StudioChoice(label: okt(_lang, 'pairs'), icon: Icons.drag_indicator_rounded, onPressed: _cover ? null : () => _okArrange(true)),
    ];
    final drawPhase = legal.isNotEmpty && s.vars[0] == 0;
    final playPhase = legal.isNotEmpty && s.vars[0] == 1;
    if (drawPhase) {
      for (final a in legal) {
        items.add(StudioChoice(label: rules.actionLabel(a, _lang), hinted: _hint == a, onPressed: () => _okAct(a)));
      }
    }
    if (o != null && !s.over) {
      if (!o.opened(s, me)) {
        final o5 = legal.where((a) => a.kind == 5).toList();
        final o6 = legal.where((a) => a.kind == 6).toList();
        final (v, np) = _okOpenProgress();
        if (o5.isNotEmpty) {
          items.add(StudioChoice(label: '${kt(_lang, 'openHand')} · $v', selected: true, hinted: _hint == o5.first, onPressed: () => _okAct(o5.first)));
        }
        if (o6.isNotEmpty) {
          items.add(StudioChoice(label: '${kt(_lang, 'openHand')}: ${kt(_lang, 'pairs')} ($np)', hinted: _hint == o6.first, onPressed: () => _okAct(o6.first)));
        }
        if (o5.isEmpty && o6.isEmpty) items.add(_okInfo('${okt(_lang, 'opening')}: $v/101 · ${kt(_lang, 'pairs')} $np/5'));
      } else if (playPhase) {
        final lay = _okLayAction(legal);
        if (lay != null) {
          items.add(StudioChoice(
              label: '${okt(_lang, 'lay')} (${lay.cards.length})',
              selected: _selected.length >= 2,
              hinted: _hint == lay,
              onPressed: () => _okAct(lay, _selected.length >= 2 ? _selected.toList() : null)));
        }
        if (_selected.length == 1) {
          final add = legal.where((a) => a.kind == 3).map((a) => _okFind([a], 3, [_selected.first])).whereType<TAction>().toList();
          if (add.isNotEmpty) {
            items.add(StudioChoice(label: okt(_lang, 'add'), selected: true, onPressed: () => _okAct(add.first, [_selected.first])));
          }
        } else if (_selected.isEmpty) {
          final add = legal.where((a) => a.kind == 3).toList();
          if (add.isNotEmpty) items.add(StudioChoice(label: '${okt(_lang, 'add')} (${add.length})', hinted: _hint == add.first, onPressed: () => _okAct(add.first)));
        }
      }
    }
    if (playPhase && _selected.length == 1) {
      final t = _selected.first;
      final fin = _okFind(legal, 9, [t]) != null;
      final can = fin || _okFind(legal, 0, [t]) != null;
      if (can) {
        items.add(StudioChoice(label: fin ? '${kt(_lang, 'finish')} ✓' : okt(_lang, 'discardBtn'), selected: true, onPressed: () => _okDiscard(t)));
      }
    } else if (playPhase && rules is! Okey101Rules) {
      // Okey: bitirebiliyorsa tek dokunuşla bitir (ipucu taşıyla).
      final fin = legal.where((a) => a.kind == 9).toList();
      if (fin.isNotEmpty) {
        items.add(StudioChoice(label: '${kt(_lang, 'finish')} ✓', selected: true, onPressed: () => _okAct(fin.first)));
      }
    }
    return SizedBox(
      height: 50,
      child: Row(children: [
        Expanded(
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            children: [
              for (final w in items)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: Center(
                    child: w is StudioChoice && w.hinted ? KeyedSubtree(key: const ValueKey('ok-hint-act'), child: w) : w,
                  ),
                ),
            ],
          ),
        ),
        StudioRoundAction(
            onPressed: _ended || _busy || !_isLocal(s.turn) || _cover || s.over ? null : _useHint, icon: Icons.lightbulb, tooltip: ctx.t('hint')),
        StudioRoundAction(onPressed: _undo.isNotEmpty && !_busy && !_ended && !s.over ? _doUndo : null, icon: Icons.undo, tooltip: ctx.t('undo')),
        const SizedBox(width: 4),
      ]),
    );
  }

  Widget _okTopBar() {
    final o = _o101;
    String goal;
    if (o != null) {
      final pen = o.inPlayPenalty(s, me);
      goal = '${level.goal.text(rules, s, _lang)}${pen > 0 ? '  ·  ${okt(_lang, 'penalty')}: $pen' : ''}';
    } else {
      goal = level.goal.text(rules, s, _lang);
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 2),
      child: Row(children: [
        Expanded(
          child: Text(goal,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: kStudioText, fontWeight: FontWeight.w800, fontSize: 14)),
        ),
        const SizedBox(width: 8),
        StudioTag(icon: Icons.timer_outlined, text: '${_seconds ~/ 60}:${(_seconds % 60).toString().padLeft(2, '0')}'),
      ]),
    );
  }

  Widget _okSummary(double w) {
    final o = _o101;
    final match = widget.onHandOver != null;
    final finals = rules.finalScores(s);
    final mp = match ? rules.matchPoints(s) : null;
    int winner = -1;
    if (o != null) {
      for (var p = 0; p < s.seats; p++) {
        if (s.hands[p].isEmpty) winner = p;
      }
    } else if (s.vars[2] > 0) {
      winner = s.vars[2] - 1;
    }
    final okeyOut = winner >= 0 && s.piles[1].isNotEmpty && _okJoker(s.piles[1].last);
    final title = winner >= 0
        ? '${okt(_lang, 'wentOut', _okName(winner))}${okeyOut ? ' (${okt(_lang, 'okeyOut')})' : ''}'
        : okt(_lang, 'stockOut');
    final tw = (w / 26).clamp(14.0, 26.0);
    Widget row(int seat) {
      final hand = [...s.hands[seat]]..sort((a, b) {
          final ma = okeyMeaning(a, _okKind), mb = okeyMeaning(b, _okKind);
          return (ma < 0 ? 999 : ma).compareTo(mb < 0 ? 999 : mb);
        });
      final String val;
      if (o != null) {
        final pen = mp != null ? mp[seat] : -finals[seat];
        val = '${okt(_lang, 'penalty')}: $pen';
      } else {
        final pts = mp != null ? mp[seat] : finals[seat];
        val = '${okt(_lang, 'points')}: ${pts > 0 ? '+' : ''}$pts';
      }
      final good = seat == winner || (o == null && (mp != null ? mp[seat] : finals[seat]) > 0);
      return Container(
        margin: const EdgeInsets.symmetric(vertical: 3),
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: seat == winner ? 0.35 : 0.2),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: seat == winner ? _gold : Colors.white12, width: seat == winner ? 2 : 1),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          _okAvatar(seat, 26),
          const SizedBox(width: 6),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Row(children: [
                Flexible(
                  child: Text(_okName(seat),
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
                ),
                if (o != null) ...[
                  const SizedBox(width: 6),
                  Text(o.opened(s, seat) ? okt(_lang, 'opened') : okt(_lang, 'notOpened'),
                      style: TextStyle(color: o.opened(s, seat) ? const Color(0xFF7CF29C) : Colors.white60, fontSize: 11.5, fontWeight: FontWeight.w700)),
                ],
              ]),
              if (hand.isNotEmpty) ...[
                const SizedBox(height: 3),
                Wrap(spacing: 1, runSpacing: 2, children: [for (final t in hand) _okTile(t, tw)]),
              ],
            ]),
          ),
          const SizedBox(width: 6),
          Text(val, style: TextStyle(color: good ? _gold : Colors.white, fontWeight: FontWeight.w900, fontSize: 13.5)),
        ]),
      );
    }

    return ColoredBox(
      color: Colors.black.withValues(alpha: 0.55),
      child: Center(
        child: SingleChildScrollView(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: StudioBoardPanel(
              margin: const EdgeInsets.all(12),
              padding: const EdgeInsets.all(12),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text(okt(_lang, 'handOver'),
                    style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w700, fontSize: 13)),
                const SizedBox(height: 2),
                Text(title,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 19)),
                const SizedBox(height: 8),
                for (var k = 0; k < s.seats; k++) row((me + k) % s.seats),
                const SizedBox(height: 10),
                StudioButton(
                  label: okt(_lang, 'continue'),
                  icon: Icons.arrow_forward_rounded,
                  onPressed: () {
                    _summaryDone = true;
                    _end();
                  },
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  Widget _tileFrame(Widget child) {
    final look = StudioLook.of(context);
    final th = _tileThemeFor(rules);
    return StudioChrome(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 2, 4, 4),
        child: DecoratedBox(
          position: DecorationPosition.foreground,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: look.accent.withValues(alpha: 0.55), width: 1.4),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(22),
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: th.room),
              ),
              child: child,
            ),
          ),
        ),
      ),
    );
  }

  Widget _okeyBuild(BuildContext context) {
    final legal = _okLegal();
    return LayoutBuilder(builder: (context, cons) {
      final w = cons.maxWidth, h = cons.maxHeight;
      final wide = w > h;
      final cols = rules is Okey101Rules ? 13 : 11;
      _syncRack(cols);
      final ts = MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 1.6);
      final rackMax = wide ? math.min(w * 0.72, 1000.0) : w - 8;
      var tw = (rackMax - 16) / cols - 2;
      tw = math.min(tw, ((h * (wide ? 0.32 : 0.25)) / ts - 30) / 2 / rules.tileAspect - 9);
      tw = tw.clamp(18.0, 62.0);
      return Stack(children: [
        Column(children: [
          _okTopBar(),
          Expanded(child: _okTableArea(tw, legal, wide)),
          _okActions(legal),
          if (_cover)
            _CoverCard(
              text: ctx.t('pass_device', {'p': ctx.seatName(_shown)}),
              sub: ctx.t('tap_when_ready'),
              height: (tw * rules.tileAspect + 9) * 2 + 16,
              onTap: () => _set(() => _cover = false),
            )
          else
            _okRack(tw, legal),
          const SizedBox(height: 6),
        ]),
        if (_summary) Positioned.fill(child: _okSummary(w)),
      ]);
    });
  }
}
