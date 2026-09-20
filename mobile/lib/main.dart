import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:geolocator/geolocator.dart';
import 'package:uuid/uuid.dart';
import 'package:url_launcher/url_launcher.dart';

import 'app_state.dart';
import 'admin_page.dart';
import 'services/location_service.dart';

const green = Color(0xFF245B42);
const cropNames = [
  'Grape',
  'Pomegranate',
  'Onion',
  'Vegetables',
  'Guava',
  'General farm work',
  'Animal husbandry',
];
const cropLabels = [
  '🍇 द्राक्ष',
  '🔴 डाळिंब',
  '🧅 कांदा',
  '🥬 भाजीपाला',
  '🍐 पेरू',
  '🌱 सामान्य शेतीकाम',
  '🐄 पशुपालन',
];
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(KrishiApp(state: AppState()));
}

class KrishiApp extends StatefulWidget {
  final AppState state;
  const KrishiApp({super.key, required this.state});
  @override
  State<KrishiApp> createState() => _KrishiAppState();
}

class _KrishiAppState extends State<KrishiApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(widget.state.initialize());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    widget.state.foreground = state == AppLifecycleState.resumed;
    if (state == AppLifecycleState.resumed) {
      widget.state.resumeLocationUpdates();
      if (widget.state.user != null) {
        unawaited(widget.state.loadAccountData().catchError((Object e) {}));
      }
    } else {
      unawaited(widget.state.stopLocationUpdates());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.state.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.state,
    builder: (context, _) => MaterialApp(
      title: 'Krishi Saathi',
      debugShowCheckedModeBanner: false,
      locale: Locale(widget.state.marathi ? 'mr' : 'en'),
      supportedLocales: const [Locale('en'), Locale('mr')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: green),
        scaffoldBackgroundColor: const Color(0xFFF8F9F5),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          foregroundColor: green,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: green,
            minimumSize: const Size(0, 52),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        cardTheme: CardThemeData(
          color: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: Color(0xFFE3E8DC)),
          ),
        ),
      ),
      home: widget.state.admin
          ? AdminPage(state: widget.state)
          : HomePage(state: widget.state),
    ),
  );
}

void message(BuildContext context, Object error) =>
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(error.toString())));
Widget gap([double height = 16]) => SizedBox(height: height);
String? requiredText(String? value) => value == null || value.trim().isEmpty
    ? 'Please enter this detail / माहिती भरा'
    : null;
