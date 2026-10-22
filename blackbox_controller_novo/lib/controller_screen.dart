import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'configs.dart';

class ControllerScreen extends StatefulWidget {
  const ControllerScreen({super.key});

  @override
  State<ControllerScreen> createState() => _ControllerScreenState();
}

class _ControllerScreenState extends State<ControllerScreen> {
  BluetoothDevice? _device;
  BluetoothCharacteristic? _midiChar;
  int _activePresetIndex = 0;
  String _status = "Pedaleira Desconectada";
  int? _blockIdPiscando;

  // Controle da busca/conexão Bluetooth
  StreamSubscription<List<ScanResult>>? _scanSub;
  StreamSubscription<BluetoothConnectionState>? _connSub;
  bool _ocupado = false; // evita várias buscas/conexões ao mesmo tempo

  final List<PresetConfig> _presets = [
    PresetConfig(label: 'PRESET A', subLabel: 'Preset 01', blackboxPresetNumber: 0, ledColor: const Color(0xff00e5ff), initialEffectsState: [false, false, false, false, false, false]),
    PresetConfig(label: 'PRESET B', subLabel: 'Preset 02', blackboxPresetNumber: 1, ledColor: Colors.green, initialEffectsState: [false, false, false, false, false, false]),
    PresetConfig(label: 'PRESET C', subLabel: 'Preset 03', blackboxPresetNumber: 2, ledColor: Colors.purple, initialEffectsState: [false, false, false, false, false, false]),
    PresetConfig(label: 'PRESET D', subLabel: 'Preset 04', blackboxPresetNumber: 3, ledColor: Colors.red, initialEffectsState: [false, false, false, false, false, false]),
    PresetConfig(label: 'PRESET E', subLabel: 'Preset 05', blackboxPresetNumber: 4, ledColor: Colors.orange, initialEffectsState: [false, false, false, false, false, false]),
    PresetConfig(label: 'PRESET F', subLabel: 'Preset 06', blackboxPresetNumber: 5, ledColor: Colors.yellow, initialEffectsState: [false, false, false, false, false, false]),
    PresetConfig(label: 'PRESET G', subLabel: 'Preset 07', blackboxPresetNumber: 6, ledColor: Colors.pink, initialEffectsState: [false, false, false, false, false, false]),
    PresetConfig(label: 'PRESET H', subLabel: 'Preset 08', blackboxPresetNumber: 7, ledColor: Colors.blue, initialEffectsState: [false, false, false, false, false, false]),
  ];

  final List<EffectBlockConfig> _effectsChain = [
    EffectBlockConfig(name: 'FX', ccNumber: 0, activeColor: Colors.green, isEnabled: false),
    EffectBlockConfig(name: 'AMP', ccNumber: 1, activeColor: Colors.red, isEnabled: false),
    EffectBlockConfig(name: 'MOD', ccNumber: 2, activeColor: Colors.blue, isEnabled: false),
    EffectBlockConfig(name: 'DLY', ccNumber: 3, activeColor: Colors.purple, isEnabled: false),
    EffectBlockConfig(name: 'REV', ccNumber: 4, activeColor: Colors.teal, isEnabled: false),
    EffectBlockConfig(name: 'CAB', ccNumber: 5, activeColor: Colors.orange, isEnabled: false),
  ];

  @override
  void initState() {
    super.initState();
    _carregarPresetsSalvos();
  }

  @override
  void dispose() {
    _scanSub?.cancel();
    _connSub?.cancel();
    FlutterBluePlus.stopScan();
    _device?.disconnect();
    super.dispose();
  }

  void _setStatus(String texto) {
    if (!mounted) return;
    setState(() => _status = texto);
  }

