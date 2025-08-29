import 'dart:convert';
import 'dart:io';

import 'package:flutter_app_publisher/src/api/app_package_publisher.dart';
import 'package:flutter_app_publisher/src/publishers/oppo/app_package_publisher_oppo.dart';
import 'package:flutter_app_publisher/src/publishers/playstore/publish_playstore_config.dart';
import 'package:googleapis/androidpublisher/v3.dart';
import 'package:googleapis_auth/auth_io.dart';

const kEnvTrack = 'GOOGLE_PLAYSTORE_TRACK';
const kEnvAppName = 'APP_NAME';

class AppPackagePublisherPlayStore extends AppPackagePublisher {
  @override
  String get name => 'playstore';

  @override
  List<String> get supportedPlatforms => ['android'];

  late Map<String, String> globalEnvironment;


  @override
  Future<PublishResult> publish(
    FileSystemEntity fileSystemEntity, {
    Map<String, String>? environment,
    Map<String, dynamic>? publishArguments,
    PublishProgressCallback? onPublishProgress,
  }) async {
    globalEnvironment = environment ?? Platform.environment;
    //ceshi
    File file = fileSystemEntity as File;
    try {
      PublishPlayStoreConfig publishConfig = PublishPlayStoreConfig.parse(
        globalEnvironment,
        {
          "package-name": globalEnvironment[kEnvPkgName],
          "track": globalEnvironment[kEnvTrack]
        },
      );

      String jsonString =
          File(publishConfig.credentialsFile).readAsStringSync();
      ServiceAccountCredentials serviceAccountCredentials =
          ServiceAccountCredentials.fromJson(json.decode(jsonString));

      final client = await clientViaServiceAccount(
        serviceAccountCredentials,
        [AndroidPublisherApi.androidpublisherScope],
      );

      final AndroidPublisherApi publisherApi = AndroidPublisherApi(client);

      AppEdit appEdit = await publisherApi.edits.insert(
        AppEdit(),
        publishConfig.packageName,
      );

      Media uploadMedia = Media(file.openRead(), file.lengthSync());

      final bundle = await publisherApi.edits.bundles.upload(
        publishConfig.packageName,
        appEdit.id!,
        uploadMedia: uploadMedia,
      );

      if (publishConfig.track != null) {
        final track = Track(
          track: publishConfig.track,
          releases: [
            TrackRelease(
              versionCodes: [bundle.versionCode!.toString()],
              status: 'completed',
            ),
          ],
        );
        await publisherApi.edits.tracks.update(
          track,
          publishConfig.packageName,
          appEdit.id!,
          publishConfig.track!,
        );
      }

      await publisherApi.edits.commit(
        publishConfig.packageName,
        appEdit.id!,
      );

      return PublishResult(
        url: '${globalEnvironment[kEnvAppName]} $name 提交成功',
      );
    } catch (e, stack) {
      // 打印调试信息
      print('发布失败: $e\n$stack');
      throw PublishError('${globalEnvironment[kEnvAppName]} $name 提交失败: $e');
    }
  }
}
