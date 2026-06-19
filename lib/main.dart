import 'package:flutter/material.dart';

import 'src/domain/formatters.dart';
import 'src/domain/history_periods.dart';
import 'src/domain/models.dart';
import 'src/storage/repository_factory.dart';
import 'src/ui/app_controller.dart';
import 'src/ui/browser_login.dart';

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
          if (controller.session != null) SettingsMenu(controller: controller),
          if (controller.session != null)
            IconButton(
              tooltip: 'Log out',
              onPressed: controller.isBusy
                  ? null
                  : () async {
                      if (canOpenBrowserLogin) {
                        openLoggedOutLogin();
                      } else {
                        await controller.logout();
                      }
                    },
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
                        child: canOpenBrowserLogin
                            ? const BrowserLoginRedirect()
                            : LoginPanel(controller: controller),
                      )
                    else ...<Widget>[
                      TopControls(controller: controller),
                      const SizedBox(height: 14),
                      TotalsPanel(
                        totals: controller.totals,
                        currencyCode: controller.currencyCode,
                      ),
                      const SizedBox(height: 14),
                      HistoryPanel(controller: controller),
                    ],
                  ],
                ),
              ),
            ),
    );
  }
}

class SettingsMenu extends StatelessWidget {
  const SettingsMenu({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: 'Settings',
      icon: const Icon(Icons.settings),
      enabled: !controller.isBusy,
      onSelected: (String value) async {
        if (value == 'kwh-price') {
          final _KwhPriceEdit? edit = await _editKwhPrice(context);
          if (context.mounted && edit != null) {
            await controller.setCostSettings(
              kwhPrice: edit.price,
              currencyCode: edit.currencyCode,
            );
          }
          return;
        }
        if (value == 'delete-server-data' &&
            await _confirmDeleteServerData(context)) {
          await controller.deleteStoredData();
        }
      },
      itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
        const PopupMenuItem<String>(
          value: 'kwh-price',
          child: ListTile(
            leading: Icon(Icons.payments_outlined),
            title: Text('Cost settings'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
        if (canOpenBrowserLogin)
          const PopupMenuItem<String>(
            value: 'delete-server-data',
            child: ListTile(
              leading: Icon(Icons.delete_outline),
              title: Text('Delete server data'),
              contentPadding: EdgeInsets.zero,
            ),
          ),
      ],
    );
  }

  Future<_KwhPriceEdit?> _editKwhPrice(BuildContext context) async {
    final TextEditingController priceController = TextEditingController(
      text: controller.kwhPrice == null ? '' : controller.kwhPrice.toString(),
    );
    final TextEditingController currencyController = TextEditingController(
      text: controller.currencyCode,
    );
    try {
      final String? value = await showDialog<String>(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            title: const Text('Cost settings'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                TextField(
                  controller: currencyController,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(labelText: 'Currency'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: priceController,
                  autofocus: true,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(labelText: 'Price per kWh'),
                ),
              ],
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () {
                  priceController.clear();
                  Navigator.of(context).pop(currencyController.text);
                },
                child: const Text('Clear price'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(null),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(
                  context,
                ).pop('${currencyController.text}\n${priceController.text}'),
                child: const Text('Save'),
              ),
            ],
          );
        },
      );
      if (value == null) {
        return null;
      }
      final List<String> parts = value.split('\n');
      final String currencyCode = _normalizeCurrencyCode(parts.first);
      final String priceText = (parts.length > 1 ? parts[1] : '').trim();
      if (priceText.isEmpty) {
        return _KwhPriceEdit(price: null, currencyCode: currencyCode);
      }
      final double? price = double.tryParse(priceText.replaceAll(',', '.'));
      return price == null
          ? null
          : _KwhPriceEdit(price: price, currencyCode: currencyCode);
    } finally {
      priceController.dispose();
      currencyController.dispose();
    }
  }

  Future<bool> _confirmDeleteServerData(BuildContext context) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Delete server data?'),
          content: const Text(
            'This removes your stored chargers, charge history, and server session data.',
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );
    return confirmed ?? false;
  }
}

class _KwhPriceEdit {
  const _KwhPriceEdit({required this.price, required this.currencyCode});

  final double? price;
  final String currencyCode;
}

