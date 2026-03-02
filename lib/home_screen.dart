import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'models.dart';
import 'app_state.dart';
import 'endpoint_card.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(
      builder: (context, state, _) {
        final cs = Theme.of(context).colorScheme;
        return Scaffold(
          appBar: AppBar(
            title: const Text('Modbus TCP Client'),
            centerTitle: false,
            actions: [
              // Byte Order button
              IconButton(
                icon: const Icon(Icons.swap_horiz),
                tooltip: 'Byte Order',
                onPressed: () => _showByteOrderSheet(context, state),
              ),
              // Profiles button
              IconButton(
                icon: const Icon(Icons.folder_open),
                tooltip: 'Profiles',
                onPressed: () => _showProfilesSheet(context, state),
              ),
              // Disconnect all
              IconButton(
                icon: const Icon(Icons.link_off),
                tooltip: 'Disconnect All',
                onPressed: () async {
                  state.stopPolling();
                  await state.modbus.disconnectAll();
                  for (final ep in state.endpoints) {
                    ep.status = ConnectionStatus.disconnected;
                    ep.currentValue = null;
                    ep.errorMessage = null;
                  }
                  state.notifyListeners();
                },
              ),
            ],
          ),
          body: Column(
            children: [
              // ─── Polling Controls ──────────────────────────
              _PollBar(state: state),
              // ─── Endpoint List ─────────────────────────────
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.only(top: 4, bottom: 80),
                  itemCount: state.endpoints.length,
                  itemBuilder: (ctx, i) => EndpointCard(
                    key: ValueKey(state.endpoints[i].id),
                    index: i,
                  ),
                ),
              ),
            ],
          ),
          // ─── FAB: Add Endpoint ─────────────────────────────
          floatingActionButton: FloatingActionButton(
            onPressed: () => state.addEndpoint(),
            tooltip: 'Add Endpoint',
            child: const Icon(Icons.add),
          ),
        );
      },
    );
  }

  // ─── Byte Order Bottom Sheet ──────────────────────────────────

  void _showByteOrderSheet(BuildContext context, AppState state) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Byte Order (32-bit types)',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 4),
              Text(
                'Applies to INT32, UINT32, FLOAT32',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              ...ByteOrder.values.map((bo) {
                return RadioListTile<ByteOrder>(
                  title: Text(bo.label),
                  value: bo,
                  groupValue: state.byteOrder,
                  dense: true,
                  onChanged: (v) {
                    if (v != null) {
                      state.setByteOrder(v);
                      Navigator.pop(ctx);
                    }
                  },
                );
              }),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  // ─── Profiles Bottom Sheet ────────────────────────────────────

  void _showProfilesSheet(BuildContext context, AppState state) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return _ProfileSheet(state: state);
      },
    );
  }
}

// ─── Poll Bar Widget ─────────────────────────────────────────────────

class _PollBar extends StatelessWidget {
  final AppState state;
  const _PollBar({required this.state});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        border: Border(
          bottom: BorderSide(color: cs.outlineVariant, width: 0.5),
        ),
      ),
      child: Row(
        children: [
          // Polling rate selector
          SegmentedButton<PollingRate>(
            segments: PollingRate.values.map((r) {
              return ButtonSegment(
                value: r,
                label: Text(r.label, style: const TextStyle(fontSize: 11)),
              );
            }).toList(),
            selected: {state.pollingRate},
            onSelectionChanged: (s) => state.setPollingRate(s.first),
            style: ButtonStyle(
              visualDensity: VisualDensity.compact,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
          const SizedBox(width: 8),
          // Start/Stop toggle
          if (state.pollingRate != PollingRate.manual)
            SizedBox(
              height: 34,
              child: ElevatedButton.icon(
                onPressed: () => state.togglePolling(),
                icon: Icon(
                  state.isPolling ? Icons.stop : Icons.play_arrow,
                  size: 16,
                ),
                label: Text(
                  state.isPolling ? 'STOP' : 'START',
                  style: const TextStyle(fontSize: 11),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor:
                      state.isPolling ? cs.error : cs.primary,
                  foregroundColor:
                      state.isPolling ? cs.onError : cs.onPrimary,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                ),
              ),
            ),
          const Spacer(),
          // Read All button
          SizedBox(
            height: 34,
            child: OutlinedButton.icon(
              onPressed: () => state.readAll(),
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('READ ALL', style: TextStyle(fontSize: 11)),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 10),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Profile Sheet ───────────────────────────────────────────────────

class _ProfileSheet extends StatefulWidget {
  final AppState state;
  const _ProfileSheet({required this.state});

  @override
  State<_ProfileSheet> createState() => _ProfileSheetState();
}

class _ProfileSheetState extends State<_ProfileSheet> {
  final _nameCtrl = TextEditingController();

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final profiles = widget.state.getProfileNames();
    final cs = Theme.of(context).colorScheme;

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Profiles', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          // Save new profile
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _nameCtrl,
                  decoration: InputDecoration(
                    hintText: 'Profile name',
                    isDense: true,
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: () async {
                  final name = _nameCtrl.text.trim();
                  if (name.isEmpty) return;
                  await widget.state.saveProfile(name);
                  _nameCtrl.clear();
                  setState(() {});
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Profile "$name" saved')),
                    );
                  }
                },
                child: const Text('SAVE'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Profile list
          if (profiles.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: Text(
                  'No saved profiles',
                  style: TextStyle(color: cs.onSurfaceVariant),
                ),
              ),
            )
          else
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 300),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: profiles.length,
                itemBuilder: (ctx, i) {
                  final name = profiles[i];
                  return ListTile(
                    dense: true,
                    leading: const Icon(Icons.description_outlined, size: 20),
                    title: Text(name),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.upload, size: 20),
                          tooltip: 'Load',
                          onPressed: () async {
                            await widget.state.loadProfile(name);
                            if (context.mounted) {
                              Navigator.pop(context);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Loaded "$name"')),
                              );
                            }
                          },
                        ),
                        IconButton(
                          icon: Icon(Icons.delete_outline,
                              size: 20, color: cs.error),
                          tooltip: 'Delete',
                          onPressed: () async {
                            await widget.state.deleteProfile(name);
                            setState(() {});
                          },
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
