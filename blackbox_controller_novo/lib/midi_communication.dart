import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

class MidiMessage {
  final int status;
  final int data1;
  final int? data2;
  
  MidiMessage({required this.status, required this.data1, this.data2});
  
  factory MidiMessage.fromBytes(List<int> bytes) {
    if (bytes.isEmpty) throw ArgumentError('Empty message');
    
    final status = bytes[0];
    final data1 = bytes.length > 1 ? bytes[1] : 0;
    final data2 = bytes.length > 2 ? bytes[2] : null;
    
    return MidiMessage(status: status, data1: data1, data2: data2);
  }
  
  bool get isProgramChange => (status & 0xF0) == 0xC0;
  bool get isControlChange => (status & 0xF0) == 0xB0;
  bool get isNoteOn => (status & 0xF0) == 0x90;
  bool get isNoteOff => (status & 0xF0) == 0x80;
  
  int get channel => status & 0x0F;
}

class MidiCommunicationService {
  BluetoothDevice? _device;
  BluetoothCharacteristic? _midiChar;
  StreamSubscription<List<int>>? _midiSubscription;
  StreamSubscription<BluetoothConnectionState>? _connectionSubscription;

  /// Avisa quando a conexão cai sem o usuário pedir (pedaleira desligada, fora de alcance...)
  final StreamController<void> _connectionLostController = StreamController<void>.broadcast();
  Stream<void> get connectionLostStream => _connectionLostController.stream;
  
  final StreamController<MidiMessage> _messageController = StreamController<MidiMessage>.broadcast();
  final StreamController<int> _presetChangeController = StreamController<int>.broadcast();
  final StreamController<ControlChangeMessage> _controlChangeController = StreamController<ControlChangeMessage>.broadcast();
  final StreamController<List<int>> _sysExMessageController = StreamController<List<int>>.broadcast();
  
  Stream<MidiMessage> get messageStream => _messageController.stream;
  Stream<int> get presetChangeStream => _presetChangeController.stream;
  Stream<ControlChangeMessage> get controlChangeStream => _controlChangeController.stream;
  Stream<List<int>> get sysExMessageStream => _sysExMessageController.stream;
  
  bool get isConnected => _device != null && _midiChar != null;
  
  Future<void> connect(BluetoothDevice device) async {
    _device = device;
    try {
      await device.connect(timeout: const Duration(seconds: 15));
      debugPrint('✅ Bluetooth: Conectado ao dispositivo ${device.platformName}');

      await _connectionSubscription?.cancel();
      _connectionSubscription = device.connectionState.listen((state) {
        if (state == BluetoothConnectionState.disconnected && _device != null) {
          debugPrint('⚠️ Bluetooth: Conexão perdida');
          _connectionSubscription?.cancel();
          _connectionSubscription = null;
          _midiSubscription?.cancel();
          _midiSubscription = null;
          _device = null;
          _midiChar = null;
          if (!_connectionLostController.isClosed) _connectionLostController.add(null);
        }
      });
    } catch (e) {
      debugPrint('❌ Bluetooth: Erro ao conectar: $e');
      rethrow;
    }
  }
  
  Future<void> discoverMidiCharacteristic() async {
    if (_device == null) return;
    
    try {
      debugPrint('🔍 Bluetooth: Descobrindo serviços...');
      final List<BluetoothService> services = await _device!.discoverServices();
      debugPrint('🔍 Bluetooth: ${services.length} serviços encontrados');
      
      final List<String> targetServices = ["03b80e5aede84b33a7516ce34ec4c700", "0000fee700001000800000805f9b34fb"];
      final List<String> targetCharacteristics = ["7772e5db38684112a1a9f2669d106bf3", "0000387200001000800000805f9b34fb"];
      
      for (final BluetoothService s in services) {
        final String cleanServiceUuid = s.uuid.str128.replaceAll('-', '').toLowerCase();
        debugPrint('🔍 Bluetooth: Serviço encontrado: $cleanServiceUuid');
        
        if (targetServices.contains(cleanServiceUuid)) {
          debugPrint('✅ Bluetooth: Serviço MIDI encontrado!');
          
          for (final BluetoothCharacteristic c in s.characteristics) {
            final String cleanCharUuid = c.uuid.str128.replaceAll('-', '').toLowerCase();
            debugPrint('🔍 Bluetooth: Característica: $cleanCharUuid');
            
            if (targetCharacteristics.contains(cleanCharUuid)) {
              _midiChar = c;
              debugPrint('✅ Bluetooth: Característica MIDI encontrada!');
              await _startListening();
              return;
            }
          }
        }
      }
      
      throw Exception('Característica MIDI não encontrada nos serviços disponíveis');
    } catch (e) {
      debugPrint('❌ Bluetooth: Erro ao descobrir característica MIDI: $e');
      rethrow;
    }
  }
  
