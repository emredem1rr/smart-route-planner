import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../models/route_result_model.dart';

class PdfService {

  Future<void> generateRouteReport(OptimizeResponse response) async {
    final pdf   = pw.Document();
    final sonuc = response.result!;
    final now   = DateTime.now();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin:     const pw.EdgeInsets.all(32),
        header:     (context) => _buildHeader(now),
        footer:     (context) => _buildFooter(context),
        build:      (context) => [
          _buildSummarySection(sonuc),
          pw.SizedBox(height: 20),
          _buildTasksSection(sonuc),
          pw.SizedBox(height: 20),
          _buildComparisonSection(response.comparisonLogs, sonuc),
        ],
      ),
    );

    await Printing.layoutPdf(
      onLayout: (format) async => pdf.save(),
      name:     'smart_route_rapor_${now.day}_${now.month}_${now.year}.pdf',
    );
  }

  pw.Widget _buildHeader(DateTime now) {
    return pw.Container(
      padding:    const pw.EdgeInsets.only(bottom: 12),
      decoration: const pw.BoxDecoration(
        border: pw.Border(
          bottom: pw.BorderSide(color: PdfColors.blue900, width: 2),
        ),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            'Smart Route Planner',
            style: pw.TextStyle(
              fontSize:   20,
              fontWeight: pw.FontWeight.bold,
              color:      PdfColors.blue900,
            ),
          ),
          pw.Text(
            '${now.day}.${now.month}.${now.year}  '
                '${now.hour.toString().padLeft(2, '0')}:'
                '${now.minute.toString().padLeft(2, '0')}',
            style: const pw.TextStyle(
              fontSize: 10,
              color:    PdfColors.grey600,
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _buildFooter(pw.Context context) {
    return pw.Container(
      padding:    const pw.EdgeInsets.only(top: 8),
      decoration: const pw.BoxDecoration(
        border: pw.Border(
          top: pw.BorderSide(color: PdfColors.grey300),
        ),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text('Smart Route Planner — Optimizasyon Raporu',
            style: const pw.TextStyle(
              fontSize: 8, color: PdfColors.grey600,
            ),
          ),
          pw.Text(
            'Sayfa ${context.pageNumber} / ${context.pagesCount}',
            style: const pw.TextStyle(
              fontSize: 8, color: PdfColors.grey600,
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _buildSummarySection(RouteResult sonuc) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text('Rota Özeti',
          style: pw.TextStyle(
            fontSize:   16,
            fontWeight: pw.FontWeight.bold,
            color:      PdfColors.blue900,
          ),
        ),
        pw.SizedBox(height: 12),
        pw.Container(
          padding:    const pw.EdgeInsets.all(16),
          decoration: pw.BoxDecoration(
            color:        PdfColors.blue50,
            borderRadius: pw.BorderRadius.circular(8),
          ),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
            children: [
              _summaryItem(
                '${sonuc.totalDistance.toStringAsFixed(2)} km',
                'Toplam Mesafe',
              ),
              _summaryItem(
                '${sonuc.totalTravelTime.toStringAsFixed(0)} dk',
                'Toplam Süre',
              ),
              _summaryItem(
                sonuc.fitnessScore.toStringAsFixed(4),
                'Fitness Skoru',
              ),
              _summaryItem(
                _algoLabel(sonuc.algorithmUsed),
                'Kullanılan Algoritma',
              ),
            ],
          ),
        ),
      ],
    );
  }

  pw.Widget _summaryItem(String value, String label) {
    return pw.Column(
      children: [
        pw.Text(value,
          style: pw.TextStyle(
            fontSize:   14,
            fontWeight: pw.FontWeight.bold,
            color:      PdfColors.blue900,
          ),
        ),
        pw.SizedBox(height: 4),
        pw.Text(label,
          style: const pw.TextStyle(
            fontSize: 9, color: PdfColors.grey600,
          ),
        ),
      ],
    );
  }

  pw.Widget _buildTasksSection(RouteResult sonuc) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text('Görev Sıralaması',
          style: pw.TextStyle(
            fontSize:   16,
            fontWeight: pw.FontWeight.bold,
            color:      PdfColors.blue900,
          ),
        ),
        pw.SizedBox(height: 12),
        pw.Table(
          border: pw.TableBorder.all(color: PdfColors.grey300),
          columnWidths: {
            0: const pw.FixedColumnWidth(30),
            1: const pw.FlexColumnWidth(3),
            2: const pw.FlexColumnWidth(4),
            3: const pw.FixedColumnWidth(50),
            4: const pw.FixedColumnWidth(60),
          },
          children: [
            // Header
            pw.TableRow(
              decoration: const pw.BoxDecoration(color: PdfColors.blue900),
              children: [
                _tableHeader('#'),
                _tableHeader('Görev'),
                _tableHeader('Adres'),
                _tableHeader('Süre'),
                _tableHeader('Öncelik'),
              ],
            ),
            // Rows
            ...sonuc.orderedTasks.asMap().entries.map((e) {
              final i    = e.key;
              final task = e.value;
              return pw.TableRow(
                decoration: pw.BoxDecoration(
                  color: i.isEven ? PdfColors.grey50 : PdfColors.white,
                ),
                children: [
                  _tableCell('${i + 1}', center: true),
                  _tableCell(task.name),
                  _tableCell(task.address.isNotEmpty ? task.address : '-'),
                  _tableCell('${task.duration} dk', center: true),
                  _tableCell(task.priorityLabel, center: true),
                ],
              );
            }),
          ],
        ),
      ],
    );
  }

  pw.Widget _buildComparisonSection(
      List<AlgorithmLog> loglar,
      RouteResult sonuc,
      ) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text('Algoritma Karşılaştırması',
          style: pw.TextStyle(
            fontSize:   16,
            fontWeight: pw.FontWeight.bold,
            color:      PdfColors.blue900,
          ),
        ),
        pw.SizedBox(height: 12),
        pw.Table(
          border: pw.TableBorder.all(color: PdfColors.grey300),
          children: [
            pw.TableRow(
              decoration: const pw.BoxDecoration(color: PdfColors.blue900),
              children: [
                _tableHeader('Algoritma'),
                _tableHeader('Fitness'),
                _tableHeader('Mesafe'),
                _tableHeader('Süre (ms)'),
                _tableHeader('Sonuç'),
              ],
            ),
            ...loglar.map((log) {
              final kazanan = log.algorithm == sonuc.algorithmUsed;
              return pw.TableRow(
                decoration: pw.BoxDecoration(
                  color: kazanan
                      ? PdfColors.green50
                      : PdfColors.white,
                ),
                children: [
                  _tableCell(log.label),
                  _tableCell(log.fitnessScore.toStringAsFixed(4),
                      center: true),
                  _tableCell(
                    '${log.totalDistance.toStringAsFixed(2)} km',
                    center: true,
                  ),
                  _tableCell(
                    log.executionTimeMs.toStringAsFixed(1),
                    center: true,
                  ),
                  _tableCell(kazanan ? '✓ Kazanan' : '-',
                    center: true,
                    bold:   kazanan,
                    color:  kazanan ? PdfColors.green900 : PdfColors.grey600,
                  ),
                ],
              );
            }),
          ],
        ),
      ],
    );
  }

  pw.Widget _tableHeader(String text) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(6),
      child: pw.Text(text,
        style: pw.TextStyle(
          fontSize:   9,
          fontWeight: pw.FontWeight.bold,
          color:      PdfColors.white,
        ),
        textAlign: pw.TextAlign.center,
      ),
    );
  }

  pw.Widget _tableCell(
      String text, {
        bool       center = false,
        bool       bold   = false,
        PdfColor?  color,
      }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(6),
      child: pw.Text(
        text,
        style: pw.TextStyle(
          fontSize:   9,
          fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
          color:      color ?? PdfColors.black,
        ),
        textAlign: center ? pw.TextAlign.center : pw.TextAlign.left,
      ),
    );
  }

  String _algoLabel(String algo) {
    switch (algo) {
      case 'genetic':             return 'Genetik Algoritma';
      case 'simulated_annealing': return 'Simüle Tavlama';
      default:                    return 'Greedy';
    }
  }
}