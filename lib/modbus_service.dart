import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:math';
import 'models.dart';

// ─── Modbus TCP Connection ───────────────────────────────────────────

class _ModbusConnection {
  final String ip;
  final int port;
  Socket? _socket;
  final List<int> _buffer = [];
  Completer<Uint8List>? _pending;
  int _expectedLength = 0;
  bool _connected = false;

  _ModbusConnection(this.ip, this.port);

  bool get isConnected => _connected;

  Future<void> connect() async {
    if (_connected) return;
    try {
      _socket = await Socket.connect(
        ip, port,
        timeout: const Duration(seconds: 5),
      );
      _connected = true;
      _socket!.listen(
        _onData,
        onError: (e) { _onClose(); },
        onDone: _onClose,
        cancelOnError: false,
      );
    } catch (e) {
      _connected = false;
      rethrow;
    }
  }

  void _onData(Uint8List data) {
    _buffer.addAll(data);
    _tryComplete();
  }

  void _tryComplete() {
    if (_pending == null || _pending!.isCompleted) return;

    // Need at least MBAP header (6 bytes) to know total length
    if (_buffer.length >= 6 && _expectedLength == 0) {
      _expectedLength = (_buffer[4] << 8 | _buffer[5]) + 6;
    }

    if (_expectedLength > 0 && _buffer.length >= _expectedLength) {
      final response = Uint8List.fromList(
        _buffer.sublist(0, _expectedLength),
      );
      _buffer.removeRange(0, _expectedLength);
      _expectedLength = 0;
      if (!_pending!.isCompleted) {
        _pending!.complete(response);
      }
    }
  }

  void _onClose() {
    _connected = false;
    _socket = null;
    if (_pending != null && !_pending!.isCompleted) {
      _pending!.completeError('Connection closed');
    }
  }

  Future<Uint8List> sendRequest(Uint8List request) async {
    if (!_connected || _socket == null) {
      throw Exception('Not connected');
    }

    _buffer.clear();
    _expectedLength = 0;
    _pending = Completer<Uint8List>();

    _socket!.add(request);
    await _socket!.flush();

    return _pending!.future.timeout(
      const Duration(seconds: 5),
      onTimeout: () => throw TimeoutException('Modbus response timeout'),
    );
  }

  Future<void> disconnect() async {
    _connected = false;
    try {
      await _socket?.close();
    } catch (_) {}
    _socket = null;
    _buffer.clear();
    _expectedLength = 0;
  }
}

// ─── Modbus TCP Service ──────────────────────────────────────────────

class ModbusTcpService {
  final Map<String, _ModbusConnection> _connections = {};
  int _transactionId = 0;

  int get _nextTransactionId => (_transactionId++) & 0xFFFF;

  _ModbusConnection _getConnection(String ip, int port) {
    final key = '$ip:$port';
    return _connections.putIfAbsent(key, () => _ModbusConnection(ip, port));
  }

  Future<void> ensureConnected(String ip, int port) async {
    final conn = _getConnection(ip, port);
    if (!conn.isConnected) {
      await conn.connect();
    }
  }

  bool isConnected(String ip, int port) {
    final key = '$ip:$port';
    return _connections[key]?.isConnected ?? false;
  }

  Future<void> disconnect(String ip, int port) async {
    final key = '$ip:$port';
    await _connections[key]?.disconnect();
    _connections.remove(key);
  }

  Future<void> disconnectAll() async {
    for (final conn in _connections.values) {
      await conn.disconnect();
    }
    _connections.clear();
  }

  // ─── Build MBAP + PDU ───────────────────────────────────────────

  Uint8List _buildReadRequest(int unitId, int fc, int register, int quantity) {
    final txId = _nextTransactionId;
    final data = ByteData(12);
    data.setUint16(0, txId, Endian.big);       // Transaction ID
    data.setUint16(2, 0, Endian.big);          // Protocol ID
    data.setUint16(4, 6, Endian.big);          // Length (Unit ID + FC + Addr + Qty)
    data.setUint8(6, unitId);                  // Unit ID
    data.setUint8(7, fc);                      // Function Code
    data.setUint16(8, register, Endian.big);   // Starting Address
    data.setUint16(10, quantity, Endian.big);  // Quantity
    return data.buffer.asUint8List();
  }