String _normalizeCurrencyCode(String value) {
  final String normalized = value.trim().toUpperCase();
  return normalized.isEmpty ? 'EUR' : normalized;
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
  String _chargerType = 'zaptec';

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
            DropdownButtonFormField<String>(
              initialValue: _chargerType,
              decoration: const InputDecoration(
                labelText: 'Charger type',
                border: OutlineInputBorder(),
              ),
              items: const <DropdownMenuItem<String>>[
                DropdownMenuItem<String>(
                  value: 'zaptec',
                  child: Text('Zaptec'),
                ),
              ],
              onChanged: widget.controller.isBusy
                  ? null
                  : (String? value) {
                      if (value != null) {
                        setState(() {
                          _chargerType = value;
                        });
                      }
                    },
            ),
            const SizedBox(height: 10),
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

class BrowserLoginRedirect extends StatefulWidget {
  const BrowserLoginRedirect({super.key});

  @override
  State<BrowserLoginRedirect> createState() => _BrowserLoginRedirectState();
}

class _BrowserLoginRedirectState extends State<BrowserLoginRedirect> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      openBrowserLogin();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 440,
      padding: const EdgeInsets.all(20),
      decoration: _panelDecoration(context),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text('Zaptec login', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),
          const LinearProgressIndicator(),
          const SizedBox(height: 12),
          const Text('Opening browser login...'),
        ],
      ),
    );
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
                onPressed: controller.isBusy ? null : controller.syncAll,
                icon: controller.isSyncingHistory
                    ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.sync),
                label: const Text('Sync'),
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
                          filter.period != HistoryPeriod.custom)
                        SizedBox(
                          width: narrow
                              ? constraints.maxWidth
                              : fieldWidth + 96,
                          child: Row(
                            children: <Widget>[
                              IconButton.outlined(
                                tooltip: 'Previous',
                                onPressed:
                                    controller.isBusy ||
                                        !controller.canShiftPeriod(1)
                                    ? null
                                    : () => controller.shiftPeriod(1),
                                icon: const Icon(Icons.chevron_left),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: FilterDropdown<String>(
                                  label: 'Selection',
                                  value: _periodValue(filter),
                                  items: controller
                                      .periodOptionsFor(filter.period)
                                      .map(
                                        (String value) =>
                                            DropdownMenuItem<String>(
                                              value: value,
                                              child: Text(
                                                value,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                      )
                                      .toList(),
                                  onChanged: controller.isBusy
                                      ? null
                                      : (String? value) {
                                          if (value != null) {
                                            controller.setFilter(
                                              filter.copyWith(
                                                periodValue: value,
                                              ),
                                            );
                                          }
                                        },
                                ),
                              ),
                              const SizedBox(width: 8),
                              IconButton.outlined(
                                tooltip: 'Next',
                                onPressed:
                                    controller.isBusy ||
                                        !controller.canShiftPeriod(-1)
                                    ? null
                                    : () => controller.shiftPeriod(-1),
                                icon: const Icon(Icons.chevron_right),
                              ),
                            ],
                          ),
                        ),
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
    final List<String> options = controller.periodOptionsFor(filter.period);
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
  const TotalsPanel({
    super.key,
    required this.totals,
    required this.currencyCode,
  });

  final HistoryTotals totals;
  final String currencyCode;

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
              value: displayMoney(totals.cost, currencyCode),
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
  const HistoryPanel({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final List<ChargeSession> sessions = controller.sessions;
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
                IconButton(
                  tooltip: 'Columns',
                  onPressed: () => _editColumns(context),
                  icon: const Icon(Icons.view_column_outlined),
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
            _HistoryTable(
              sessions: sessions,
              currencyCode: controller.currencyCode,
              columns: controller.historyColumns,
            ),
        ],
      ),
    );
  }

  Future<void> _editColumns(BuildContext context) async {
    final List<HistoryColumn>? columns = await showDialog<List<HistoryColumn>>(
      context: context,
      builder: (BuildContext context) {
        return _HistoryColumnsDialog(initialColumns: controller.historyColumns);
      },
    );
    if (columns != null) {
      await controller.setHistoryColumns(columns);
    }
  }
}

