import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:flutter_tts/flutter_tts.dart';
import 'package:translator/translator.dart';

void main() => runApp(const TongTongApp());

// 앱 없는 상대가 QR을 찍으면 열리는 웹 버전 주소 (같은 방에 연결됨)
const webBase = 'https://deonaeum-1.github.io/tongtong/';

// ---------- 민트 프렌들리 팔레트 ----------
class C {
  static const bg = Color(0xFFF0FBF7);
  static const card = Colors.white;
  static const primary = Color(0xFF10B981);
  static const primary2 = Color(0xFF0EA5A3);
  static const ink = Color(0xFF134E4A);
  static const sub = Color(0xFF5B8578);
  static const hint = Color(0xFF7AA396);
  static const line = Color(0xFFD9F2E9);
  static const grad = LinearGradient(
      colors: [primary, primary2],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight);
}

// ---------- 언어 정보 ----------
const langs = <String, Map<String, String>>{
  'ko': {'label': '한국어', 'locale': 'ko-KR', 'stt': 'ko_KR'},
  'en': {'label': 'English', 'locale': 'en-US', 'stt': 'en_US'},
  'ja': {'label': '日本語', 'locale': 'ja-JP', 'stt': 'ja_JP'},
  'zh': {'label': '中文', 'locale': 'zh-CN', 'stt': 'zh_CN'},
  'es': {'label': 'Español', 'locale': 'es-ES', 'stt': 'es_ES'},
  'fr': {'label': 'Français', 'locale': 'fr-FR', 'stt': 'fr_FR'},
  'vi': {'label': 'Tiếng Việt', 'locale': 'vi-VN', 'stt': 'vi_VN'},
  'th': {'label': 'ไทย', 'locale': 'th-TH', 'stt': 'th_TH'},
};

const uiText = <String, Map<String, String>>{
  'ko': {
    'tagline': '서로의 말을 실시간으로 통역해요',
    'pickLang': '내 언어를 골라주세요',
    'newRoom': '새 대화 만들기',
    'joinRoom': '코드로 참가하기',
    'enterCode': '상대에게 받은 코드 입력',
    'waiting': '상대 연결을 기다리는 중…',
    'shareCode': '상대에게 이 코드를 알려주세요',
    'scanHint': '앱이 없어도 돼요! 상대가 카메라로\n이 QR을 찍으면 바로 연결돼요',
    'connected': '연결됨',
    'connecting': '연결 중…',
    'typeOrMic': '입력하거나 🎤를 누르고 말해주세요',
    'listening': '듣는 중… 말이 끝나면 자동 전송돼요',
    'partner': '상대',
  },
  'en': {
    'tagline': 'We translate for each other in real time',
    'pickLang': 'Choose your language',
    'newRoom': 'Start a new chat',
    'joinRoom': 'Join with a code',
    'enterCode': 'Enter the code you received',
    'waiting': 'Waiting for the other person…',
    'shareCode': 'Share this code with the other person',
    'scanHint': 'No app needed! The other person just\nscans this QR with their camera',
    'connected': 'Connected',
    'connecting': 'Connecting…',
    'typeOrMic': 'Type, or tap 🎤 and speak',
    'listening': 'Listening… sends automatically when you pause',
    'partner': 'Partner',
  },
};

String tr(String lang, String key) =>
    uiText[lang]?[key] ?? uiText['en']![key] ?? key;

// ---------- 무료 번역 (구글 무료 엔진 → 실패 시 MyMemory) ----------
final _gt = GoogleTranslator();
Future<String> translateText(String text, String from, String to) async {
  if (from == to) return text;
  try {
    final r = await _gt.translate(text, from: from, to: to);
    return r.text;
  } catch (_) {
    try {
      final u = Uri.parse(
          'https://api.mymemory.translated.net/get?q=${Uri.encodeComponent(text)}&langpair=$from|$to');
      final res = await http.get(u).timeout(const Duration(seconds: 8));
      final j = jsonDecode(res.body);
      return (j['responseData']?['translatedText'] as String?) ?? text;
    } catch (_) {
      return text;
    }
  }
}

// ---------- 로고: 마주 보는 두 사람 + 통TONG ----------
class TongLogo extends StatelessWidget {
  final double size;
  const TongLogo({super.key, this.size = 34});
  @override
  Widget build(BuildContext context) {
    final person = SvgPicture.asset('assets/person.svg', height: size * 1.5);
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        person,
        const SizedBox(width: 6),
        ShaderMask(
          shaderCallback: (b) => C.grad.createShader(b),
          child: Text('통TONG',
              style: TextStyle(
                  fontSize: size,
                  fontWeight: FontWeight.w800,
                  color: Colors.white)),
        ),
        const SizedBox(width: 6),
        Transform.flip(flipX: true, child: person),
      ],
    );
  }
}