  Future<void> _carregarPresetsSalvos() async {
    final prefs = await SharedPreferences.getInstance();
    final String? presetsJson = prefs.getString('saved_presets_data');

    if (presetsJson != null) {
      try {
        final List<dynamic> decodedList = jsonDecode(presetsJson);
        if (!mounted) return;
        setState(() {
          for (int i = 0; i < decodedList.length && i < _presets.length; i++) {
            _presets[i].label = decodedList[i]['label'] ?? _presets[i].label;
            _presets[i].subLabel = decodedList[i]['subLabel'] ?? _presets[i].subLabel;
            _presets[i].blackboxPresetNumber = decodedList[i]['number'] ?? _presets[i].blackboxPresetNumber;
          }
        });
      } catch (e) {
        debugPrint("Erro ao carregar dados salvos: $e");
      }
    }
  }

  Future<void> _salvarPresetsNoDispositivo() async {
    final prefs = await SharedPreferences.getInstance();
    final List<Map<String, dynamic>> listaParaSalvar = _presets
        .map((p) => {
              'label': p.label,
              'subLabel': p.subLabel,
              'number': p.blackboxPresetNumber,
            })
        .toList();

    await prefs.setString('saved_presets_data', jsonEncode(listaParaSalvar));
  }

  // Botão de Bluetooth: conecta se estiver desconectado, desconecta se estiver conectado
  Future<void> _conectarBlackbox() async {
    if (_ocupado) return;
    if (_device != null || _midiChar != null) {
      await _desconectar();
      return;
    }

    _ocupado = true;
    try {
      // 1. O aparelho tem Bluetooth?
      if (!await FlutterBluePlus.isSupported) {
        _setStatus("Este aparelho não tem Bluetooth");
        return;
      }

      // 2. O Bluetooth está ligado? (no Android tenta ligar sozinho)
      if (!await _bluetoothLigado()) {
        _setStatus("Ligue o Bluetooth do celular e tente de novo");
        return;
      }

      // 3. Procura a pedaleira (máx. 6 segundos)
      _setStatus("Buscando...");
      final BluetoothDevice? encontrado = await _procurarPedaleira();
      if (encontrado == null) {
        _setStatus("Pedaleira não encontrada. Ligue-a e tente de novo");
        return;
      }

      // 4. Conecta
      _device = encontrado;
      _setStatus("Conectando...");
      await encontrado.connect(timeout: const Duration(seconds: 10));

      // 5. Avisa se a conexão cair (pedaleira desligada, fora de alcance...)
      await _connSub?.cancel();
      _connSub = encontrado.connectionState.listen((estado) {
        if (estado == BluetoothConnectionState.disconnected && _device != null) {
          _connSub?.cancel();
          _connSub = null;
          if (!mounted) return;
          setState(() {
            _device = null;
            _midiChar = null;
            _status = "Conexão perdida. Toque no Bluetooth para reconectar";
          });
        }
      });

      // 6. Encontra o canal MIDI
      await _acharMidi();
    } catch (e) {
      debugPrint("Erro ao conectar: $e");
      await _desconectar(mensagem: "Falha ao conectar. Tente novamente");
    } finally {
      _ocupado = false;
    }
  }

