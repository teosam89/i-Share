import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../core/dashboard_prefs.dart';
import '../core/dashboard_theme.dart';
import '../services/analytics_service.dart';
import '../widgets/chart_override_menu.dart';
import '../widgets/dashboard_sidebar.dart';
import '../widgets/kpi_card.dart';
import '../widgets/range_pill_filter.dart';
import '../widgets/users_line_chart.dart';
import '../widgets/category_pie_chart.dart';
import '../widgets/credibility_bar_chart.dart';
import '../widgets/co_request_map.dart';
import '../widgets/co_requests_timeline.dart';
import '../widgets/status_donut.dart';
import '../widgets/top_stores_chart.dart';
import '../widgets/score_distribution.dart';
import 'tables_screen.dart';

class OverviewScreen extends StatefulWidget {
  const OverviewScreen({super.key});

  @override
  State<OverviewScreen> createState() => _OverviewScreenState();
}

class _OverviewScreenState extends State<OverviewScreen> {
  late Future<DashboardData> _future;

  // Chart IDs — must be stable across builds (used for preference keys).
  static const _cidUsersLine = 'users_line';
  static const _cidCategoryPie = 'category_pie';
  static const _cidTimeline = 'timeline';
  static const _cidStatusDonut = 'status_donut';
  static const _cidCredBar = 'cred_bar';
  static const _cidTopStores = 'top_stores';
  static const _cidScoreDist = 'score_dist';
  static const _cidMap = 'map';

  // KPI IDs
  static const _kpiUsers = 'users';
  static const _kpiCoRequests = 'corequests';
  static const _kpiCompletion = 'completion';
  static const _kpiRtm = 'rtm';

  DashboardPrefs? _prefs;
  int? _masterDays;
  Map<String, int?> _overrides = {};
  Map<String, KpiDisplay> _kpiDisplays = {};
  Set<String> _overrideKeys = {}; // tracks which charts have an explicit override

  @override
  void initState() {
    super.initState();
    _future = AnalyticsService.load();
    _hydratePrefs();
  }

  Future<void> _hydratePrefs() async {
    final prefs = await DashboardPrefs.load();
    final overrides = prefs.chartOverrides;
    final displays = prefs.kpiDisplays.map((k, v) {
      final d = KpiDisplay.values.firstWhere(
        (e) => e.name == v,
        orElse: () => KpiDisplay.number,
      );
      return MapEntry(k, d);
    });
    if (!mounted) return;
    setState(() {
      _prefs = prefs;
      _masterDays = prefs.masterDays;
      _overrides = overrides;
      _overrideKeys = overrides.keys.toSet();
      _kpiDisplays = displays;
    });
  }

  void _refresh() => setState(() => _future = AnalyticsService.load());

