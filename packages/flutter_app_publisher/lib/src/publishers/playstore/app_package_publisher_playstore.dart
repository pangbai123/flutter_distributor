import 'dart:convert';
import 'dart:io';

import 'package:flutter_app_publisher/src/api/app_package_publisher.dart';
import 'package:flutter_app_publisher/src/publishers/oppo/app_package_publisher_oppo.dart';
import 'package:flutter_app_publisher/src/publishers/playstore/publish_playstore_config.dart';
import 'package:googleapis/androidpublisher/v3.dart';
import 'package:googleapis_auth/auth_io.dart';

const kEnvTrack = 'GOOGLE_PLAYSTORE_TRACK';

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
    File file = fileSystemEntity as File;
    PublishPlayStoreConfig publishConfig = PublishPlayStoreConfig.parse(
      globalEnvironment,
      {
        "package-name": globalEnvironment[kEnvPkgName],
        "track": globalEnvironment[kEnvTrack]
      },
    );

    String jsonString = File(publishConfig.credentialsFile).readAsStringSync();
    ServiceAccountCredentials serviceAccountCredentials =
    ServiceAccountCredentials.fromJson(json.decode(jsonString));

    final client = await clientViaServiceAccount(
      serviceAccountCredentials,
      [
        AndroidPublisherApi.androidpublisherScope,
      ],
    );

    final AndroidPublisherApi publisherApi = AndroidPublisherApi(client);

    // Step 1: Create a new edit
    AppEdit appEdit = await publisherApi.edits.insert(
      AppEdit(),
      publishConfig.packageName,
    );

    // Step 2: Upload the APK or AAB
    Media uploadMedia = Media(file.openRead(), file.lengthSync());
    await publisherApi.edits.bundles.upload(
      publishConfig.packageName,
      appEdit.id!,
      uploadMedia: uploadMedia,
    );

    // Step 3: Create the localized release notes (multi-language support)
    List<LocalizedText> releaseNotes = [
      LocalizedText(
        language: 'zh-CN',  // Simplified Chinese
        text: globalEnvironment[kEnvUpdateLog],  // Update log passed via environment
      ),
      // You can add more languages here
    ];

    // Step 4: Create the TrackRelease object
    TrackRelease trackRelease = TrackRelease(
      status: 'completed',  // Mark as completed to indicate it's ready for release
      releaseNotes: releaseNotes,
    );

    // Step 5: Create the Track object
    Track track = Track(
      track: publishConfig.track,  // e.g., 'production', 'beta', 'alpha'
      releases: [trackRelease],
    );

    // Step 6: Update the track with the new release
    if (publishConfig.track != null) {
      try {
        await publisherApi.edits.tracks.update(
          track,
          publishConfig.packageName,
          appEdit.id!,
          publishConfig.track!,
        );
      } on Exception catch (e) {
        print('Error updating track: $e');
        throw Exception('Failed to update track: $e');
      }
    }

    // Step 7: Commit the changes (this actually publishes the version)
    try {
      await publisherApi.edits.commit(
        publishConfig.packageName!,
        appEdit.id!,
      );
    } catch (e) {
      throw Exception('Failed to commit app edit: $e');
    }

    // Return the URL of the app in the Play Store
    String appUrl = 'https://play.google.com/store/apps/details?id=${publishConfig.packageName}';
    return PublishResult(url: appUrl);
  }
}