class TongTongApp extends StatelessWidget {
  const TongTongApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '통TONG',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.light,
        scaffoldBackgroundColor: C.bg,
        colorScheme:
            ColorScheme.fromSeed(seedColor: C.primary, brightness: Brightness.light),
        useMaterial3: true,
        textTheme: Typography.blackMountainView
            .apply(bodyColor: C.ink, displayColor: C.ink),
      ),
      home: const SetupScreen(),
    );
  }
}

// ---------- 1. 시작 화면 ----------
class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key});
  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  String myLang = 'ko';
  final codeCtl = TextEditingController();

  void _go(String room, bool isHost) {
    Navigator.of(context).push(MaterialPageRoute(
        builder: (_) =>
            ChatScreen(myLang: myLang, room: room, isHost: isHost)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const TongLogo(size: 36),
                const SizedBox(height: 10),
                Text(tr(myLang, 'tagline'),
                    style: const TextStyle(color: C.sub)),
                const SizedBox(height: 30),
                Text(tr(myLang, 'pickLang'),
                    style: const TextStyle(color: C.sub)),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    color: C.card,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: C.line),
                    boxShadow: [
                      BoxShadow(
                          color: const Color(0xFF105A50).withOpacity(.06),
                          blurRadius: 10,
                          offset: const Offset(0, 3))
                    ],
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: myLang,
                      isExpanded: true,
                      dropdownColor: C.card,
                      style: const TextStyle(color: C.ink, fontSize: 16),
                      items: langs.entries
                          .map((e) => DropdownMenuItem(
                              value: e.key, child: Text(e.value['label']!)))
                          .toList(),
                      onChanged: (v) => setState(() => myLang = v ?? 'ko'),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: C.grad,
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        BoxShadow(
                            color: C.primary.withOpacity(.35),
                            blurRadius: 14,
                            offset: const Offset(0, 5))
                      ],
                    ),
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                          padding: const EdgeInsets.all(16),
                          backgroundColor: Colors.transparent,
                          shadowColor: Colors.transparent),
                      onPressed: () {
                        const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
                        final rnd = Random();
                        final room = List.generate(
                            5, (_) => chars[rnd.nextInt(chars.length)]).join();
                        _go(room, true);
                      },
                      child: Text(tr(myLang, 'newRoom'),
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w700)),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: codeCtl,
                  textCapitalization: TextCapitalization.characters,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      letterSpacing: 4, fontSize: 18, color: C.ink),
                  decoration: InputDecoration(
                    hintText: tr(myLang, 'enterCode'),
                    hintStyle: const TextStyle(
                        color: C.hint, fontSize: 14, letterSpacing: 0),
                    filled: true,
                    fillColor: C.card,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(color: C.line)),
                    enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(color: C.line)),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.all(14),
                        foregroundColor: C.primary2,
                        side: const BorderSide(color: C.primary2)),
                    onPressed: () {
                      final c = codeCtl.text.trim().toUpperCase();
                      if (c.length >= 4) _go(c, false);
                    },
                    child: Text(tr(myLang, 'joinRoom'),
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------- 2. 채팅 화면 ----------
class Msg {
  final String text;
  final String? orig;
  final bool mine;
  Msg(this.text, this.orig, this.mine);
}

class ChatScreen extends StatefulWidget {
  final String myLang;
  final String room;
  final bool isHost;
  const ChatScreen(
      {super.key,
      required this.myLang,
      required this.room,
      required this.isHost});
  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  late final String myId;
  late final String topic;
  MqttServerClient? client;
  String? peerLang;
  bool mqttOk = false;
  bool saidHello = false;

  final msgs = <Msg>[];
  final textCtl = TextEditingController();
  final scrollCtl = ScrollController();

  final speech = stt.SpeechToText();
  bool speechReady = false;
  bool listening = false;
  String partial = '';

  final tts = FlutterTts();

  @override
  void initState() {
    super.initState();
    myId = DateTime.now().microsecondsSinceEpoch.toRadixString(36) +
        Random().nextInt(9999).toString();
    topic = 'tongtong2026/${widget.room}';
    _initMqtt();
    _initSpeech();
  }

  // ----- MQTT -----
  Future<void> _initMqtt() async {
    final c = MqttServerClient.withPort('broker.emqx.io', 'tt_$myId', 1883);
    c.keepAlivePeriod = 30;
    c.autoReconnect = true;
    c.onConnected = () {
      setState(() => mqttOk = true);
      c.subscribe(topic, MqttQos.atLeastOnce);
      _pub({'type': 'hello', 'lang': widget.myLang});
    };
    c.onDisconnected = () => setState(() => mqttOk = false);
    try {
      await c.connect();
    } catch (_) {
      final w = MqttServerClient.withPort(
          'wss://broker.emqx.io/mqtt', 'tt_$myId', 8084);
      w.useWebSocket = true;
      w.keepAlivePeriod = 30;
      w.autoReconnect = true;
      w.onConnected = () {
        setState(() => mqttOk = true);
        w.subscribe(topic, MqttQos.atLeastOnce);
        _pub({'type': 'hello', 'lang': widget.myLang});
      };
      try {
        await w.connect();
        client = w;
        _listen(w);
        return;
      } catch (_) {
        return;
      }
    }
    client = c;
    _listen(c);
  }

  void _listen(MqttServerClient c) {
    c.updates?.listen((events) async {
      for (final e in events) {
        final p = e.payload;
        if (p is! MqttPublishMessage) continue;
        final raw = MqttPublishPayload.bytesToStringAsString(p.payload.message);
        Map<String, dynamic> d;
        try {
          d = jsonDecode(raw) as Map<String, dynamic>;
        } catch (_) {
          continue;
        }
        if (d['id'] == myId) continue;
        if (d['type'] == 'hello') {
          setState(() => peerLang = d['lang'] as String?);
          if (!saidHello) {
            saidHello = true;
            _pub({'type': 'hello', 'lang': widget.myLang});
          }
        } else if (d['type'] == 'msg') {
          final from = (d['lang'] as String?) ?? 'en';
          final text = (d['text'] as String?) ?? '';
          final t = await translateText(text, from, widget.myLang);
          setState(() => msgs.add(Msg(t, text, false)));
          _scrollDown();
          _speak(t);
        }
      }
    });
  }

  void _pub(Map<String, dynamic> obj) {
    final c = client;
    if (c == null ||
        c.connectionStatus?.state != MqttConnectionState.connected) {
      return;
    }
    obj['id'] = myId;
    final b = MqttClientPayloadBuilder()..addString(jsonEncode(obj));
    c.publishMessage(topic, MqttQos.atLeastOnce, b.payload!);
  }

  // ----- 음성 (폰 내장 STT — 아이폰/안드로이드 모두 지원) -----
  Future<void> _initSpeech() async {
    speechReady = await speech.initialize(
      onStatus: (s) {
        if (s == 'done' || s == 'notListening') {
          if (listening) _finishListening();
        }
      },
      onError: (_) {
        if (listening) setState(() => listening = false);
      },
    );
    setState(() {});
  }

  Future<void> _startListening() async {
    if (!speechReady) return;
    partial = '';
    setState(() => listening = true);
    await speech.listen(
      localeId: langs[widget.myLang]!['stt']!,
      listenOptions: stt.SpeechListenOptions(
        partialResults: true,
        listenMode: stt.ListenMode.dictation,
      ),
      onResult: (r) {
        setState(() => partial = r.recognizedWords);
      },
    );
  }

  Future<void> _finishListening() async {
    if (!listening) return; // 중복 호출 방지 (자동종료+버튼 동시)
    setState(() => listening = false);
    final text = partial.trim();
    partial = '';
    await speech.stop();
    if (text.isNotEmpty) _sendText(text);
  }

  // ----- TTS -----
  Future<void> _speak(String text) async {
    try {
      await tts.setLanguage(langs[widget.myLang]!['locale']!);
      await tts.speak(text);
    } catch (_) {}
  }

  // ----- 전송 -----
  void _sendText(String text) {
    if (text.isEmpty) return;
    setState(() => msgs.add(Msg(text, null, true)));
    _scrollDown();
    _pub({'type': 'msg', 'text': text, 'lang': widget.myLang});
    textCtl.clear();
  }

  void _scrollDown() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (scrollCtl.hasClients) {
        scrollCtl.animateTo(scrollCtl.position.maxScrollExtent,
            duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
      }
    });
  }

  @override
  void dispose() {
    client?.disconnect();
    speech.stop();
    tts.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final lang = widget.myLang;
    final connectedToPeer = peerLang != null;
    return Scaffold(
      appBar: AppBar(
        flexibleSpace:
            Container(decoration: const BoxDecoration(gradient: C.grad)),
        foregroundColor: Colors.white,
        title: Row(children: [
          Icon(Icons.circle,
              size: 11,
              color: connectedToPeer
                  ? const Color(0xFFB9FBD9)
                  : (mqttOk
                      ? const Color(0xFFFDE68A)
                      : const Color(0xFFFCA5A5))),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              connectedToPeer
                  ? '${tr(lang, 'partner')}: ${langs[peerLang]?['label'] ?? peerLang}'
                  : (mqttOk ? tr(lang, 'waiting') : tr(lang, 'connecting')),
              style: const TextStyle(
                  fontSize: 15, color: Colors.white, fontWeight: FontWeight.w600),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ]),
      ),
      body: SafeArea(
        child: Column(children: [
          if (!connectedToPeer)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.all(14),
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                  color: C.card,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                        color: const Color(0xFF105A50).withOpacity(.08),
                        blurRadius: 12,
                        offset: const Offset(0, 4))
                  ]),
              child: Column(children: [
                QrImageView(
                  data: '$webBase?room=${widget.room}',
                  version: QrVersions.auto,
                  size: 168,
                  backgroundColor: Colors.white,
                  eyeStyle: const QrEyeStyle(
                      eyeShape: QrEyeShape.square, color: C.ink),
                  dataModuleStyle: const QrDataModuleStyle(
                      dataModuleShape: QrDataModuleShape.square, color: C.ink),
                ),
                const SizedBox(height: 10),
                Text(tr(lang, 'scanHint'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: C.sub, fontSize: 13)),
                const SizedBox(height: 12),
                Text(tr(lang, 'shareCode'),
                    style: const TextStyle(color: C.hint, fontSize: 12)),
                const SizedBox(height: 4),
                ShaderMask(
                  shaderCallback: (b) => C.grad.createShader(b),
                  child: Text(widget.room,
                      style: const TextStyle(
                          fontSize: 30,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 8,
                          color: Colors.white)),
                ),
              ]),
            ),
          Expanded(
            child: ListView.builder(
              controller: scrollCtl,
              padding: const EdgeInsets.all(14),
              itemCount: msgs.length,
              itemBuilder: (_, i) {
                final m = msgs[i];
                return Align(
                  alignment:
                      m.mine ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 13, vertical: 10),
                    constraints: BoxConstraints(
                        maxWidth: MediaQuery.of(context).size.width * .78),
                    decoration: BoxDecoration(
                      color: m.mine ? C.primary : C.card,
                      borderRadius: m.mine
                          ? const BorderRadius.only(
                              topLeft: Radius.circular(18),
                              topRight: Radius.circular(4),
                              bottomLeft: Radius.circular(18),
                              bottomRight: Radius.circular(18))
                          : const BorderRadius.only(
                              topLeft: Radius.circular(4),
                              topRight: Radius.circular(18),
                              bottomLeft: Radius.circular(18),
                              bottomRight: Radius.circular(18)),
                      boxShadow: [
                        BoxShadow(
                            color: const Color(0xFF105A50)
                                .withOpacity(m.mine ? .18 : .07),
                            blurRadius: 8,
                            offset: const Offset(0, 3))
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(m.text,
                            style: TextStyle(
                                fontSize: 16,
                                color: m.mine ? Colors.white : C.ink)),
                        if (m.orig != null && m.orig != m.text)
                          Padding(
                            padding: const EdgeInsets.only(top: 3),
                            child: Text(m.orig!,
                                style: TextStyle(
                                    fontSize: 11,
                                    color: m.mine
                                        ? Colors.white.withOpacity(.7)
                                        : C.hint)),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          if (listening)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Text(
                partial.isEmpty ? tr(lang, 'listening') : partial,
                style: const TextStyle(color: C.sub, fontSize: 13),
                textAlign: TextAlign.center,
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
            child: Row(children: [
              Expanded(
                child: TextField(
                  controller: textCtl,
                  onSubmitted: _sendText,
                  style: const TextStyle(color: C.ink),
                  decoration: InputDecoration(
                    hintText: tr(lang, 'typeOrMic'),
                    hintStyle: const TextStyle(color: C.hint, fontSize: 13),
                    filled: true,
                    fillColor: C.card,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(22),
                        borderSide: const BorderSide(color: C.line)),
                    enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(22),
                        borderSide: const BorderSide(color: C.line)),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                style: IconButton.styleFrom(backgroundColor: C.primary2),
                onPressed: () => _sendText(textCtl.text.trim()),
                icon: const Icon(Icons.send, color: Colors.white),
              ),
              const SizedBox(width: 6),
              GestureDetector(
                onTap: listening ? _finishListening : _startListening,
                child: Container(
                  width: 54,
                  height: 54,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: listening
                        ? const LinearGradient(
                            colors: [Color(0xFFEF4444), Color(0xFFF97316)])
                        : (speechReady
                            ? C.grad
                            : const LinearGradient(
                                colors: [Color(0xFF94A3B8), Color(0xFF94A3B8)])),
                    boxShadow: [
                      BoxShadow(
                          color: (listening ? const Color(0xFFEF4444) : C.primary)
                              .withOpacity(.4),
                          blurRadius: 12,
                          offset: const Offset(0, 4))
                    ],
                  ),
                  child: Icon(listening ? Icons.stop : Icons.mic,
                      color: Colors.white, size: 26),
                ),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}
