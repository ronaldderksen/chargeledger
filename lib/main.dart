import 'package:flutter/material.dart';

import 'src/domain/formatters.dart';
import 'src/domain/history_periods.dart';
import 'src/domain/models.dart';
import 'src/storage/repository_factory.dart';
import 'src/ui/app_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final controller = AppController(await createRepository());
  runApp(ChargeLedgerApp(controller: controller));
  await controller.initialize();
}

class ChargeLedgerApp extends StatelessWidget {
  const ChargeLedgerApp({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ChargeLedger',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xff24745b),
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: const Color(0xfff6f8f7),
        useMaterial3: true,
        visualDensity: VisualDensity.compact,
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.white,
          elevation: 0,
          centerTitle: false,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          isDense: true,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Color(0xffd7ded9)),
          ),
        ),
      ),
      home: AnimatedBuilder(
        animation: controller,
        builder: (BuildContext context, _) {
          return HomePage(controller: controller);
        },
      ),
    );
  }
}

class HomePage extends StatelessWidget {
  const HomePage({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ChargeLedger'),
        actions: <Widget>[
          if (controller.session != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Center(child: Text(controller.session!.email)),
            ),
          if (controller.session != null)
            IconButton(
              tooltip: 'Log out',
              onPressed: controller.isBusy ? null : controller.logout,
              icon: const Icon(Icons.logout),
            ),
        ],
      ),
      body: controller.isLoading
          ? const Center(child: CircularProgressIndicator())
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1180),
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
                  children: <Widget>[
                    if (controller.error != null)
                      StatusBanner(text: controller.error!, isError: true),
                    if (controller.message != null)
                      StatusBanner(text: controller.message!, isError: false),
                    if (controller.session == null)
                      Align(
                        alignment: Alignment.topCenter,
                        child: LoginPanel(controller: controller),
                      )
                    else ...<Widget>[
                      TopControls(controller: controller),
                      const SizedBox(height: 14),
                      TotalsPanel(totals: controller.totals),
                      const SizedBox(height: 14),
                      HistoryPanel(sessions: controller.sessions),
                    ],
                  ],
                ),
              ),
            ),
    );
  }
}

class StatusBanner extends StatelessWidget {
  const StatusBanner({super.key, required this.text, required this.isError});

  final String text;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isError ? colors.errorContainer : colors.secondaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: isError
              ? colors.onErrorContainer
              : colors.onSecondaryContainer,
        ),
      ),
    );
  }
}

class LoginPanel extends StatefulWidget {
  const LoginPanel({super.key, required this.controller});

  final AppController controller;

  @override
  State<LoginPanel> createState() => _LoginPanelState();
}

class _LoginPanelState extends State<LoginPanel> {
  final TextEditingController _email = TextEditingController();
  final TextEditingController _password = TextEditingController();

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 440,
      padding: const EdgeInsets.all(20),
      decoration: _panelDecoration(context),
      child: AutofillGroup(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text('Zaptec login', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            TextField(
              controller: _email,
              autofillHints: const <String>[
                AutofillHints.username,
                AutofillHints.email,
              ],
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'Email',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _password,
              autofillHints: const <String>[AutofillHints.password],
              obscureText: true,
              textInputAction: TextInputAction.done,
              decoration: const InputDecoration(
                labelText: 'Password',
                border: OutlineInputBorder(),
              ),
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: widget.controller.isBusy ? null : _submit,
              icon: widget.controller.isBusy
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.login),
              label: const Text('Log in'),
            ),
          ],
        ),
      ),
    );
  }

  void _submit() {
    widget.controller.login(_email.text, _password.text);
  }
}

