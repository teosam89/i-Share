import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// Backgrounds
const kBgPage = Color(0xFFF0F2F5);

// Semantic colours
const kBlue   = Color(0xFF3B6FD4);
const kGreen  = Color(0xFF16A34A);
const kAmber  = Color(0xFFD97706);
const kRed    = Color(0xFFDC2626);
const kPurple = Color(0xFF7C3AED);
const kCyan   = Color(0xFF0891B2);

// Neutral scale
const kN900 = Color(0xFF111827);
const kN700 = Color(0xFF374151);
const kN500 = Color(0xFF6B7280);
const kN400 = Color(0xFF9CA3AF);
const kN300 = Color(0xFFD1D5DB);
const kN100 = Color(0xFFF3F4F6);

// Text styles (call as getters so GoogleFonts is initialised by the time they're used)
TextStyle get kLabelCaps => GoogleFonts.inter(
  fontSize: 11,
  fontWeight: FontWeight.w500,
  letterSpacing: 0.8,
  color: kN500,
);

TextStyle get kKpiValue => GoogleFonts.inter(
  fontSize: 40,
  fontWeight: FontWeight.w700,
  letterSpacing: -1.5,
  height: 1.0,
);

TextStyle get kKpiSubtitle => GoogleFonts.inter(fontSize: 12, color: kN500);

TextStyle get kCardBody => GoogleFonts.inter(fontSize: 12, color: kN500);

TextStyle get kSectionLabel => GoogleFonts.inter(
  fontSize: 12,
  fontWeight: FontWeight.w600,
  color: kN500,
  letterSpacing: 0.3,
);
