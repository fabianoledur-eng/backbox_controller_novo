import 'package:flutter/material.dart';
import 'midi_communication.dart';
import 'configs.dart';

class PedaleiraStateManager extends ChangeNotifier {
  final MidiCommunicationService _midiService;
  
  int _activePresetIndex = 0;
  final List<PresetConfig> _presets = [];
  final List<EffectBlockConfig> _effectsChain = [];
  
  bool _isConnected = false;
  bool _disposed = false;

  // Evita erro se algum envio MIDI terminar depois que a tela foi fechada
  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
  
  PedaleiraStateManager(this._midiService) {
    _initializeEffectsChain();
  }
  
  void _initializeEffectsChain() {
    _effectsChain.clear();
    _effectsChain.addAll([
      EffectBlockConfig(name: 'FX', ccNumber: 0, activeColor: const Color(0xff4CAF50), isEnabled: false),
      EffectBlockConfig(name: 'AMP', ccNumber: 1, activeColor: const Color(0xffF44336), isEnabled: false),
      EffectBlockConfig(name: 'MOD', ccNumber: 2, activeColor: const Color(0xff2196F3), isEnabled: false),
      EffectBlockConfig(name: 'DLY', ccNumber: 3, activeColor: const Color(0xff9C27B0), isEnabled: false),
      EffectBlockConfig(name: 'REV', ccNumber: 4, activeColor: const Color(0xff009688), isEnabled: false),
      EffectBlockConfig(name: 'CAB', ccNumber: 5, activeColor: const Color(0xffFF9800), isEnabled: false),
    ]);
  }
  
  Future<void> initializePresets(List<PresetConfig> presets) async {
    _presets.clear();
    _presets.addAll(presets);
    notifyListeners();
  }
  
  Future<void> changePreset(int index) async {
    if (index < 0 || index >= _presets.length) return;
    
    _activePresetIndex = index;
    
    // Reseta todos os efeitos para desligado ao mudar de preset
    for (final effect in _effectsChain) {
      effect.isEnabled = false;
    }
    
    notifyListeners();
    
    await _midiService.sendProgramChange(_presets[index].blackboxPresetNumber);
  }
  
  Future<void> toggleEffect(int index) async {
    if (index < 0 || index >= _effectsChain.length) return;
    
    final effect = _effectsChain[index];
    debugPrint('🎛️ Toggle efeito: ${effect.name} (CC ${effect.ccNumber}), estado atual: ${effect.isEnabled}');
    
    final newState = !effect.isEnabled;
    effect.isEnabled = newState;
    notifyListeners();
    
    debugPrint('📤 Enviando toggle MIDI para ${effect.name}...');
    
    await _midiService.sendControlChange(effect.ccNumber, 127);
    await Future.delayed(const Duration(milliseconds: 60));
    await _midiService.sendControlChange(effect.ccNumber, 0);
    
    debugPrint('✅ Toggle enviado para ${effect.name}, novo estado: ${effect.isEnabled}');
    
    await Future.delayed(const Duration(milliseconds: 100));
    if (effect.isEnabled != newState) {
      effect.isEnabled = newState;
      notifyListeners();
      debugPrint('🔄 Corrigindo estado visual de ${effect.name} para $newState');
    }
  }
  
  void setConnectedState(bool connected) {
    _isConnected = connected;
    notifyListeners();
  }
  
  // Getters
  int get activePresetIndex => _activePresetIndex;
  List<PresetConfig> get presets => _presets;
  List<EffectBlockConfig> get effectsChain => _effectsChain;
  bool get isConnected => _isConnected;
  
  PresetConfig get activePreset => _presets.isNotEmpty ? _presets[_activePresetIndex] : _presets[0];
}