class TopControls extends StatelessWidget {
  const TopControls({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final HistoryFilter filter = controller.filter;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _panelDecoration(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Text('Filters', style: Theme.of(context).textTheme.titleMedium),
              const Spacer(),
              FilledButton.icon(
                onPressed: controller.isBusy || filter.chargerId == null
                    ? null
                    : controller.syncHistory,
                icon: controller.isBusy
                    ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.sync),
                label: const Text('Sync history'),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: controller.isBusy ? null : controller.syncChargers,
                icon: const Icon(Icons.ev_station),
                label: const Text('Sync chargers'),
              ),
            ],
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              final bool narrow = constraints.maxWidth < 760;
              final double fieldWidth = narrow
                  ? constraints.maxWidth
                  : (constraints.maxWidth - 24) / 4;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Wrap(
                    spacing: 8,
                    runSpacing: 10,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: <Widget>[
                      SizedBox(
                        width: narrow ? fieldWidth : fieldWidth + 80,
                        child: FilterDropdown<String>(
                          label: 'Charger',
                          value: filter.chargerId,
                          items: <DropdownMenuItem<String>>[
                            ...controller.chargers.map(
                              (Charger charger) => DropdownMenuItem<String>(
                                value: charger.id,
                                child: Text(
                                  charger.name,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                          ],
                          onChanged: controller.isBusy
                              ? null
                              : (String? value) {
                                  if (value != null) {
                                    controller.setFilter(
                                      filter.copyWith(chargerId: value),
                                    );
                                  }
                                },
                        ),
                      ),
                      SizedBox(
                        width: fieldWidth,
                        child: FilterDropdown<HistoryTimeField>(
                          label: 'Time field',
                          value: filter.timeField,
                          items: const <DropdownMenuItem<HistoryTimeField>>[
                            DropdownMenuItem<HistoryTimeField>(
                              value: HistoryTimeField.startTime,
                              child: Text('Start'),
                            ),
                            DropdownMenuItem<HistoryTimeField>(
                              value: HistoryTimeField.endTime,
                              child: Text('End'),
                            ),
                          ],
                          onChanged: controller.isBusy
                              ? null
                              : (HistoryTimeField? value) {
                                  if (value != null) {
                                    controller.setFilter(
                                      filter.copyWith(timeField: value),
                                    );
                                  }
                                },
                        ),
                      ),
                      SizedBox(
                        width: fieldWidth,
                        child: FilterDropdown<HistoryPeriod>(
                          label: 'Period',
                          value: filter.period,
                          items: const <DropdownMenuItem<HistoryPeriod>>[
                            DropdownMenuItem<HistoryPeriod>(
                              value: HistoryPeriod.all,
                              child: Text('All'),
                            ),
                            DropdownMenuItem<HistoryPeriod>(
                              value: HistoryPeriod.year,
                              child: Text('Year'),
                            ),
                            DropdownMenuItem<HistoryPeriod>(
                              value: HistoryPeriod.quarter,
                              child: Text('Quarter'),
                            ),
                            DropdownMenuItem<HistoryPeriod>(
                              value: HistoryPeriod.month,
                              child: Text('Month'),
                            ),
                            DropdownMenuItem<HistoryPeriod>(
                              value: HistoryPeriod.week,
                              child: Text('Week'),
                            ),
                            DropdownMenuItem<HistoryPeriod>(
                              value: HistoryPeriod.custom,
                              child: Text('Custom'),
                            ),
                          ],
                          onChanged: controller.isBusy
                              ? null
                              : (HistoryPeriod? value) {
                                  if (value != null) {
                                    controller.setFilter(
                                      filter.copyWith(
                                        period: value,
                                        periodValue: defaultPeriodValue(value),
                                        clearDates:
                                            value != HistoryPeriod.custom,
                                      ),
                                    );
                                  }
                                },
                        ),
                      ),
                    ],
                  ),
                  if (filter.period != HistoryPeriod.all ||
                      filter.period == HistoryPeriod.custom)
                    const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 10,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: <Widget>[
                      if (filter.period != HistoryPeriod.all &&
                          filter.period != HistoryPeriod.custom) ...<Widget>[
                        IconButton.outlined(
                          tooltip: 'Previous',
                          onPressed: controller.isBusy
                              ? null
                              : () => controller.shiftPeriod(-1),
                          icon: const Icon(Icons.chevron_left),
                        ),
                        SizedBox(
                          width: fieldWidth,
                          child: FilterDropdown<String>(
                            label: 'Selection',
                            value: _periodValue(filter),
                            items: periodOptions(filter.period)
                                .map(
                                  (String value) => DropdownMenuItem<String>(
                                    value: value,
                                    child: Text(value),
                                  ),
                                )
                                .toList(),
                            onChanged: controller.isBusy
                                ? null
                                : (String? value) {
                                    if (value != null) {
                                      controller.setFilter(
                                        filter.copyWith(periodValue: value),
                                      );
                                    }
                                  },
                          ),
                        ),
                        IconButton.outlined(
                          tooltip: 'Next',
                          onPressed: controller.isBusy
                              ? null
                              : () => controller.shiftPeriod(1),
                          icon: const Icon(Icons.chevron_right),
                        ),
                      ],
                      if (filter.period == HistoryPeriod.custom) ...<Widget>[
                        DateButton(
                          label: 'Start date',
                          value: filter.startDate,
                          onChanged: (DateTime date) => controller.setFilter(
                            filter.copyWith(startDate: date),
                          ),
                        ),
                        DateButton(
                          label: 'End date',
                          value: filter.endDate,
                          onChanged: (DateTime date) => controller.setFilter(
                            filter.copyWith(endDate: date),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  String? _periodValue(HistoryFilter filter) {
    if (filter.period == HistoryPeriod.all ||
        filter.period == HistoryPeriod.custom) {
      return null;
    }
    final String value = filter.periodValue?.isNotEmpty == true
        ? filter.periodValue!
        : defaultPeriodValue(filter.period);
    final List<String> options = periodOptions(filter.period);
    return options.contains(value) ? value : options.firstOrNull;
  }
}

class DateButton extends StatelessWidget {
  const DateButton({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final DateTime? value;
  final ValueChanged<DateTime> onChanged;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: () async {
        final DateTime now = DateTime.now();
        final DateTime? picked = await showDatePicker(
          context: context,
          firstDate: DateTime(now.year - 10),
          lastDate: DateTime(now.year + 1),
          initialDate: value ?? now,
        );
        if (picked != null) {
          onChanged(picked);
        }
      },
      icon: const Icon(Icons.calendar_month),
      label: Text(value == null ? label : '$label ${displayDate(value)}'),
    );
  }
}

class FilterDropdown<T> extends StatelessWidget {
  const FilterDropdown({
    super.key,
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  final String label;
  final T? value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?>? onChanged;

  @override
  Widget build(BuildContext context) {
    final bool hasValue =
        value != null &&
        items.any((DropdownMenuItem<T> item) => item.value == value);
    return InputDecorator(
      decoration: InputDecoration(labelText: label),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: hasValue ? value : null,
          isDense: true,
          isExpanded: true,
          items: items,
          onChanged: onChanged,
        ),
      ),
    );
  }
}

class TotalsPanel extends StatelessWidget {
  const TotalsPanel({super.key, required this.totals});

  final HistoryTotals totals;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final bool narrow = constraints.maxWidth < 720;
        final double tileWidth = narrow
            ? (constraints.maxWidth - 8) / 2
            : (constraints.maxWidth - 24) / 4;
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            TotalTile(
              label: 'Sessions',
              value: totals.sessions.toString(),
              width: tileWidth,
            ),
            TotalTile(
              label: 'Energy',
              value: '${displayNumber(totals.energyKwh)} kWh',
              width: tileWidth,
            ),
            TotalTile(
              label: 'Duration',
              value: displayDuration(totals.durationSeconds),
              width: tileWidth,
            ),
            TotalTile(
              label: 'Cost',
              value: displayNumber(totals.cost),
              width: tileWidth,
            ),
          ],
        );
      },
    );
  }
}

class TotalTile extends StatelessWidget {
  const TotalTile({
    super.key,
    required this.label,
    required this.value,
    required this.width,
  });

  final String label;
  final String value;
  final double width;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    return Container(
      width: width,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: colors.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.labelMedium?.copyWith(color: colors.onSurfaceVariant),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class HistoryPanel extends StatelessWidget {
  const HistoryPanel({super.key, required this.sessions});

  final List<ChargeSession> sessions;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: _panelDecoration(context),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
            child: Row(
              children: <Widget>[
                Text(
                  'Charge sessions',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const Spacer(),
                Text(
                  '${sessions.length} shown',
                  style: Theme.of(context).textTheme.labelMedium,
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          if (sessions.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text('No stored charge sessions for this selection.'),
            )
          else
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                headingRowColor: WidgetStatePropertyAll<Color>(
                  Theme.of(context).colorScheme.surfaceContainerHighest,
                ),
                dataRowMinHeight: 44,
                dataRowMaxHeight: 52,
                columnSpacing: 28,
                columns: const <DataColumn>[
                  DataColumn(label: Text('Start')),
                  DataColumn(label: Text('End')),
                  DataColumn(label: Text('Charger')),
                  DataColumn(label: Text('User')),
                  DataColumn(label: Text('kWh'), numeric: true),
                  DataColumn(label: Text('Duration')),
                  DataColumn(label: Text('Cost'), numeric: true),
                ],
                rows: sessions
                    .map(
                      (ChargeSession session) => DataRow(
                        cells: <DataCell>[
                          DataCell(Text(displayDateTime(session.startTime))),
                          DataCell(Text(displayDateTime(session.endTime))),
                          DataCell(
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 260),
                              child: Text(
                                displayText(
                                  session.chargerName ?? session.chargerId,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                          DataCell(
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 180),
                              child: Text(
                                displayText(session.userName),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                          DataCell(Text(displayNumber(session.energyKwh))),
                          DataCell(
                            Text(displayDuration(session.durationSeconds)),
                          ),
                          DataCell(Text(displayNumber(session.cost))),
                        ],
                      ),
                    )
                    .toList(),
              ),
            ),
        ],
      ),
    );
  }
}

BoxDecoration _panelDecoration(BuildContext context) {
  final ColorScheme colors = Theme.of(context).colorScheme;
  return BoxDecoration(
    color: Colors.white,
    border: Border.all(color: colors.outlineVariant),
    borderRadius: BorderRadius.circular(8),
  );
}
