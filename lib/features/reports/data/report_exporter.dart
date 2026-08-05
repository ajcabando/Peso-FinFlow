import 'dart:convert';
import 'dart:typed_data';

import 'package:file_saver/file_saver.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../transactions/domain/models/category_spend.dart';
import '../../transactions/domain/models/transaction_context.dart';

/// Data needed to render a period report (income/expense + transactions).
class ReportData {
  const ReportData({
    required this.from,
    required this.to,
    required this.currencyCode,
    required this.incomeMinor,
    required this.expenseMinor,
    required this.categories,
    required this.contexts,
  });

  final DateTime from;
  final DateTime to;
  final String currencyCode;
  final int incomeMinor;
  final int expenseMinor;
  final List<CategorySpend> categories;
  final List<TransactionContext> contexts;

  int get netMinor => incomeMinor - expenseMinor;
}

/// Generates and saves CSV / PDF reports for a period.
///
/// Pure Dart generation (`package:pdf`) keeps the output identical on every
/// platform; saving goes through `file_saver`, which downloads the file on
/// web and writes it to the device on native targets.
abstract final class ReportExporter {
  static final DateFormat _day = DateFormat('yyyy-MM-dd');
  static final DateFormat _short = DateFormat('MMM d, yyyy');

  static String _csvEscape(String value) {
    if (value.contains(',') ||
        value.contains('"') ||
        value.contains('\n') ||
        value.contains('\r')) {
      return '"${value.replaceAll('"', '""')}"';
    }
    return value;
  }

  /// Builds a UTF-8 CSV string: a header block, a blank line, then one row
  /// per transaction (newest first).
  static String buildCsv(ReportData report) {
    final buffer = StringBuffer()
      ..writeln('FinFlow transaction report')
      ..writeln(
        'Period,${_day.format(report.from)} to ${_day.format(report.to)}',
      )
      ..writeln('Currency,${report.currencyCode}')
      ..writeln(
        'Income,${CurrencyFormatter.format(report.incomeMinor, report.currencyCode)}',
      )
      ..writeln(
        'Expense,${CurrencyFormatter.format(report.expenseMinor, report.currencyCode)}',
      )
      ..writeln(
        'Net,${CurrencyFormatter.format(report.netMinor, report.currencyCode)}',
      )
      ..writeln()
      ..writeln(
        'Date,Type,Title,Category,Account,Amount,Note,Currency',
      );

    for (final context in report.contexts) {
      final transaction = context.transaction;
      final amount = _asMajor(transaction.amountMinor, report.currencyCode);
      buffer
        ..write(_csvEscape(_day.format(transaction.occurredAt)))
        ..write(',')
        ..write(_csvEscape(transaction.type.label))
        ..write(',')
        ..write(_csvEscape(transaction.title))
        ..write(',')
        ..write(_csvEscape(context.categoryName ?? ''))
        ..write(',')
        ..write(_csvEscape(context.accountName ?? ''))
        ..write(',')
        ..write(_csvEscape(amount))
        ..write(',')
        ..write(_csvEscape(transaction.note ?? ''))
        ..write(',')
        ..writeln(_csvEscape(report.currencyCode));
    }
    return buffer.toString();
  }