  void _onNav(int index) {
    if (index == 1) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const TablesScreen()),
      );
    }
  }

  void _setMaster(int? days) {
    setState(() => _masterDays = days);
    _prefs?.setMasterDays(days);
  }

  void _setOverride(String chartId, OverrideValue v) {
    setState(() {
      if (v.inherit) {
        _overrides.remove(chartId);
        _overrideKeys.remove(chartId);
      } else {
        _overrides[chartId] = v.days;
        _overrideKeys.add(chartId);
      }
    });
    if (v.inherit) {
      _prefs?.clearChartOverride(chartId);
    } else {
      _prefs?.setChartOverride(chartId, v.days);
    }
  }

  void _setKpiDisplay(String kpiId, KpiDisplay d) {
    setState(() => _kpiDisplays[kpiId] = d);
    _prefs?.setKpiDisplay(kpiId, d.name);
  }

  int? _effective(String chartId) =>
      _overrideKeys.contains(chartId) ? _overrides[chartId] : _masterDays;

  OverrideValue _override(String chartId) => _overrideKeys.contains(chartId)
      ? OverrideValue.window(_overrides[chartId])
      : const OverrideValue.inherit();

  KpiDisplay _displayFor(String kpiId, KpiDisplay fallback) =>
      _kpiDisplays[kpiId] ?? fallback;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBgPage,
      body: Row(
        children: [
          DashboardSidebar(selectedIndex: 0, onNavTap: _onNav),
          Expanded(
            child: Column(
              children: [
                _buildTopBar(),
                Expanded(
                  child: FutureBuilder<DashboardData>(
                    future: _future,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      if (snapshot.hasError) {
                        return _buildError(snapshot.error);
                      }
                      return _buildContent(snapshot.data!);
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopBar() {
    return Container(
      height: 60,
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: kN300)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Row(
        children: [
          Text(
            'Overview',
            style: GoogleFonts.inter(
              fontSize: 17,
              fontWeight: FontWeight.w600,
              color: kN900,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: kGreen.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: const BoxDecoration(
                    color: kGreen,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 5),
                Text(
                  'Live',
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    color: kGreen,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          // Master date filter
          Text(
            'Range:',
            style: GoogleFonts.inter(fontSize: 12, color: kN500),
          ),
          const SizedBox(width: 8),
          RangePillFilter(
            value: _masterDays,
            onChanged: _setMaster,
            dense: true,
          ),
          const Spacer(),
          FutureBuilder<DashboardData>(
            future: _future,
            builder: (context, snapshot) {
              if (!snapshot.hasData) return const SizedBox();
              final d = snapshot.data!;
              final m = d.metricsFor(days: _masterDays);
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: kPurple.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.group_outlined, size: 13, color: kPurple),
                        const SizedBox(width: 5),
                        Text(
                          'Avg ${m.avgGroupSize.toStringAsFixed(1)} per group',
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            color: kPurple,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Updated ${DateFormat('d MMM, HH:mm').format(d.fetchedAt)}',
                    style: GoogleFonts.inter(fontSize: 12, color: kN400),
                  ),
                ],
              );
            },
          ),
          const SizedBox(width: 16),
          OutlinedButton.icon(
            onPressed: _refresh,
            icon: const Icon(Icons.refresh, size: 15),
            label: Text('Refresh', style: GoogleFonts.inter(fontSize: 13)),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: kN300),
              foregroundColor: kN700,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              minimumSize: Size.zero,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildError(Object? error) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, size: 48, color: kRed),
          const SizedBox(height: 12),
          Text('Failed to load data',
              style: GoogleFonts.inter(
                  fontSize: 16, fontWeight: FontWeight.w600, color: kN700)),
          const SizedBox(height: 4),
          Text('$error', style: GoogleFonts.inter(fontSize: 12, color: kN500)),
          const SizedBox(height: 16),
          FilledButton(onPressed: _refresh, child: const Text('Retry')),
        ],
      ),
    );
  }

  Widget _buildContent(DashboardData data) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(28, 24, 28, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionLabel('Key Metrics'),
          const SizedBox(height: 12),

          // Row 1: 4 KPI cards (each respects master filter; KPIs don't have per-card override
          // — their display TYPE is the per-card choice instead)
          Row(
            children: [
              Expanded(child: _buildUsersKpi(data)),
              const SizedBox(width: 16),
              Expanded(child: _buildCoRequestsKpi(data)),
              const SizedBox(width: 16),
              Expanded(child: _buildCompletionKpi(data)),
              const SizedBox(width: 16),
              Expanded(child: _buildRtmKpi(data)),
            ],
          ),

          const SizedBox(height: 28),
          _sectionLabel('Analytics'),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 5,
                child: () {
                  final d = _effective(_cidUsersLine);
                  return UsersLineChart(
                    data: data.newUsersTimeSeries(days: d),
                    totalUsers: data.profilesIn(days: d).length,
                    days: d,
                    dateOverride: _override(_cidUsersLine),
                    masterDays: _masterDays,
                    onOverrideChange: (v) => _setOverride(_cidUsersLine, v),
                  );
                }(),
              ),
              const SizedBox(width: 16),
              Expanded(
                flex: 4,
                child: CategoryPieChart(
                  data: data.categoryCounts(days: _effective(_cidCategoryPie)),
                  dateOverride: _override(_cidCategoryPie),
                  masterDays: _masterDays,
                  onOverrideChange: (v) => _setOverride(_cidCategoryPie, v),
                ),
              ),
            ],
          ),

          const SizedBox(height: 28),
          _sectionLabel('Trends'),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 5,
                child: () {
                  final d = _effective(_cidTimeline);
                  return CoRequestsTimeline(
                    data: data.coRequestsPerDay(days: d),
                    days: d,
                    dateOverride: _override(_cidTimeline),
                    masterDays: _masterDays,
                    onOverrideChange: (v) => _setOverride(_cidTimeline, v),
                  );
                }(),
              ),
              const SizedBox(width: 16),
              Expanded(
                flex: 4,
                child: StatusDonut(
                  data: data.statusCounts(days: _effective(_cidStatusDonut)),
                  dateOverride: _override(_cidStatusDonut),
                  masterDays: _masterDays,
                  onOverrideChange: (v) => _setOverride(_cidStatusDonut, v),
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),
          CredibilityBarChart(
            data: data.scoreEventCounts(days: _effective(_cidCredBar)),
            dateOverride: _override(_cidCredBar),
            masterDays: _masterDays,
            onOverrideChange: (v) => _setOverride(_cidCredBar, v),
          ),

          const SizedBox(height: 28),
          _sectionLabel('Insights'),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 5,
                child: TopStoresChart(
                  data: data.topStores(days: _effective(_cidTopStores)),
                  dateOverride: _override(_cidTopStores),
                  masterDays: _masterDays,
                  onOverrideChange: (v) => _setOverride(_cidTopStores, v),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                flex: 4,
                child: ScoreDistribution(
                  data: data.scoreDistribution(days: _effective(_cidScoreDist)),
                  dateOverride: _override(_cidScoreDist),
                  masterDays: _masterDays,
                  onOverrideChange: (v) => _setOverride(_cidScoreDist, v),
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),
          CoRequestMap(
            points: data.mapPoints(days: _effective(_cidMap)),
            dateOverride: _override(_cidMap),
            masterDays: _masterDays,
            onOverrideChange: (v) => _setOverride(_cidMap, v),
          ),
        ],
      ),
    );
  }

  // ─── KPI builders ───────────────────────────────────────────────────────────

  Widget _buildUsersKpi(DashboardData data) {
    final m = data.metricsFor(days: _masterDays);
    final display = _displayFor(_kpiUsers, KpiDisplay.number);
    final series = data.newUsersTimeSeries(days: _masterDays);
    final scoreDist = data.scoreDistribution(days: _masterDays);
    return KpiCard(
      kpiId: _kpiUsers,
      icon: Icons.people_outline,
      label: 'Total Users',
      value: '${m.totalUsers}',
      subtitle: _masterDays == null
          ? 'Registered accounts'
          : 'New in ${windowLabel(_masterDays)}',
      color: kBlue,
      availableDisplays: const [KpiDisplay.number, KpiDisplay.line, KpiDisplay.bar],
      display: display,
      onDisplayChange: (d) => _setKpiDisplay(_kpiUsers, d),
      lineData: series.map((p) => p.count.toDouble()).toList(),
      barData: {
        'User': (count: scoreDist['User'] ?? 0, color: kN500),
        'Trusted': (count: scoreDist['Trusted'] ?? 0, color: kBlue),
        'Elite': (count: scoreDist['Elite'] ?? 0, color: kAmber),
      },
    );
  }

  Widget _buildCoRequestsKpi(DashboardData data) {
    final m = data.metricsFor(days: _masterDays);
    final display = _displayFor(_kpiCoRequests, KpiDisplay.number);
    final statusCounts = data.statusCounts(days: _masterDays);
    final catCounts = data.categoryCounts(days: _masterDays);

    // Fixed 8-category order — matches RequestCategories in the main app.
    const orderedCats = <String>[
      'groceries', 'fresh', 'snacks', 'household',
      'personal', 'baby_pets', 'electronics', 'others',
    ];
    const catColors = <String, Color>{
      'groceries': Color(0xFF3B82F6),
      'fresh': kGreen,
      'snacks': Color(0xFFF97316),
      'household': kPurple,
      'personal': Color(0xFFEC4899),
      'baby_pets': Color(0xFFD946EF),
      'electronics': kBlue,
      'others': Color(0xFFCA8A04),
    };
    const catLabels = <String, String>{
      'groceries': 'Groceries',
      'fresh': 'Fresh',
      'snacks': 'Snacks',
      'household': 'Household',
      'personal': 'Personal',
      'baby_pets': 'Baby/Pets',
      'electronics': 'Electron.',
      'others': 'Others',
    };

    return KpiCard(
      kpiId: _kpiCoRequests,
      icon: Icons.shopping_bag_outlined,
      label: 'Co-Requests',
      value: '${m.totalCoRequests}',
      subtitle: '${m.completedCoRequests} completed',
      color: kPurple,
      availableDisplays: const [KpiDisplay.number, KpiDisplay.donut, KpiDisplay.bar],
      display: display,
      onDisplayChange: (d) => _setKpiDisplay(_kpiCoRequests, d),
      donutSegments: {
        'Active': (count: statusCounts['active'] ?? 0, color: kGreen),
        'Completed': (count: statusCounts['completed'] ?? 0, color: kBlue),
        'Expired': (count: statusCounts['expired'] ?? 0, color: kCyan),
        'Cancelled': (count: statusCounts['cancelled'] ?? 0, color: kRed),
      },
      barData: {
        for (final k in orderedCats)
          catLabels[k] ?? k:
              (count: catCounts[k] ?? 0, color: catColors[k] ?? kN500),
      },
    );
  }

  Widget _buildCompletionKpi(DashboardData data) {
    final m = data.metricsFor(days: _masterDays);
    final display = _displayFor(_kpiCompletion, KpiDisplay.number);
    return KpiCard(
      kpiId: _kpiCompletion,
      icon: Icons.check_circle_outline,
      label: 'Completion Rate',
      value: '${(m.completionRate * 100).toStringAsFixed(1)}%',
      subtitle: '${m.completedCoRequests} of ${m.totalCoRequests}',
      color: kGreen,
      availableDisplays: const [KpiDisplay.number, KpiDisplay.donut],
      display: display,
      onDisplayChange: (d) => _setKpiDisplay(_kpiCompletion, d),
      gaugePercent: m.completionRate,
    );
  }

  Widget _buildRtmKpi(DashboardData data) {
    final m = data.metricsFor(days: _masterDays);
    final display = _displayFor(_kpiRtm, KpiDisplay.number);
    return KpiCard(
      kpiId: _kpiRtm,
      icon: Icons.swap_horiz,
      label: 'RTM → Co-Buy',
      value: '${(m.rtmConversionRate * 100).toStringAsFixed(1)}%',
      subtitle: '${m.convertedRtms} of ${m.totalRtms} sessions',
      color: kAmber,
      availableDisplays: const [KpiDisplay.number, KpiDisplay.donut],
      display: display,
      onDisplayChange: (d) => _setKpiDisplay(_kpiRtm, d),
      gaugePercent: m.rtmConversionRate,
    );
  }

  Widget _sectionLabel(String text) {
    return Text(
      text,
      style: GoogleFonts.inter(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: kN500,
        letterSpacing: 0.4,
      ),
    );
  }
}
