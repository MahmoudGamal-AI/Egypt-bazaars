import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:iconsax/iconsax.dart';
import '../core/constants/colors.dart';
import '../core/theme/app_theme.dart';

class GenerativeUIParser extends StatelessWidget {
  final String text;
  final bool isUser;

  const GenerativeUIParser({super.key, required this.text, required this.isUser});

  @override
  Widget build(BuildContext context) {
    if (isUser) {
      return _buildRichText(text);
    }

    final widgets = <Widget>[];
    String remainingText = text;

    final tags = ['[InsightCard]', '[ChartCard]', '[DataGrid]', '[Flowchart]'];
    
    while (remainingText.isNotEmpty) {
      int firstTagIndex = -1;
      String firstTag = '';
      
      for (final tag in tags) {
        final index = remainingText.indexOf(tag);
        if (index != -1 && (firstTagIndex == -1 || index < firstTagIndex)) {
          firstTagIndex = index;
          firstTag = tag;
        }
      }
      
      if (firstTagIndex != -1) {
        // Add text before the match
        if (firstTagIndex > 0) {
          final beforeText = remainingText.substring(0, firstTagIndex).trim();
          if (beforeText.isNotEmpty) {
            widgets.add(_buildRichText(beforeText));
            widgets.add(const SizedBox(height: 16));
          }
        }

        // Find JSON block starting after the tag
        final afterTag = remainingText.substring(firstTagIndex + firstTag.length);
        final braceStartIndex = afterTag.indexOf('{');
        
        if (braceStartIndex != -1) {
          int openBraces = 0;
          int braceEndIndex = -1;
          
          for (int i = braceStartIndex; i < afterTag.length; i++) {
            if (afterTag[i] == '{') openBraces++;
            if (afterTag[i] == '}') openBraces--;
            
            if (openBraces == 0) {
              braceEndIndex = i;
              break;
            }
          }
          
          if (braceEndIndex != -1) {
            final jsonStr = afterTag.substring(braceStartIndex, braceEndIndex + 1);
            final tagType = firstTag.replaceAll('[', '').replaceAll(']', '');
            
            try {
              final Map<String, dynamic> data = json.decode(jsonStr);
              switch (tagType) {
                case 'InsightCard':
                  widgets.add(_buildInsightCard(data));
                  break;
                case 'ChartCard':
                  widgets.add(_buildChartCard(data));
                  break;
                case 'DataGrid':
                  widgets.add(_buildDataGrid(data));
                  break;
                case 'Flowchart':
                  widgets.add(_buildFlowchart(data));
                  break;
              }
              widgets.add(const SizedBox(height: 16));
            } catch (e) {
              widgets.add(_buildRichText('$firstTag\n$jsonStr\n(Error: Invalid JSON)'));
              widgets.add(const SizedBox(height: 16));
            }
            
            remainingText = afterTag.substring(braceEndIndex + 1);
            
            // Remove trailing markdown codeblock ticks if they exist
            final trailingMatch = RegExp(r'^\s*```').firstMatch(remainingText);
            if (trailingMatch != null) {
                remainingText = remainingText.substring(trailingMatch.end);
            }

          } else {
            widgets.add(_buildRichText(firstTag));
            remainingText = afterTag;
          }
        } else {
           widgets.add(_buildRichText(firstTag));
           remainingText = afterTag;
        }

      } else {
        // No more tags, add remaining text
        if (remainingText.trim().isNotEmpty) {
          widgets.add(_buildRichText(remainingText.trim()));
        }
        break;
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: widgets,
    );
  }

  Widget _buildRichText(String text) {
    if (text.isEmpty) return const SizedBox.shrink();
    
    final color = isUser ? Colors.white : AppColors.textPrimary;
    final List<Widget> widgets = [];
    final lines = text.split('\n');
    
    List<InlineSpan> currentSpans = [];
    
    void flushText() {
      if (currentSpans.isNotEmpty) {
        widgets.add(SelectableText.rich(
          TextSpan(children: currentSpans),
          textDirection: TextDirection.rtl,
        ));
        currentSpans = [];
      }
    }

    bool inTable = false;
    List<List<String>> tableRows = [];

    void flushTable() {
      if (tableRows.isNotEmpty) {
        final header = tableRows.first;
        final rows = tableRows.skip(1).where((r) => r.join().replaceAll('-', '').trim().isNotEmpty).toList();
        widgets.add(SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(border: Border.all(color: AppColors.divider), borderRadius: BorderRadius.circular(8)),
            child: DataTable(
              headingRowColor: WidgetStateProperty.all(AppColors.primary.withOpacity(0.1)),
              dataRowMinHeight: 30, dataRowMaxHeight: 45,
              columns: header.map((e) => DataColumn(label: Text(e, style: GoogleFonts.cairo(fontWeight: FontWeight.w700, fontSize: 13, color: AppColors.primary)))).toList(),
              rows: rows.map((row) {
                List<String> padded = List.from(row);
                while (padded.length < header.length) padded.add('');
                if (padded.length > header.length) padded = padded.sublist(0, header.length);
                return DataRow(cells: padded.map((e) => DataCell(Text(e, style: GoogleFonts.cairo(fontSize: 12, color: color)))).toList());
              }).toList(),
            ),
          ),
        ));
        tableRows = [];
      }
      inTable = false;
    }

