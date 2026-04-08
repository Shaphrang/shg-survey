// lib\features\survey\screens\splash_screen.dart
import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'household_entry_screen.dart';
import 'location_setup_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  final SupabaseClient supabase = Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    initializeApp();
  }

  Route _noAnimationRoute(Widget page) {
    return PageRouteBuilder(
      pageBuilder: (_, __, ___) => page,
      transitionDuration: Duration.zero,
      reverseTransitionDuration: Duration.zero,
    );
  }

  Future<void> initializeApp() async {
    debugPrint("🚀 Splash started");

    try {
      final box = Hive.box('session_box');
      final rawSession = box.get('survey_session');

      await Future.delayed(const Duration(milliseconds: 1200));

      if (!mounted) return;

      if (rawSession is Map) {
        final session = Map<String, dynamic>.from(rawSession);

        final districtId = session["district_id"];
        final blockId = session["block_id"];
        final villageId = session["village_id"];
        final authVerified = session["auth_verified"] == true;

        if (districtId != null &&
            blockId != null &&
            villageId != null &&
            authVerified) {
          Navigator.of(context).pushReplacement(
            _noAnimationRoute(const HouseholdEntryScreen()),
          );
          return;
        } else {
          await box.delete('survey_session');
        }
      }

      final districtData = await supabase
          .from('districts')
          .select('id, name')
          .order('name');

      if (!mounted) return;

      final districts = List<Map<String, dynamic>>.from(districtData);

      Navigator.of(context).pushReplacement(
        _noAnimationRoute(
          LocationSetupScreen(
            initialDistricts: districts,
          ),
        ),
      );
    } catch (e) {
      debugPrint("❌ Splash error: $e");

      if (!mounted) return;

      Navigator.of(context).pushReplacement(
        _noAnimationRoute(
          const LocationSetupScreen(),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF0F6FFF),
              Color(0xFF2F80ED),
              Color(0xFF38D39F),
            ],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 28),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.14),
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: Colors.white.withOpacity(0.22)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    height: 110,
                    width: 110,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Image.asset("assets/images/msrls_logo.png"),
                    ),
                  ),
                  const SizedBox(height: 22),
                  const Text(
                    "SHG Survey",
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    "Household Data Collection",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 28),
                  const SizedBox(
                    height: 28,
                    width: 28,
                    child: CircularProgressIndicator(
                      strokeWidth: 3,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}