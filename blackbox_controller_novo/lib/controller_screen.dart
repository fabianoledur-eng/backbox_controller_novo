import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';
import 'configs.dart';
import 'midi_communication.dart';
import 'pedaleira_state_manager.dart';

class ControllerScreen extends StatefulWidget {
  const ControllerScreen({super.key});

  @override
  State<ControllerScreen> createState() => _ControllerScreenState();
}

class _ControllerScreenState extends State<ControllerScreen> {
  final MidiCommunicationService _midiService = MidiCommunicationService();
  late PedaleiraStateManager _stateManager;
  
  String _status = "Pedaleira Desconectada";
  int? _blockIdPiscando;

  // Controle da busca/conexão Bluetooth
  StreamSubscription<List<ScanResult>>? _scanSub;
  StreamSubscription<void>? _connectionLostSub;
  bool _ocupado = false; // evita várias buscas/conexões ao mesmo tempo

  final List<PresetConfig> _presets = [
    PresetConfig(label: 'PRESET A', subLabel: 'Preset 01', blackboxPresetNumber: 0, ledColor: const Color(0xff00ff88), initialEffectsState: [false, false, false, false, false, false]),
    PresetConfig(label: 'PRESET B', subLabel: 'Preset 02', blackboxPresetNumber: 1, ledColor: const Color(0xff9d4edd), initialEffectsState: [false, false, false, false, false, false]),
    PresetConfig(label: 'PRESET C', subLabel: 'Preset 03', blackboxPresetNumber: 2, ledColor: const Color(0xff00d4ff), initialEffectsState: [false, false, false, false, false, false]),
    PresetConfig(label: 'PRESET D', subLabel: 'Preset 04', blackboxPresetNumber: 3, ledColor: const Color(0xffff6b35), initialEffectsState: [false, false, false, false, false, false]),
    PresetConfig(label: 'PRESET E', subLabel: 'Preset 05', blackboxPresetNumber: 4, ledColor: const Color(0xffff006e), initialEffectsState: [false, false, false, false, false, false]),
    PresetConfig(label: 'PRESET F', subLabel: 'Preset 06', blackboxPresetNumber: 5, ledColor: const Color(0xff8338ec), initialEffectsState: [false, false, false, false, false, false]),
    PresetConfig(label: 'PRESET G', subLabel: 'Preset 07', blackboxPresetNumber: 6, ledColor: const Color(0xff3a86ff), initialEffectsState: [false, false, false, false, false, false]),
    PresetConfig(label: 'PRESET H', subLabel: 'Preset 08', blackboxPresetNumber: 7, ledColor: const Color(0xfffb5607), initialEffectsState: [false, false, false, false, false, false]),
  ];

  @override
  void initState() {
    super.initState();
    _stateManager = PedaleiraStateManager(_midiService);
    _stateManager.initializePresets(_presets);
    _initializeStateListeners();
    _connectionLostSub = _midiService.connectionLostStream.listen((_) {
      _stateManager.setConnectedState(false);
      _setStatus("Conexão perdida. Toque no Bluetooth para reconectar");
    });
    // Carrega os presets salvos de forma assíncrona sem bloquear a UI
    Future.microtask(() => _carregarPresetsSalvos());
  }

  @override
  void dispose() {
    _scanSub?.cancel();
    _connectionLostSub?.cancel();
    _stateManager.removeListener(_onStateChanged);
    _stateManager.dispose();
    FlutterBluePlus.stopScan();
    _midiService.disconnect().whenComplete(_midiService.dispose);
    super.dispose();
  }

  void _setStatus(String texto) {
    if (!mounted) return;
    setState(() => _status = texto);
  }

  void _onStateChanged() {
    if (mounted) setState(() {});
  }

  void _initializeStateListeners() {
    _stateManager.addListener(_onStateChanged);
  }

  Future<void> _carregarPresetsSalvos() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? presetsJson = prefs.getString('saved_presets_data');

