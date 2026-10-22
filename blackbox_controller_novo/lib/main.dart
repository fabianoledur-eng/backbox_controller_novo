import 'package:flutter/material.dart';
import 'controller_screen.dart';
import 'activation_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  // Inicialização síncrona instantânea (Garante carregamento imediato)
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const QuadCortexApp());
}

class QuadCortexApp extends StatefulWidget {
  const QuadCortexApp({super.key});

  @override
  State<QuadCortexApp> createState() => _QuadCortexAppState();
}

class _QuadCortexAppState extends State<QuadCortexApp> {
  bool? _isActivated;

  @override
  void initState() {
    super.initState();
    _checarAtivacao();
  }

  // Carrega o banco em segundo plano sem travar a inicialização do app
  Future<void> _checarAtivacao() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _isActivated = prefs.getBool('is_activated') ?? false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xff121212),
        primaryColor: const Color(0xff00e5ff),
      ),
      // Enquanto lê a memória, mostra uma tela preta nativa limpa instantânea
      home: _isActivated == null
          ? const Scaffold(backgroundColor: Color(0xff121212), body: Center(child: CircularProgressIndicator(color: Color(0xff00e5ff))))
          : (_isActivated! ? const ControllerScreen() : const ActivationScreen()),
    );
  }
}
