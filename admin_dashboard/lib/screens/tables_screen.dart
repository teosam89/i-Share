import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../core/dashboard_theme.dart';
import '../services/analytics_service.dart';
import '../widgets/dashboard_sidebar.dart';
import '../widgets/pill_tabs.dart';
import '../widgets/profiles_table.dart';
import '../widgets/co_requests_table.dart';
import '../widgets/rtm_table.dart';
import '../widgets/score_activities_table.dart';

class TablesScreen extends StatefulWidget {
  const TablesScreen({super.key});

  @override
  State<TablesScreen> createState() => _TablesScreenState();
}

class _TablesScreenState extends State<TablesScreen> {
  late Future<TableRawData> _future;
  int _tabIndex = 0;

  @override
  void initState() {
    super.initState();
    _future = AnalyticsService.loadTableData();
  }

  void _reload() => setState(() => _future = AnalyticsService.loadTableData());

  void _onNav(int index) {
    if (index == 0) {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBgPage,
      body: Row(
        children: [
          DashboardSidebar(selectedIndex: 1, onNavTap: _onNav),
          Expanded(
            child: Column(
              children: [
                _buildTopBar(),
                Expanded(
                  child: FutureBuilder<TableRawData>(
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
            'Data Tables',
            style: GoogleFonts.inter(
              fontSize: 17,
              fontWeight: FontWeight.w600,
              color: kN900,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 8,
              vertical: 3,
            ),
            decoration: BoxDecoration(
              color: kBlue.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              'Read-only',
              style: GoogleFonts.inter(
                fontSize: 11,
                color: kBlue,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const Spacer(),
          OutlinedButton.icon(
            onPressed: _reload,
            icon: const Icon(Icons.refresh, size: 15),
            label: Text('Refresh', style: GoogleFonts.inter(fontSize: 13)),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: kN300),
              foregroundColor: kN700,
              padding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 8,
              ),
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
          Text(
            'Failed to load data',
            style: GoogleFonts.inter(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: kN700,
            ),
          ),
          const SizedBox(height: 4),
          Text('$error', style: GoogleFonts.inter(fontSize: 12, color: kN500)),
          const SizedBox(height: 16),
          FilledButton(onPressed: _reload, child: const Text('Retry')),
        ],
      ),
    );
  }

  Widget _buildContent(TableRawData data) {
    final tabs = [
      PillTabItem(
        label: 'Profiles',
        icon: Icons.people_outline,
        count: data.profiles.length,
      ),
      PillTabItem(
        label: 'Co-Requests',
        icon: Icons.shopping_bag_outlined,
        count: data.coRequests.length,
      ),
      PillTabItem(
        label: 'RTM',
        icon: Icons.swap_horiz,
        count: data.realtimeMatches.length,
      ),
      PillTabItem(
        label: 'Score Activities',
        icon: Icons.star_border,
        count: data.scoreActivities.length,
      ),
    ];

    final tables = [
      ProfilesTable(rows: data.profiles),
      CoRequestsTable(rows: data.coRequests),
      RtmTable(rows: data.realtimeMatches),
      ScoreActivitiesTable(rows: data.scoreActivities),
    ];

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(28, 24, 28, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: PillTabs(
              items: tabs,
              selectedIndex: _tabIndex,
              onChanged: (i) => setState(() => _tabIndex = i),
            ),
          ),
          const SizedBox(height: 20),
          tables[_tabIndex],
        ],
      ),
    );
  }
}
