import 'package:flutter/material.dart';

import 'app_state.dart';

const adminGreen = Color(0xFF245B42);

class AdminPage extends StatefulWidget {
  final AppState state;
  const AdminPage({super.key, required this.state});
  @override
  State<AdminPage> createState() => _AdminPageState();
}

class _AdminPageState extends State<AdminPage> {
  int tab = 0;
  bool busy = false;
  AppState get s => widget.state;
  String t(String en, String mr) => s.tr(en, mr);
  void alert(Object error) =>
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.toString())));
  Future<void> run(Future<void> Function() work) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await work();
    } catch (e) {
      if (mounted) alert(e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<bool> confirm(String title) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(t('Go back', 'मागे जा')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(t('Confirm', 'निश्चित करा')),
            ),
          ],
        ),
      ) ??
      false;
  Widget count(String label, Object? number) => Card(
    child: Padding(
      padding: const EdgeInsets.all(17),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 12, color: Colors.black54),
          ),
          const SizedBox(height: 10),
          Text(
            '${number ?? 0}',
            style: const TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.bold,
              color: adminGreen,
            ),
          ),
        ],
      ),
    ),
  );
  Widget item(String title, String subtitle, List<Widget> actions) => Card(
    margin: const EdgeInsets.only(bottom: 12),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 7),
          Text(subtitle, style: const TextStyle(fontSize: 12, height: 1.6)),
          if (actions.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(spacing: 8, runSpacing: 7, children: actions),
          ],
        ],
      ),
    ),
  );
  Widget button(String label, VoidCallback callback) =>
      OutlinedButton(onPressed: busy ? null : callback, child: Text(label));
  List<Widget> overview() {
    final c = s.adminCounts;
    return [
      Text(
        t('KVK operations', 'KVK व्यवस्थापन'),
        style: const TextStyle(fontSize: 23, fontWeight: FontWeight.bold),
      ),
      const SizedBox(height: 15),
      GridView.count(
        crossAxisCount: 2,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        childAspectRatio: 1.55,
        children: [
          count(t('Farmers', 'शेतकरी'), c['farmers']),
          count(t('Providers', 'मजूर गट'), c['providers']),
          count(t('Teams', 'गट'), c['teams']),
          count(
            t('Pending requests', 'प्रलंबित मागण्या'),
            c['pendingBookings'],
          ),
          count(t('Unverified teams', 'पडताळणी बाकी'), c['unverifiedTeams']),
          count(t('Confirmed', 'निश्चित'), c['acceptedBookings']),
        ],
      ),
      const SizedBox(height: 14),
      Text(
        t(
          'All admin changes are recorded in the activity log.',
          'सर्व प्रशासकीय बदल नोंदवले जातात.',
        ),
      ),
    ];
  }

  List<Widget> users() => [
    Text(
      t('Farmers and providers', 'शेतकरी आणि मजूर गट'),
      style: const TextStyle(fontSize: 21, fontWeight: FontWeight.bold),
    ),
    const SizedBox(height: 12),
    ...s.adminUsers.map(
      (u) => item(
        '${u['name']} · ${u['role']}',
        '${u['phone']}\n${u['address']}\n${u['suspended'] == true ? t('Suspended', 'बंद') : t('Active', 'सक्रिय')}',
        [
          button(
            u['suspended'] == true
                ? t('Restore access', 'पुन्हा सुरू करा')
                : t('Suspend access', 'प्रवेश बंद करा'),
            () async {
              final suspend = u['suspended'] != true;
              if (await confirm(
                suspend
                    ? t('Suspend this account?', 'हे खाते बंद करायचे?')
                    : t('Restore this account?', 'हे खाते सुरू करायचे?'),
              )) {
                await run(
                  () => s.setAdminUserSuspended(u['id'] as int, suspend),
                );
              }
            },
          ),
        ],
      ),
    ),
  ];
  List<Widget> teams() => [
    Text(
      t('Labour teams', 'मजूर गट'),
      style: const TextStyle(fontSize: 21, fontWeight: FontWeight.bold),
    ),
    const SizedBox(height: 12),
    ...s.adminTeams.map(
      (team) => item(
        '${team['name']} · ${team['place']}',
        '${team['providerName']} · ${team['providerPhone']}\n${team['people']} ${t('workers', 'मजूर')} · ₹${team['price']}/day\n${(team['skills'] as List).join(', ')}\n${team['verified'] == true ? t('Verified', 'पडताळलेले') : t('Needs review', 'पडताळणी बाकी')} · ${team['adminHidden'] == true ? t('Hidden', 'लपवलेले') : t('Listed', 'यादीत आहे')}',
        [
          button(
            team['verified'] == true
                ? t('Remove verification', 'पडताळणी काढा')
                : t('Mark verified', 'पडताळणी करा'),
            () async {
              final verified = team['verified'] != true;
              if (await confirm(
                t('Change team verification?', 'गटाची पडताळणी बदलायची?'),
              )) {
                await run(
                  () =>
                      s.setAdminTeam(team['id'] as int, {'verified': verified}),
                );
              }
            },
          ),
          button(
            team['adminHidden'] == true
                ? t('Show listing', 'यादीत दाखवा')
                : t('Hide listing', 'यादीतून लपवा'),
            () async {
              final hidden = team['adminHidden'] != true;
              if (await confirm(
                t('Change listing visibility?', 'गटाची दृश्यमानता बदलायची?'),
              )) {
                await run(
                  () => s.setAdminTeam(team['id'] as int, {
                    'adminHidden': hidden,
                  }),
                );
              }
            },
          ),
        ],
      ),
    ),
  ];
  Future<void> cancelBooking(int id) async {
    final controller = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t('Cancel booking', 'बुकिंग रद्द करा')),
        content: TextField(
          controller: controller,
          maxLength: 300,
          decoration: InputDecoration(
            labelText: t(
              'Reason (at least 5 characters)',
              'कारण (किमान ५ अक्षरे)',
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(t('Go back', 'मागे जा')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: Text(t('Cancel booking', 'बुकिंग रद्द करा')),
          ),
        ],
      ),
    );
    controller.dispose();
    if (reason == null || !mounted) return;
    if (reason.length < 5) {
      alert(t('Please enter a reason.', 'कृपया कारण लिहा.'));
      return;
    }
    await run(() => s.adminCancelBooking(id, reason));
  }

  List<Widget> bookings() => [
    Text(
      t('All bookings', 'सर्व बुकिंग'),
      style: const TextStyle(fontSize: 21, fontWeight: FontWeight.bold),
    ),
    const SizedBox(height: 12),
    ...s.adminBookings.map(
      (b) => item(
        '#${b['id']} · ${b['team']}',
        '${b['farmerName']} · ${b['farmerPhone']}\n${b['providerName']} · ${b['providerPhone']}\n${b['task']} · ${b['workers']} ${t('workers', 'मजूर')} · ${b['date']}\n₹${b['total']} · ${b['status']}',
        <Widget>[
          if (['pending', 'accepted'].contains(b['status']))
            button(
              t('Cancel with reason', 'कारणासह रद्द करा'),
              () => cancelBooking(b['id'] as int),
            ),
        ],
      ),
    ),
  ];
  List<Widget> audit() => [
    Text(
      t('Admin activity', 'प्रशासकीय नोंदी'),
      style: const TextStyle(fontSize: 21, fontWeight: FontWeight.bold),
    ),
    const SizedBox(height: 12),
    ...s.adminEvents.map(
      (e) => item(
        '${e['action']} · ${e['targetType']} #${e['targetId']}',
        '${e['adminName']} · ${e['createdAt']}\n${e['detail'] ?? ''}',
        [],
      ),
    ),
  ];
  @override
  Widget build(BuildContext context) {
    if (s.user?['mustChangePassword'] == true) {
      return AdminPasswordPage(state: s);
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(t('KVK admin', 'KVK प्रशासक')),
        actions: [
          TextButton(
            onPressed: s.language,
            child: Text(s.marathi ? 'English' : 'मराठी'),
          ),
          IconButton(
            tooltip: t('Refresh', 'पुन्हा पहा'),
            onPressed: () => run(s.loadAdminData),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: s.loadAdminData,
        child: ListView(
          padding: const EdgeInsets.all(17),
          children: [
            ...(switch (tab) {
              0 => overview(),
              1 => users(),
              2 => teams(),
              3 => bookings(),
              4 => audit(),
              _ => [],
            }),
            const SizedBox(height: 20),
            if (tab == 0)
              OutlinedButton.icon(
                onPressed: () => run(s.logout),
                icon: const Icon(Icons.logout),
                label: Text(t('Sign out', 'लॉगआउट')),
              ),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: (v) => setState(() => tab = v),
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.dashboard_outlined),
            label: t('Overview', 'आढावा'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.people_outline),
            label: t('People', 'लोक'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.groups_outlined),
            label: t('Teams', 'गट'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.calendar_month_outlined),
            label: t('Bookings', 'बुकिंग'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.history),
            label: t('Activity', 'नोंदी'),
          ),
        ],
      ),
    );
  }
}

