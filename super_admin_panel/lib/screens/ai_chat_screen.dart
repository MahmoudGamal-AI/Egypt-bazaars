import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:iconsax/iconsax.dart';
import '../core/constants/colors.dart';
import '../core/theme/app_theme.dart';
import '../services/admin_ai_service.dart';
import '../widgets/generative_ui_parser.dart';

/// 🤖 AI Chat Screen — Premium Redesign
/// SSE Streaming, Glassmorphism, Animated Messages, Smart Suggestions
class AIChatScreen extends StatefulWidget {
  const AIChatScreen({super.key});
  @override
  State<AIChatScreen> createState() => _AIChatScreenState();
}

class _AIChatScreenState extends State<AIChatScreen>
    with TickerProviderStateMixin {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();
  final List<_ChatMessage> _messages = [];
  bool _isLoading = false;
  bool _isOnline = false;
  late AnimationController _pulseController;
  late AnimationController _fadeController;

  final List<String> _quickSuggestions = [
    '📊 تقرير أداء المنصة',
    '🏪 ترتيب البازارات',
    '📈 تحليل الإيرادات',
    '🔍 فحص صحة المنصة',
    '💡 اقتراحات تسويقية',
    '📋 إحصائيات المنتجات',
  ];

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this, duration: const Duration(seconds: 2))..repeat(reverse: true);
    _fadeController = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 600));
    _fadeController.forward();
    _checkConnection();
    _addWelcomeMessage();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _fadeController.dispose();
    _controller.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _addWelcomeMessage() {
    _messages.add(_ChatMessage(
      text: '🤖 مرحباً بك في **مساعد الإدارة الذكي**!\n\n'
          'يمكنني مساعدتك في:\n'
          '• 📊 تحليل أداء المنصة والإيرادات\n'
          '• 🏪 ترتيب البازارات ومراقبة الأداء\n'
          '• 🔍 فحص صحة المنتجات والبيانات\n'
          '• 💡 اقتراحات تسويقية ذكية\n'
          '• 📋 تقارير تفصيلية فورية\n\n'
          'اكتب سؤالك أو اختر من الاقتراحات أدناه 👇',
      isUser: false,
      timestamp: DateTime.now(),
    ));
  }

  Future<void> _checkConnection() async {
    final health = await AdminAIService.checkHealth();
    if (mounted) setState(() => _isOnline = health.isOnline);
  }

  void _sendMessage(String text) async {
    if (text.trim().isEmpty || _isLoading) return;
    final userMsg = text.trim();
    _controller.clear();

    setState(() {
      _messages.add(_ChatMessage(text: userMsg, isUser: true, timestamp: DateTime.now()));
      _isLoading = true;
    });
    _scrollToBottom();

    // Add placeholder for AI response
    final aiMsg = _ChatMessage(text: '', isUser: false, timestamp: DateTime.now(), isStreaming: true);
    setState(() => _messages.add(aiMsg));
    _scrollToBottom();

    try {
      // Try streaming first
      final stream = AdminAIService.streamMessage(userMsg);
      final buffer = StringBuffer();
      await for (final token in stream) {
        if (token.startsWith('__STATUS__:')) {
          final status = token.substring(11);
          if (mounted) setState(() => aiMsg.statusText = status);
        } else if (token.startsWith('__ACTIONS__:')) {
          final actionsJson = token.substring(12);
          try {
            final actions = (json.decode(actionsJson) as List).map((e) => e.toString()).toList();
            if (mounted) setState(() => aiMsg.quickActions = actions);
          } catch (_) {}
        } else {
          buffer.write(token);
          if (mounted) {
            setState(() => aiMsg.text = buffer.toString());
            _scrollToBottom();
          }
        }
      }
      if (mounted) {
        setState(() {
          aiMsg.isStreaming = false;
          aiMsg.statusText = null;
        });
      }
    } catch (_) {
      // Fallback to full response
      try {
        final response = await AdminAIService.sendMessage(userMsg);
        final reply = response['response'] ?? response['text'] ?? 'لم أتمكن من المعالجة';
        if (mounted) {
          setState(() {
            aiMsg.text = reply.toString();
            aiMsg.isStreaming = false;
            aiMsg.statusText = null;
          });
        }
      } catch (e) {
        if (mounted) {
          setState(() {
            aiMsg.text = '⚠️ حدث خطأ: ${e.toString().substring(0, (e.toString().length).clamp(0, 120))}';
            aiMsg.isStreaming = false;
            aiMsg.statusText = null;
            aiMsg.isError = true;
          });
        }
      }
    }

    if (mounted) setState(() => _isLoading = false);
    _scrollToBottom();
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fadeController,
      child: Container(
        color: AppColors.background,
        child: Column(
          children: [
            _buildHeader(),
            Expanded(child: _buildMessageList()),
            _buildSuggestionsBar(),
            _buildInputArea(),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // Header with connection status
  // ═══════════════════════════════════════════════════════════════
  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0F1419), Color(0xFF1A2332)],
          begin: Alignment.centerLeft, end: Alignment.centerRight,
        ),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.15), blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: Row(
        children: [
          // AI Avatar with pulse
          AnimatedBuilder(
            animation: _pulseController,
            builder: (context, child) {
              return Container(
                width: 48, height: 48,
                decoration: BoxDecoration(
                  gradient: AppGradients.emerald,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [BoxShadow(
                    color: AppColors.primary.withOpacity(0.3 + _pulseController.value * 0.2),
                    blurRadius: 12 + _pulseController.value * 6, offset: const Offset(0, 4),
                  )],
                ),
                child: const Center(child: Text('🤖', style: TextStyle(fontSize: 22))),
              );
            },
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('مساعد الإدارة الذكي',
                  style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Row(children: [
                  Container(
                    width: 8, height: 8,
                    decoration: BoxDecoration(
                      color: _isOnline ? AppColors.success : AppColors.error,
                      shape: BoxShape.circle,
                      boxShadow: [BoxShadow(
                        color: (_isOnline ? AppColors.success : AppColors.error).withOpacity(0.5),
                        blurRadius: 6,
                      )],
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(_isOnline ? 'متصل ونشط' : 'غير متصل',
                    style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 12)),
                ]),
              ],
            ),
          ),
          // Actions
          _headerButton(Iconsax.refresh, 'تحديث', () {
            _checkConnection();
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('جاري فحص الاتصال...'), duration: Duration(seconds: 1)));
          }),
          const SizedBox(width: 8),
          _headerButton(Iconsax.trash, 'مسح', () {
            setState(() { _messages.clear(); _addWelcomeMessage(); });
          }),
        ],
      ),
    );
  }

  Widget _headerButton(IconData icon, String tooltip, VoidCallback onTap) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.white.withOpacity(0.08),
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Icon(icon, color: Colors.white.withOpacity(0.7), size: 18),
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // Message List
  // ═══════════════════════════════════════════════════════════════
  Widget _buildMessageList() {
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      itemCount: _messages.length + (_isLoading && (_messages.isEmpty || !_messages.last.isStreaming) ? 1 : 0),
      itemBuilder: (context, index) {
        if (index >= _messages.length) return _buildTypingIndicator();
        return _buildMessageBubble(_messages[index], index);
      },
    );
  }

  Widget _buildMessageBubble(_ChatMessage msg, int index) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: Duration(milliseconds: 400 + (index.clamp(0, 5) * 50)),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        return Transform.translate(
          offset: Offset(0, 20 * (1 - value)),
          child: Opacity(opacity: value, child: child),
        );
      },
      child: Align(
        alignment: msg.isUser ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.55),
          margin: const EdgeInsets.only(bottom: 16),
          child: Column(
            crossAxisAlignment: msg.isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              // Bubble
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: msg.isUser
                      ? AppColors.primary
                      : msg.isError ? AppColors.error.withOpacity(0.08) : AppColors.surface,
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(20),
                    topRight: const Radius.circular(20),
                    bottomLeft: Radius.circular(msg.isUser ? 20 : 4),
                    bottomRight: Radius.circular(msg.isUser ? 4 : 20),
                  ),
                  boxShadow: [BoxShadow(
                    color: (msg.isUser ? AppColors.primary : Colors.black).withOpacity(msg.isUser ? 0.25 : 0.06),
                    blurRadius: 12, offset: const Offset(0, 4),
                  )],
                  border: msg.isUser ? null : Border.all(color: AppColors.divider.withOpacity(0.5)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (!msg.isUser) ...[
                      Row(children: [
                        const Text('🤖', style: TextStyle(fontSize: 14)),
                        const SizedBox(width: 6),
                        Text('المساعد الذكي', style: GoogleFonts.cairo(
                          fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.primary)),
                        if (msg.isStreaming) ...[
                          const SizedBox(width: 8),
                          SizedBox(width: 12, height: 12,
                            child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary)),
                        ],
                        if (msg.isStreaming && msg.statusText != null) ...[
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              msg.statusText!,
                              style: GoogleFonts.cairo(fontSize: 10, color: AppColors.textTertiary, fontStyle: FontStyle.italic),
                              maxLines: 1, overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ]),
                      const SizedBox(height: 8),
                    ],
                    GenerativeUIParser(text: msg.text, isUser: msg.isUser),
                    if (!msg.isStreaming && msg.quickActions != null && msg.quickActions!.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8, runSpacing: 8,
                        children: msg.quickActions!.map((action) => _actionChip(action)).toList(),
                      ),
                    ],
                  ],
                ),
              ),
              // Timestamp + actions
              Padding(
                padding: const EdgeInsets.only(top: 6, left: 4, right: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${msg.timestamp.hour.toString().padLeft(2, '0')}:${msg.timestamp.minute.toString().padLeft(2, '0')}',
                      style: TextStyle(fontSize: 10, color: AppColors.textTertiary),
                    ),
                    if (!msg.isUser) ...[
                      const SizedBox(width: 8),
                      _copyButton(msg.text),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _actionChip(String label) {
    return Material(
      color: AppColors.primary.withOpacity(0.08),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: () => _sendMessage(label),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Iconsax.flash, size: 14, color: AppColors.primary),
              const SizedBox(width: 4),
              Text(label, style: GoogleFonts.cairo(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.primary)),
            ],
          ),
        ),
      ),
    );
  }


  Widget _copyButton(String text) {
    return InkWell(
      onTap: () {
        Clipboard.setData(ClipboardData(text: text));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(children: [
              const Icon(Icons.check_circle, color: Colors.white, size: 18),
              const SizedBox(width: 8),
              const Text('تم النسخ بنجاح'),
            ]),
            duration: const Duration(seconds: 1),
            backgroundColor: AppColors.success,
          ),
        );
      },
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.all(2),
        child: Icon(Iconsax.copy, size: 13, color: AppColors.textTertiary),
      ),
    );
  }

  Widget _buildTypingIndicator() {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(20), topRight: Radius.circular(20),
            bottomRight: Radius.circular(20), bottomLeft: Radius.circular(4),
          ),
          border: Border.all(color: AppColors.divider.withOpacity(0.5)),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8)],
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const Text('🤖', style: TextStyle(fontSize: 14)),
          const SizedBox(width: 10),
          _buildDot(0), _buildDot(1), _buildDot(2),
          const SizedBox(width: 8),
          Text('يفكر...', style: GoogleFonts.cairo(fontSize: 12, color: AppColors.textTertiary)),
        ]),
      ),
    );
  }

  Widget _buildDot(int index) {
    return AnimatedBuilder(
      animation: _pulseController,
      builder: (context, _) {
        final offset = ((_pulseController.value * 3 - index).clamp(0.0, 1.0));
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 2),
          width: 8, height: 8,
          decoration: BoxDecoration(
            color: AppColors.primary.withOpacity(0.3 + offset * 0.7),
            shape: BoxShape.circle,
          ),
        );
      },
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // Suggestions Bar
  // ═══════════════════════════════════════════════════════════════
  Widget _buildSuggestionsBar() {
    if (_messages.length > 2) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: SizedBox(
        height: 38,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: _quickSuggestions.length,
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemBuilder: (context, index) {
            return Material(
              color: AppColors.primary.withOpacity(0.08),
              borderRadius: BorderRadius.circular(20),
              child: InkWell(
                onTap: () => _sendMessage(_quickSuggestions[index]),
                borderRadius: BorderRadius.circular(20),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Text(_quickSuggestions[index],
                    style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.primary)),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // Input Area
  // ═══════════════════════════════════════════════════════════════
  Widget _buildInputArea() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.divider.withOpacity(0.5))),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, -2))],
      ),
      child: Row(
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.divider),
              ),
              child: TextField(
                controller: _controller,
                focusNode: _focusNode,
                onSubmitted: _sendMessage,
                textInputAction: TextInputAction.send,
                maxLines: 3,
                minLines: 1,
                style: GoogleFonts.cairo(fontSize: 14, color: AppColors.textPrimary),
                textDirection: TextDirection.rtl,
                decoration: InputDecoration(
                  hintText: 'اكتب سؤالك هنا...',
                  hintStyle: GoogleFonts.cairo(fontSize: 14, color: AppColors.textHint),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          // Send button
          AnimatedContainer(
            duration: AppDurations.fast,
            width: 48, height: 48,
            decoration: BoxDecoration(
              gradient: _isLoading ? null : AppGradients.emerald,
              color: _isLoading ? AppColors.textTertiary : null,
              borderRadius: BorderRadius.circular(14),
              boxShadow: _isLoading ? [] : [BoxShadow(
                color: AppColors.primary.withOpacity(0.3), blurRadius: 10, offset: const Offset(0, 4))],
            ),
            child: Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(14),
              child: InkWell(
                onTap: _isLoading ? null : () => _sendMessage(_controller.text),
                borderRadius: BorderRadius.circular(14),
                child: Center(
                  child: _isLoading
                      ? const SizedBox(width: 20, height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Iconsax.send_1, color: Colors.white, size: 20),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// Chat Message Model
// ═══════════════════════════════════════════════════════════════
class _ChatMessage {
  String text;
  final bool isUser;
  final DateTime timestamp;
  bool isStreaming;
  bool isError;
  String? statusText;
  List<String>? quickActions;

  _ChatMessage({
    required this.text,
    required this.isUser,
    required this.timestamp,
    this.isStreaming = false,
    this.isError = false,
    this.statusText,
    this.quickActions,
  });
}
