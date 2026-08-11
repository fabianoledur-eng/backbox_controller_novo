import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'controller_screen.dart';

class ActivationScreen extends StatefulWidget {
  const ActivationScreen({super.key});

  @override
  State<ActivationScreen> createState() => _ActivationScreenState();
}

class _ActivationScreenState extends State<ActivationScreen> {
  late final TextEditingController _keyController = TextEditingController();
  bool _isLoading = false;
  String _errorMessage = "";

  final List<String> _chavesValidas = [
    "MVAV-1001-A9", "MVAV-1002-B4", "MVAV-1003-C7", "MVAV-1004-D2", "MVAV-1005-E8",
    "MVAV-1006-F1", "MVAV-1007-G3", "MVAV-1008-H5", "MVAV-1009-J7", "MVAV-1010-K9",
    "MVAV-1011-L2", "MVAV-1012-M4", "MVAV-1013-N6", "MVAV-1014-P8", "MVAV-1015-Q1",
    "MVAV-1016-R3", "MVAV-1017-S5", "MVAV-1018-T7", "MVAV-1019-U9", "MVAV-1020-V2",
    "MVAV-1021-W4", "MVAV-1022-X6", "MVAV-1023-Y8", "MVAV-1024-Z1", "MVAV-1025-A3",
    "MVAV-1026-B5", "MVAV-1027-C7", "MVAV-1028-D9", "MVAV-1029-E2", "MVAV-1030-F4",
    "MVAV-1031-G6", "MVAV-1032-H8", "MVAV-1033-J1", "MVAV-1034-K3", "MVAV-1035-L5",
    "MVAV-1036-M7", "MVAV-1037-N9", "MVAV-1038-P2", "MVAV-1039-Q4", "MVAV-1040-R6",
    "MVAV-1041-S8", "MVAV-1042-T1", "MVAV-1043-U3", "MVAV-1044-V5", "MVAV-1045-W7",
    "MVAV-1046-X9", "MVAV-1047-Y2", "MVAV-1048-Z4", "MVAV-1049-A6", "MVAV-1050-B8"
  ];

  @override
  void dispose() {
    _keyController.dispose();
    super.dispose();
  }

  Future<void> _verificarChave() async {
    final String chaveDigitada = _keyController.text.trim().toUpperCase();
    if (chaveDigitada.isEmpty) {
      setState(() => _errorMessage = "Por favor, digite sua chave de licença.");
      return;
    }
    setState(() {
      _isLoading = true;
      _errorMessage = "";
    });
    
    await Future.delayed(const Duration(milliseconds: 600));
    final prefs = await SharedPreferences.getInstance();

    // 1. Busca a lista de chaves que já foram queimadas/usadas neste aparelho
    List<String> chavesUsadas = prefs.getStringList('chaves_utilizadas') ?? [];

    // 2. Verifica se a chave digitada está na lista de usadas
    if (chavesUsadas.contains(chaveDigitada)) {
      setState(() {
        _errorMessage = "Esta chave de licença já foi utilizada.";
        _isLoading = false;
      });
      return;
    }

    // 3. Verifica se a chave é válida dentro da sua lista principal
    if (_chavesValidas.contains(chaveDigitada)) {
      // Adiciona a chave atual na lista de chaves queimadas
      chavesUsadas.add(chaveDigitada);
      await prefs.setStringList('chaves_utilizadas', chavesUsadas);
      
      // Ativa o aplicativo
      await prefs.setBool('is_activated', true);
      
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const ControllerScreen()),
      );
    } else {
      setState(() {
        _errorMessage = "Chave de licença inválida. Verifique os caracteres.";
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xff121212),
      body: Center(
        child: SingleChildScrollView(
          child: Container(
            width: 450, 
            padding: const EdgeInsets.all(24.0),
            decoration: BoxDecoration(
              color: const Color(0xff1e1e1e),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xff00e5ff).withAlpha(76), width: 1.5),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.lock_outline, size: 64, color: Color(0xff00e5ff)),
                const SizedBox(height: 16),
                const Text(
                  "Ativação do Aplicativo",
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  "Insira a chave de licença única enviada após a confirmação do pagamento.",
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14, color: Colors.grey.shade400),
                ),
                const SizedBox(height: 24),
                TextField(
                  controller: _keyController,
                  textAlign: TextAlign.center,
                  style: const TextStyle(letterSpacing: 2, fontWeight: FontWeight.bold, fontSize: 16),
                  decoration: InputDecoration(
                    hintText: "X-XXXX-XXXX-XXXX",
                    hintStyle: TextStyle(color: Colors.grey.shade600, letterSpacing: 0),
                    filled: true,
                    fillColor: const Color(0xff2a2a2a),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                  ),
                ),
                if (_errorMessage.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(_errorMessage, style: const TextStyle(color: Colors.redAccent, fontSize: 13)),
                ],
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _verificarChave,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xff00e5ff),
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    child: _isLoading 
                      ? const CircularProgressIndicator(color: Colors.black)
                      : const Text("ATIVAR APLICATIVO", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
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