      if (presetsJson != null && presetsJson.isNotEmpty) {
        final List<dynamic> decodedList = jsonDecode(presetsJson);
        bool hasChanges = false;
        
        for (int i = 0; i < decodedList.length && i < _presets.length; i++) {
          final newLabel = (decodedList[i]['label'] as String?) ?? _presets[i].label;
          final newSubLabel = (decodedList[i]['subLabel'] as String?) ?? _presets[i].subLabel;
          final newNumber = (decodedList[i]['number'] as int?) ?? _presets[i].blackboxPresetNumber;
          final newColor = decodedList[i]['color'] != null 
              ? Color(decodedList[i]['color'] as int) 
              : _presets[i].ledColor;
          
          // Só atualiza se houver mudanças
          if (_presets[i].label != newLabel || 
              _presets[i].subLabel != newSubLabel || 
              _presets[i].blackboxPresetNumber != newNumber ||
              _presets[i].ledColor != newColor) {
            _presets[i].label = newLabel;
            _presets[i].subLabel = newSubLabel;
            _presets[i].blackboxPresetNumber = newNumber;
            _presets[i].ledColor = newColor;
            hasChanges = true;
          }
        }
        
        // Só atualiza o state manager se houver mudanças
        if (hasChanges) {
          await _stateManager.initializePresets(_presets);
        }
      }
    } catch (e) {
      debugPrint("Erro ao carregar dados salvos: $e");
    }
  }

  Future<void> _salvarPresetsNoDispositivo() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final List<Map<String, dynamic>> listaParaSalvar = _presets
          .map((p) => {
                'label': p.label,
                'subLabel': p.subLabel,
                'number': p.blackboxPresetNumber,
                'color': p.ledColor.toARGB32(),
              })
          .toList();

      await prefs.setString('saved_presets_data', jsonEncode(listaParaSalvar));
    } catch (e) {
      debugPrint("Erro ao salvar presets: $e");
    }
  }

  Future<bool> _requestBluetoothPermissions() async {
    // As permissões em tempo de execução só existem no Android (12+ usa SCAN/CONNECT).
    // No iPhone o próprio sistema pergunta na primeira conexão.
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return true;

    final Map<Permission, PermissionStatus> statuses = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
    ].request();

    final bool allGranted = statuses.values.every((status) => status.isGranted);

    if (!allGranted) {
      debugPrint('❌ Permissões negadas: ${statuses.entries.where((e) => !e.value.isGranted).map((e) => e.key).join(', ')}');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Permita o acesso a "Dispositivos próximos" para conectar à pedaleira.'),
            duration: const Duration(seconds: 4),
            action: SnackBarAction(
              label: 'Configurações',
              onPressed: () {
                openAppSettings();
              },
            ),
          ),
        );
      }
      return false;
    }

    debugPrint('✅ Todas as permissões Bluetooth concedidas');
    return true;
  }

  // Botão de Bluetooth: conecta se estiver desconectado, desconecta se estiver conectado
  Future<void> _conectarBlackbox() async {
    if (_ocupado) return;

    if (_midiService.isConnected) {
      _ocupado = true;
      _setStatus("Desconectando...");
      await _midiService.disconnect();
      _stateManager.setConnectedState(false);
      _setStatus("Pedaleira Desconectada");
      _ocupado = false;
      return;
    }

    _ocupado = true;
    try {
      // 1. Permissões
      if (!await _requestBluetoothPermissions()) {
        _setStatus("Permissões negadas");
        return;
      }

      // 2. O aparelho tem Bluetooth?
      if (!await FlutterBluePlus.isSupported) {
        _setStatus("Bluetooth não suportado");
        return;
      }

      // 3. O Bluetooth está ligado? (no Android tenta ligar sozinho)
      if (!await _bluetoothLigado()) {
        _setStatus("Ligue o Bluetooth do celular e tente de novo");
        return;
      }

      // 4. Procura a pedaleira (máx. 8 segundos)
      _setStatus("Buscando...");
      final BluetoothDevice? encontrado = await _procurarPedaleira();
      if (encontrado == null) {
        _setStatus("Nenhum dispositivo encontrado. Ligue a pedaleira e tente de novo");
        return;
      }

      // 5. Conecta e encontra o canal MIDI
      _setStatus("Conectando...");
      await _connectToDevice(encontrado);
    } catch (e) {
      debugPrint('❌ Bluetooth: Erro ao buscar: $e');
      _setStatus("Erro ao buscar. Tente novamente");
    } finally {
      _ocupado = false;
    }
  }

  Future<bool> _bluetoothLigado() async {
    // Logo que o app abre o estado pode ainda ser "unknown": espera a resposta real
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
            debugPrint('✅ Bluetooth: Dispositivo alvo encontrado: $nome');
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
      debugPrint('🔍 Bluetooth: Iniciando scan...');
      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 8));
      return await completer.future.timeout(const Duration(seconds: 9), onTimeout: () => null);
    } finally {
      await FlutterBluePlus.stopScan();
      await _scanSub?.cancel();
      _scanSub = null;
    }
  }

  Future<void> _connectToDevice(BluetoothDevice device) async {
    try {
      debugPrint('🔗 Bluetooth: Conectando ao dispositivo ${device.platformName}...');
      await _midiService.connect(device);

      debugPrint('🔍 Bluetooth: Descobrindo serviços MIDI...');
      await _midiService.discoverMidiCharacteristic();

      _stateManager.setConnectedState(true);
      _setStatus("CONECTADO!");
      debugPrint('✅ Bluetooth: Conexão estabelecida com sucesso!');
    } catch (e) {
      debugPrint('❌ Bluetooth: Erro de conexão: $e');
      await _midiService.disconnect();
      _stateManager.setConnectedState(false);
      _setStatus("Falha ao conectar. Tente novamente");
    }
  }

  Future<void> _mudarPreset(int index) async {
    await _stateManager.changePreset(index);
  }

  void _handleBlockClick(int index) {
    setState(() => _blockIdPiscando = index);
    Future.delayed(const Duration(milliseconds: 120), () {
      if (mounted) setState(() => _blockIdPiscando = null);
    });
    _toggleEffect(index);
  }

  Future<void> _toggleEffect(int index) async {
    await _stateManager.toggleEffect(index);
    // Força um rebuild extra para garantir atualização visual
    if (mounted) setState(() {});
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
                        color: _stateManager.isConnected ? const Color(0xff00e5ff) : Colors.white,
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
                  _stateManager.presets,
                  (index) {
                    final isSelected = _stateManager.activePresetIndex == index;
                    final preset = _stateManager.presets[index];
                    return InkWell(
                      onTap: () => _mudarPreset(index),
                      onLongPress: () => _abrirConfiguracaoPreset(index),
                      splashColor: Colors.white.withValues(alpha: 0.3),
                      highlightColor: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(16.0),
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              preset.ledColor.withValues(alpha: 0.8),
                              preset.ledColor.withValues(alpha: 0.4),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(16.0),
                          border: Border.all(
                            color: isSelected ? Colors.white : Colors.white.withValues(alpha: 0.3),
                            width: isSelected ? 3 : 1,
                          ),
                          boxShadow: isSelected
                              ? [
                                  BoxShadow(
                                    color: preset.ledColor.withValues(alpha: 0.8),
                                    blurRadius: 25,
                                    spreadRadius: 4,
                                  ),
                                  BoxShadow(
                                    color: Colors.white.withValues(alpha: 0.3),
                                    blurRadius: 15,
                                    spreadRadius: 2,
                                  ),
                                ]
                              : [
                                  BoxShadow(
                                    color: preset.ledColor.withValues(alpha: 0.3),
                                    blurRadius: 10,
                                    spreadRadius: 1,
                                  ),
                                ],
                        ),
                        child: Stack(
                          children: [
                            // Conteúdo do preset
                            Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  FittedBox(
                                    fit: BoxFit.scaleDown,
                                    child: Text(
                                      preset.label,
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: isLandscape ? 18 : 22,
                                        shadows: [
                                          Shadow(
                                            color: Colors.black.withValues(alpha: 0.5),
                                            blurRadius: 8,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    preset.subLabel,
                                    style: TextStyle(
                                      color: Colors.white70,
                                      fontSize: isLandscape ? 12 : 14,
                                      fontWeight: FontWeight.w500,
                                      shadows: [
                                        Shadow(
                                          color: Colors.black.withValues(alpha: 0.3),
                                          blurRadius: 4,
                                        ),
                                      ],
                                    ),
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
                  children: List.generate(_stateManager.effectsChain.length, (index) {
                    final block = _stateManager.effectsChain[index];
                    bool ledAceso = block.isEnabled;
                    return Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4.0),
                        child: InkWell(
                          onTap: () => _handleBlockClick(index),
                          splashColor: Colors.white.withValues(alpha: 0.3),
                          highlightColor: Colors.white.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(8.0),
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
                                const SizedBox(height: 12),
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
    debugPrint('Abrindo configuração do preset $index');
    try {
      final nCtrl = TextEditingController(text: _stateManager.presets[index].label);
      final sCtrl = TextEditingController(text: _stateManager.presets[index].subLabel);
      final pCtrl = TextEditingController(text: _stateManager.presets[index].blackboxPresetNumber.toString());
      
      // Lista de cores disponíveis estilo Quad Cortex
      final List<Color> availableColors = [
        const Color(0xff00ff88), // Verde neon
        const Color(0xff9d4edd), // Roxo
        const Color(0xff00d4ff), // Ciano
        const Color(0xffff6b35), // Laranja
        const Color(0xffff006e), // Rosa neon
        const Color(0xff8338ec), // Roxo escuro
        const Color(0xff3a86ff), // Azul
        const Color(0xfffb5607), // Laranja escuro
        const Color(0xffFFD236), // Amarelo
        const Color(0xff6954FF), // Roxo claro
        const Color(0xff00FFDD), // Verde água
        const Color(0xffE44A5D), // Vermelho rosado
        const Color(0xffFF2727), // Vermelho
        const Color(0xff87DAFF), // Azul claro
        const Color(0xffFF7000), // Laranja vibrante
        const Color(0xff0A74E0), // Azul royal
        const Color(0xff3500F1), // Índigo
      ];
      
      int selectedColorIndex = availableColors.indexOf(_stateManager.presets[index].ledColor);
      if (selectedColorIndex == -1) selectedColorIndex = 0;
      String? erroNumero;
      
      showDialog(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, dialogSetState) => AlertDialog(
            backgroundColor: const Color(0xff1a1a1a),
            title: Text('Editar ${_stateManager.presets[index].label}', style: const TextStyle(color: Colors.white)),
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
                  const SizedBox(height: 20),
                  const Text('Cor:', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.maxFinite,
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: List.generate(availableColors.length, (colorIndex) {
                        return GestureDetector(
                          onTap: () {
                            dialogSetState(() {
                              selectedColorIndex = colorIndex;
                            });
                          },
                          child: Container(
                            width: 50,
                            height: 50,
                            decoration: BoxDecoration(
                              color: availableColors[colorIndex],
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: selectedColorIndex == colorIndex ? Colors.white : Colors.grey,
                                width: selectedColorIndex == colorIndex ? 3 : 1,
                              ),
                              boxShadow: selectedColorIndex == colorIndex
                                  ? [
                                      BoxShadow(
                                        color: availableColors[colorIndex],
                                        blurRadius: 10,
                                        spreadRadius: 2,
                                      ),
                                    ]
                                  : null,
                            ),
                          ),
                        );
                      }),
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
                onPressed: () async {
                  final int? numero = int.tryParse(pCtrl.text.trim());
                  if (numero == null || numero < 0 || numero > 127) {
                    dialogSetState(() => erroNumero = 'Digite um número de 0 a 127');
                    return;
                  }
                  final String nome = nCtrl.text.trim().isEmpty
                      ? _stateManager.presets[index].label
                      : nCtrl.text.trim();
                  final String sub = sCtrl.text.trim();
                  final Color cor = availableColors[selectedColorIndex];

                  // Atualiza no state manager (fonte de verdade) e na lista local
                  for (final p in [_stateManager.presets[index], _presets[index]]) {
                    p.label = nome;
                    p.subLabel = sub;
                    p.blackboxPresetNumber = numero;
                    p.ledColor = cor;
                  }

                  Navigator.pop(dialogContext);
                  await _salvarPresetsNoDispositivo();
                  if (mounted) setState(() {});
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
    } catch (e) {
      debugPrint('Erro ao abrir configuração: $e');
    }
  }
}