    for (int i = 0; i < lines.length; i++) {
      String line = lines[i];
      
      // Ignore markdown json ticks safely
      if (line.trim().startsWith('```') && !line.trim().contains('{') && !line.trim().contains('}')) {
          continue; 
      }
      
      if (line.trim().startsWith('|') && line.trim().endsWith('|')) {
        if (!inTable) {
          flushText();
          inTable = true;
        }
        final cells = line.trim().split('|').map((e) => e.trim()).toList();
        if (cells.length >= 3) tableRows.add(cells.sublist(1, cells.length - 1));
        continue;
      } else if (inTable) {
        flushTable();
      }

      if (currentSpans.isNotEmpty) currentSpans.add(const TextSpan(text: '\n'));
      
      // Headers
      bool isHeader = false;
      double fontSize = 14;
      FontWeight fw = FontWeight.w400;
      
      if (line.startsWith('### ')) {
        isHeader = true; fontSize = 16; fw = FontWeight.w700; line = line.substring(4);
      } else if (line.startsWith('## ')) {
        isHeader = true; fontSize = 18; fw = FontWeight.w800; line = line.substring(3);
      } else if (line.startsWith('# ')) {
        isHeader = true; fontSize = 20; fw = FontWeight.w800; line = line.substring(2);
      }

      // Numbered lists
      final numMatch = RegExp(r'^(\d+)\.\s(.*)').firstMatch(line.trim());
      if (numMatch != null) {
        line = '${numMatch.group(1)}. ${numMatch.group(2)}';
      } else if (line.trim().startsWith('- ') || line.trim().startsWith('* ')) {
        line = '• ' + line.trim().substring(2);
      }

      // Parse **bold** markers
      final parts = line.split(RegExp(r'\*\*'));
      for (int j = 0; j < parts.length; j++) {
        currentSpans.add(TextSpan(
          text: parts[j],
          style: GoogleFonts.cairo(
            fontSize: fontSize, height: 1.7, color: isHeader ? AppColors.primary : color,
            fontWeight: j.isOdd ? FontWeight.w800 : fw,
          ),
        ));
      }
    }