class _HistoryTable extends StatelessWidget {
  const _HistoryTable({
    required this.sessions,
    required this.currencyCode,
    required this.columns,
  });

  final List<ChargeSession> sessions;
  final String currencyCode;
  final List<HistoryColumn> columns;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final String widestCostAmount = _historyWidestCostAmount(sessions);
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: constraints.maxWidth),
            child: Table(
              defaultColumnWidth: const IntrinsicColumnWidth(),
              border: TableBorder(
                horizontalInside: BorderSide(color: colors.outlineVariant),
              ),
              defaultVerticalAlignment: TableCellVerticalAlignment.middle,
              children: <TableRow>[
                TableRow(
                  decoration: BoxDecoration(
                    color: colors.surfaceContainerHighest,
                  ),
                  children: <Widget>[
                    for (final HistoryColumn column in columns)
                      _HistoryHeaderCell(
                        _historyColumnLabel(column),
                        alignment: _historyColumnAlignment(column),
                      ),
                  ],
                ),
                ...sessions.map(
                  (ChargeSession session) => TableRow(
                    children: <Widget>[
                      for (final HistoryColumn column in columns)
                        if (column == HistoryColumn.cost)
                          _HistoryMoneyCell(
                            value: session.cost,
                            currencyCode: currencyCode,
                            widestAmount: widestCostAmount,
                          )
                        else
                          _HistoryCell(
                            _historyColumnValue(column, session, currencyCode),
                            alignment: _historyColumnAlignment(column),
                          ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _HistoryColumnsDialog extends StatefulWidget {
  const _HistoryColumnsDialog({required this.initialColumns});

  final List<HistoryColumn> initialColumns;

  @override
  State<_HistoryColumnsDialog> createState() => _HistoryColumnsDialogState();
}

class _HistoryColumnsDialogState extends State<_HistoryColumnsDialog> {
  late final Set<HistoryColumn> _visible = widget.initialColumns.toSet();
  late List<HistoryColumn> _columns = <HistoryColumn>[
    ...widget.initialColumns,
    for (final HistoryColumn column in HistoryColumn.values)
      if (!widget.initialColumns.contains(column)) column,
  ];

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Columns'),
      content: SizedBox(
        width: 360,
        height: 360,
        child: ReorderableListView.builder(
          itemCount: _columns.length,
          onReorder: (int oldIndex, int newIndex) {
            setState(() {
              if (newIndex > oldIndex) {
                newIndex -= 1;
              }
              final HistoryColumn column = _columns.removeAt(oldIndex);
              _columns.insert(newIndex, column);
            });
          },
          itemBuilder: (BuildContext context, int index) {
            final HistoryColumn column = _columns[index];
            return CheckboxListTile(
              key: ValueKey<HistoryColumn>(column),
              value: _visible.contains(column),
              onChanged: (bool? value) {
                setState(() {
                  if (value == true) {
                    _visible.add(column);
                    return;
                  }
                  if (_visible.length > 1) {
                    _visible.remove(column);
                  }
                });
              },
              secondary: const Icon(Icons.drag_handle),
              title: Text(_historyColumnLabel(column)),
              controlAffinity: ListTileControlAffinity.leading,
            );
          },
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () {
            setState(() {
              _columns = HistoryColumn.values;
              _visible
                ..clear()
                ..addAll(HistoryColumn.values);
            });
          },
          child: const Text('Reset'),
        ),
        FilledButton(
          onPressed: () {
            Navigator.of(context).pop(
              _columns
                  .where((HistoryColumn column) => _visible.contains(column))
                  .toList(),
            );
          },
          child: const Text('Apply'),
        ),
      ],
    );
  }
}

String _historyColumnLabel(HistoryColumn column) {
  return switch (column) {
    HistoryColumn.start => 'Start',
    HistoryColumn.end => 'End',
    HistoryColumn.charger => 'Charger',
    HistoryColumn.user => 'User',
    HistoryColumn.energy => 'kWh',
    HistoryColumn.duration => 'Duration',
    HistoryColumn.cost => 'Cost',
  };
}

String _historyColumnValue(
  HistoryColumn column,
  ChargeSession session,
  String currencyCode,
) {
  return switch (column) {
    HistoryColumn.start => displayDateTime(session.startTime),
    HistoryColumn.end => displayDateTime(session.endTime),
    HistoryColumn.charger => displayText(
      session.chargerName ?? session.chargerId,
    ),
    HistoryColumn.user => displayText(session.userName),
    HistoryColumn.energy => displayNumber(session.energyKwh),
    HistoryColumn.duration => displayDuration(session.durationSeconds),
    HistoryColumn.cost => displayMoney(session.cost, currencyCode),
  };
}

String _historyWidestCostAmount(List<ChargeSession> sessions) {
  num? highestCost;
  for (final ChargeSession session in sessions) {
    final num? cost = session.cost;
    if (cost != null && (highestCost == null || cost > highestCost)) {
      highestCost = cost;
    }
  }
  return highestCost == null ? '-' : displayNumber(highestCost);
}

AlignmentGeometry _historyColumnAlignment(HistoryColumn column) {
  return switch (column) {
    HistoryColumn.energy || HistoryColumn.cost => Alignment.centerRight,
    _ => Alignment.centerLeft,
  };
}

class _HistoryHeaderCell extends StatelessWidget {
  const _HistoryHeaderCell(this.text, {this.alignment = Alignment.centerLeft});

  final String text;
  final AlignmentGeometry alignment;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: Align(
        alignment: alignment,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelMedium,
          ),
        ),
      ),
    );
  }
}