  Uint8List _buildWriteCoilRequest(int unitId, int register, bool value) {
    final txId = _nextTransactionId;
    final data = ByteData(12);
    data.setUint16(0, txId, Endian.big);
    data.setUint16(2, 0, Endian.big);
    data.setUint16(4, 6, Endian.big);
    data.setUint8(6, unitId);
    data.setUint8(7, 5); // FC05
    data.setUint16(8, register, Endian.big);
    data.setUint16(10, value ? 0xFF00 : 0x0000, Endian.big);
    return data.buffer.asUint8List();
  }

  Uint8List _buildWriteRegisterRequest(int unitId, int register, int value) {
    final txId = _nextTransactionId;
    final data = ByteData(12);
    data.setUint16(0, txId, Endian.big);
    data.setUint16(2, 0, Endian.big);
    data.setUint16(4, 6, Endian.big);
    data.setUint8(6, unitId);
    data.setUint8(7, 6); // FC06
    data.setUint16(8, register, Endian.big);
    data.setUint16(10, value & 0xFFFF, Endian.big);
    return data.buffer.asUint8List();
  }

  // ─── Parse Responses ────────────────────────────────────────────

  void _checkError(Uint8List response) {
    if (response.length < 9) {
      throw Exception('Response too short (${response.length} bytes)');
    }
    final fc = response[7];
    if (fc & 0x80 != 0) {
      final exceptionCode = response[8];
      throw ModbusException(fc & 0x7F, exceptionCode);
    }
  }

  List<int> _parseReadBitsResponse(Uint8List response) {
    _checkError(response);
    final byteCount = response[8];
    final bits = <int>[];
    for (int i = 0; i < byteCount; i++) {
      for (int bit = 0; bit < 8; bit++) {
        bits.add((response[9 + i] >> bit) & 1);
      }
    }
    return bits;
  }

  List<int> _parseReadRegistersResponse(Uint8List response) {
    _checkError(response);
    final byteCount = response[8];
    final registers = <int>[];
    for (int i = 0; i < byteCount; i += 2) {
      registers.add((response[9 + i] << 8) | response[10 + i]);
    }
    return registers;
  }

  // ─── Value Interpretation ───────────────────────────────────────

  String interpretValue(
    List<int> rawRegisters,
    DataType dataType,
    ByteOrder byteOrder,
    int bitIndex,
    bool isBitFunction,
  ) {
    if (isBitFunction) {
      // rawRegisters here actually contains bit values from _parseReadBitsResponse
      if (bitIndex < rawRegisters.length) {
        return rawRegisters[bitIndex] == 1 ? 'TRUE' : 'FALSE';
      }
      return rawRegisters.isNotEmpty
          ? (rawRegisters[0] == 1 ? 'TRUE' : 'FALSE')
          : 'N/A';
    }

    if (rawRegisters.isEmpty) return 'N/A';

    switch (dataType) {
      case DataType.bool_:
        final regVal = rawRegisters[0];
        return (regVal >> bitIndex) & 1 == 1 ? 'TRUE' : 'FALSE';

      case DataType.uint16:
        return rawRegisters[0].toString();

      case DataType.int16:
        final v = rawRegisters[0];
        return (v >= 0x8000 ? v - 0x10000 : v).toString();

      case DataType.uint32:
        if (rawRegisters.length < 2) return 'N/A';
        final raw = _combine32(rawRegisters[0], rawRegisters[1], byteOrder);
        return raw.toString();

      case DataType.int32:
        if (rawRegisters.length < 2) return 'N/A';
        final raw = _combine32(rawRegisters[0], rawRegisters[1], byteOrder);
        return (raw >= 0x80000000 ? raw - 0x100000000 : raw).toString();

      case DataType.float32:
        if (rawRegisters.length < 2) return 'N/A';
        final raw = _combine32(rawRegisters[0], rawRegisters[1], byteOrder);
        final bd = ByteData(4);
        bd.setUint32(0, raw, Endian.big);
        final f = bd.getFloat32(0, Endian.big);
        // Show reasonable precision
        if (f == f.roundToDouble()) return f.toStringAsFixed(1);
        return f.toStringAsFixed(4);
    }
  }

