import 'package:flutter/material.dart';

import '../models.dart';
import '../state.dart';
import '../todo_theme.dart';

/// The project chooser, shared by adding a task and moving one. [state]'s
/// `addableProjects` supplies the order: favourites pinned, then A→Z with
/// numbers compared naturally, so a Johnny.Decimal prefix keeps its order
/// (1.2 before 1.10). Archived projects are not targets and are left out.
Future<VikunjaProject?> showProjectPicker(
  BuildContext context,
  AppState state, {
  String title = 'Choose a project',
  int? selectedId,
}) {
  return showModalBottomSheet<VikunjaProject>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: ListView(
        shrinkWrap: true,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              title,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
          ),
          for (final p in state.addableProjects)
            ListTile(
              leading: Icon(
                Icons.list_alt,
                color: TodoColors.serverColor(
                  p.hexColor,
                  TodoColors.of(context),
                ),
              ),
              title: Text(p.title),
              trailing: p.id == selectedId ? const Icon(Icons.check) : null,
              onTap: () => Navigator.pop(context, p),
            ),
        ],
      ),
    ),
  );
}