    flushText();
    flushTable();

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: widgets);
  }

  Widget _buildInsightCard(Map<String, dynamic> data) {
    final title = data['title']?.toString() ?? 'Insight';
    final metric = data['metric']?.toString() ?? '';
    final trend = data['trend']?.toString() ?? 'neutral';
    final analysis = data['analysis']?.toString() ?? '';

    Color trendColor = AppColors.info;
    IconData trendIcon = Iconsax.minus;
    
    if (trend.toLowerCase() == 'up') {
      trendColor = AppColors.success;
      trendIcon = Iconsax.trend_up;
    } else if (trend.toLowerCase() == 'down') {
      trendColor = AppColors.error;
      trendIcon = Iconsax.trend_down;
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.surface, AppColors.surface.withOpacity(0.8)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.divider.withOpacity(0.5)),
        boxShadow: AppShadows.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(title, style: GoogleFonts.cairo(fontSize: 14, color: AppColors.textSecondary, fontWeight: FontWeight.w600)),
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: trendColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(trendIcon, size: 16, color: trendColor),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(metric, style: GoogleFonts.cairo(fontSize: 28, fontWeight: FontWeight.w800, color: AppColors.primary)),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.background.withOpacity(0.5),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.divider.withOpacity(0.2)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Iconsax.lamp_on, size: 18, color: AppColors.warning),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    analysis,
                    style: GoogleFonts.cairo(fontSize: 13, height: 1.5, color: AppColors.textSecondary),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChartCard(Map<String, dynamic> data) {
    final imageUrl = data['image_url']?.toString() ?? '';
    final caption = data['caption']?.toString() ?? '';

    if (imageUrl.isEmpty) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.white, // QuickChart usually returns white background by default
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.divider.withOpacity(0.5)),
        boxShadow: AppShadows.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Image.network(
            imageUrl,
            fit: BoxFit.contain,
            loadingBuilder: (context, child, loadingProgress) {
              if (loadingProgress == null) return child;
              return const SizedBox(
                height: 200,
                child: Center(child: CircularProgressIndicator()),
              );
            },
            errorBuilder: (context, error, stackTrace) => const SizedBox(
              height: 200,
              child: Center(child: Icon(Icons.broken_image, size: 40, color: Colors.grey)),
            ),
          ),
          if (caption.isNotEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              color: AppColors.surface,
              child: Text(
                caption,
                style: GoogleFonts.cairo(fontSize: 13, color: AppColors.textSecondary, fontWeight: FontWeight.w600),
                textAlign: TextAlign.center,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildDataGrid(Map<String, dynamic> data) {
    final columns = (data['columns'] as List?)?.map((e) => e.toString()).toList() ?? [];
    final rows = (data['rows'] as List?)?.map((e) => (e as List).map((v) => v.toString()).toList()).toList() ?? [];

    if (columns.isEmpty || rows.isEmpty) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.divider.withOpacity(0.5)),
        boxShadow: AppShadows.card,
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingRowColor: WidgetStateProperty.all(AppColors.primary.withOpacity(0.05)),
          dataRowMinHeight: 40,
          dataRowMaxHeight: 50,
          columns: columns.map((c) => DataColumn(
            label: Text(c, style: GoogleFonts.cairo(fontWeight: FontWeight.w800, fontSize: 13, color: AppColors.primary)),
          )).toList(),
          rows: rows.map((row) {
            return DataRow(
              cells: row.map((cell) => DataCell(
                Text(cell, style: GoogleFonts.cairo(fontSize: 13, color: AppColors.textPrimary)),
              )).toList(),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildFlowchart(Map<String, dynamic> data) {
    final mermaidCode = data['mermaid_code']?.toString() ?? '';
    
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E), // Dark code background
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.divider.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Iconsax.diagram, size: 16, color: AppColors.info),
              const SizedBox(width: 8),
              Text('Mermaid Flowchart', style: GoogleFonts.cairo(fontSize: 12, color: AppColors.info, fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            mermaidCode,
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 12,
              color: Color(0xFFD4D4D4),
              height: 1.5,
            ),
            textDirection: TextDirection.ltr,
          ),
        ],
      ),
    );
  }
}
