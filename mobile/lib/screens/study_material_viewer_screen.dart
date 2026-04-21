// lib/screens/study_material_viewer_screen.dart
//
// StudyMaterialViewerScreen — displays an AI-generated summary, reviewer,
// or study guide with a clean reading UI, share options, and type switcher.

import "package:flutter/material.dart";
import "package:flutter/services.dart";

import "../design_tokens.dart";
import "../models/app_models.dart";
import "../models/study_material_models.dart";
import "../services/claude_service_study.dart";

class StudyMaterialViewerScreen extends StatefulWidget {
  const StudyMaterialViewerScreen({
    super.key,
    required this.type,
    required this.subject,
    required this.content,
    this.taskId = "",
    this.taskName = "",
    this.profile,
  });

  final StudyMaterialType type;
  final String subject;
  final String content;
  final String taskId;
  final String taskName;
  final UserProfile? profile;

  @override
  State<StudyMaterialViewerScreen> createState() =>
      _StudyMaterialViewerScreenState();
}

class _StudyMaterialViewerScreenState
    extends State<StudyMaterialViewerScreen> {
  StudyMaterialType _currentType = StudyMaterialType.summary;
  StudyMaterial? _material;
  bool _loading = true;
  String? _error;

  // Cache per type so switching is instant after first load
  final Map<StudyMaterialType, StudyMaterial> _cache =
      <StudyMaterialType, StudyMaterial>{};

  @override
  void initState() {
    super.initState();
    _currentType = widget.type;
    _generate();
  }

  Future<void> _generate() async {
    if (_cache.containsKey(_currentType)) {
      setState(() {
        _material = _cache[_currentType];
        _loading = false;
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    final StudyMaterial? mat =
        await ClaudeStudyService.generateStudyMaterial(
      type: _currentType,
      subject: widget.subject,
      content: widget.content,
      taskId: widget.taskId,
      taskName: widget.taskName,
      profile: widget.profile,
    );

    if (!mounted) return;

    if (mat == null) {
      setState(() {
        _loading = false;
        _error =
            "Couldn't generate this material. Please check your connection and try again.";
      });
      return;
    }

    _cache[_currentType] = mat;
    setState(() {
      _material = mat;
      _loading = false;
    });
  }

  void _switchType(StudyMaterialType type) {
    if (type == _currentType) return;
    setState(() => _currentType = type);
    _generate();
  }

  void _copyContent() {
    if (_material == null) return;
    Clipboard.setData(ClipboardData(text: _material!.content));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("Copied to clipboard"),
        duration: Duration(seconds: 1),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        backgroundColor: kBg,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              _material?.typeLabel ??
                  _currentType.name[0].toUpperCase() +
                      _currentType.name.substring(1),
              style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: kDark),
            ),
            Text(widget.subject, style: kSubtitle),
          ],
        ),
        actions: <Widget>[
          if (_material != null)
            IconButton(
              icon: const Icon(Icons.copy_outlined,
                  color: kMuted, size: 20),
              tooltip: "Copy content",
              onPressed: _copyContent,
            ),
        ],
      ),
      body: Column(
        children: <Widget>[
          // Type switcher
          Padding(
            padding:
                const EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: Row(
              children: StudyMaterialType.values.map((StudyMaterialType t) {
                final bool sel = t == _currentType;
                return Expanded(
                  child: GestureDetector(
                    onTap: () => _switchType(t),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      margin: const EdgeInsets.symmetric(
                          horizontal: 3, vertical: 8),
                      padding: const EdgeInsets.symmetric(
                          vertical: 9),
                      decoration: BoxDecoration(
                        color: sel ? kDark : kSurface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: sel
                              ? kDark
                              : kMuted.withOpacity(0.2),
                          width: 1.2,
                        ),
                      ),
                      child: Column(
                        children: <Widget>[
                          Text(
                            switch (t) {
                              StudyMaterialType.summary => "📋",
                              StudyMaterialType.reviewer => "📖",
                              StudyMaterialType.studyGuide => "🗺️",
                            },
                            style: const TextStyle(fontSize: 15),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            switch (t) {
                              StudyMaterialType.summary => "Summary",
                              StudyMaterialType.reviewer => "Reviewer",
                              StudyMaterialType.studyGuide => "Guide",
                            },
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: sel
                                    ? Colors.white
                                    : kDark),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),

          // Content area
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              child: _loading
                  ? _buildLoading()
                  : _error != null
                      ? _buildError()
                      : _buildContent(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoading() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const SunMascot(walking: true, size: 72),
          const SizedBox(height: 20),
          Text(
            "Generating ${_currentType == StudyMaterialType.summary ? 'Summary' : _currentType == StudyMaterialType.reviewer ? 'Reviewer' : 'Study Guide'}…",
            style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: kDark),
          ),
          const SizedBox(height: 14),
          const BouncingDots(),
        ],
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Text("😕",
                style: TextStyle(fontSize: 48)),
            const SizedBox(height: 14),
            Text(_error!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: kMuted, fontSize: 14, height: 1.4)),
            const SizedBox(height: 22),
            DarkPillButton(
                label: "Try Again", onPressed: _generate),
          ],
        ),
      ),
    );
  }

  Widget _buildContent() {
    final StudyMaterial mat = _material!;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // Header card
          LocketCard(
            color: kOrangeSoft,
            child: Row(
              children: <Widget>[
                Text(mat.typeEmoji,
                    style: const TextStyle(fontSize: 24)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        mat.title,
                        style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: kDark),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        "${mat.subject} · ${mat.wordCount > 0 ? '~${mat.wordCount} words' : 'AI-generated'}",
                        style: kSubtitle,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Content body — parsed as pseudo-markdown
          _MarkdownBody(content: mat.content),
          const SizedBox(height: 24),

          // Regen button
          OutlinePillButton(
            label: "Regenerate",
            onPressed: () {
              _cache.remove(_currentType);
              _generate();
            },
            icon: Icons.refresh_rounded,
          ),
        ],
      ),
    );
  }
}

