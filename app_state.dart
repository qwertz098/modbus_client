import 'dart:async';
import 'package:flutter/foundation.dart';
import 'models.dart';
import 'modbus_service.dart';
import 'storage_service.dart';

class AppState extends ChangeNotifier {
  final ModbusTcpService modbus = ModbusTcpService();
  final StorageService storage = StorageService();

  List<Endpoint> endpoints = [];
  ByteOrder byteOrder = ByteOrder.bigEndian;
  PollingRate pollingRate = PollingRate.manual;
  bool isPolling = false;
  Timer? _pollTimer;

  // ─── Initialization ─────────────────────────────────────────────

  Future<void> init() async {
    await storage.init();
    final saved = storage.loadAutoSaveEndpoints();
    byteOrder = storage.loadAutoSaveByteOrder();
    if (saved != null && saved.isNotEmpty) {
      endpoints = saved;
    } else {
      endpoints = [Endpoint()]; // Default first endpoint
    }
    notifyListeners();
  }

  Future<void> _autoSave() async {
    await storage.autoSave(endpoints, byteOrder);
  }

  // ─── Endpoint Management ────────────────────────────────────────

  void addEndpoint() {
    final last = endpoints.isNotEmpty ? endpoints.last : Endpoint();
    endpoints.add(last.clone());
    _autoSave();
    notifyListeners();
  }

  void removeEndpoint(int index) {
    if (index >= 0 && index < endpoints.length) {
      endpoints.removeAt(index);
      if (endpoints.isEmpty) {
        endpoints.add(Endpoint());
      }
      _autoSave();
      notifyListeners();
    }
  }

  void updateEndpoint(int index, Endpoint ep) {
    if (index >= 0 && index < endpoints.length) {
      endpoints[index] = ep;
      _autoSave();
      notifyListeners();
    }
  }

  void toggleExpanded(int index) {
    if (index >= 0 && index < endpoints.length) {
      endpoints[index].isExpanded = !endpoints[index].isExpanded;
      notifyListeners();
    }
  }

  // ─── Byte Order ─────────────────────────────────────────────────

  void setByteOrder(ByteOrder order) {
    byteOrder = order;
    _autoSave();
    notifyListeners();
  }

  // ─── Read / Write ───────────────────────────────────────────────

  Future<void> readSingle(int index) async {
    if (index < 0 || index >= endpoints.length) return;
    final ep = endpoints[index];
    if (!ep.isRead) return;

    ep.status = ConnectionStatus.connecting;
    ep.errorMessage = null;
    notifyListeners();

    try {
      await modbus.ensureConnected(ep.ip, ep.port);
      ep.status = ConnectionStatus.connected;
      notifyListeners();

      final value = await modbus.readEndpoint(ep, byteOrder);
      ep.currentValue = value;
      ep.status = ConnectionStatus.connected;
    } catch (e) {
      ep.status = ConnectionStatus.error;
      ep.errorMessage = e.toString();
      ep.currentValue = 'ERR';
    }
    notifyListeners();
  }

  Future<void> writeSingle(int index) async {
    if (index < 0 || index >= endpoints.length) return;
    final ep = endpoints[index];
    if (!ep.isWrite) return;

    ep.status = ConnectionStatus.connecting;
    ep.errorMessage = null;
    notifyListeners();

    try {
      await modbus.ensureConnected(ep.ip, ep.port);
      ep.status = ConnectionStatus.connected;
      notifyListeners();

      final result = await modbus.writeEndpoint(ep, ep.writeValue);
      ep.currentValue = result;
      ep.status = ConnectionStatus.connected;
    } catch (e) {
      ep.status = ConnectionStatus.error;
      ep.errorMessage = e.toString();
      ep.currentValue = 'ERR';
    }
    notifyListeners();
  }

  Future<void> readAll() async {
    final readEndpoints = <int>[];
    for (int i = 0; i < endpoints.length; i++) {
      if (endpoints[i].isRead) readEndpoints.add(i);
    }
    for (final idx in readEndpoints) {
      await readSingle(idx);
    }
  }

  // ─── Polling ────────────────────────────────────────────────────

  void setPollingRate(PollingRate rate) {
    pollingRate = rate;
    if (isPolling) {
      stopPolling();
      if (rate != PollingRate.manual) {
        startPolling();
      }
    }
    notifyListeners();
  }

  void startPolling() {
    if (pollingRate == PollingRate.manual) return;
    final duration = pollingRate.duration;
    if (duration == null) return;

    isPolling = true;
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(duration, (_) => readAll());
    notifyListeners();
  }

  void stopPolling() {
    isPolling = false;
    _pollTimer?.cancel();
    _pollTimer = null;
    notifyListeners();
  }

  void togglePolling() {
    if (isPolling) {
      stopPolling();
    } else {
      startPolling();
    }
  }

  // ─── Profiles ───────────────────────────────────────────────────

  List<String> getProfileNames() => storage.getProfileNames();

  Future<void> saveProfile(String name) async {
    final profile = Profile(
      name: name,
      endpoints: endpoints.map((e) => e.clone()).toList(),
      byteOrder: byteOrder,
    );
    await storage.saveProfile(profile);
  }

  Future<void> loadProfile(String name) async {
    final profiles = storage.loadProfiles();
    final profile = profiles[name];
    if (profile == null) return;

    stopPolling();
    await modbus.disconnectAll();

    endpoints = profile.endpoints
        .map((e) => Endpoint.fromJson(e.toJson()))
        .toList();
    byteOrder = profile.byteOrder;
    _autoSave();
    notifyListeners();
  }

  Future<void> deleteProfile(String name) async {
    await storage.deleteProfile(name);
    notifyListeners();
  }

  // ─── Cleanup ────────────────────────────────────────────────────

  @override
  void dispose() {
    stopPolling();
    modbus.disconnectAll();
    super.dispose();
  }
}