class _HistoryCell extends StatelessWidget {
  const _HistoryCell(this.text, {this.alignment = Alignment.centerLeft});

  final String text;
  final AlignmentGeometry alignment;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: Align(
        alignment: alignment,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Stack(
            children: <Widget>[
              ExcludeSemantics(
                child: Opacity(
                  opacity: 0,
                  child: Text(
                    _historyCellMeasurementText(text),
                    maxLines: 1,
                    softWrap: false,
                  ),
                ),
              ),
              Text(text, maxLines: 1, softWrap: false),
            ],
          ),
        ),
      ),
    );
  }
}

class _HistoryMoneyCell extends StatelessWidget {
  const _HistoryMoneyCell({
    required this.value,
    required this.currencyCode,
    required this.widestAmount,
  });

  final num? value;
  final String currencyCode;
  final String widestAmount;

  @override
  Widget build(BuildContext context) {
    if (value == null) {
      return const _HistoryCell('-', alignment: Alignment.centerRight);
    }

    final String currency = currencyCode.trim().toUpperCase();
    final String amount = displayNumber(value);
    return SizedBox(
      height: 48,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Align(
          alignment: Alignment.centerRight,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              _HistoryMeasuredText(currency),
              const SizedBox(width: 8),
              _HistoryMeasuredText(
                amount,
                measurementText: widestAmount,
                alignment: Alignment.centerRight,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HistoryMeasuredText extends StatelessWidget {
  const _HistoryMeasuredText(
    this.text, {
    String? measurementText,
    this.alignment = Alignment.centerLeft,
  }) : measurementText = measurementText ?? text;

  final String text;
  final String measurementText;
  final AlignmentGeometry alignment;

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: alignment,
      children: <Widget>[
        ExcludeSemantics(
          child: Opacity(
            opacity: 0,
            child: Text(
              _historyCellMeasurementText(measurementText),
              maxLines: 1,
              softWrap: false,
            ),
          ),
        ),
        Text(text, maxLines: 1, softWrap: false),
      ],
    );
  }
}

String _historyCellMeasurementText(String value) {
  final StringBuffer buffer = StringBuffer();
  for (final int codeUnit in value.codeUnits) {
    if (codeUnit >= 48 && codeUnit <= 57) {
      buffer.write('8');
    } else if ((codeUnit >= 65 && codeUnit <= 90) ||
        (codeUnit >= 97 && codeUnit <= 122)) {
      buffer.write('Q');
    } else {
      buffer.writeCharCode(codeUnit);
    }
  }
  return buffer.toString();
}

BoxDecoration _panelDecoration(BuildContext context) {
  final ColorScheme colors = Theme.of(context).colorScheme;
  return BoxDecoration(
    color: Colors.white,
    border: Border.all(color: colors.outlineVariant),
    borderRadius: BorderRadius.circular(8),
  );
}