String workDate(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
String lastGpsUpdate(String value) {
  final d = DateTime.parse(value).toLocal();
  return '${d.day}/${d.month} · ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

DateTime indiaToday() {
  final now = DateTime.now().toUtc().add(const Duration(hours: 5, minutes: 30));
  return DateTime(now.year, now.month, now.day);
}

class HomePage extends StatefulWidget {
  final AppState state;
  const HomePage({super.key, required this.state});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int tab = 0;
  String query = '';
  AppState get s => widget.state;
  Timer? bookingTimer;
  bool refreshingBookings = false;
  @override
  void initState() {
    super.initState();
    bookingTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (tab != 1 || !s.foreground || s.user == null || refreshingBookings) {
        return;
      }
      refreshingBookings = true;
      unawaited(
        s.loadAccountData().catchError((Object e) {}).whenComplete(() {
          refreshingBookings = false;
        }),
      );
    });
  }

  @override
  void dispose() {
    bookingTimer?.cancel();
    super.dispose();
  }

  Future<void> signIn() async {
    await Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => AuthPage(state: s)));
    if (mounted) setState(() {});
  }

  Future<void> refresh() async {
    try {
      await s.loadTeams();
      await s.loadAccountData();
    } catch (e) {
      if (mounted) message(context, e);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Row(
        children: [
          Icon(Icons.eco),
          SizedBox(width: 9),
          Text(
            'Krishi Saathi',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 20),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: s.language,
          child: Text(s.marathi ? 'English' : 'मराठी'),
        ),
      ],
    ),
    body: RefreshIndicator(
      onRefresh: refresh,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          if (tab == 0) ...[
            Text(
              '${s.tr('Namaste', 'नमस्कार')}, ${s.user?['name'] ?? s.tr('farmer', 'शेतकरी')}!',
              style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700),
            ),
            gap(6),
            Text(
              s.tr(
                'The right hands. At the right time.',
                'योग्य मजूर. योग्य वेळी.',
              ),
              style: const TextStyle(color: Color(0xFF76846A)),
            ),
            gap(22),
            if (s.provider) ...providerHome() else ...farmerHome(),
          ],
          if (tab == 1) ...bookingList(),
          if (tab == 2) ...account(),
        ],
      ),
    ),
    bottomNavigationBar: NavigationBar(
      selectedIndex: tab,
      onDestinationSelected: (value) {
        setState(() => tab = value);
        if (value == 1 && s.user != null) {
          unawaited(
            s.loadAccountData().catchError((Object e) {
              if (context.mounted) message(context, e);
            }),
          );
        }
      },
      destinations: [
        NavigationDestination(
          icon: const Icon(Icons.agriculture_outlined),
          selectedIcon: const Icon(Icons.agriculture),
          label: s.tr(
            s.provider ? 'My team' : 'Find labour',
            s.provider ? 'माझा गट' : 'मजूर शोधा',
          ),
        ),
        NavigationDestination(
          icon: const Icon(Icons.calendar_month_outlined),
          label: s.tr('Bookings', 'बुकिंग'),
        ),
        NavigationDestination(
          icon: const Icon(Icons.person_outline),
          label: s.tr('My account', 'माझे खाते'),
        ),
      ],
    ),
  );
  List<Widget> farmerHome() => [
    Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: const Color(0xFFEAF0E2),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            s.tr('Farm help, close to home.', 'तुमच्या शेताजवळ मदत.'),
            style: const TextStyle(
              fontSize: 25,
              fontWeight: FontWeight.w800,
              color: green,
            ),
          ),
          gap(10),
          Text(
            s.tr(
              'Choose a crop, find a local team, and send a work request.',
              'पीक निवडा, जवळचा मजूर गट शोधा आणि कामाची मागणी पाठवा.',
            ),
          ),
          gap(),
          FilledButton.icon(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => LocationPage(state: s)),
            ),
            icon: const Icon(Icons.my_location),
            label: Text(s.tr('Set farm GPS location', 'शेताचे GPS स्थान ठेवा')),
          ),
          if (s.location != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                '${s.location!.lat.toStringAsFixed(4)}, ${s.location!.lng.toStringAsFixed(4)}${s.liveLocation ? ' · GPS live' : ''}',
              ),
            ),
        ],
      ),
    ),
    gap(24),
    Text(
      s.tr('What crop needs help?', 'कोणत्या पिकासाठी मदत हवी?'),
      style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
    ),
    gap(12),
    Wrap(
      spacing: 8,
      runSpacing: 6,
      children: ['All crops', ...cropNames]
          .map(
            (c) => ChoiceChip(
              label: Text(
                c == 'All crops'
                    ? s.tr('🌱 All crops', '🌱 सर्व पिके')
                    : s.marathi
                    ? cropLabels[cropNames.indexOf(c)]
                    : c,
              ),
              selected: s.crop == c,
              onSelected: (_) {
                s.crop = c;
                unawaited(s.loadTeams());
              },
            ),
          )
          .toList(),
    ),
    gap(22),
    TextField(
      decoration: InputDecoration(
        prefixIcon: const Icon(Icons.search),
        hintText: s.tr('Search a team or skill', 'गट किंवा कौशल्य शोधा'),
      ),
      onChanged: (value) => setState(() => query = value),
    ),
    gap(12),
    if (s.location != null)
      Row(
        children: [
          Text(s.tr('Search within', 'अंतर मर्यादा')),
          const SizedBox(width: 12),
          DropdownButton<int>(
            value: s.radius,
            items: [10, 25, 50, 100]
                .map((r) => DropdownMenuItem(value: r, child: Text('$r km')))
                .toList(),
            onChanged: (r) {
              s.radius = r!;
              unawaited(s.loadTeams());
            },
          ),
        ],
      ),
    if (s.loading)
      const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: CircularProgressIndicator(),
        ),
      ),
    if (s.error != null) ...[
      Text(s.error!, style: const TextStyle(color: Colors.red)),
      TextButton(
        onPressed: s.loadTeams,
        child: Text(s.tr('Try again', 'पुन्हा प्रयत्न करा')),
      ),
    ],
    if (!s.loading && s.error == null && s.teams.isEmpty)
      empty(
        s.tr(
          'No teams here yet. Try a larger distance, or ask a local provider to register.',
          'अजून गट उपलब्ध नाहीत. अंतर वाढवा किंवा स्थानिक गटाला नोंदणी करण्यास सांगा.',
        ),
      ),
    ...s.teams
        .where(
          (t) => '${t['name']} ${(t['skills'] as List).join(' ')}'
              .toLowerCase()
              .contains(query.toLowerCase()),
        )
        .map(teamCard),
  ];
  Widget teamCard(Map<String, dynamic> t) => Card(
    margin: const EdgeInsets.only(bottom: 15),
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const CircleAvatar(
                backgroundColor: Color(0xFFEAF0E2),
                child: Icon(Icons.groups_outlined, color: green),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  t['name'] as String,
                  style: const TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          gap(12),
          Text(
            '${t['place']}${t['distanceKm'] != null ? ' · ${t['distanceKm']} km' : ''}',
          ),
          gap(8),
          Text(
            '${t['people']} ${s.tr('workers', 'मजूर')} · ${t['verified'] == true ? s.tr('KVK verified', 'केव्हीके पडताळणी झाली') : s.tr('Verification pending', 'पडताळणी बाकी')}',
          ),
          gap(12),
          Wrap(
            spacing: 6,
            children: (t['skills'] as List)
                .map((skill) => Chip(label: Text(skill as String)))
                .toList(),
          ),
          gap(12),
          Text(
            '₹${t['price']} ${s.tr('/ person / day', '/ व्यक्ती / दिवस')}',
            style: const TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.w700,
              color: green,
            ),
          ),
          gap(14),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () async {
                if (s.user == null) await signIn();
                if (!mounted || s.user == null) return;
                if (s.provider) {
                  return message(
                    context,
                    s.tr(
                      'Use a farmer account to book a team.',
                      'बुकिंगसाठी शेतकरी खाते वापरा.',
                    ),
                  );
                }
                final sent = await Navigator.of(context).push<bool>(
                  MaterialPageRoute(
                    builder: (_) => BookingPage(state: s, team: t),
                  ),
                );
                if (sent == true && mounted) setState(() => tab = 1);
              },
              icon: const Icon(Icons.calendar_month),
              label: Text(s.tr('Request this team', 'या गटाला मागणी पाठवा')),
            ),
          ),
        ],
      ),
    ),
  );
  List<Widget> providerHome() => [
    Text(
      s.tr('Your labour team', 'तुमचा मजूर गट'),
      style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w700),
    ),
    gap(),
    if (s.ownTeam == null)
      empty(
        s.tr(
          'Publish your skills, daily rate and team location so nearby farmers can find you.',
          'कौशल्ये, दर आणि गटाचे स्थान द्या. जवळचे शेतकरी तुम्हाला शोधू शकतील.',
        ),
      ),
    if (s.ownTeam != null)
      Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                s.ownTeam!['name'] as String,
                style: const TextStyle(
                  fontSize: 23,
                  fontWeight: FontWeight.w700,
                ),
              ),
              gap(),
              Text(
                '${s.ownTeam!['people']} ${s.tr('workers', 'मजूर')} · ₹${s.ownTeam!['price']} / day',
              ),
              gap(),
              Text((s.ownTeam!['skills'] as List).join(' · ')),
              gap(),
              Text(
                s.ownTeam!['available'] == true
                    ? s.tr('Accepting requests', 'मागण्या स्वीकारत आहोत')
                    : s.tr('Not available', 'उपलब्ध नाही'),
              ),
            ],
          ),
        ),
      ),
    gap(),
    FilledButton.icon(
      onPressed: () => Navigator.of(context)
          .push(MaterialPageRoute<void>(builder: (_) => TeamPage(state: s))),
      icon: const Icon(Icons.edit_outlined),
      label: Text(
        s.tr(
          s.ownTeam == null ? 'Publish my team' : 'Edit my team',
          s.ownTeam == null ? 'गट नोंदवा' : 'गटाची माहिती बदला',
        ),
      ),
    ),
    gap(20),
    Text(
      s.tr('Pending requests: ', 'प्रलंबित मागण्या: ') +
          s.bookings.where((b) => b['status'] == 'pending').length.toString(),
    ),
    gap(),
    OutlinedButton(
      onPressed: () => setState(() => tab = 1),
      child: Text(s.tr('View farm requests', 'शेतकऱ्यांच्या मागण्या पहा')),
    ),
  ];
  Widget empty(String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 30),
    child: Center(
      child: Text(
        value,
        textAlign: TextAlign.center,
        style: const TextStyle(color: Color(0xFF78876B), height: 1.6),
      ),
    ),
  );
  String statusLabel(String status) => switch (status) {
    'pending' => s.tr('Waiting for provider', 'गटाच्या उत्तराची प्रतीक्षा'),
    'accepted' => s.tr('Confirmed', 'निश्चित झाले'),
    'declined' => s.tr('Declined', 'नाकारले'),
    'cancelled' => s.tr('Cancelled', 'रद्द केले'),
    'completed' => s.tr('Completed', 'पूर्ण झाले'),
    _ => status,
  };
  List<Widget> bookingList() => [
    Row(
      children: [
        Expanded(
          child: Text(
            s.tr(
              s.provider ? 'Farm requests' : 'My bookings',
              s.provider ? 'कामाच्या मागण्या' : 'माझे बुकिंग',
            ),
            style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w700),
          ),
        ),
        IconButton(
          onPressed: refresh,
          tooltip: s.tr('Refresh', 'पुन्हा पहा'),
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    gap(),
    if (s.user == null)
      FilledButton(
        onPressed: signIn,
        child: Text(
          s.tr('Sign in to see bookings', 'बुकिंग पाहण्यासाठी लॉगिन करा'),
        ),
      ),
    if (s.user != null && s.bookings.isEmpty)
      empty(
        s.tr(
          'No requests yet. Your bookings will appear here.',
          'अजून मागण्या नाहीत. तुमचे बुकिंग येथे दिसेल.',
        ),
      ),
    ...s.bookings.map(
      (b) => Card(
        margin: const EdgeInsets.only(bottom: 16),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                b['team'] as String,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              gap(8),
              Text('${b['task']} · ${b['workers']} ${s.tr('workers', 'मजूर')}'),
              gap(8),
              Text('${b['date']} · ₹${b['total']} / day'),
              gap(8),
              Text(b['address'] as String),
              gap(8),
              Chip(
                label: Text(statusLabel(b['status'] as String)),
                backgroundColor: b['status'] == 'accepted'
                    ? const Color(0xFFE4EFDB)
                    : const Color(0xFFF5EEDC),
              ),
              TextButton.icon(
                onPressed: () async {
                  final phone =
                      b[s.provider ? 'farmerPhone' : 'providerPhone'] as String;
                  if (!await launchUrl(Uri(scheme: 'tel', path: phone)) &&
                      mounted) {
                    message(context, 'Call $phone');
                  }
                },
                icon: const Icon(Icons.phone_outlined),
                label: Text(
                  '${s.tr('Call', 'फोन करा')} ${b[s.provider ? 'farmerName' : 'providerName']}',
                ),
              ),
              if (s.provider && b['status'] == 'accepted')
                OutlinedButton.icon(
                  onPressed: changing.contains(b['id'])
                      ? null
                      : () async {
                          setState(() => changing.add(b['id'] as int));
                          try {
                            await s.shareLocation(
                              b['id'] as int,
                              b['locationSharing'] != true,
                            );
                          } catch (e) {
                            if (mounted) message(context, e);
                          } finally {
                            if (mounted) {
                              setState(() => changing.remove(b['id']));
                            }
                          }
                        },
                  icon: Icon(
                    b['locationSharing'] == true
                        ? Icons.location_disabled
                        : Icons.share_location,
                  ),
                  label: Text(
                    b['locationSharing'] == true
                        ? s.tr(
                            'Stop sharing my GPS',
                            'माझे GPS शेअर करणे थांबवा',
                          )
                        : s.tr(
                            'Share my GPS with this farmer',
                            'या शेतकऱ्याला माझे GPS दाखवा',
                          ),
                  ),
                ),
              if (!s.provider && b['providerLocation'] != null) ...[
                Text(
                  '${s.tr('Last team GPS update', 'गटाचे शेवटचे GPS अपडेट')}: ${lastGpsUpdate(b['providerLocation']['updatedAt'] as String)}',
                  style: const TextStyle(fontSize: 11),
                ),
                TextButton.icon(
                  onPressed: () => launchUrl(
                    Uri.https('www.google.com', '/maps/search/', {
                      'api': '1',
                      'query':
                          '${b['providerLocation']['lat']},${b['providerLocation']['lng']}',
                    }),
                    mode: LaunchMode.externalApplication,
                  ),
                  icon: const Icon(Icons.share_location),
                  label: Text(
                    s.tr('See team location on map', 'नकाशावर गटाचे स्थान पहा'),
                  ),
                ),
              ],
              if (s.provider && b['lat'] != null)
                TextButton.icon(
                  onPressed: () => launchUrl(
                    Uri.https('www.google.com', '/maps/search/', {
                      'api': '1',
                      'query': '${b['lat']},${b['lng']}',
                    }),
                    mode: LaunchMode.externalApplication,
                  ),
                  icon: const Icon(Icons.directions_outlined),
                  label: Text(s.tr('Open farm directions', 'शेताचा मार्ग पहा')),
                ),
              Wrap(
                spacing: 10,
                children: [
                  if (s.provider && b['status'] == 'pending') ...[
                    statusButton(b, 'accepted', s.tr('Accept', 'स्वीकारा')),
                    statusButton(b, 'declined', s.tr('Decline', 'नाकारा')),
                  ],
                  if (s.provider && b['status'] == 'accepted')
                    statusButton(
                      b,
                      'completed',
                      s.tr('Mark completed', 'पूर्ण झाले'),
                    ),
                  if (!s.provider &&
                      ['pending', 'accepted'].contains(b['status']))
                    statusButton(
                      b,
                      'cancelled',
                      s.tr('Cancel request', 'मागणी रद्द करा'),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  ];
  final Set<int> changing = {};
  Widget statusButton(
    Map<String, dynamic> b,
    String value,
    String label,
  ) => OutlinedButton(
    onPressed: changing.contains(b['id'])
        ? null
        : () async {
            final confirm = await showDialog<bool>(
              context: context,
              builder: (context) => AlertDialog(
                title: Text('$label?'),
                content: Text(
                  '${b['team']} · ${b['date']} · ${b['workers']} ${s.tr('workers', 'मजूर')}',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: Text(s.tr('Go back', 'मागे जा')),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: Text(label),
                  ),
                ],
              ),
            );
            if (confirm != true || !mounted) return;
            setState(() => changing.add(b['id'] as int));
            try {
              await s.status(b['id'] as int, value);
            } catch (e) {
              if (mounted) message(context, e);
            } finally {
              if (mounted) setState(() => changing.remove(b['id']));
            }
          },
    child: Text(label),
  );
  List<Widget> account() => [
    Text(
      s.tr('My account', 'माझे खाते'),
      style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
    ),
    gap(24),
    if (s.user == null) ...[
      Text(
        s.tr(
          'Farmers and labour providers can register here.',
          'शेतकरी आणि मजूर गट येथे नोंदणी करू शकतात.',
        ),
      ),
      gap(),
      FilledButton(
        onPressed: signIn,
        child: Text(s.tr('Sign in / Register', 'लॉगिन / नोंदणी')),
      ),
    ],
    if (s.user != null) ...[
      Text(
        s.user!['name'] as String,
        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
      ),
      gap(8),
      Text(
        '${s.user!['phone']} · ${s.provider ? s.tr('Labour provider', 'मजूर गट') : s.tr('Farmer', 'शेतकरी')}',
      ),
      gap(8),
      Text(s.user!['address'] as String),
      gap(24),
      OutlinedButton.icon(
        onPressed: () => Navigator.of(
          context,
        ).push(MaterialPageRoute<void>(builder: (_) => LocationPage(state: s))),
        icon: const Icon(Icons.my_location),
        label: Text(s.tr('Manage GPS location', 'GPS स्थान बदला')),
      ),
      gap(),
      FilledButton(
        onPressed: () async {
          try {
            await s.logout();
            if (mounted) setState(() => tab = 0);
          } catch (e) {
            if (mounted) message(context, e);
          }
        },
        child: Text(s.tr('Sign out', 'लॉगआउट')),
      ),
    ],
    gap(24),
    Text(
      s.tr(
        'Krishi Saathi connects farmers directly with registered labour teams. Registration is not independent skill verification.',
        'कृषी साथी शेतकऱ्यांना नोंदणीकृत मजूर गटांशी जोडते. नोंदणी म्हणजे स्वतंत्र कौशल्य पडताळणी नाही.',
      ),
      style: const TextStyle(fontSize: 12, color: Color(0xFF829074)),
    ),
  ];
}

class AuthPage extends StatefulWidget {
  final AppState state;
  const AuthPage({super.key, required this.state});
  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  final form = GlobalKey<FormState>();
  final name = TextEditingController(),
      phone = TextEditingController(),
      code = TextEditingController(),
      password = TextEditingController(),
      age = TextEditingController(),
      address = TextEditingController();
  bool busy = false, adminLogin = false;
  String step = 'phone', role = 'farmer', signupToken = '';
  String? error;
  AppState get s => widget.state;

  @override
  void dispose() {
    for (final c in [name, phone, code, password, age, address]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> submit() async {
    if (!form.currentState!.validate()) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      if (adminLogin) {
        await s.authenticate({
          'phone': phone.text.trim(),
          'password': password.text,
        }, adminLogin: true);
        if (mounted) Navigator.pop(context);
      } else if (step == 'phone') {
        await s.requestOtp(phone.text.trim());
        if (mounted) setState(() => step = 'code');
      } else if (step == 'code') {
        final result = await s.verifyOtp(phone.text.trim(), code.text.trim());
        if (result['needsProfile'] == true) {
          if (mounted) {
            setState(() {
              signupToken = result['signupToken'] as String;
              step = 'profile';
            });
          }
        } else if (mounted) {
          Navigator.pop(context);
        }
      } else {
        await s.completeOtp({
          'signupToken': signupToken,
          'name': name.text.trim(),
          'age': int.parse(age.text),
          'address': address.text.trim(),
          'role': role,
          if (s.location != null) 'lat': s.location!.lat,
          if (s.location != null) 'lng': s.location!.lng,
        });
        if (mounted) Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      actions: [
        TextButton(
          onPressed: () => setState(s.language),
          child: Text(s.marathi ? 'English' : 'मराठी'),
        ),
      ],
      title: Text(
        s.tr(
          adminLogin ? 'KVK admin sign in' : 'Continue with mobile',
          adminLogin ? 'केव्हीके प्रशासक लॉगिन' : 'मोबाईलने पुढे जा',
        ),
      ),
    ),
    body: Form(
      key: form,
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const Icon(Icons.eco, color: green, size: 54),
          gap(20),
          Text(
            s.tr(
              adminLogin
                  ? 'Admin password'
                  : step == 'phone'
                  ? 'No password needed'
                  : step == 'code'
                  ? 'Enter SMS code'
                  : 'A few details about you',
              adminLogin
                  ? 'प्रशासक पासवर्ड'
                  : step == 'phone'
                  ? 'पासवर्ड लागत नाही'
                  : step == 'code'
                  ? 'SMS कोड टाका'
                  : 'तुमची थोडी माहिती',
            ),
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          gap(18),
          if (step == 'phone') ...[
            SwitchListTile(
              title: Text(s.tr('KVK admin sign in', 'केव्हीके प्रशासक लॉगिन')),
              value: adminLogin,
              onChanged: busy ? null : (v) => setState(() => adminLogin = v),
            ),
            TextFormField(
              controller: phone,
              keyboardType: TextInputType.phone,
              autofillHints: const [AutofillHints.telephoneNumber],
              maxLength: 10,
              decoration: InputDecoration(
                labelText: s.tr('Mobile number', 'मोबाईल नंबर'),
              ),
              validator: (v) => RegExp(r'^[6-9]\d{9}$').hasMatch(v ?? '')
                  ? null
                  : s.tr(
                      'Enter a 10-digit Indian number',
                      '१० अंकी भारतीय मोबाईल नंबर द्या',
                    ),
            ),
            gap(),
            if (adminLogin)
              TextFormField(
                controller: password,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: s.tr('Admin password', 'प्रशासक पासवर्ड'),
                ),
                validator: (v) => v == null || v.length < 8
                    ? s.tr('Enter admin password', 'प्रशासक पासवर्ड टाका')
                    : null,
              ),
          ],
          if (step == 'code') ...[
            Text(
              s.tr(
                'Code sent to ${phone.text}.',
                '${phone.text} वर कोड पाठवला आहे.',
              ),
            ),
            gap(),
            TextFormField(
              controller: code,
              autofocus: true,
              keyboardType: TextInputType.number,
              autofillHints: const [AutofillHints.oneTimeCode],
              maxLength: 6,
              decoration: InputDecoration(
                labelText: s.tr('Six-digit SMS code', '६ अंकी SMS कोड'),
              ),
              validator: (v) => RegExp(r'^\d{6}$').hasMatch(v ?? '')
                  ? null
                  : s.tr('Enter six digits', '६ अंक टाका'),
            ),
            gap(),
            TextButton(
              onPressed: busy
                  ? null
                  : () => setState(() {
                      step = 'phone';
                      code.clear();
                      error = null;
                    }),
              child: Text(s.tr('Change number', 'नंबर बदला')),
            ),
            TextButton(
              onPressed: busy
                  ? null
                  : () async {
                      setState(() {
                        busy = true;
                        error = null;
                      });
                      try {
                        await s.requestOtp(phone.text.trim());
                      } catch (e) {
                        if (mounted) setState(() => error = e.toString());
                      } finally {
                        if (mounted) setState(() => busy = false);
                      }
                    },
              child: Text(s.tr('Resend code', 'कोड पुन्हा पाठवा')),
            ),
          ],
          if (step == 'profile') ...[
            TextFormField(
              controller: name,
              decoration: InputDecoration(
                labelText: s.tr('Your name', 'तुमचे नाव'),
              ),
              validator: requiredText,
            ),
            gap(),
            TextFormField(
              controller: age,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(labelText: s.tr('Age', 'वय')),
              validator: (v) {
                final n = int.tryParse(v ?? '');
                return n == null || n < 18 || n > 110
                    ? s.tr('Age must be 18–110', 'वय १८ ते ११० दरम्यान हवे')
                    : null;
              },
            ),
            gap(),
            DropdownButtonFormField<String>(
              initialValue: role,
              decoration: InputDecoration(labelText: s.tr('I am a', 'मी आहे')),
              items: [
                DropdownMenuItem(
                  value: 'farmer',
                  child: Text(s.tr('Farmer', 'शेतकरी')),
                ),
                DropdownMenuItem(
                  value: 'provider',
                  child: Text(s.tr('Labour provider', 'मजूर गट / कंत्राटदार')),
                ),
              ],
              onChanged: (v) => role = v!,
            ),
            gap(),
            TextFormField(
              controller: address,
              decoration: InputDecoration(
                labelText: s.tr('Village / farm address', 'गाव / शेताचा पत्ता'),
              ),
              validator: requiredText,
            ),
          ],
          if (error != null) ...[
            gap(),
            Text(error!, style: const TextStyle(color: Colors.red)),
          ],
          gap(16),
          SizedBox(
            height: 56,
            child: FilledButton(
              onPressed: busy ? null : submit,
              child: Text(
                busy
                    ? s.tr('Please wait…', 'थांबा…')
                    : s.tr(
                        adminLogin
                            ? 'Sign in'
                            : step == 'phone'
                            ? 'Send SMS code'
                            : step == 'code'
                            ? 'Verify code'
                            : 'Finish',
                        adminLogin
                            ? 'लॉगिन करा'
                            : step == 'phone'
                            ? 'SMS कोड पाठवा'
                            : step == 'code'
                            ? 'कोड तपासा'
                            : 'पूर्ण करा',
                      ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class LocationPage extends StatefulWidget {
  final AppState state;
  const LocationPage({super.key, required this.state});
  @override
  State<LocationPage> createState() => _LocationPageState();
}

class _LocationPageState extends State<LocationPage> {
  final form = GlobalKey<FormState>();
  late final lat = TextEditingController(
        text: widget.state.location?.lat.toString() ?? '',
      ),
      lng = TextEditingController(
        text: widget.state.location?.lng.toString() ?? '',
      );
  bool busy = false, settings = false;
  String? error;
  AppState get s => widget.state;
  @override
  void dispose() {
    lat.dispose();
    lng.dispose();
    super.dispose();
  }

  Future<void> locate() async {
    setState(() {
      busy = true;
      error = null;
      settings = false;
    });
    try {
      final p = await s.gps.current();
      await s.setLocation(p);
      lat.text = '${p.lat}';
      lng.text = '${p.lng}';
      if (mounted) {
        message(context, s.tr('Farm location saved', 'शेताचे स्थान जतन केले'));
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          error = e.toString();
          settings = e is LocationException && e.needsSettings;
        });
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(s.tr('Farm GPS location', 'शेताचे GPS स्थान'))),
    body: Form(
      key: form,
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const Icon(Icons.location_on_outlined, size: 60, color: green),
          gap(20),
          Text(
            s.tr(
              'Use GPS while you are at the farm. Only providers you send a request to can see your precise farm coordinates.',
              'शेतावर असताना GPS वापरा. तुम्ही मागणी पाठवलेल्या गटालाच शेताचे अचूक स्थान दिसेल.',
            ),
            style: const TextStyle(height: 1.6),
          ),
          gap(24),
          FilledButton.icon(
            onPressed: busy ? null : locate,
            icon: const Icon(Icons.my_location),
            label: Text(
              busy
                  ? s.tr('Finding location…', 'स्थान शोधत आहोत…')
                  : s.tr(
                      'Use my current GPS location',
                      'माझे सध्याचे GPS स्थान वापरा',
                    ),
            ),
          ),
          gap(),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(
              s.tr('Live GPS while app is open', 'अॅप सुरू असताना थेट GPS'),
            ),
            subtitle: Text(
              s.tr(
                'Updates stop when the app goes into the background.',
                'अॅप मागे गेल्यावर स्थान अपडेट थांबतात.',
              ),
            ),
            value: s.liveLocation,
            onChanged: busy
                ? null
                : (v) async {
                    try {
                      await s.setLiveLocation(v);
                      if (mounted) setState(() {});
                    } catch (e) {
                      if (mounted) setState(() => error = e.toString());
                    }
                  },
          ),
          gap(),
          Text(
            s.tr(
              'Away from the farm? Enter its coordinates.',
              'शेतापासून दूर आहात? शेताचे स्थानांक द्या.',
            ),
          ),
          gap(),
          TextFormField(
            controller: lat,
            keyboardType: const TextInputType.numberWithOptions(
              decimal: true,
              signed: true,
            ),
            decoration: InputDecoration(
              labelText: s.tr('Farm latitude', 'शेताचा अक्षांश'),
            ),
            validator: (v) {
              final n = double.tryParse(v ?? '');
              return n == null || !n.isFinite || n < -90 || n > 90
                  ? '−90 to 90'
                  : null;
            },
          ),
          gap(),
          TextFormField(
            controller: lng,
            keyboardType: const TextInputType.numberWithOptions(
              decimal: true,
              signed: true,
            ),
            decoration: InputDecoration(
              labelText: s.tr('Farm longitude', 'शेताचा रेखांश'),
            ),
            validator: (v) {
              final n = double.tryParse(v ?? '');
              return n == null || !n.isFinite || n < -180 || n > 180
                  ? '−180 to 180'
                  : null;
            },
          ),
          gap(),
          if (error != null) ...[
            Text(error!, style: const TextStyle(color: Colors.red)),
            gap(),
          ],
          if (settings)
            TextButton(
              onPressed: () => Geolocator.openAppSettings(),
              child: Text(s.tr('Open app settings', 'अॅप सेटिंग्ज उघडा')),
            ),
          OutlinedButton(
            onPressed: busy
                ? null
                : () async {
                    if (!form.currentState!.validate()) return;
                    setState(() => busy = true);
                    try {
                      await s.setLiveLocation(false);
                      await s.setLocation(
                        FarmLocation(
                          double.parse(lat.text),
                          double.parse(lng.text),
                        ),
                      );
                      if (context.mounted) Navigator.pop(context);
                    } catch (e) {
                      if (mounted) setState(() => error = e.toString());
                    } finally {
                      if (mounted) setState(() => busy = false);
                    }
                  },
            child: Text(
              s.tr('Save farm coordinates', 'शेताचे स्थानांक जतन करा'),
            ),
          ),
        ],
      ),
    ),
  );
}

class BookingPage extends StatefulWidget {
  final AppState state;
  final Map<String, dynamic> team;
  const BookingPage({super.key, required this.state, required this.team});
  @override
  State<BookingPage> createState() => _BookingPageState();
}

class _BookingPageState extends State<BookingPage> {
  final form = GlobalKey<FormState>();
  final requestKey = const Uuid().v4();
  late final address = TextEditingController(
    text: widget.state.user?['address'] as String? ?? '',
  );
  late final workers = TextEditingController(
    text: '${(widget.team['people'] as int) < 4 ? widget.team['people'] : 4}',
  );
  late String task = (widget.team['skills'] as List).first as String;
  DateTime date = indiaToday();
  bool busy = false;
  String? error;
  AppState get s => widget.state;
  @override
  void dispose() {
    address.dispose();
    workers.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    if (!form.currentState!.validate()) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await s.requestBooking({
        'teamId': widget.team['id'],
        'task': task,
        'date': workDate(date),
        'workers': int.parse(workers.text),
        'address': address.text.trim(),
        'requestKey': requestKey,
        if (s.location != null) ...s.location!.toJson(),
      });
      if (mounted) {
        message(
          context,
          s.tr(
            'Request sent. Wait for the provider to accept.',
            'मागणी पाठवली. गटाच्या उत्तराची प्रतीक्षा करा.',
          ),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(s.tr('Request labour', 'मजुरांची मागणी'))),
    body: Form(
      key: form,
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(
            widget.team['name'] as String,
            style: const TextStyle(fontSize: 25, fontWeight: FontWeight.w700),
          ),
          gap(8),
          Text(
            '₹${widget.team['price']} ${s.tr('/ person / day', '/ व्यक्ती / दिवस')}',
          ),
          gap(24),
          DropdownButtonFormField<String>(
            initialValue: task,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: s.tr('Farm work', 'शेतीचे काम'),
            ),
            items: (widget.team['skills'] as List)
                .map(
                  (skill) => DropdownMenuItem(
                    value: skill as String,
                    child: Text(skill),
                  ),
                )
                .toList(),
            onChanged: busy ? null : (v) => task = v!,
          ),
          gap(),
          OutlinedButton.icon(
            onPressed: busy
                ? null
                : () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: date,
                      firstDate: indiaToday(),
                      lastDate: indiaToday().add(const Duration(days: 730)),
                    );
                    if (picked != null) setState(() => date = picked);
                  },
            icon: const Icon(Icons.calendar_month),
            label: Text(
              '${s.tr('Work date', 'कामाची तारीख')}: ${workDate(date)}',
            ),
          ),
          gap(),
          TextFormField(
            controller: workers,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: s.tr('Number of workers', 'मजुरांची संख्या'),
            ),
            onChanged: (_) => setState(() {}),
            validator: (v) {
              final n = int.tryParse(v ?? '');
              return n == null || n < 1 || n > (widget.team['people'] as int)
                  ? '1–${widget.team['people']}'
                  : null;
            },
          ),
          gap(),
          TextFormField(
            controller: address,
            maxLines: 2,
            decoration: InputDecoration(
              labelText: s.tr('Farm address / landmark', 'शेताचा पत्ता / खूण'),
            ),
            validator: requiredText,
          ),
          gap(24),
          Text(
            '${s.tr('Estimated daily total', 'अंदाजे दिवसाचा खर्च')}: ₹${(int.tryParse(workers.text) ?? 0) * (widget.team['price'] as int)}',
            style: const TextStyle(
              fontSize: 21,
              fontWeight: FontWeight.w700,
              color: green,
            ),
          ),
          gap(),
          Text(
            s.tr(
              'The provider receives your name, phone and farm details. Your booking is confirmed only after they accept.',
              'गटाला तुमचे नाव, फोन आणि शेताची माहिती मिळेल. गटाने स्वीकारल्यानंतरच बुकिंग निश्चित होईल.',
            ),
            style: const TextStyle(fontSize: 12, height: 1.6),
          ),
          gap(),
          if (error != null) ...[
            Text(error!, style: const TextStyle(color: Colors.red)),
            gap(),
          ],
          FilledButton(
            onPressed: busy ? null : submit,
            child: Text(
              busy
                  ? s.tr('Sending…', 'पाठवत आहोत…')
                  : s.tr('Send booking request', 'बुकिंग मागणी पाठवा'),
            ),
          ),
        ],
      ),
    ),
  );
}

class TeamPage extends StatefulWidget {
  final AppState state;
  const TeamPage({super.key, required this.state});
  @override
  State<TeamPage> createState() => _TeamPageState();
}

class _TeamPageState extends State<TeamPage> {
  final form = GlobalKey<FormState>();
  late final name = TextEditingController(
        text: widget.state.ownTeam?['name'] as String? ?? '',
      ),
      place = TextEditingController(
        text:
            widget.state.ownTeam?['place'] as String? ??
            widget.state.user!['address'] as String,
      ),
      skills = TextEditingController(
        text: (widget.state.ownTeam?['skills'] as List? ?? []).join(', '),
      ),
      people = TextEditingController(
        text: '${widget.state.ownTeam?['people'] ?? 5}',
      ),
      price = TextEditingController(
        text: '${widget.state.ownTeam?['price'] ?? 450}',
      ),
      lat = TextEditingController(
        text:
            '${widget.state.ownTeam?['lat'] ?? widget.state.location?.lat ?? ''}',
      ),
      lng = TextEditingController(
        text:
            '${widget.state.ownTeam?['lng'] ?? widget.state.location?.lng ?? ''}',
      );
  late Set<String> crops = Set<String>.from(
    widget.state.ownTeam?['crops'] as List? ?? [],
  );
  late bool available = widget.state.ownTeam?['available'] as bool? ?? true;
  bool busy = false;
  String? error;
  AppState get s => widget.state;
  @override
  void dispose() {
    for (final c in [name, place, skills, people, price, lat, lng]) {
      c.dispose();
    }
    super.dispose();
  }

  String? validInt(String? v, int max) {
    final n = int.tryParse(v ?? '');
    return n == null || n < 1 || n > max ? '1–$max' : null;
  }

  Future<void> submit() async {
    if (!form.currentState!.validate()) return;
    if (crops.isEmpty) {
      setState(
        () => error = s.tr('Choose at least one crop.', 'किमान एक पीक निवडा.'),
      );
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await s.publishTeam({
        'name': name.text.trim(),
        'place': place.text.trim(),
        'crops': crops.toList(),
        'skills': skills.text
            .split(',')
            .map((v) => v.trim())
            .where((v) => v.isNotEmpty)
            .toList(),
        'people': int.parse(people.text),
        'price': int.parse(price.text),
        'lat': double.parse(lat.text),
        'lng': double.parse(lng.text),
        'available': available,
      });
      if (mounted) {
        message(
          context,
          s.tr(
            'Team published. Farmers can now request your help.',
            'गट नोंदवला. शेतकरी आता मागणी पाठवू शकतात.',
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(s.tr('My labour team', 'माझा मजूर गट'))),
    body: Form(
      key: form,
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          TextFormField(
            controller: name,
            decoration: InputDecoration(
              labelText: s.tr('Team name', 'गटाचे नाव'),
            ),
            validator: requiredText,
          ),
          gap(),
          TextFormField(
            controller: place,
            decoration: InputDecoration(
              labelText: s.tr('Village / area', 'गाव / परिसर'),
            ),
            validator: requiredText,
          ),
          gap(24),
          Text(
            s.tr('Which crops can you help with?', 'कोणत्या पिकांचे काम करता?'),
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          gap(8),
          Wrap(
            spacing: 6,
            children: cropNames
                .map(
                  (c) => FilterChip(
                    label: Text(
                      s.marathi ? cropLabels[cropNames.indexOf(c)] : c,
                    ),
                    selected: crops.contains(c),
                    onSelected: (v) => setState(() {
                      v ? crops.add(c) : crops.remove(c);
                    }),
                  ),
                )
                .toList(),
          ),
          gap(),
          TextFormField(
            controller: skills,
            maxLines: 2,
            decoration: InputDecoration(
              labelText: s.tr(
                'Skills, separated by commas',
                'कौशल्ये (स्वल्पविरामाने वेगळी करा)',
              ),
              hintText: 'Harvesting, Pruning, Weeding',
            ),
            validator: requiredText,
          ),
          gap(),
          TextFormField(
            controller: people,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: s.tr('Number of workers', 'मजुरांची संख्या'),
            ),
            validator: (v) => validInt(v, 500),
          ),
          gap(),
          TextFormField(
            controller: price,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: s.tr(
                'Daily rate per person (₹)',
                'प्रति व्यक्ती दिवसाचा दर (₹)',
              ),
            ),
            validator: (v) => validInt(v, 100000),
          ),
          gap(),
          OutlinedButton.icon(
            onPressed: busy
                ? null
                : () async {
                    try {
                      final p = await s.gps.current();
                      lat.text = '${p.lat}';
                      lng.text = '${p.lng}';
                    } catch (e) {
                      if (mounted) setState(() => error = e.toString());
                    }
                  },
            icon: const Icon(Icons.my_location),
            label: Text(
              s.tr('Use GPS for team base', 'गटाच्या ठिकाणासाठी GPS वापरा'),
            ),
          ),
          gap(),
          TextFormField(
            controller: lat,
            keyboardType: const TextInputType.numberWithOptions(
              decimal: true,
              signed: true,
            ),
            decoration: InputDecoration(
              labelText: s.tr('Team base latitude', 'गटाच्या ठिकाणाचा अक्षांश'),
            ),
            validator: (v) {
              final n = double.tryParse(v ?? '');
              return n == null || !n.isFinite || n < -90 || n > 90
                  ? '−90 to 90'
                  : null;
            },
          ),
          gap(),
          TextFormField(
            controller: lng,
            keyboardType: const TextInputType.numberWithOptions(
              decimal: true,
              signed: true,
            ),
            decoration: InputDecoration(
              labelText: s.tr('Team base longitude', 'गटाच्या ठिकाणाचा रेखांश'),
            ),
            validator: (v) {
              final n = double.tryParse(v ?? '');
              return n == null || !n.isFinite || n < -180 || n > 180
                  ? '−180 to 180'
                  : null;
            },
          ),
          gap(),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: available,
            onChanged: (v) => setState(() => available = v),
            title: Text(s.tr('Available for requests', 'कामासाठी उपलब्ध')),
          ),
          gap(),
          Text(
            s.tr(
              'Farmers will see your listing. Registration does not mean the platform has independently verified your skills.',
              'शेतकऱ्यांना तुमची माहिती दिसेल. नोंदणी म्हणजे मंचाने स्वतंत्र कौशल्य पडताळणी केली असे नाही.',
            ),
            style: const TextStyle(fontSize: 12, height: 1.6),
          ),
          gap(),
          if (error != null) ...[
            Text(error!, style: const TextStyle(color: Colors.red)),
            gap(),
          ],
          FilledButton(
            onPressed: busy ? null : submit,
            child: Text(
              busy
                  ? s.tr('Saving…', 'जतन करत आहोत…')
                  : s.tr('Publish my team', 'माझा गट नोंदवा'),
            ),
          ),
        ],
      ),
    ),
  );
}