  int _combine32(int regHi, int regLo, ByteOrder byteOrder) {
    switch (byteOrder) {
      case ByteOrder.bigEndian:
        return (regHi << 16) | regLo;
      case ByteOrder.littleEndian:
        return (regLo << 16) | regHi;
      case ByteOrder.wordSwap:
        final hi = ((regHi & 0xFF) << 8) | ((regHi >> 8) & 0xFF);
        final lo = ((regLo & 0xFF) << 8) | ((regLo >> 8) & 0xFF);
        return (hi << 16) | lo;
    }
  }

  // ─── High-Level Read/Write ──────────────────────────────────────

  Future<String> readEndpoint(
    Endpoint ep,
    ByteOrder byteOrder,
  ) async {
    final conn = _getConnection(ep.ip, ep.port);
    if (!conn.isConnected) await conn.connect();

    final isBitFn = ModbusFC.isBitFunction(ep.functionCode);
    int quantity;
    if (isBitFn) {
      quantity = ep.bitIndex + 1; // Read enough bits
    } else {
      quantity = ep.dataType.registerCount;
    }

    final request = _buildReadRequest(
      ep.unitId,
      ep.functionCode,
      ep.registerAddress,
      quantity,
    );

    final response = await conn.sendRequest(request);

    if (isBitFn) {
      final bits = _parseReadBitsResponse(response);
      return interpretValue(bits, ep.dataType, byteOrder, ep.bitIndex, true);
    } else {
      final regs = _parseReadRegistersResponse(response);
      return interpretValue(regs, ep.dataType, byteOrder, ep.bitIndex, false);
    }
  }

  Future<String> writeEndpoint(
    Endpoint ep,
    String value,
  ) async {
    final conn = _getConnection(ep.ip, ep.port);
    if (!conn.isConnected) await conn.connect();

    Uint8List request;

    if (ep.functionCode == ModbusFC.writeSingleCoil) {
      final boolVal = value.toUpperCase() == 'TRUE' ||
                      value == '1' ||
                      value.toUpperCase() == 'ON';
      request = _buildWriteCoilRequest(ep.unitId, ep.registerAddress, boolVal);
    } else {
      final intVal = int.tryParse(value) ?? 0;
      request = _buildWriteRegisterRequest(
        ep.unitId, ep.registerAddress, intVal,
      );
    }

    final response = await conn.sendRequest(request);
    _checkError(response);

    if (ep.functionCode == ModbusFC.writeSingleCoil) {
      final val = (response[10] << 8) | response[11];
      return val == 0xFF00 ? 'TRUE' : 'FALSE';
    } else {
      final val = (response[10] << 8) | response[11];
      return val.toString();
    }
  }
}

// ─── Exception ───────────────────────────────────────────────────────

class ModbusException implements Exception {
  final int functionCode;
  final int exceptionCode;

  ModbusException(this.functionCode, this.exceptionCode);

  String get message {
    switch (exceptionCode) {
      case 1:  return 'Illegal Function';
      case 2:  return 'Illegal Data Address';
      case 3:  return 'Illegal Data Value';
      case 4:  return 'Server Device Failure';
      case 5:  return 'Acknowledge';
      case 6:  return 'Server Device Busy';
      case 8:  return 'Memory Parity Error';
      case 10: return 'Gateway Path Unavailable';
      case 11: return 'Gateway Target Failed';
      default: return 'Exception Code $exceptionCode';
    }
  }

  @override
  String toString() => 'Modbus Error FC${functionCode}: $message';
}
