import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:intl/intl.dart';
import '../services/ai_service.dart';

const _green = Color(0xFF157A52);
const _ink = Color(0xFF18251F);
const _muted = Color(0xFF78827B);
const _line = Color(0xFFE5EAE5);

class WorkspaceScreen extends StatefulWidget {
  const WorkspaceScreen({super.key});
  @override
  State<WorkspaceScreen> createState() => _WorkspaceScreenState();
}

class _WorkspaceScreenState extends State<WorkspaceScreen> {
  final _api = AiService();
  final _input = TextEditingController();
  final _focus = FocusNode();
  final _scroll = ScrollController();
  Map<String, dynamic>? _config;
  String? _roomId;
  String _page = 'chat';
  String _modelKey = 'economy';
  List<String> _plugins = [];
  bool _busy = false;
  String _draft = '';
  String? _configError;
  int _contextTokens = 0;
  int _lastCharge = 0;
  int _lastTokens = 0;

  User? get _user => FirebaseAuth.instance.currentUser;
  List<Map<String, dynamic>> get _models => ((_config?['models'] as List?) ?? const [])
      .whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();

  @override
  void initState() { super.initState(); _loadConfig(); }
  @override
  void dispose() { _input.dispose(); _focus.dispose(); _scroll.dispose(); super.dispose(); }