  Future<void> _startListening() async {
    if (_midiChar == null) return;
    
    await _midiChar!.setNotifyValue(true);
    
    _midiSubscription = _midiChar!.lastValueStream.listen((data) {
      _processIncomingData(data);
    });
  }
  
  void _processIncomingData(List<int> data) {
    List<int> midiData = data;
    if (data.length >= 2 && data[0] == 0x80 && data[1] == 0x80) {
      midiData = data.sublist(2);
    }
    
    if (midiData.isEmpty) return;
    
    try {
      final message = MidiMessage.fromBytes(midiData);
      _messageController.add(message);
      
      if (message.isProgramChange) {
        _presetChangeController.add(message.data1);
      } else if (message.isControlChange && message.data2 != null) {
        _controlChangeController.add(ControlChangeMessage(
          ccNumber: message.data1,
          value: message.data2!,
        ));
      } else if (midiData[0] == 0xF0) {
        _processSysExMessage(midiData);
      }
    } catch (e) {
      // Ignora mensagens inválidas
    }
  }
  
  void _processSysExMessage(List<int> sysExData) {
    debugPrint('📥 MIDI SysEx recebido: ${sysExData.map((b) => '0x${b.toRadixString(16).padLeft(2, '0')}').join(' ')}');
    _sysExMessageController.add(sysExData);
  }
  
  Future<void> sendProgramChange(int programNumber) async {
    if (_midiChar == null) return;
    
    // MIDI Program Change: 0xC0 + channel (0) + program number
    final bytes = [0xC0, programNumber];
    await _midiChar!.write([0x80, 0x80, ...bytes], withoutResponse: true);
  }
  
  Future<void> sendControlChange(int ccNumber, int value) async {
    if (_midiChar == null) {
      debugPrint('❌ MIDI: Não conectado - impossível enviar CC $ccNumber');
      return;
    }
    
    // MIDI Control Change: 0xB0 + channel (0) + CC number + value
    final bytes = [0xB0, ccNumber, value];
    debugPrint('📤 MIDI Enviando CC: canal=0, cc=$ccNumber, valor=$value, bytes=$bytes');
    
    try {
      await _midiChar!.write([0x80, 0x80, ...bytes], withoutResponse: true);
      debugPrint('✅ MIDI: CC $ccNumber enviado com sucesso');
    } catch (e) {
      debugPrint('❌ MIDI: Erro ao enviar CC $ccNumber: $e');
    }
  }
  
  Future<void> sendSysEx(List<int> data) async {
    if (_midiChar == null) {
      debugPrint('❌ MIDI: Não conectado - impossível enviar SysEx');
      return;
    }
    
    final bytes = [0xF0, ...data, 0xF7];
    debugPrint('📤 MIDI Enviando SysEx: bytes=$bytes');
    
    try {
      await _midiChar!.write([0x80, 0x80, ...bytes], withoutResponse: true);
      debugPrint('✅ MIDI: SysEx enviado com sucesso');
    } catch (e) {
      debugPrint('❌ MIDI: Erro ao enviar SysEx: $e');
    }
  }
  
  Future<void> disconnect() async {
    // Desconexão pedida pelo usuário: para de vigiar antes, para não avisar "conexão perdida"
    await _connectionSubscription?.cancel();
    _connectionSubscription = null;
    try {
      await _midiSubscription?.cancel();
      _midiSubscription = null;
      
      if (_midiChar != null) {
        await _midiChar!.setNotifyValue(false);
      }
      
      if (_device != null) {
        await _device!.disconnect();
        debugPrint('✅ Bluetooth: Desconectado com sucesso');
      }
      
      _device = null;
      _midiChar = null;
    } catch (e) {
      debugPrint('❌ Bluetooth: Erro ao desconectar: $e');
      // Limpa os recursos mesmo em caso de erro
      _device = null;
      _midiChar = null;
      _midiSubscription = null;
    }
  }
  
  void dispose() {
    _connectionSubscription?.cancel();
    _connectionLostController.close();
    _midiSubscription?.cancel();
    _messageController.close();
    _presetChangeController.close();
    _controlChangeController.close();
    _sysExMessageController.close();
  }
}

class ControlChangeMessage {
  final int ccNumber;
  final int value;
  
  ControlChangeMessage({required this.ccNumber, required this.value});
  
  bool get isOn => value >= 64;
}