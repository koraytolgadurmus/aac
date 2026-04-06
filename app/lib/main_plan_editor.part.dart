part of 'main.dart';

// ===== Plan Editor =====
class _PlanEditor extends StatefulWidget {
  const _PlanEditor({
    required this.i18n,
    required this.isDoa,
    this.initial,
    this.overlaps,
  });
  final I18n i18n;
  final bool isDoa;
  final _PlanItem? initial;
  final bool Function(_PlanItem)? overlaps; // yeni
  @override
  State<_PlanEditor> createState() => _PlanEditorState();
}

class _PlanEditorState extends State<_PlanEditor> {
  late bool enabled;
  late TimeOfDay start;
  late TimeOfDay end;
  int mode = 1;
  bool lightOn = false;
  bool ionOn = false;
  bool rgbOn = false; // NEW
  // Otomatik nem (plan bazlı)
  bool autoHumEnabled = false;
  double autoHumTarget = 55;

  int _pctForMode(int m) {
    switch (m) {
      case 0:
        return 20;
      case 1:
        return 35;
      case 2:
        return 50;
      case 3:
        return 65;
      case 4:
        return 100;
      default:
        return 35;
    }
  }

  @override
  void initState() {
    super.initState();
    final i = widget.initial;
    enabled = i?.enabled ?? true;
    start = i?.start ?? const TimeOfDay(hour: 8, minute: 0);
    end = i?.end ?? const TimeOfDay(hour: 9, minute: 0);
    mode = i?.mode ?? 1;
    lightOn = i?.lightOn ?? false;
    ionOn = i?.ionOn ?? false;
    rgbOn = i?.rgbOn ?? false;
    autoHumEnabled = i?.autoHumEnabled ?? false;
    autoHumTarget = (i?.autoHumTarget ?? 55).toDouble();
  }

  Future<TimeOfDay?> _pick(TimeOfDay v) async {
    return showTimePicker(
      context: context,
      initialTime: v,
      builder: (ctx, child) => MediaQuery(
        data: MediaQuery.of(ctx).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final modeNames = [
      widget.i18n.t('sleep'),
      widget.i18n.t('low'),
      widget.i18n.t('med'),
      widget.i18n.t('high'),
      widget.i18n.t('turbo'),
      widget.i18n.t('auto'),
    ];

    final pctInfo = mode == 5 ? '' : '  %${_pctForMode(mode)}';

    final candidate = _PlanItem(
      enabled: enabled,
      start: start,
      end: end,
      mode: mode,
      fanPercent: _pctForMode(mode),
      lightOn: lightOn,
      ionOn: ionOn,
      rgbOn: rgbOn,
      autoHumEnabled: autoHumEnabled,
      autoHumTarget: autoHumTarget.round(),
    );
    final hasOverlap = (widget.overlaps?.call(candidate) ?? false);

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.schedule),
                  const SizedBox(width: 8),
                  Text(widget.i18n.t('planner')),
                  const Spacer(),
                  Switch(
                    value: enabled,
                    onChanged: (v) => setState(() => enabled = v),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _timeField(widget.i18n.t('start'), start, () {
                      _pick(start).then((p) {
                        if (p != null) setState(() => start = p);
                      });
                    }),
                  ),
                  Expanded(
                    child: _timeField(widget.i18n.t('end'), end, () {
                      _pick(end).then((p) {
                        if (p != null) setState(() => end = p);
                      });
                    }),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<int>(
                value: mode,
                items: List.generate(
                  6,
                  (i) => DropdownMenuItem(value: i, child: Text(modeNames[i])),
                ),
                onChanged: (v) {
                  setState(() => mode = v ?? 1);
                },
                decoration: InputDecoration(labelText: widget.i18n.t('mode')),
              ),
              if (mode != 5)
                Padding(
                  padding: const EdgeInsets.only(top: 8.0),
                  child: Text('${widget.i18n.t('plan_speed')}$pctInfo'),
                ),
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  child: Column(
                    children: [
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        secondary: const Icon(Icons.bubble_chart_outlined),
                        title: Text(
                          widget.i18n.t('ion'),
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        value: ionOn,
                        onChanged: (v) => setState(() => ionOn = v),
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        secondary: const Icon(Icons.light_mode_outlined),
                        title: Text(
                          widget.i18n.t('light'),
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        value: lightOn,
                        onChanged: (v) => setState(() => lightOn = v),
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        secondary: const Icon(Icons.local_fire_department),
                        title: Text(
                          widget.i18n.t('flame'),
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        value: rgbOn,
                        onChanged: (v) => setState(() => rgbOn = v),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              if (!widget.isDoa)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.water_drop_outlined, size: 20),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                widget.i18n.t('auto_humidity'),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Theme.of(
                                  context,
                                ).colorScheme.primary.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                '${autoHumTarget.round()}%',
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Switch(
                              value: autoHumEnabled,
                              onChanged: (v) =>
                                  setState(() => autoHumEnabled = v),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Slider(
                          min: 30,
                          max: 70,
                          divisions: 40,
                          value: autoHumTarget.clamp(30, 70),
                          label: '${autoHumTarget.round()}%',
                          onChanged: (v) => setState(() => autoHumTarget = v),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          widget.i18n.t('auto_humidity_hint'),
                          style: Theme.of(
                            context,
                          ).textTheme.bodySmall?.copyWith(fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 16),
              if (hasOverlap)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8.0),
                  child: Text(
                    'Zaman diliminde aktif planlar var.',
                    style: TextStyle(
                      color: Colors.red.shade400,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              Row(
                children: [
                  OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(widget.i18n.t('cancel')),
                  ),
                  const Spacer(),
                  FilledButton(
                    onPressed: hasOverlap
                        ? null
                        : () {
                            Navigator.pop(context, candidate);
                          },
                    child: Text(widget.i18n.t('save')),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _timeField(String label, TimeOfDay v, VoidCallback onTap) {
    String two(int x) => x.toString().padLeft(2, '0');
    return TextFormField(
      readOnly: true,
      onTap: onTap,
      decoration: InputDecoration(labelText: label),
      controller: TextEditingController(
        text: '${two(v.hour)}:${two(v.minute)}',
      ),
    );
  }
}