  String _money(int amount) => NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0).format(amount);
  void _notify(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message), behavior: SnackBarBehavior.floating,
      backgroundColor: error ? const Color(0xFFB42318) : _green,
    ));
  }

  Future<void> _loadConfig() async {
    try {
      final config = await _api.getConfig();
      if (!mounted) return;
      final models = (config['models'] as List? ?? const []).whereType<Map>().toList();
      setState(() {
        _config = config;
        _configError = null;
        if (!models.any((m) => m['key'] == _modelKey) && models.isNotEmpty) {
          _modelKey = models.first['key']?.toString() ?? 'economy';
        }
      });
    } catch (e) { if (mounted) setState(() => _configError = e.toString()); }
  }

  Future<void> _newRoom() async {
    try {
      final result = await _api.createRoom();
      if (!mounted) return;
      setState(() { _roomId = result['roomId']?.toString(); _page = 'chat'; _modelKey = 'economy'; _plugins = []; _draft = ''; _contextTokens = 0; });
      if (MediaQuery.sizeOf(context).width < 980) Navigator.of(context).maybePop();
      _input.clear();
      _focus.requestFocus();
    } catch (e) { _notify('Ruang baru gagal dibuat: $e', error: true); }
  }

  Future<void> _selectRoom(String id, Map<String, dynamic> room) async {
    setState(() {
      _roomId = id;
      _page = 'chat';
      _draft = '';
      _contextTokens = (room['estimatedContextTokens'] as num?)?.toInt() ?? 0;
      _plugins = (room['plugins'] as List? ?? const []).map((e) => e.toString()).toList();
      final saved = room['model']?.toString();
      for (final model in _models) {
        if (model['key'] == saved || model['id'] == saved) {
          _modelKey = model['key']?.toString() ?? _modelKey;
          break;
        }
      }
    });
  }

  Future<void> _renameRoom(String id, String old) async {
    final controller = TextEditingController(text: old);
    final title = await showDialog<String>(context: context, builder: (context) => AlertDialog(
      title: const Text('Ubah nama chat'),
      content: TextField(controller: controller, autofocus: true, maxLength: 60, decoration: const InputDecoration(hintText: 'Nama ruang'),
        onSubmitted: (v) => Navigator.pop(context, v.trim())),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Batal')),
        FilledButton(onPressed: () => Navigator.pop(context, controller.text.trim()), child: const Text('Simpan')),
      ],
    ));
    controller.dispose();
    if (title == null || title.isEmpty) return;
    try { await _api.renameRoom(id, title); _notify('Nama chat diperbarui.'); }
    catch (e) { _notify('Tidak dapat mengubah nama: $e', error: true); }
  }

  Future<void> _deleteRoom(String id) async {
    final yes = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
      title: const Text('Hapus ruang chat?'),
      content: const Text('Semua pesan pada ruang ini akan dihapus. Tindakan tidak dapat dibatalkan.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Batal')),
        FilledButton(onPressed: () => Navigator.pop(context, true), style: FilledButton.styleFrom(backgroundColor: const Color(0xFFB42318)), child: const Text('Hapus')),
      ],
    ));
    if (yes != true) return;
    try {
      await _api.deleteRoom(id);
      if (_roomId == id && mounted) setState(() { _roomId = null; _draft = ''; });
      _notify('Ruang chat dihapus.');
    } catch (e) { _notify('Ruang belum bisa dihapus: $e', error: true); }
  }

  Future<void> _send() async {
    final message = _input.text.trim();
    if (_busy || message.isEmpty) return;
    if (_models.isEmpty) { _notify('Model belum dikonfigurasi di backend.', error: true); return; }
    var id = _roomId;
    try {
      if (id == null) {
        final room = await _api.createRoom();
        id = room['roomId']?.toString();
        if (id == null) throw StateError('Server tidak mengembalikan ID ruang.');
        if (mounted) setState(() { _roomId = id; _page = 'chat'; });
      }
      final roomRef = FirebaseFirestore.instance.collection('ai_users').doc(_user!.uid).collection('rooms').doc(id);
      final room = await roomRef.get();
      final oldTitle = room.data()?['title']?.toString() ?? 'Chat baru';
      if (oldTitle == 'Chat baru') {
        final title = message.replaceAll(RegExp(r'\s+'), ' ');
        try { await _api.renameRoom(id, title.length > 42 ? title.substring(0, 39) + '…' : title); } catch (_) {}
      }
      final requestId = DateTime.now().microsecondsSinceEpoch.toString() + Random.secure().nextInt(99999999).toString().padLeft(8, '0');
      final model = _modelKey;
      final plugins = List<String>.from(_plugins);
      _input.clear();
      setState(() { _busy = true; _draft = ''; _contextTokens = 0; _lastCharge = 0; _lastTokens = 0; });
      await for (final event in _api.sendMessage(roomId: id, message: message, model: model, requestId: requestId, plugins: plugins)) {
        if (!mounted) return;
        switch (event['type']) {
          case 'started':
            setState(() => _contextTokens = (event['contextTokens'] as num?)?.toInt() ?? 0);
            break;
          case 'token':
            setState(() => _draft += event['text']?.toString() ?? '');
            _scrollToEnd();
            break;
          case 'final':
            setState(() {
              _lastCharge = (event['chargedAmountIdr'] as num?)?.toInt() ?? 0;
              _lastTokens = (event['totalTokens'] as num?)?.toInt() ?? 0;
              _draft = '';
              _busy = false;
            });
            break;
          case 'pending':
            _notify(event['message']?.toString() ?? 'Pemakaian sedang direkonsiliasi.');
            setState(() { _draft = ''; _busy = false; });
            break;
          case 'error':
            _notify(event['message']?.toString() ?? 'Chat gagal diproses.', error: true);
            setState(() { _draft = ''; _busy = false; });
            break;
        }
      }
      if (mounted && _busy) setState(() { _draft = ''; _busy = false; });
    } catch (e) {
      if (mounted) { setState(() { _draft = ''; _busy = false; }); _notify(e.toString(), error: true); }
    }
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.animateTo(_scroll.position.maxScrollExtent, duration: const Duration(milliseconds: 160), curve: Curves.easeOut);
    });
  }

  Future<void> _topUp(int amount) async {
    try {
      final channels = await _api.getPaymentChannels();
      if (!mounted) return;
      if (channels.isEmpty) { _notify('Tidak ada channel pembayaran aktif di merchant TriPay.', error: true); return; }
      final method = await showModalBottomSheet<String>(
        context: context, showDragHandle: true, isScrollControlled: true,
        builder: (context) => SafeArea(child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 7, 18, 22),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Pilih metode pembayaran', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900)),
            const SizedBox(height: 5),
            Text('Paket ' + _money(amount) + ' • channel aktif dari TriPay', style: const TextStyle(color: _muted, fontSize: 12)),
            const SizedBox(height: 10),
            SizedBox(height: min(MediaQuery.sizeOf(context).height * .55, 440), child: ListView.separated(
              itemCount: channels.length, separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final ch = channels[i];
                return ListTile(
                  leading: Container(width: 42, height: 42, decoration: BoxDecoration(color: const Color(0xFFEAF4EE), borderRadius: BorderRadius.circular(13)), child: const Icon(Icons.account_balance_wallet_outlined, color: _green)),
                  title: Text(ch['name']?.toString() ?? ch['code'].toString(), style: const TextStyle(fontWeight: FontWeight.w800)),
                  subtitle: Text(ch['group']?.toString() ?? 'Pembayaran'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => Navigator.pop(context, ch['code']?.toString()),
                );
              },
            )),
          ]),
        )),
      );
      if (method == null || !mounted) return;
      final invoice = await _api.createTopup(amount: amount, method: method, email: _user?.email);
      if (mounted) await showDialog<void>(context: context, builder: (context) => _InvoiceDialog(data: invoice, money: _money));
    } catch (e) { _notify('Gagal membuat tagihan: $e', error: true); }
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 980;
    final sidebar = _sidebar(wide);
    return Scaffold(
      drawer: wide ? null : Drawer(width: 295, child: sidebar),
      body: SafeArea(child: Row(children: [
        if (wide) SizedBox(width: 282, child: sidebar),
        Expanded(child: Column(children: [
          _topBar(wide),
          Expanded(child: switch (_page) {
            'plugins' => _pluginStore(),
            'wallet' => _wallet(),
            'settings' => _settings(),
            _ => _chat(),
          }),
        ])),
      ])),
    );
  }

  Widget _sidebar(bool wide) {
    final email = _user?.email ?? _user?.displayName ?? 'Pengguna';
    return Container(
      decoration: const BoxDecoration(color: Colors.white, border: Border(right: BorderSide(color: _line))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(padding: const EdgeInsets.fromLTRB(18, 20, 14, 20), child: Row(children: [
          Container(width: 40, height: 40, decoration: BoxDecoration(color: _green, borderRadius: BorderRadius.circular(13)), child: const Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 21)),
          const SizedBox(width: 11),
          const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Desa AI', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: _ink)),
            Text('AI workspace', style: TextStyle(fontSize: 11, color: Color(0xFF87918A))),
          ])),
          if (wide) IconButton(tooltip: 'Chat baru', onPressed: _newRoom, icon: const Icon(Icons.edit_square, size: 20)),
        ])),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 13), child: wide
            ? OutlinedButton.icon(onPressed: _newRoom, icon: const Icon(Icons.add_rounded), label: const Text('Chat baru'))
            : FilledButton.icon(onPressed: _newRoom, icon: const Icon(Icons.add_rounded), label: const Text('Chat baru'))),
        const SizedBox(height: 15),
        _nav(Icons.chat_bubble_outline_rounded, 'Chat AI', 'chat'),
        _nav(Icons.extension_outlined, 'Plugin store', 'plugins'),
        _nav(Icons.account_balance_wallet_outlined, 'Saldo & top-up', 'wallet'),
        _nav(Icons.tune_rounded, 'Pengaturan', 'settings'),
        const Padding(padding: EdgeInsets.fromLTRB(20, 24, 20, 10), child: Text('RIWAYAT CHAT', style: TextStyle(fontSize: 10, letterSpacing: 1.15, color: Color(0xFF9AA19C), fontWeight: FontWeight.w900))),
        Expanded(child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance.collection('ai_users').doc(_user!.uid).collection('rooms').orderBy('updatedAt', descending: true).limit(100).snapshots(),
          builder: (context, snapshot) {
            if (snapshot.hasError) return const Padding(padding: EdgeInsets.all(16), child: Text('Riwayat belum dapat dimuat.', style: TextStyle(fontSize: 12, color: _muted)));
            if (!snapshot.hasData) return const Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)));
            final docs = snapshot.data!.docs.where((d) => d.data()['deleted'] != true).toList();
            if (docs.isEmpty) return const Padding(padding: EdgeInsets.all(20), child: Text('Chat Anda akan tampil di sini.', style: TextStyle(color: _muted, fontSize: 12)));
            final now = DateTime.now();
            final today = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
            final yesterday = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
            final week = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
            final older = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
            for (final doc in docs) {
              final data = doc.data();
              final stamp = data['updatedAt'] ?? data['createdAt'];
              final date = stamp is Timestamp ? stamp.toDate() : now;
              final dateOnly = DateTime(date.year, date.month, date.day);
              final todayOnly = DateTime(now.year, now.month, now.day);
              final days = todayOnly.difference(dateOnly).inDays;
              if (days <= 0) {
                today.add(doc);
              } else if (days == 1) {
                yesterday.add(doc);
              } else if (days <= 7) {
                week.add(doc);
              } else {
                older.add(doc);
              }
            }
            final children = <Widget>[];
            void addGroup(String label, List<QueryDocumentSnapshot<Map<String, dynamic>>> group) {
              if (group.isEmpty) return;
              children.add(Padding(
                padding: const EdgeInsets.fromLTRB(13, 12, 10, 5),
                child: Text(label, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Color(0xFF9AA19C))),
              ));
              children.addAll(group.map(_roomRow));
            }
            addGroup('HARI INI', today);
            addGroup('KEMARIN', yesterday);
            addGroup('7 HARI TERAKHIR', week);
            addGroup('SEBELUMNYA', older);
            return ListView(padding: const EdgeInsets.symmetric(horizontal: 8), children: children);
          },
        )),
        const Divider(height: 1, color: _line),
        Padding(padding: const EdgeInsets.all(13), child: Row(children: [
          CircleAvatar(radius: 18, backgroundColor: const Color(0xFFEAF4EE), child: Text((email.isEmpty ? 'D' : email[0]).toUpperCase(), style: const TextStyle(color: _green, fontWeight: FontWeight.w900))),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(_user?.displayName ?? 'Akun Desa AI', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
            Text(email, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10, color: _muted)),
          ])),
          IconButton(tooltip: 'Keluar', onPressed: _signOut, icon: const Icon(Icons.logout_rounded, size: 18)),
        ])),
      ]),
    );
  }

  Widget _roomRow(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    final title = data['title']?.toString() ?? 'Chat baru';
    final active = _roomId == doc.id && _page == 'chat';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(children: [
        Expanded(child: Material(
          color: active ? const Color(0xFFEAF4EE) : Colors.transparent,
          borderRadius: BorderRadius.circular(11),
          child: InkWell(
            borderRadius: BorderRadius.circular(11),
            onTap: () {
              _selectRoom(doc.id, data);
              if (MediaQuery.sizeOf(context).width < 980) Navigator.of(context).maybePop();
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              child: Row(children: [
                Icon(Icons.chat_bubble_outline_rounded, size: 16, color: active ? _green : _muted),
                const SizedBox(width: 10),
                Expanded(child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: active ? _ink : const Color(0xFF5D675F),
                    fontWeight: active ? FontWeight.w800 : FontWeight.w500))),
              ]),
            ),
          ),
        )),
        PopupMenuButton<String>(
          tooltip: 'Opsi chat', padding: EdgeInsets.zero, iconSize: 18,
          onSelected: (value) {
            if (value == 'rename') _renameRoom(doc.id, title);
            if (value == 'delete') _deleteRoom(doc.id);
          },
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'rename', child: Row(children: [Icon(Icons.edit_outlined, size: 17), SizedBox(width: 10), Text('Ubah nama')])),
            PopupMenuItem(value: 'delete', child: Row(children: [Icon(Icons.delete_outline, size: 17, color: Color(0xFFB42318)), SizedBox(width: 10), Text('Hapus ruang')])),
          ],
        ),
      ]),
    );
  }

  Widget _nav(IconData icon, String title, String id) {
    final active = _page == id;
    return Padding(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2), child: Material(
      color: active ? const Color(0xFFEAF4EE) : Colors.transparent, borderRadius: BorderRadius.circular(12),
      child: InkWell(borderRadius: BorderRadius.circular(12), onTap: () {
          setState(() => _page = id);
          if (MediaQuery.sizeOf(context).width < 980) Navigator.of(context).maybePop();
        },
        child: Padding(padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12), child: Row(children: [
          Icon(icon, color: active ? _green : const Color(0xFF657069), size: 19), const SizedBox(width: 12),
          Text(title, style: TextStyle(fontWeight: active ? FontWeight.w800 : FontWeight.w600, fontSize: 13, color: active ? _ink : const Color(0xFF66716A))),
        ])),
      ),
    ));
  }

  Widget _topBar(bool wide) {
    final title = switch (_page) { 'plugins' => 'Plugin store', 'wallet' => 'Saldo & top-up', 'settings' => 'Pengaturan', _ => 'Chat AI' };
    return Container(height: 68, padding: const EdgeInsets.symmetric(horizontal: 18),
      decoration: const BoxDecoration(color: Color(0xFFF7F8F6), border: Border(bottom: BorderSide(color: _line))),
      child: Row(children: [
        if (!wide) Builder(builder: (context) => IconButton(onPressed: () => Scaffold.of(context).openDrawer(), icon: const Icon(Icons.menu_rounded, color: _ink))),
        if (_page != 'chat' || wide) Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: _ink)),
        if (_page == 'chat') ...[
          const SizedBox(width: 10),
          Flexible(child: Container(constraints: const BoxConstraints(maxWidth: 245), padding: const EdgeInsets.symmetric(horizontal: 9),
            decoration: BoxDecoration(color: Colors.white, border: Border.all(color: _line), borderRadius: BorderRadius.circular(13)),
            child: DropdownButtonHideUnderline(child: DropdownButton<String>(
              isExpanded: true, value: _models.any((m) => m['key'] == _modelKey) ? _modelKey : null, icon: const Icon(Icons.expand_more_rounded, size: 18),
              hint: const Text('Pilih model', style: TextStyle(fontSize: 12)),
              items: _models.map((m) => DropdownMenuItem<String>(value: m['key']?.toString(), child: Row(children: [
                Icon(m['mode'] == 'premium' ? Icons.auto_awesome_rounded : Icons.bolt_rounded, color: m['mode'] == 'premium' ? const Color(0xFF7B61C9) : _green, size: 17),
                const SizedBox(width: 7), Expanded(child: Text(m['name']?.toString() ?? 'Model', overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800))),
              ]))).toList(),
              onChanged: _busy ? null : (v) { if (v != null) setState(() => _modelKey = v); },
            )),
          )),
        ],
        const Spacer(),
        StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance.collection('users').doc(_user!.uid).snapshots(),
          builder: (context, snapshot) {
            final balance = (snapshot.data?.data()?['balance'] as num?)?.toInt() ?? 0;
            return InkWell(borderRadius: BorderRadius.circular(13), onTap: () => setState(() => _page = 'wallet'),
              child: Container(padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
                decoration: BoxDecoration(color: Colors.white, border: Border.all(color: _line), borderRadius: BorderRadius.circular(13)),
                child: Row(children: [const Icon(Icons.account_balance_wallet_outlined, size: 17, color: _green), const SizedBox(width: 6),
                  Text(_money(balance), style: const TextStyle(fontWeight: FontWeight.w900, color: _ink, fontSize: 12))])),
            );
          }),
        IconButton(tooltip: 'Pengaturan', onPressed: () => setState(() => _page = 'settings'), icon: const Icon(Icons.account_circle_outlined, color: _muted)),
      ]),
    );
  }

  Widget _chat() {
    if (_configError != null && _config == null) return _error(_configError!);
    return Column(children: [
      if (_contextTokens >= 25000) Container(width: double.infinity, margin: const EdgeInsets.fromLTRB(18, 12, 18, 0), padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: const Color(0xFFFFF7E6), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFF5D48C))),
        child: const Row(children: [Icon(Icons.warning_amber_rounded, color: Color(0xFF9A6700), size: 20), SizedBox(width: 10),
          Expanded(child: Text('Memori chat hampir penuh. Buka ruang baru agar biaya input terkendali.', style: TextStyle(fontSize: 12, height: 1.4, color: Color(0xFF7B5514))))])),
      Expanded(child: _roomId == null ? _welcome() : StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance.collection('ai_users').doc(_user!.uid).collection('rooms').doc(_roomId!)
          .collection('messages').orderBy('createdAt').limit(200).snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) return _error('Pesan belum dapat dimuat. Periksa Firestore Rules.');
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator(strokeWidth: 2));
          final messages = snapshot.data!.docs.map((d) => d.data()).toList();
          if (messages.isEmpty && !_busy) return _welcome();
          return ListView.builder(controller: _scroll, padding: const EdgeInsets.fromLTRB(18, 22, 18, 30),
            itemCount: messages.length + (_busy ? 1 : 0), itemBuilder: (context, i) {
              if (i >= messages.length) return _bubble('assistant', _draft, streaming: true);
              final m = messages[i];
              return _bubble(m['role']?.toString() ?? 'assistant', m['text']?.toString() ?? '');
            });
        },
      )),
      if (_lastCharge > 0) Padding(padding: const EdgeInsets.only(bottom: 5), child: Text(
        'Pemakaian terakhir: $_lastTokens token • ' + _money(_lastCharge), style: const TextStyle(fontSize: 10, color: _muted))),
      _composer(),
    ]);
  }

  Widget _welcome() => Center(child: SingleChildScrollView(padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 30),
    child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 760), child: Column(children: [
      Container(width: 64, height: 64, decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xFF176647), Color(0xFF3C9D73)]), borderRadius: BorderRadius.circular(22)),
        child: const Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 30)),
      const SizedBox(height: 22),
      const Text('Apa yang bisa kita kerjakan?', textAlign: TextAlign.center, style: TextStyle(fontSize: 27, fontWeight: FontWeight.w900, color: _ink, letterSpacing: -.6)),
      const SizedBox(height: 9),
      const Text('Tanya, rancang, pelajari, atau pecahkan masalah—mulai dari satu pesan.', textAlign: TextAlign.center,
        style: TextStyle(color: _muted, fontSize: 14, height: 1.5)),
      const SizedBox(height: 26),
      Wrap(spacing: 12, runSpacing: 12, alignment: WrapAlignment.center, children: [
        _suggest(Icons.lightbulb_outline_rounded, 'Cari ide', 'Bantu saya menemukan ide bisnis digital', const Color(0xFFE8F5ED)),
        _suggest(Icons.code_rounded, 'Buat kode', 'Jelaskan dan perbaiki kode Flutter saya', const Color(0xFFEAF0FF)),
        _suggest(Icons.menu_book_outlined, 'Belajar', 'Ajari saya konsep baru langkah demi langkah', const Color(0xFFF5EDFF)),
        _suggest(Icons.edit_note_rounded, 'Tulis', 'Bantu saya menyusun rencana yang jelas', const Color(0xFFFFF0E4)),
      ]),
      const SizedBox(height: 22),
      const Text('Jawaban AI bisa keliru. Periksa fakta penting sebelum mengambil keputusan.', textAlign: TextAlign.center,
        style: TextStyle(color: Color(0xFFA0A7A2), fontSize: 10)),
    ]))));

  Widget _suggest(IconData icon, String title, String prompt, Color tint) => SizedBox(width: 260,
    child: InkWell(borderRadius: BorderRadius.circular(17), onTap: () { _input.text = prompt; _focus.requestFocus(); },
      child: Container(padding: const EdgeInsets.all(15), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(17), border: Border.all(color: _line)),
        child: Row(children: [
          Container(width: 39, height: 39, decoration: BoxDecoration(color: tint, borderRadius: BorderRadius.circular(13)), child: Icon(icon, color: const Color(0xFF45534A), size: 20)),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w900, color: _ink, fontSize: 12)),
            const SizedBox(height: 4), Text(prompt, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, height: 1.4, color: _muted)),
          ])),
        ]))));

  Widget _bubble(String role, String text, {bool streaming = false}) {
    final isUser = role == 'user';
    final body = text.isEmpty && streaming ? 'Sedang menyiapkan jawaban…' : text;
    return Padding(padding: const EdgeInsets.only(bottom: 22), child: Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 850), child: Row(
        crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          if (!isUser) Container(width: 30, height: 30, margin: const EdgeInsets.only(right: 12, top: 2),
            decoration: BoxDecoration(color: const Color(0xFFE4F2E9), borderRadius: BorderRadius.circular(11)),
            child: const Icon(Icons.auto_awesome_rounded, size: 16, color: _green)),
          Flexible(child: Container(constraints: BoxConstraints(maxWidth: min(MediaQuery.sizeOf(context).width * .76, 760)),
            padding: EdgeInsets.symmetric(horizontal: isUser ? 16 : 0, vertical: isUser ? 12 : 3),
            decoration: BoxDecoration(color: isUser ? const Color(0xFFEDF2ED) : Colors.transparent, borderRadius: BorderRadius.circular(18)),
            child: isUser ? SelectableText(body, style: const TextStyle(fontSize: 14, color: _ink, height: 1.55))
              : (body.isEmpty ? const SizedBox(width: 90, child: LinearProgressIndicator(minHeight: 2))
              : MarkdownBody(data: body, selectable: true, styleSheet: MarkdownStyleSheet(
                p: const TextStyle(fontSize: 14, color: _ink, height: 1.65),
                h1: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: _ink),
                h2: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: _ink),
                h3: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: _ink),
                code: const TextStyle(fontFamily: 'monospace', fontSize: 12, color: Color(0xFF246647)),
                codeblockDecoration: BoxDecoration(color: const Color(0xFF19241E), borderRadius: BorderRadius.circular(13)),
                codeblockPadding: const EdgeInsets.all(14),
                blockquoteDecoration: const BoxDecoration(border: Border(left: BorderSide(color: _green, width: 3))),
                blockquotePadding: const EdgeInsets.only(left: 12),
              ))))),
        ])) ));
  }

  Widget _composer() {
    Map<String, dynamic>? model;
    for (final item in _models) { if (item['key'] == _modelKey) { model = item; break; } }
    final inputPrice = (model?['inputIdrPer1000'] as num?)?.toInt() ?? 0;
    final outputPrice = (model?['outputIdrPer1000'] as num?)?.toInt() ?? 0;
    final compact = MediaQuery.sizeOf(context).width < 600;
    return Container(padding: EdgeInsets.fromLTRB(compact ? 12 : 22, 10, compact ? 12 : 22, 13), color: const Color(0xFFF7F8F6),
      child: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 850), child: Column(children: [
        Container(padding: const EdgeInsets.fromLTRB(14, 8, 9, 8),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(22), border: Border.all(color: const Color(0xFFDDE5DD)),
            boxShadow: const [BoxShadow(color: Color(0x08000000), blurRadius: 18, offset: Offset(0, 4))]),
          child: Column(children: [
            TextField(controller: _input, focusNode: _focus, minLines: 1, maxLines: 5, maxLength: 8000,
              textCapitalization: TextCapitalization.sentences, onSubmitted: (_) { if (!_busy) _send(); },
              decoration: const InputDecoration(hintText: 'Kirim pesan ke Desa AI…', border: InputBorder.none, filled: false,
                contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 6), counterText: '')),
            Row(children: [
              IconButton(tooltip: 'Plugin', visualDensity: VisualDensity.compact, onPressed: () => setState(() => _page = 'plugins'),
                icon: Icon(Icons.extension_outlined, color: _plugins.isEmpty ? _muted : _green, size: 19)),
              if (_plugins.contains('web_search')) Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                decoration: BoxDecoration(color: const Color(0xFFE7F4EB), borderRadius: BorderRadius.circular(8)),
                child: const Text('Web aktif', style: TextStyle(color: _green, fontSize: 10, fontWeight: FontWeight.w800))),
              const Spacer(),
              FilledButton(onPressed: _busy ? null : _send,
                style: FilledButton.styleFrom(minimumSize: const Size(42, 42), padding: const EdgeInsets.all(10), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                child: _busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.arrow_upward_rounded, size: 21)),
            ]),
          ]),
        ),
        const SizedBox(height: 9),
        Wrap(alignment: WrapAlignment.center, spacing: 7, children: [
          Text('Input ' + _money(inputPrice) + '/1.000 token', style: const TextStyle(fontSize: 10, color: _muted)),
          const Text('•', style: TextStyle(fontSize: 10, color: Color(0xFFBAC0BB))),
          Text('Output ' + _money(outputPrice) + '/1.000 token', style: const TextStyle(fontSize: 10, color: _muted)),
          const Text('•', style: TextStyle(fontSize: 10, color: Color(0xFFBAC0BB))),
          const Text('Maks. 30.000 token per ruang', style: TextStyle(fontSize: 10, color: _muted)),
        ]),
      ]))));
  }

  Widget _pluginStore() {
    final plugins = ((_config?['plugins'] as List?) ?? const []).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
    return ListView(padding: const EdgeInsets.all(22), children: [
      const Text('Plugin yang Anda butuhkan', style: TextStyle(fontSize: 25, fontWeight: FontWeight.w900, color: _ink)),
      const SizedBox(height: 8),
      const Text('Aktifkan hanya alat yang diperlukan. Plugin yang belum memiliki integrasi resmi tetap terkunci.', style: TextStyle(color: _muted, height: 1.5)),
      const SizedBox(height: 20),
      ...plugins.map((plugin) {
        final id = plugin['id']?.toString() ?? '';
        final available = plugin['available'] == true;
        final icon = switch (id) {
          'web_search' => Icons.travel_explore_rounded,
          'shipment_tracking' => Icons.local_shipping_outlined,
          'ecommerce_search' => Icons.shopping_bag_outlined,
          'image_generation' => Icons.image_outlined,
          _ => Icons.extension_outlined,
        };
        return Container(margin: const EdgeInsets.only(bottom: 12), padding: const EdgeInsets.all(17),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(19), border: Border.all(color: _line)),
          child: Row(children: [
            Container(width: 47, height: 47, decoration: BoxDecoration(color: available ? const Color(0xFFE9F5ED) : const Color(0xFFF0F2F0), borderRadius: BorderRadius.circular(15)),
              child: Icon(icon, color: available ? _green : const Color(0xFF939B95), size: 23)),
            const SizedBox(width: 14),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Flexible(child: Text(plugin['name']?.toString() ?? 'Plugin', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14))),
                if (!available) const Padding(padding: EdgeInsets.only(left: 7), child: Text('Segera hadir', style: TextStyle(fontSize: 9, color: _muted, fontWeight: FontWeight.w800))),
              ]),
              const SizedBox(height: 5), Text(plugin['description']?.toString() ?? '', style: const TextStyle(fontSize: 12, height: 1.4, color: _muted)),
            ])),
            Switch(value: available && _plugins.contains(id), onChanged: available ? (value) {
              setState(() { if (value) { if (!_plugins.contains(id)) _plugins.add(id); } else { _plugins.remove(id); } });
              _notify(value ? 'Browsing ditambahkan untuk pesan berikutnya.' : 'Browsing dinonaktifkan.');
            } : null, activeColor: _green),
          ]),
        );
      }),
      OutlinedButton.icon(onPressed: () => setState(() => _page = 'chat'), icon: const Icon(Icons.arrow_back_rounded), label: const Text('Kembali ke chat')),
    ]);
  }

  Widget _wallet() {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.collection('users').doc(_user!.uid).snapshots(),
      builder: (context, snapshot) {
        final balance = (snapshot.data?.data()?['balance'] as num?)?.toInt() ?? 0;
        return ListView(padding: const EdgeInsets.all(22), children: [
          const Text('Dompet AI', style: TextStyle(fontSize: 25, fontWeight: FontWeight.w900, color: _ink)),
          const SizedBox(height: 8), const Text('Saldo dipotong oleh server berdasarkan pemakaian token provider.', style: TextStyle(color: _muted, height: 1.5)),
          const SizedBox(height: 20),
          Container(padding: const EdgeInsets.all(23), decoration: BoxDecoration(gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
            colors: [Color(0xFF164832), Color(0xFF207B54)]), borderRadius: BorderRadius.circular(24)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Row(children: [Icon(Icons.account_balance_wallet_outlined, color: Colors.white70, size: 20), SizedBox(width: 8),
                Text('SALDO TERSEDIA', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w800, fontSize: 11, letterSpacing: 1.1))]),
              const SizedBox(height: 11), Text(_money(balance), style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w900)),
              const SizedBox(height: 9), const Text('Biaya mengikuti model aktif. Tidak ada potongan jika permintaan gagal sebelum diproses provider.',
                style: TextStyle(color: Colors.white70, fontSize: 12, height: 1.45)),
            ]),
          ),
          const SizedBox(height: 25), const Text('Pilih paket top-up', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900)), const SizedBox(height: 12),
          GridView.count(crossAxisCount: MediaQuery.sizeOf(context).width > 720 ? 4 : 2, shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(), mainAxisSpacing: 12, crossAxisSpacing: 12, childAspectRatio: 1.35,
            children: [10000, 25000, 50000, 100000].map((amount) => InkWell(borderRadius: BorderRadius.circular(18), onTap: () => _topUp(amount),
              child: Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), border: Border.all(color: _line)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
                  const Icon(Icons.add_card_rounded, color: _green, size: 23), const SizedBox(height: 10),
                  Text(_money(amount), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: _ink)),
                  const SizedBox(height: 3), const Text('Sekali top-up', style: TextStyle(color: _muted, fontSize: 11)),
                ])))).toList()),
          const SizedBox(height: 20),
          const _InfoCard(icon: Icons.verified_user_outlined, title: 'Pembayaran aman', body: 'Saldo masuk setelah callback TriPay cocok dengan invoice dan signature terverifikasi.'),
          const SizedBox(height: 10), const _InfoCard(icon: Icons.receipt_long_outlined, title: 'Ledger pemakaian', body: 'Debit, kredit, token, dan rekonsiliasi dicatat untuk audit.'),
        ]);
      },
    );
  }

  Widget _settings() => ListView(padding: const EdgeInsets.all(22), children: [
    const Text('Pengaturan akun', style: TextStyle(fontSize: 25, fontWeight: FontWeight.w900, color: _ink)),
    const SizedBox(height: 8), const Text('Kelola akun dan keamanan penggunaan.', style: TextStyle(color: _muted)),
    const SizedBox(height: 20),
    Container(padding: const EdgeInsets.all(19), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), border: Border.all(color: _line)),
      child: Row(children: [
        CircleAvatar(radius: 25, backgroundColor: const Color(0xFFEAF4EE), child: Text((_user?.email?.isNotEmpty == true ? _user!.email![0] : 'D').toUpperCase(),
          style: const TextStyle(color: _green, fontWeight: FontWeight.w900, fontSize: 18))),
        const SizedBox(width: 13), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(_user?.displayName ?? 'Pengguna Desa AI', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14)),
          Text(_user?.email ?? 'Email tidak tersedia', style: const TextStyle(color: _muted, fontSize: 12)),
        ])), const Icon(Icons.verified_user_outlined, color: _green),
      ])),
    const SizedBox(height: 12),
    const _InfoCard(icon: Icons.lock_outline_rounded, title: 'Kunci API di server', body: 'Kunci provider tidak ada di Flutter. Endpoint chat memakai token autentikasi Firebase.'),
    const SizedBox(height: 12),
    const _InfoCard(icon: Icons.privacy_tip_outlined, title: 'Privasi ruang chat', body: 'Pesan hanya bisa dibaca pemilik akun. Pesan dan saldo ditulis oleh server.'),
    const SizedBox(height: 22),
    OutlinedButton.icon(onPressed: _signOut, icon: const Icon(Icons.logout_rounded), label: const Text('Keluar dari akun')),
    const SizedBox(height: 20), const Text('Desa AI • build awal', textAlign: TextAlign.center, style: TextStyle(color: Color(0xFFA0A7A2), fontSize: 11)),
  ]);

  Widget _error(String message) => Center(child: Padding(padding: const EdgeInsets.all(25), child: Column(mainAxisSize: MainAxisSize.min, children: [
    const Icon(Icons.cloud_off_rounded, color: Color(0xFFB42318), size: 42), const SizedBox(height: 13),
    const Text('Layanan belum siap', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18)), const SizedBox(height: 8),
    Text(message, textAlign: TextAlign.center, style: const TextStyle(color: _muted, height: 1.4)), const SizedBox(height: 15),
    OutlinedButton.icon(onPressed: _loadConfig, icon: const Icon(Icons.refresh_rounded), label: const Text('Coba lagi')),
  ])));

  Future<void> _signOut() async {
    final ok = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
      title: const Text('Keluar dari Desa AI?'), content: const Text('Anda perlu masuk kembali untuk membuka riwayat chat.'),
      actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Batal')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Keluar'))]));
    if (ok == true) await FirebaseAuth.instance.signOut();
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.icon, required this.title, required this.body});
  final IconData icon; final String title; final String body;
  @override
  Widget build(BuildContext context) => Container(padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(17), border: Border.all(color: _line)),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(width: 38, height: 38, decoration: BoxDecoration(color: const Color(0xFFEAF4EE), borderRadius: BorderRadius.circular(12)), child: Icon(icon, color: _green, size: 20)),
      const SizedBox(width: 12), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13)), const SizedBox(height: 5),
        Text(body, style: const TextStyle(color: _muted, fontSize: 12, height: 1.5)),
      ])),
    ]));
}