// ── Simple Markdown Renderer ──────────────────────────────────────────────────

class _MarkdownBody extends StatelessWidget {
  const _MarkdownBody({required this.content});
  final String content;

  @override
  Widget build(BuildContext context) {
    final List<_Block> blocks = _parse(content);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: blocks.map((b) => _BlockWidget(block: b)).toList(),
    );
  }

  static List<_Block> _parse(String text) {
    final List<_Block> blocks = <_Block>[];
    final List<String> lines = text.split("\n");

    for (final String line in lines) {
      if (line.startsWith("## ")) {
        blocks.add(_Block(type: _BType.h2, text: line.substring(3)));
      } else if (line.startsWith("# ")) {
        blocks.add(_Block(type: _BType.h1, text: line.substring(2)));
      } else if (line.startsWith("- ") || line.startsWith("• ")) {
        blocks.add(_Block(
            type: _BType.bullet, text: line.substring(2)));
      } else if (RegExp(r"^\d+\. ").hasMatch(line)) {
        blocks.add(_Block(
            type: _BType.numbered,
            text: line.replaceFirst(RegExp(r"^\d+\. "), "")));
      } else if (line.trim().isEmpty) {
        blocks.add(_Block(type: _BType.spacer, text: ""));
      } else {
        blocks.add(_Block(type: _BType.body, text: line));
      }
    }
    return blocks;
  }
}

enum _BType { h1, h2, bullet, numbered, body, spacer }

class _Block {
  const _Block({required this.type, required this.text});
  final _BType type;
  final String text;
}

class _BlockWidget extends StatelessWidget {
  const _BlockWidget({required this.block});
  final _Block block;

  @override
  Widget build(BuildContext context) {
    return switch (block.type) {
      _BType.h1 => Padding(
          padding: const EdgeInsets.only(top: 20, bottom: 6),
          child: Text(block.text,
              style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: kDark,
                  letterSpacing: -0.3))),
      _BType.h2 => Padding(
          padding: const EdgeInsets.only(top: 16, bottom: 6),
          child: Row(
            children: <Widget>[
              Container(
                width: 3,
                height: 16,
                margin: const EdgeInsets.only(right: 8),
                decoration: BoxDecoration(
                  color: kOrange,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Expanded(
                child: Text(block.text,
                    style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: kDark)),
              ),
            ],
          )),
      _BType.bullet => Padding(
          padding: const EdgeInsets.only(bottom: 5, left: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Container(
                width: 6,
                height: 6,
                margin: const EdgeInsets.only(top: 7, right: 10),
                decoration: const BoxDecoration(
                    color: kOrange, shape: BoxShape.circle),
              ),
              Expanded(
                child: Text(block.text,
                    style: const TextStyle(
                        fontSize: 14,
                        color: kDark,
                        height: 1.5)),
              ),
            ],
          )),
      _BType.numbered => Padding(
          padding: const EdgeInsets.only(bottom: 6, left: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text("• ",
                  style: const TextStyle(
                      fontSize: 14,
                      color: kOrange,
                      fontWeight: FontWeight.w700)),
              Expanded(
                child: Text(block.text,
                    style: const TextStyle(
                        fontSize: 14,
                        color: kDark,
                        height: 1.5)),
              ),
            ],
          )),
      _BType.body => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(block.text,
              style: const TextStyle(
                  fontSize: 14, color: kDark, height: 1.6))),
      _BType.spacer => const SizedBox(height: 8),
    };
  }
}