  /// Generates the PDF statement bytes for [report].
  static Future<Uint8List> buildPdf(ReportData report) async {
    final doc = pw.Document(title: 'FinFlow Report');
    final accent = PdfColor.fromInt(AppColors.brand.toARGB32());
    final green = PdfColor.fromInt(AppColors.income.toARGB32());
    final red = PdfColor.fromInt(AppColors.expense.toARGB32());

    pw.Widget summaryRow(String label, String value, {PdfColor? color}) =>
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              label,
              style: const pw.TextStyle(
                fontSize: 12,
                color: PdfColors.grey700,
              ),
            ),
            pw.Text(
              value,
              style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: color),
            ),
          ],
        );

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(36),
        header: (context) => pw.Container(
          padding: const pw.EdgeInsets.only(bottom: 10),
          decoration: const pw.BoxDecoration(
            border: pw.Border(
              bottom: pw.BorderSide(color: PdfColors.grey300, width: 1),
            ),
          ),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                'FinFlow',
                style: pw.TextStyle(
                  fontSize: 18,
                  fontWeight: pw.FontWeight.bold,
                  color: accent,
                ),
              ),
              pw.Text(
                'Transaction report',
                style: const pw.TextStyle(fontSize: 11, color: PdfColors.grey600),
              ),
            ],
          ),
        ),
        footer: (context) => pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text(
            'Page ${context.pageNumber} of ${context.pagesCount}',
            style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey500),
          ),
        ),
        build: (context) => [
          pw.SizedBox(height: 8),
          pw.Text(
            '${report.from.monthYearLabel} report',
            style: const pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 4),
          pw.Text(
            '${_short.format(report.from)} — ${_short.format(report.to)} · '
            'Generated ${_short.format(DateTime.now())}',
            style: const pw.TextStyle(fontSize: 11, color: PdfColors.grey600),
          ),
          pw.SizedBox(height: 18),
          pw.Container(
            padding: const pw.EdgeInsets.all(16),
            decoration: pw.BoxDecoration(
              color: PdfColor.fromInt(0x0F6D5DF6),
              borderRadius: pw.BorderRadius.circular(10),
            ),
            child: pw.Column(
              children: [
                summaryRow(
                  'Income',
                  CurrencyFormatter.format(
                    report.incomeMinor,
                    report.currencyCode,
                  ),
                  color: green,
                ),
                pw.SizedBox(height: 8),
                summaryRow(
                  'Expense',
                  CurrencyFormatter.format(
                    report.expenseMinor,
                    report.currencyCode,
                  ),
                  color: red,
                ),
                pw.SizedBox(height: 8),
                summaryRow(
                  'Net savings',
                  CurrencyFormatter.format(report.netMinor, report.currencyCode),
                  color: report.netMinor >= 0 ? green : red,
                ),
              ],
            ),
          ),
          if (report.categories.isNotEmpty) ...[
            pw.SizedBox(height: 24),
            pw.Text(
              'Spending by category',
              style: const pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 8),
            pw.TableHelper.fromTextArray(
              headers: ['Category', 'Amount', 'Share'],
              data: [
                for (final category in report.categories)
                  [
                    category.categoryName,
                    CurrencyFormatter.format(
                      category.amountMinor,
                      report.currencyCode,
                    ),
                    '${report.expenseMinor == 0 ? 0 : (category.amountMinor / report.expenseMinor * 100).round()}%',
                  ],
              ],
              headerStyle: const pw.TextStyle(
                fontSize: 10,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.white,
              ),
              headerDecoration: pw.BoxDecoration(color: accent),
              cellStyle: const pw.TextStyle(fontSize: 10),
              cellAlignments: {
                1: pw.Alignment.centerRight,
                2: pw.Alignment.centerRight,
              },
              columnWidths: {
                0: const pw.FlexColumnWidth(3),
                1: const pw.FlexColumnWidth(2),
                2: const pw.FlexColumnWidth(1),
              },
            ),
          ],
          pw.SizedBox(height: 24),
          pw.Text(
            'Transactions (${report.contexts.length})',
            style: const pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 8),
          if (report.contexts.isEmpty)
            pw.Text('No transactions in this period.', style: const pw.TextStyle(fontSize: 10))
          else
            pw.TableHelper.fromTextArray(
              headers: ['Date', 'Type', 'Title', 'Category', 'Account', 'Amount'],
              data: [
                for (final context in report.contexts)
                  [
                    _day.format(context.transaction.occurredAt),
                    context.transaction.type.label,
                    context.transaction.title,
                    context.categoryName ?? '',
                    context.accountName ?? '',
                    CurrencyFormatter.format(
                      context.transaction.amountMinor,
                      report.currencyCode,
                    ),
                  ],
              ],
              headerStyle: const pw.TextStyle(
                fontSize: 9,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.white,
              ),
              headerDecoration: pw.BoxDecoration(color: PdfColors.grey700),
              cellStyle: const pw.TextStyle(fontSize: 9),
              cellAlignments: {5: pw.Alignment.centerRight},
              columnWidths: {
                0: const pw.FlexColumnWidth(1),
                1: const pw.FlexColumnWidth(1),
                2: const pw.FlexColumnWidth(2.4),
                3: const pw.FlexColumnWidth(1.6),
                4: const pw.FlexColumnWidth(1.6),
                5: const pw.FlexColumnWidth(1.4),
              },
            ),
        ],
      ),
    );
    return doc.save();
  }

  /// Saves [report] as a CSV file (downloaded on web).
  static Future<void> exportCsv(ReportData report) async {
    final bytes = Uint8List.fromList(utf8.encode(buildCsv(report)));
    await FileSaver.instance.saveFile(
      name: 'finflow-report-${_fileStamp(report.from)}',
      bytes: bytes,
      fileExtension: 'csv',
      mimeType: MimeType.csv,
    );
  }

  /// Saves [report] as a PDF file (downloaded on web).
  static Future<void> exportPdf(ReportData report) async {
    final bytes = await buildPdf(report);
    await FileSaver.instance.saveFile(
      name: 'finflow-report-${_fileStamp(report.from)}',
      bytes: bytes,
      fileExtension: 'pdf',
      mimeType: MimeType.pdf,
    );
  }

  static String _asMajor(int minor, String currencyCode) {
    final digits = CurrencyFormatter.decimalDigits(currencyCode);
    final divisor = CurrencyFormatter.pow10(digits);
    return (minor / divisor).toStringAsFixed(digits);
  }

  static String _fileStamp(DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}';
}

/// Small helper for month labels on the report page.
extension _MonthLabel on DateTime {
  String get monthYearLabel => DateFormat('MMMM yyyy').format(this);
}
