import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../core/dashboard_theme.dart';
import '../services/admin_auth_service.dart';

class DashboardSidebar extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onNavTap;

  const DashboardSidebar({
    super.key,
    required this.selectedIndex,
    required this.onNavTap,
  });

  static const _kBg = Color(0xFF0F172A);
  static const _kDivider = Color(0xFF1E293B);
  static const _kMuted = Color(0xFF94A3B8);
  static const _kMenuLabel = Color(0xFF475569);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 220,
      color: _kBg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildBrand(),
          Container(height: 1, color: _kDivider),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text(
              'MAIN MENU',
              style: GoogleFonts.inter(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.2,
                color: _kMenuLabel,
              ),
            ),
          ),
          _SidebarItem(
            icon: Icons.dashboard_outlined,
            label: 'Overview',
            selected: selectedIndex == 0,
            onTap: () => onNavTap(0),
          ),
          _SidebarItem(
            icon: Icons.table_chart_outlined,
            label: 'Data Tables',
            selected: selectedIndex == 1,
            onTap: () => onNavTap(1),
          ),
          const Spacer(),
          Container(height: 1, color: _kDivider),
          const SizedBox(height: 8),
          _SidebarItem(
            icon: Icons.logout,
            label: 'Sign Out',
            selected: false,
            onTap: AdminAuthService.signOut,
            iconColor: const Color(0xFFFC8181),
            labelColor: const Color(0xFFFC8181),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildBrand() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 28, 20, 20),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
            ),
            padding: const EdgeInsets.all(4),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Image.asset(
                'assets/icons/app_icon.png',
                fit: BoxFit.contain,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'i-Share',
                style: GoogleFonts.inter(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                  height: 1.2,
                ),
              ),
              Text(
                'Admin Panel',
                style: GoogleFonts.inter(fontSize: 11, color: _kMuted),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SidebarItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Color? iconColor;
  final Color? labelColor;

  const _SidebarItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.iconColor,
    this.labelColor,
  });

  @override
  Widget build(BuildContext context) {
    final fg = iconColor ?? (selected ? Colors.white : const Color(0xFF94A3B8));
    final lfg = labelColor ?? (selected ? Colors.white : const Color(0xFF94A3B8));

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: Material(
        color: selected ? kBlue : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          hoverColor: Colors.white.withValues(alpha: 0.06),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Icon(icon, size: 17, color: fg),
                const SizedBox(width: 10),
                Text(
                  label,
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                    color: lfg,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
