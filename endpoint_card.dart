import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'models.dart';
import 'app_state.dart';

class EndpointCard extends StatefulWidget {
  final int index;
  const EndpointCard({super.key, required this.index});

  @override
  State<EndpointCard> createState() => _EndpointCardState();
}

class _EndpointCardState extends State<EndpointCard> {
  late TextEditingController _ipCtrl;
  late TextEditingController _portCtrl;
  late TextEditingController _unitCtrl;
  late TextEditingController _regCtrl;
  late TextEditingController _bitCtrl;
  late TextEditingController _writeCtrl;

  @override
  void initState() {
    super.initState();
    final ep = context.read<AppState>().endpoints[widget.index];
    _ipCtrl    = TextEditingController(text: ep.ip);
    _portCtrl  = TextEditingController(text: ep.port.toString());
    _unitCtrl  = TextEditingController(text: ep.unitId.toString());
    _regCtrl   = TextEditingController(text: ep.registerAddress.toString());
    _bitCtrl   = TextEditingController(text: ep.bitIndex.toString());
    _writeCtrl = TextEditingController(text: ep.writeValue);
  }

  @override
  void didUpdateWidget(EndpointCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.index != widget.index) {
      _syncControllers();
    }
  }

  void _syncControllers() {
    final state = context.read<AppState>();
    if (widget.index >= state.endpoints.length) return;
    final ep = state.endpoints[widget.index];
    if (_ipCtrl.text != ep.ip) _ipCtrl.text = ep.ip;
    if (_portCtrl.text != ep.port.toString()) _portCtrl.text = ep.port.toString();
    if (_unitCtrl.text != ep.unitId.toString()) _unitCtrl.text = ep.unitId.toString();
    if (_regCtrl.text != ep.registerAddress.toString()) _regCtrl.text = ep.registerAddress.toString();
    if (_bitCtrl.text != ep.bitIndex.toString()) _bitCtrl.text = ep.bitIndex.toString();
  }

  @override
  void dispose() {
    _ipCtrl.dispose();
    _portCtrl.dispose();
    _unitCtrl.dispose();
    _regCtrl.dispose();
    _bitCtrl.dispose();
    _writeCtrl.dispose();
    super.dispose();
  }

  void _apply() {
    final state = context.read<AppState>();
    if (widget.index >= state.endpoints.length) return;
    final ep = state.endpoints[widget.index];
    ep.ip = _ipCtrl.text.trim();
    ep.port = int.tryParse(_portCtrl.text) ?? 502;
    ep.unitId = int.tryParse(_unitCtrl.text) ?? 1;
    ep.registerAddress = int.tryParse(_regCtrl.text) ?? 0;
    ep.bitIndex = int.tryParse(_bitCtrl.text) ?? 0;
    ep.writeValue = _writeCtrl.text;
    state.updateEndpoint(widget.index, ep);
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(
      builder: (context, state, _) {
        if (widget.index >= state.endpoints.length) {
          return const SizedBox.shrink();
        }
        final ep = state.endpoints[widget.index];
        final theme = Theme.of(context);
        final cs = theme.colorScheme;

        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          elevation: 1,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(
              color: _statusColor(ep.status).withOpacity(0.4),
              width: 1.5,
            ),
          ),
          child: Column(
            children: [
              // ─── Header (always visible) ───────────────────
              _buildHeader(ep, state, cs),
              // ─── Expanded body ─────────────────────────────
              if (ep.isExpanded) ...[
                const Divider(height: 1),
                _buildBody(ep, state, cs),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildHeader(Endpoint ep, AppState state, ColorScheme cs) {
    return InkWell(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
      onTap: () => state.toggleExpanded(widget.index),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            // Status dot
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _statusColor(ep.status),
              ),
            ),
            const SizedBox(width: 8),
            // Summary
            Expanded(
              child: Text(
                '${ep.ip}:${ep.port}  U:${ep.unitId}  '
                '${ModbusFC.shortLabel(ep.functionCode)}  '
                'R:${ep.registerAddress}  ${ep.dataType.label}'
                '${ep.showBitIndex ? ".${ep.bitIndex}" : ""}',
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12.5,
                  color: cs.onSurface,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            // Value chip
            if (ep.currentValue != null) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: ep.currentValue == 'ERR'
                      ? cs.errorContainer
                      : cs.primaryContainer,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  ep.currentValue!,
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: ep.currentValue == 'ERR'
                        ? cs.onErrorContainer
                        : cs.onPrimaryContainer,
                  ),
                ),
              ),
            ],
            // Expand icon
            Icon(
              ep.isExpanded ? Icons.expand_less : Icons.expand_more,
              size: 20,
              color: cs.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(Endpoint ep, AppState state, ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Row 1: IP + Port
          Row(
            children: [
              Expanded(
                flex: 5,
                child: _field('IP Address', _ipCtrl, onChanged: (_) => _apply()),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: _field('Port', _portCtrl,
                    keyboard: TextInputType.number, onChanged: (_) => _apply()),
              ),
            ],
          ),
          const SizedBox(height: 6),
          // Row 2: Unit ID + FC + Register
          Row(
            children: [
              Expanded(
                flex: 2,
                child: _field('Unit ID', _unitCtrl,
                    keyboard: TextInputType.number, onChanged: (_) => _apply()),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 4,
                child: _fcDropdown(ep, state),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: _field('Register', _regCtrl,
                    keyboard: TextInputType.number, onChanged: (_) => _apply()),
              ),
            ],
          ),
          const SizedBox(height: 6),
          // Row 3: Data Type + Bit (if applicable)
          Row(
            children: [
              Expanded(flex: 3, child: _typeDropdown(ep, state)),
              if (ep.showBitIndex) ...[
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: _field('Bit (0-15)', _bitCtrl,
                      keyboard: TextInputType.number,
                      onChanged: (_) => _apply()),
                ),
              ],
              if (!ep.showBitIndex) const Spacer(flex: 2),
            ],
          ),
          const SizedBox(height: 10),
          // Row 4: Value + Action
          _buildActionRow(ep, state, cs),
          // Error message
          if (ep.errorMessage != null) ...[
            const SizedBox(height: 6),
            Text(
              ep.errorMessage!,
              style: TextStyle(fontSize: 11, color: cs.error),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildActionRow(Endpoint ep, AppState state, ColorScheme cs) {
    if (ep.isWrite) {
      return Row(
        children: [
          Expanded(
            child: _field(
              ep.functionCode == ModbusFC.writeSingleCoil
                  ? 'Value (TRUE/FALSE, 1/0)'
                  : 'Value (0-65535)',
              _writeCtrl,
              keyboard: ep.functionCode == ModbusFC.writeSingleCoil
                  ? TextInputType.text
                  : TextInputType.number,
              onChanged: (v) {
                ep.writeValue = v;
              },
            ),
          ),
          const SizedBox(width: 8),
          _actionButton(
            icon: Icons.send,
            label: 'WRITE',
            color: cs.tertiary,
            onColor: cs.onTertiary,
            onPressed: () => state.writeSingle(widget.index),
          ),
          const SizedBox(width: 4),
          _deleteButton(state),
        ],
      );
    } else {
      return Row(
        children: [
          // Current value display
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest.withOpacity(0.5),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                ep.currentValue ?? '—',
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: ep.currentValue == 'ERR' ? cs.error : cs.onSurface,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          _actionButton(
            icon: Icons.download,
            label: 'READ',
            color: cs.primary,
            onColor: cs.onPrimary,
            onPressed: () => state.readSingle(widget.index),
          ),
          const SizedBox(width: 4),
          _deleteButton(state),
        ],
      );
    }
  }

  Widget _actionButton({
    required IconData icon,
    required String label,
    required Color color,
    required Color onColor,
    required VoidCallback onPressed,
  }) {
    return SizedBox(
      height: 40,
      child: ElevatedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 16),
        label: Text(label, style: const TextStyle(fontSize: 12)),
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: onColor,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
    );
  }

  Widget _deleteButton(AppState state) {
    return SizedBox(
      height: 40,
      width: 40,
      child: IconButton(
        onPressed: () => _confirmDelete(state),
        icon: Icon(Icons.delete_outline, size: 20, color: Theme.of(context).colorScheme.error),
        tooltip: 'Remove',
        style: IconButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
    );
  }

  void _confirmDelete(AppState state) {
    if (state.endpoints.length <= 1) {
      // Don't delete last one, just reset it
      state.updateEndpoint(widget.index, Endpoint());
      _syncControllers();
      return;
    }
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove Endpoint?'),
        content: Text('Remove endpoint #${widget.index + 1}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('CANCEL'),
          ),
          TextButton(
            onPressed: () {
              state.removeEndpoint(widget.index);
              Navigator.pop(ctx);
            },
            child: const Text('REMOVE'),
          ),
        ],
      ),
    );
  }

  // ─── Dropdown Builders ──────────────────────────────────────────

  Widget _fcDropdown(Endpoint ep, AppState state) {
    return InputDecorator(
      decoration: _inputDeco('Function Code'),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<int>(
          value: ep.functionCode,
          isDense: true,
          isExpanded: true,
          style: TextStyle(
            fontFamily: 'monospace',
            fontSize: 13,
            color: Theme.of(context).colorScheme.onSurface,
          ),
          items: [1, 2, 3, 4, 5, 6].map((fc) {
            return DropdownMenuItem(
              value: fc,
              child: Text(ModbusFC.label(fc), overflow: TextOverflow.ellipsis),
            );
          }).toList(),
          onChanged: (v) {
            if (v == null) return;
            ep.functionCode = v;
            state.updateEndpoint(widget.index, ep);
          },
        ),
      ),
    );
  }

  Widget _typeDropdown(Endpoint ep, AppState state) {
    return InputDecorator(
      decoration: _inputDeco('Data Type'),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<DataType>(
          value: ep.dataType,
          isDense: true,
          isExpanded: true,
          style: TextStyle(
            fontFamily: 'monospace',
            fontSize: 13,
            color: Theme.of(context).colorScheme.onSurface,
          ),
          items: DataType.values.map((dt) {
            return DropdownMenuItem(
              value: dt,
              child: Text(dt.label),
            );
          }).toList(),
          onChanged: (v) {
            if (v == null) return;
            ep.dataType = v;
            state.updateEndpoint(widget.index, ep);
          },
        ),
      ),
    );
  }

  // ─── Helpers ────────────────────────────────────────────────────

  Widget _field(
    String label,
    TextEditingController controller, {
    TextInputType? keyboard,
    ValueChanged<String>? onChanged,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboard,
      style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
      decoration: _inputDeco(label),
      onChanged: onChanged,
      inputFormatters: keyboard == TextInputType.number
          ? [FilteringTextInputFormatter.digitsOnly]
          : null,
    );
  }

  InputDecoration _inputDeco(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(fontSize: 11),
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
    );
  }

  Color _statusColor(ConnectionStatus status) {
    switch (status) {
      case ConnectionStatus.disconnected: return Colors.grey;
      case ConnectionStatus.connecting:   return Colors.amber;
      case ConnectionStatus.connected:    return Colors.green;
      case ConnectionStatus.error:        return Colors.red;
    }
  }
}
