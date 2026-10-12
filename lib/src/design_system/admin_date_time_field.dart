import 'package:flutter/material.dart';

/// Date/time input that writes an ISO-8601 value to the supplied controller.
/// The time picker is explicitly 12-hour regardless of the device preference.
class AdminDateTimeField extends StatelessWidget {
  const AdminDateTimeField({super.key, required this.controller, required this.label, this.dateOnly = false});
  final TextEditingController controller;
  final String label;
  final bool dateOnly;

  DateTime _initial() {
    final raw = controller.text.trim();
    if (raw.isNotEmpty) {
      final parsed = DateTime.tryParse(raw);
      if (parsed != null) return parsed.toLocal();
    }
    return DateTime.now();
  }

  Future<void> _pick(BuildContext context) async {
    final initial = _initial();
    final date = await showDatePicker(
      context: context,
      initialDate: DateTime(initial.year, initial.month, initial.day),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      helpText: 'اختر التاريخ',
      cancelText: 'إلغاء',
      confirmText: 'اختيار',
    );
    if (date == null || !context.mounted) return;
    if (dateOnly) {
      controller.text = '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
      return;
    }
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
      helpText: 'اختر الوقت',
      cancelText: 'إلغاء',
      confirmText: 'اختيار',
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: false),
        child: child ?? const SizedBox.shrink(),
      ),
    );
    if (time == null) return;
    final value = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    controller.text = value.toUtc().toIso8601String();
  }

  @override
  Widget build(BuildContext context) => TextFormField(
    controller: controller,
    readOnly: true,
    onTap: () => _pick(context),
    decoration: InputDecoration(
      labelText: label,
      hintText: dateOnly ? 'اختر التاريخ' : 'اختر التاريخ والوقت',
      prefixIcon: const Icon(Icons.calendar_month_outlined),
      suffixIcon: Row(mainAxisSize: MainAxisSize.min, children: [
        if (controller.text.isNotEmpty) IconButton(tooltip: 'مسح', onPressed: () => controller.clear(), icon: const Icon(Icons.clear)),
        const Padding(padding: EdgeInsetsDirectional.only(end: 8), child: Icon(Icons.arrow_drop_down)),
      ]),
    ),
  );
}
