import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:proxypin/l10n/app_localizations.dart';
import 'package:proxypin/network/util/logger.dart';
import 'package:proxypin/ui/component/app_dialog.dart';
import 'package:proxypin/utils/settings_backup.dart';

class SettingsBackupActions {
  static String importLabel(AppLocalizations localizations) =>
      localizations.localeName.startsWith('zh')
          ? '${localizations.import}${localizations.setting}'
          : '${localizations.import} ${localizations.setting}';

  static String exportLabel(AppLocalizations localizations) =>
      localizations.localeName.startsWith('zh')
          ? '${localizations.export}${localizations.setting}'
          : '${localizations.export} ${localizations.setting}';

  static Future<void> export(BuildContext context) async {
    final localizations = AppLocalizations.of(context)!;
    try {
      final bytes = await SettingsBackup.exportBytes();
      final saved = await FilePicker.saveFile(
        fileName: 'proxypin-settings.json',
        bytes: bytes,
      );
      if (saved != null && context.mounted) {
        CustomToast.success(localizations.exportSuccess).show(context);
      }
    } catch (error, stackTrace) {
      logger.e('Failed to export settings', error: error, stackTrace: stackTrace);
      if (context.mounted) {
        CustomToast.error('${localizations.exportFailed}: $error').show(context);
      }
    }
  }

  static Future<void> import(BuildContext context) async {
    final localizations = AppLocalizations.of(context)!;
    try {
      final file = await FilePicker.pickFile(type: FileType.any);
      if (file == null || !context.mounted) return;

      final isChinese = localizations.localeName.startsWith('zh');
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(importLabel(localizations)),
          content: Text(isChinese
              ? '导入将覆盖当前配置（本机监听端口和证书除外）。导入后需要重启应用才能生效。'
              : 'Importing will replace current settings except local listening ports and certificates. Restart the app to apply the imported settings.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(localizations.cancel),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(localizations.import),
            ),
          ],
        ),
      );
      if (confirmed != true || !context.mounted) return;

      final bytes = await file.xFile.readAsBytes();
      await SettingsBackup.importBytes(bytes);
      if (!context.mounted) return;
      await AppAlertDialog(
        title: localizations.importSuccess,
        message: isChinese ? '配置已导入。请重启应用以应用新配置。' : 'Settings imported. Restart the app to apply them.',
      ).show(context);
    } catch (error, stackTrace) {
      logger.e('Failed to import settings', error: error, stackTrace: stackTrace);
      if (context.mounted) {
        CustomToast.error('${localizations.importFailed}: $error').show(context);
      }
    }
  }
}
