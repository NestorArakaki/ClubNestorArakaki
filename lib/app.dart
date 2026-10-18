import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'services/api_client.dart';
import 'services/auth_service.dart';
import 'services/notification_service.dart';
import 'screens/auth_screen.dart';
import 'screens/venues_screen.dart';
import 'screens/bookings_screen.dart';
import 'screens/profile_screen.dart';
import 'widgets/async_view.dart';

class ClubApp extends StatefulWidget {
  const ClubApp({
    super.key,
    required this.auth,
    required this.api,
    this.notifications,
  });
  final AuthService auth;
  final ApiClient api;
  final NotificationService? notifications;
  @override
  State<ClubApp> createState() => _ClubAppState();
}

class _ClubAppState extends State<ClubApp> {
  late final Stream<String?> _sessions;
  @override
  void initState() {
    super.initState();
    _sessions = widget.auth.sessions;
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<String?>(
    stream: _sessions,
    initialData: widget.auth.uid,
    builder: (context, snapshot) => MaterialApp(
      // Un cambio de cuenta descarta todas las rutas y datos de la sesión anterior.
      key: ValueKey(snapshot.data),
      title: 'ClubNestorArakaki',
      locale: const Locale('es'),
      supportedLocales: const [Locale('es')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
        inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(),
        ),
        useMaterial3: true,
      ),
      home: snapshot.hasError
          ? const Scaffold(
              body: Center(
                child: Text(
                  'No se pudo recuperar la sesión. Reiniciá la aplicación.',
                ),
              ),
            )
          : snapshot.connectionState == ConnectionState.waiting &&
                snapshot.data == null
          ? const Scaffold(body: Center(child: CircularProgressIndicator()))
          : snapshot.data == null
          ? AuthScreen(auth: widget.auth)
          : HomeScreen(
              auth: widget.auth,
              api: widget.api,
              notifications: widget.notifications,
            ),
    ),
  );
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.auth,
    required this.api,
    this.notifications,
  });
  final AuthService auth;
  final ApiClient api;
  final NotificationService? notifications;
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _tab = 0, _revision = 0;
  bool _signingOut = false;
  @override
  void initState() {
    super.initState();
    widget.notifications?.target.addListener(_openPush);
    unawaited(widget.notifications?.sync());
    WidgetsBinding.instance.addPostFrameCallback((_) => _openPush());
  }

  @override
  void dispose() {
    widget.notifications?.target.removeListener(_openPush);
    super.dispose();
  }

  void _openPush() {
    if (!mounted) return;
    final service = widget.notifications;
    final destination = service?.target.value;
    if (destination == null) return;
    service!.target.value = null;
    if (destination.uid != widget.auth.uid) return;
    setState(() {
      _tab = 1;
      _revision++;
    });
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => BookingDetailScreen(
          api: widget.api,
          bookingId: destination.bookingId,
        ),
      ),
    );
  }

  Future<void> _logout() async {
    setState(() {
      _signingOut = true;
    });
    try {
      await widget.notifications?.unlink();
      await widget.auth.logout();
    } catch (e) {
      if (mounted) showMessage(context, '$e');
    } finally {
      if (mounted) {
        setState(() {
          _signingOut = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('ClubNestorArakaki'),
      actions: [
        IconButton(
          tooltip: 'Cerrar sesión',
          onPressed: _signingOut ? null : _logout,
          icon: const Icon(Icons.logout),
        ),
      ],
    ),
    body: Column(
      children: [
        if (widget.notifications != null && _tab == 0)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: ValueListenableBuilder<String>(
                    valueListenable: widget.notifications!.status,
                    builder: (_, status, child) => Text(status),
                  ),
                ),
                TextButton(
                  onPressed: () =>
                      widget.notifications!.sync(requestPermission: true),
                  child: const Text('Activar avisos'),
                ),
              ],
            ),
          ),
        Expanded(
          child: switch (_tab) {
            0 => VenuesScreen(api: widget.api),
            1 => BookingsScreen(key: ValueKey(_revision), api: widget.api),
            _ => ProfileScreen(api: widget.api),
          },
        ),
      ],
    ),
    bottomNavigationBar: NavigationBar(
      selectedIndex: _tab,
      onDestinationSelected: (index) => setState(() {
        _tab = index;
        _revision++;
      }),
      destinations: const [
        NavigationDestination(icon: Icon(Icons.stadium), label: 'Sedes'),
        NavigationDestination(
          icon: Icon(Icons.calendar_month),
          label: 'Mis reservas',
        ),
        NavigationDestination(icon: Icon(Icons.person), label: 'Perfil'),
      ],
    ),
  );
}
