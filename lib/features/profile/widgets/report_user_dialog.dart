import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../services/report_service.dart';

/// Dialog for reporting a user
class ReportUserDialog extends StatefulWidget {
  final String reportedUserId;
  final String reportedUserName;
  final String? requestId;

  const ReportUserDialog({
    super.key,
    required this.reportedUserId,
    required this.reportedUserName,
    this.requestId,
  });

  @override
  State<ReportUserDialog> createState() => _ReportUserDialogState();
}

class _ReportUserDialogState extends State<ReportUserDialog> {
  ReportReason? _selectedReason;
  final _descriptionController = TextEditingController();
  bool _isSubmitting = false;

  @override
  void dispose() {
    _descriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Icon(Icons.report_outlined, color: AppColors.error, size: 28),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Report ${widget.reportedUserName}',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Reason selection
            Text(
              'Why are you reporting this user?',
              style: TextStyle(fontSize: 14, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 12),

            RadioGroup<ReportReason>(
              groupValue: _selectedReason,
              onChanged: (value) => setState(() => _selectedReason = value),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: ReportReason.values.map(
                  (reason) => RadioListTile<ReportReason>(
                    title: Text(ReportService.getReasonText(reason)),
                    value: reason,
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                  ),
                ).toList(),
              ),
            ),

            const SizedBox(height: 12),

            // Description field
            TextField(
              controller: _descriptionController,
              maxLines: 3,
              maxLength: 500,
              decoration: InputDecoration(
                hintText: 'Additional details (optional)',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                contentPadding: const EdgeInsets.all(12),
              ),
            ),

            const SizedBox(height: 16),

            // Action buttons
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _selectedReason == null || _isSubmitting
                        ? null
                        : _submitReport,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.error,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: _isSubmitting
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text('Submit Report'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _submitReport() async {
    if (_selectedReason == null) return;

    setState(() => _isSubmitting = true);

    try {
      final success = await ReportService().submitReport(
        reportedUserId: widget.reportedUserId,
        reason: _selectedReason!,
        requestId: widget.requestId,
        description: _descriptionController.text.trim().isEmpty
            ? null
            : _descriptionController.text.trim(),
      );

      if (mounted) {
        if (success) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Report submitted. Thank you.'),
              backgroundColor: AppColors.success,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text(
                'You have already reported this user recently.',
              ),
              backgroundColor: AppColors.error,
            ),
          );
        }
        Navigator.pop(context, success);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSubmitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Something went wrong. Please try again.'),
          ),
        );
      }
    }
  }
}

/// Helper function to show report dialog
Future<bool?> showReportUserDialog({
  required BuildContext context,
  required String reportedUserId,
  required String reportedUserName,
  String? requestId,
}) {
  return showDialog<bool>(
    context: context,
    builder: (ctx) => ReportUserDialog(
      reportedUserId: reportedUserId,
      reportedUserName: reportedUserName,
      requestId: requestId,
    ),
  );
}