class AdminPasswordPage extends StatefulWidget {
  final AppState state;
  const AdminPasswordPage({super.key, required this.state});
  @override
  State<AdminPasswordPage> createState() => _AdminPasswordPageState();
}

class _AdminPasswordPageState extends State<AdminPasswordPage> {
  final form = GlobalKey<FormState>();
  final current = TextEditingController(),
      next = TextEditingController(),
      repeat = TextEditingController();
  bool busy = false;
  String? error;
  @override
  void dispose() {
    current.dispose();
    next.dispose();
    repeat.dispose();
    super.dispose();
  }

  Future<void> save() async {
    if (!form.currentState!.validate()) return;
    setState(() => busy = true);
    try {
      await widget.state.changeAdminPassword(current.text, next.text);
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(
        widget.state.tr('Change admin password', 'प्रशासक पासवर्ड बदला'),
      ),
    ),
    body: Form(
      key: form,
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(
            widget.state.tr(
              'Set a private password before viewing KVK records.',
              'KVK नोंदी पाहण्याआधी नवीन पासवर्ड ठेवा.',
            ),
            style: const TextStyle(fontSize: 16),
          ),
          const SizedBox(height: 24),
          TextFormField(
            controller: current,
            obscureText: true,
            decoration: InputDecoration(
              labelText: widget.state.tr(
                'Temporary password',
                'तात्पुरता पासवर्ड',
              ),
            ),
            validator: (v) =>
                v == null || v.length < 8 ? 'Enter temporary password' : null,
          ),
          const SizedBox(height: 15),
          TextFormField(
            controller: next,
            obscureText: true,
            decoration: InputDecoration(
              labelText: widget.state.tr(
                'New password (12+ characters)',
                'नवीन पासवर्ड (किमान १२ अक्षरे)',
              ),
            ),
            validator: (v) => v == null || v.length < 12
                ? 'Use at least 12 characters'
                : null,
          ),
          const SizedBox(height: 15),
          TextFormField(
            controller: repeat,
            obscureText: true,
            decoration: InputDecoration(
              labelText: widget.state.tr(
                'Repeat new password',
                'नवीन पासवर्ड पुन्हा लिहा',
              ),
            ),
            validator: (v) => v != next.text ? 'Passwords do not match' : null,
          ),
          const SizedBox(height: 15),
          if (error != null)
            Text(error!, style: const TextStyle(color: Colors.red)),
          FilledButton(
            onPressed: busy ? null : save,
            child: Text(
              widget.state.tr('Save new password', 'नवीन पासवर्ड जतन करा'),
            ),
          ),
        ],
      ),
    ),
  );
}