class _InvoiceDialog extends StatelessWidget {
  const _InvoiceDialog({required this.data, required this.money});
  final Map<String, dynamic> data; final String Function(int) money;
  @override
  Widget build(BuildContext context) {
    final amount = (data['total_amount'] as num?)?.toInt() ?? 0;
    final code = data['payment_code']?.toString() ?? '';
    final qr = data['qr_url']?.toString() ?? '';
    final reference = data['reference']?.toString() ?? '-';
    return AlertDialog(title: const Text('Tagihan top-up dibuat'),
      content: SizedBox(width: 390, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(money(amount), style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: _green)),
        const SizedBox(height: 6),
        const Text('Selesaikan pembayaran dengan channel yang dipilih. Saldo masuk setelah callback terverifikasi.', textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12, color: _muted, height: 1.45)),
        if (qr.isNotEmpty) ...[const SizedBox(height: 15), Image.network(qr, width: 190, height: 190, fit: BoxFit.contain,
          errorBuilder: (_, __, ___) => const Icon(Icons.qr_code_2_rounded, size: 100, color: _muted))],
        if (code.isNotEmpty) ...[const SizedBox(height: 12), SelectableText(code, textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, letterSpacing: 1.2)), const SizedBox(height: 5),
          const Text('Kode bayar / Virtual Account', style: TextStyle(color: _muted, fontSize: 11))],
        const SizedBox(height: 12), SelectableText('Referensi: ' + reference, style: const TextStyle(color: _muted, fontSize: 11)),
      ]))),
      actions: [FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Selesai'))]);
  }
}
