import 'package:appflowy/date/date_service.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/base/string_extension.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/mention/mention_block.dart';
import 'package:appflowy/plugins/inline_actions/inline_actions_command.dart';
import 'package:appflowy/plugins/inline_actions/inline_actions_result.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra_ui/style_widget/text.dart';
import 'package:flutter/material.dart';

class ReminderReferenceService {
  ReminderReferenceService(this.context) {
    // Initialize locale
    _locale = context.locale.toLanguageTag();

    // Initializes options
    _setOptions();
  }

  final BuildContext context;

  late String _locale;
  late List<InlineActionsMenuItem> _allOptions;

  List<InlineActionsMenuItem> options = [];

  static const maxSearchLength = 20;
  Future<InlineActionsResult> reminderReferenceDelegate([
    String? search,
  ]) async {
    if (search != null &&
        search.isNotEmpty &&
        search.length > maxSearchLength) {
      return _groupFromResults();
    }

    // Checks if Locale has changed since last
    _setLocale();

    final reminderLabel = LocaleKeys.inlineActions_reminder_groupTitle.tr();
    if (search != null && !search.startsWith(reminderLabel.toLowerCase())) {
      return _groupFromResults();
    }

    // Filters static options
    _filterOptions(search);

    // Searches for date by pattern
    _searchDate(search);

    // Searches for date by natural language prompt
    await _searchDateNLP(search);

    return _groupFromResults(options);
  }

  InlineActionsResult _groupFromResults([
    List<InlineActionsMenuItem>? options,
  ]) =>
      InlineActionsResult(
        title: LocaleKeys.inlineActions_reminder_groupTitle.tr(),
        results: options ?? [],
        startsWithKeywords: [
          LocaleKeys.inlineActions_reminder_groupTitle.tr().toLowerCase(),
          LocaleKeys.inlineActions_reminder_shortKeyword.tr().toLowerCase(),
        ],
      );

  void _filterOptions(String? search) {
    if (search == null || search.isEmpty) {
      options = [];
      return;
    }

    options = _allOptions
        .where(
          (option) =>
              option.keywords != null &&
              option.keywords!.isNotEmpty &&
              option.keywords!.any(
                (keyword) => keyword.contains(search.toLowerCase()),
              ),
        )
        .toList();
  }

  void _searchDate(String? search) {
    if (search == null || search.isEmpty) {
      return;
    }

    try {
      final date = DateFormat.yMd(_locale).parse(search);
      options.insert(0, _itemFromDate(date));
    } catch (_) {
      return;
    }
  }

  Future<void> _searchDateNLP(String? search) async {
    if (search == null || search.isEmpty) {
      return;
    }

    final result = await DateService.queryDate(search);

    result.fold(
      (l) {},
      (date) => options.insert(0, _itemFromDate(date)),
    );
  }

  Future<void> _insertReminderReference(
    EditorState editorState,
    DateTime date,
  ) async {
    final selection = editorState.selection;
    if (selection == null || !selection.isCollapsed) {
      return;
    }

    final node = editorState.getNodeAtPath(selection.end.path);
    final delta = node?.delta;
    if (node == null || delta == null) {
      return;
    }

    final index = selection.endIndex;
    final lastKeywordIndex = delta
        .toPlainText()
        .substring(0, index)
        .lastIndexOf(inlineActionCharacter);

    final transaction = editorState.transaction
      ..replaceText(
        node,
        lastKeywordIndex,
        index - lastKeywordIndex,
        '\$',
        attributes: {
          MentionBlockKeys.mention: {
            MentionBlockKeys.type: MentionType.reminder.name,
            MentionBlockKeys.date: date.toIso8601String(),
          }
        },
      );

    await editorState.apply(transaction);
  }

  void _setOptions() {
    final today = DateTime.now();
    final tomorrow = today.add(const Duration(days: 1));
    final yesterday = today.subtract(const Duration(days: 1));

    _allOptions = [
      _itemFromDate(
        today,
        'Today',
        [DateFormat.yMd(_locale).format(today)],
      ),
      _itemFromDate(
        tomorrow,
        'Tomorrow',
        [DateFormat.yMd(_locale).format(tomorrow)],
      ),
      _itemFromDate(
        yesterday,
        'Yesterday',
        [DateFormat.yMd(_locale).format(yesterday)],
      ),
    ];
  }

  /// Sets Locale on each search to make sure
  /// keywords are localized
  void _setLocale() {
    final locale = context.locale.toLanguageTag();

    if (locale != _locale) {
      _locale = context.locale.toLanguageTag();
      _setOptions();
    }
  }

  InlineActionsMenuItem _itemFromDate(
    DateTime date, [
    String? label,
    List<String>? keywords,
  ]) {
    final labelStr = label ?? DateFormat.yMd(_locale).format(date);

    return InlineActionsMenuItem(
      label: FlowyText.regular(labelStr.capitalize()),
      keywords: [labelStr.toLowerCase(), ...?keywords],
      onSelected: (context, editorState, menuService) =>
          _insertReminderReference(
        editorState,
        date,
      ),
    );
  }
}
