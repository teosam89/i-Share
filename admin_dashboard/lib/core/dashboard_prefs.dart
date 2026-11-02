import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Lightweight preference store for dashboard UI state — master date filter,
/// per-chart date override, and per-KPI display type. Persists locally so
/// admins keep their layout between sessions.
class DashboardPrefs {
  DashboardPrefs._(this._sp);

  final SharedPreferences _sp;

  static const _kMaster = 'dash.master_days';
  static const _kOverrides = 'dash.chart_overrides';
  static const _kKpiDisplays = 'dash.kpi_displays';

  static Future<DashboardPrefs> load() async {
    final sp = await SharedPreferences.getInstance();
    return DashboardPrefs._(sp);
  }

  // -1 sentinel = "all time" (null). Picked because shared_preferences won't
  // store null and we'd rather avoid a separate "has key" boolean.
  static const _kAllTimeSentinel = -1;

  int? get masterDays {
    if (!_sp.containsKey(_kMaster)) return null; // default: all time
    final v = _sp.getInt(_kMaster) ?? _kAllTimeSentinel;
    return v == _kAllTimeSentinel ? null : v;
  }

  Future<void> setMasterDays(int? days) =>
      _sp.setInt(_kMaster, days ?? _kAllTimeSentinel);

  Map<String, int?> get chartOverrides {
    final raw = _sp.getString(_kOverrides);
    if (raw == null) return {};
    try {
      final m = jsonDecode(raw) as Map<String, dynamic>;
      return m.map((k, v) {
        final i = v as int;
        return MapEntry(k, i == _kAllTimeSentinel ? null : i);
      });
    } catch (_) {
      return {};
    }
  }

  Future<void> setChartOverride(String chartId, int? days) async {
    final current = chartOverrides;
    if (days == null && current[chartId] == null) {
      // "Inherit" — remove the entry entirely
      current.remove(chartId);
    } else {
      current[chartId] = days;
    }
    final encoded = current.map(
      (k, v) => MapEntry(k, v ?? _kAllTimeSentinel),
    );
    await _sp.setString(_kOverrides, jsonEncode(encoded));
  }

  Future<void> clearChartOverride(String chartId) async {
    final current = chartOverrides..remove(chartId);
    final encoded = current.map(
      (k, v) => MapEntry(k, v ?? _kAllTimeSentinel),
    );
    await _sp.setString(_kOverrides, jsonEncode(encoded));
  }

  Map<String, String> get kpiDisplays {
    final raw = _sp.getString(_kKpiDisplays);
    if (raw == null) return {};
    try {
      final m = jsonDecode(raw) as Map<String, dynamic>;
      return m.map((k, v) => MapEntry(k, v.toString()));
    } catch (_) {
      return {};
    }
  }

  Future<void> setKpiDisplay(String kpiId, String displayMode) async {
    final current = kpiDisplays;
    current[kpiId] = displayMode;
    await _sp.setString(_kKpiDisplays, jsonEncode(current));
  }
}