  Future<bool> _bluetoothLigado() async {
    BluetoothAdapterState estado = await FlutterBluePlus.adapterState
        .where((s) => s != BluetoothAdapterState.unknown)
        .first
        .timeout(const Duration(seconds: 3), onTimeout: () => BluetoothAdapterState.unknown);

    if (estado == BluetoothAdapterState.on) return true;

    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      try {
        await FlutterBluePlus.turnOn(); // mostra o pedido do sistema para ligar o Bluetooth
        estado = await FlutterBluePlus.adapterState
            .where((s) => s == BluetoothAdapterState.on)
            .first
            .timeout(const Duration(seconds: 5), onTimeout: () => BluetoothAdapterState.off);
        return estado == BluetoothAdapterState.on;
      } catch (_) {
        return false;
      }
    }
    return false;
  }

  Future<BluetoothDevice?> _procurarPedaleira() async {
    final completer = Completer<BluetoothDevice?>();

    await _scanSub?.cancel();
    _scanSub = FlutterBluePlus.onScanResults.listen(
      (results) {
        for (final ScanResult r in results) {
          final String nome = (r.advertisementData.advName.isNotEmpty
                  ? r.advertisementData.advName
                  : r.device.platformName)
              .toUpperCase();
          if ((nome.contains('M-VAVE') || nome.contains('BLACKBOX')) && !completer.isCompleted) {
            completer.complete(r.device);
            return;
          }
        }
      },
      onError: (e) {
        if (!completer.isCompleted) completer.complete(null);
      },
    );

    try {
      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 6));
      // startScan com timeout só termina quando a busca acaba;
      // se a pedaleira foi achada antes, o completer já tem o resultado.
      return await completer.future.timeout(const Duration(seconds: 7), onTimeout: () => null);
    } finally {
      await FlutterBluePlus.stopScan();
      await _scanSub?.cancel();
      _scanSub = null;
    }
  }

  Future<void> _desconectar({String mensagem = "Pedaleira Desconectada"}) async {
    _setStatus("Desconectando...");
    await _connSub?.cancel();
    _connSub = null;
    await _scanSub?.cancel();
    _scanSub = null;
    try {
      await FlutterBluePlus.stopScan();
      await _device?.disconnect();
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _device = null;
      _midiChar = null;
      _status = mensagem;
    });
  }

  Future<void> _acharMidi() async {
    if (_device == null) return;
    final List<BluetoothService> services = await _device!.discoverServices();
    const List<String> targetServices = ["03b80e5aede84b33a7516ce34ec4c700", "0000fee700001000800000805f9b34fb"];
    const List<String> targetCharacteristics = ["7772e5db38684112a1a9f2669d106bf3", "0000387200001000800000805f9b34fb"];

    for (final BluetoothService s in services) {
      final String cleanServiceUuid = s.uuid.str128.replaceAll('-', '').toLowerCase();
      if (targetServices.contains(cleanServiceUuid)) {
        for (final BluetoothCharacteristic c in s.characteristics) {
          final String cleanCharUuid = c.uuid.str128.replaceAll('-', '').toLowerCase();
          if (targetCharacteristics.contains(cleanCharUuid)) {
            if (!mounted) return;
            setState(() {
              _midiChar = c;
              _status = "CONECTADO!";
            });
            return;
          }
        }
      }
    }
    await _desconectar(mensagem: "Canal MIDI não localizado nesta pedaleira");
  }

  Future<void> _enviarMidi(List<int> bytes) async {
    if (_midiChar != null) {
      await _midiChar!.write([0x80, 0x80, ...bytes], withoutResponse: true);
    }
  }

  Future<void> _mudarPreset(int index) async {
    setState(() {
      _activePresetIndex = index;
      for (final block in _effectsChain) {
        block.isEnabled = false;
      }
    });
    _enviarMidi([192, _presets[index].blackboxPresetNumber]);
  }

  void _handleBlockClick(int index) {
    setState(() => _blockIdPiscando = index);
    Future.delayed(const Duration(milliseconds: 120), () {
      if (mounted) setState(() => _blockIdPiscando = null);
    });
    _toggleEffect(index);
  }

  Future<void> _toggleEffect(int index) async {
    setState(() {
      _effectsChain[index].isEnabled = !_effectsChain[index].isEnabled;
    });
    _enviarMidi([176, _effectsChain[index].ccNumber, 127]);
    await Future.delayed(const Duration(milliseconds: 60));
    _enviarMidi([176, _effectsChain[index].ccNumber, 0]);
  }

  @override
  Widget build(BuildContext context) {
    final bool isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 8.0, bottom: 4.0),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    const Text(
                      "Blackbox Connect",
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: IconButton(
                        icon: const Icon(Icons.bluetooth),
                        color: _midiChar != null ? const Color(0xff00e5ff) : Colors.white,
                        onPressed: _conectarBlackbox,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                _status,
                style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 12),
              ),
              const SizedBox(height: 10),
              Expanded(
                child: CustomAppLayout.buildGrid(
                  isLandscape,
                  _presets,
                  (index) {
                    final isSelected = _activePresetIndex == index;
                    return GestureDetector(
                      onTap: () => _mudarPreset(index),
                      onLongPress: () => _abrirConfiguracaoPreset(index),
                      child: Container(
                        decoration: BoxDecoration(
                          color: const Color(0xff1e1e1e),
                          borderRadius: BorderRadius.circular(12.0),
                          border: Border.all(
                            color: isSelected ? _presets[index].ledColor : Colors.transparent,
                            width: 2.5,
                          ),
                        ),
                        child: Stack(
                          children: [
                            Positioned(
                              top: 10,
                              left: 10,
                              child: Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: isSelected ? _presets[index].ledColor : Colors.grey,
                                ),
                              ),
                            ),
                            Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  FittedBox(
                                    fit: BoxFit.scaleDown,
                                    child: Text(
                                      _presets[index].label,
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: isLandscape ? 16 : 18,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    _presets[index].subLabel,
                                    style: TextStyle(color: Colors.grey, fontSize: isLandscape ? 11 : 13),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 12),
              Container(
                height: isLandscape ? 70 : 85,
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  children: List.generate(_effectsChain.length, (index) {
                    final block = _effectsChain[index];
                    bool ledAceso = block.isEnabled;
                    return Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4.0),
                        child: GestureDetector(
                          onTap: () => _handleBlockClick(index),
                          child: Container(
                            decoration: BoxDecoration(
                              color: _blockIdPiscando == index ? Colors.white24 : const Color(0xff1a1a1a),
                              borderRadius: BorderRadius.circular(8.0),
                              border: Border.all(
                                color: block.activeColor,
                                width: 2,
                              ),
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  block.name,
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.white),
                                ),
                                const SizedBox(height: 6),
                                Container(
                                  width: 6,
                                  height: 6,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: ledAceso ? block.activeColor : Colors.transparent,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  }),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _abrirConfiguracaoPreset(int index) {
    final nCtrl = TextEditingController(text: _presets[index].label);
    final sCtrl = TextEditingController(text: _presets[index].subLabel);
    final pCtrl = TextEditingController(text: _presets[index].blackboxPresetNumber.toString());
    String? erroNumero;

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xff1a1a1a),
          title: Text('Editar ${_presets[index].label}', style: const TextStyle(color: Colors.white)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: nCtrl, decoration: const InputDecoration(labelText: 'Nome do Preset')),
                TextField(controller: sCtrl, decoration: const InputDecoration(labelText: 'Subtítulo')),
                TextField(
                  controller: pCtrl,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'Número do Programa MIDI (0 a 127)',
                    errorText: erroNumero,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Sair'),
            ),
            TextButton(
              onPressed: () {
                final int? numero = int.tryParse(pCtrl.text.trim());
                if (numero == null || numero < 0 || numero > 127) {
                  setDialogState(() => erroNumero = 'Digite um número de 0 a 127');
                  return;
                }
                setState(() {
                  _presets[index].label = nCtrl.text.trim().isEmpty ? _presets[index].label : nCtrl.text.trim();
                  _presets[index].subLabel = sCtrl.text.trim();
                  _presets[index].blackboxPresetNumber = numero;
                });
                _salvarPresetsNoDispositivo();
                Navigator.pop(dialogContext);
              },
              child: const Text('Salvar'),
            ),
          ],
        ),
      ),
    ).then((_) {
      // Só descarta os campos depois que a janela terminou de fechar
      nCtrl.dispose();
      sCtrl.dispose();
      pCtrl.dispose();
    });
  }
}
