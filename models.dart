import 'dart:convert';

// ─── Enums ───────────────────────────────────────────────────────────

enum DataType { bool_, int16, uint16, int32, uint32, float32 }

extension DataTypeExt on DataType {
  String get label {
    switch (this) {
      case DataType.bool_:   return 'BOOL';
      case DataType.int16:   return 'INT16';
      case DataType.uint16:  return 'UINT16';
      case DataType.int32:   return 'INT32';
      case DataType.uint32:  return 'UINT32';
      case DataType.float32: return 'FLOAT32';
    }
  }

  int get registerCount {
    switch (this) {
      case DataType.bool_:
      case DataType.int16:
      case DataType.uint16:
        return 1;
      case DataType.int32:
      case DataType.uint32:
      case DataType.float32:
        return 2;
    }
  }

  static DataType fromString(String s) {
    return DataType.values.firstWhere(
      (e) => e.label == s || e.name == s,
      orElse: () => DataType.uint16,
    );
  }
}

enum ByteOrder { bigEndian, littleEndian, wordSwap }

extension ByteOrderExt on ByteOrder {
  String get label {
    switch (this) {
      case ByteOrder.bigEndian:    return 'Big-Endian (AB CD)';
      case ByteOrder.littleEndian: return 'Little-Endian (CD AB)';
      case ByteOrder.wordSwap:    return 'Word-Swap (BA DC)';
    }
  }

  static ByteOrder fromString(String s) {
    return ByteOrder.values.firstWhere(
      (e) => e.label == s || e.name == s,
      orElse: () => ByteOrder.bigEndian,
    );
  }
}

enum ConnectionStatus { disconnected, connecting, connected, error }

enum PollingRate { manual, ms500, s1, s5, s10 }

extension PollingRateExt on PollingRate {
  String get label {
    switch (this) {
      case PollingRate.manual: return 'Manual';
      case PollingRate.ms500:  return '500 ms';
      case PollingRate.s1:     return '1 s';
      case PollingRate.s5:     return '5 s';
      case PollingRate.s10:    return '10 s';
    }
  }

  Duration? get duration {
    switch (this) {
      case PollingRate.manual: return null;
      case PollingRate.ms500:  return const Duration(milliseconds: 500);
      case PollingRate.s1:     return const Duration(seconds: 1);
      case PollingRate.s5:     return const Duration(seconds: 5);
      case PollingRate.s10:    return const Duration(seconds: 10);
    }
  }

  static PollingRate fromString(String s) {
    return PollingRate.values.firstWhere(
      (e) => e.label == s || e.name == s,
      orElse: () => PollingRate.manual,
    );
  }
}

// ─── Function Code Helper ────────────────────────────────────────────

class ModbusFC {
  static const int readCoils            = 1;
  static const int readDiscreteInputs   = 2;
  static const int readHoldingRegisters = 3;
  static const int readInputRegisters   = 4;
  static const int writeSingleCoil      = 5;
  static const int writeSingleRegister  = 6;

  static bool isRead(int fc)  => fc >= 1 && fc <= 4;
  static bool isWrite(int fc) => fc == 5 || fc == 6;
  static bool isBitFunction(int fc) => fc == 1 || fc == 2 || fc == 5;

  static String label(int fc) {
    switch (fc) {
      case 1:  return 'FC01 Read Coils';
      case 2:  return 'FC02 Read Disc.Inp.';
      case 3:  return 'FC03 Read Hold.Reg.';
      case 4:  return 'FC04 Read Inp.Reg.';
      case 5:  return 'FC05 Write Coil';
      case 6:  return 'FC06 Write Register';
      default: return 'FC${fc.toString().padLeft(2, '0')}';
    }
  }

  static String shortLabel(int fc) {
    switch (fc) {
      case 1:  return 'FC01';
      case 2:  return 'FC02';
      case 3:  return 'FC03';
      case 4:  return 'FC04';
      case 5:  return 'FC05';
      case 6:  return 'FC06';
      default: return 'FC$fc';
    }
  }
}

// ─── Endpoint Model ──────────────────────────────────────────────────

class Endpoint {
  String id;
  String ip;
  int port;
  int unitId;
  int functionCode;
  int registerAddress;
  DataType dataType;
  int bitIndex;

  // Runtime state (not persisted)
  String? currentValue;
  String writeValue;
  ConnectionStatus status;
  String? errorMessage;
  bool isExpanded;

  Endpoint({
    String? id,
    this.ip = '192.168.0.1',
    this.port = 502,
    this.unitId = 3,
    this.functionCode = 3,
    this.registerAddress = 0,
    this.dataType = DataType.uint16,
    this.bitIndex = 0,
    this.currentValue,
    this.writeValue = '',
    this.status = ConnectionStatus.disconnected,
    this.errorMessage,
    this.isExpanded = true,
  }) : id = id ?? DateTime.now().microsecondsSinceEpoch.toString();

  bool get isRead  => ModbusFC.isRead(functionCode);
  bool get isWrite => ModbusFC.isWrite(functionCode);
  bool get showBitIndex => dataType == DataType.bool_;

  int get registerCount {
    if (ModbusFC.isBitFunction(functionCode)) return 1;
    return dataType.registerCount;
  }

  String get connectionKey => '$ip:$port:$unitId';

  Endpoint clone() => Endpoint(
    ip: ip,
    port: port,
    unitId: unitId,
    functionCode: functionCode,
    registerAddress: registerAddress,
    dataType: dataType,
    bitIndex: bitIndex,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'ip': ip,
    'port': port,
    'unitId': unitId,
    'functionCode': functionCode,
    'registerAddress': registerAddress,
    'dataType': dataType.name,
    'bitIndex': bitIndex,
  };

  factory Endpoint.fromJson(Map<String, dynamic> json) => Endpoint(
    id: json['id'] as String?,
    ip: json['ip'] as String? ?? '192.168.0.1',
    port: json['port'] as int? ?? 502,
    unitId: json['unitId'] as int? ?? 3,
    functionCode: json['functionCode'] as int? ?? 3,
    registerAddress: json['registerAddress'] as int? ?? 0,
    dataType: DataType.values.firstWhere(
      (e) => e.name == json['dataType'],
      orElse: () => DataType.uint16,
    ),
    bitIndex: json['bitIndex'] as int? ?? 0,
  );
}

// ─── Profile Model ───────────────────────────────────────────────────

class Profile {
  final String name;
  final List<Endpoint> endpoints;
  final ByteOrder byteOrder;

  Profile({
    required this.name,
    required this.endpoints,
    required this.byteOrder,
  });

  Map<String, dynamic> toJson() => {
    'name': name,
    'endpoints': endpoints.map((e) => e.toJson()).toList(),
    'byteOrder': byteOrder.name,
  };

  factory Profile.fromJson(Map<String, dynamic> json) => Profile(
    name: json['name'] as String,
    endpoints: (json['endpoints'] as List)
        .map((e) => Endpoint.fromJson(e as Map<String, dynamic>))
        .toList(),
    byteOrder: ByteOrder.values.firstWhere(
      (e) => e.name == json['byteOrder'],
      orElse: () => ByteOrder.bigEndian,
    ),
  );
}
