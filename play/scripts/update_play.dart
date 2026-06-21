import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';

import 'package:googleapis_auth/auth_io.dart';
import 'package:http/http.dart' as http;

const _publisherScope = 'https://www.googleapis.com/auth/androidpublisher';
const _defaultAabPath = 'build/app/outputs/bundle/release/app-release.aab';
const _defaultCredentialsPath =
    'play/credentials/google-play-service-account.json';
const _defaultPackageName = 'net.chargeledger';
const _defaultTrack = 'internal';
const _defaultLanguage = 'en-US';
const _supportedLanguages = {_defaultLanguage};
const _assetCachePath = 'play/.cache/uploaded-assets.json';

Future<void> main(List<String> arguments) async {
  final verbose = arguments.contains('--verbose');
  try {
    await _run(arguments);
  } catch (error, stackTrace) {
    stderr.writeln('Google Play update failed: $error');
    if (verbose) {
      stderr.writeln(stackTrace);
    }
    exitCode = 1;
  }
}

Future<void> _run(List<String> arguments) async {
  final args = _Args.parse(arguments);
  final config = _Config.read(args.value('config'));
  final packageName =
      args.value('package-name') ??
      config.string('packageName') ??
      _defaultPackageName;
  final track = args.value('track') ?? config.string('track') ?? _defaultTrack;
  final language =
      args.value('language') ?? config.string('language') ?? _defaultLanguage;
  if (!_supportedLanguages.contains(language)) {
    throw ArgumentError.value(
      language,
      'language',
      'Only en-US is supported for this app.',
    );
  }
  final aabPath = args.value('aab') ?? config.string('aab') ?? _defaultAabPath;
  final credentialsPath =
      args.value('credentials') ??
      config.string('credentials') ??
      _defaultCredentialsPath;
  final listingDir =
      args.value('listing-dir') ??
      config.string('listingDir') ??
      'play/listing/$language';
  final removeListingLanguages = config
      .stringList('removeListingLanguages')
      .where((listingLanguage) => listingLanguage != language)
      .toList();
  final releaseNotesPath =
      args.value('release-notes') ??
      config.string('releaseNotes') ??
      'play/release/release-notes-internal.txt';
  final legacyAppDetailsPath = args.value('app-details');
  final legacyTesterGroupsPath = args.value('tester-groups');
  final dataSafetyCsvPath = config.string('dataSafetyCsv');
  final appIconPath =
      args.value('app-icon') ??
      config.string('appIcon') ??
      'play/assets/app-icon.png';
  final featureGraphicPath =
      args.value('feature-graphic') ??
      config.string('featureGraphic') ??
      'play/assets/feature-graphic.png';
  final phoneScreenshotPaths = config.stringList('phoneScreenshots');
  final sevenInchScreenshotPaths = config.stringList('sevenInchScreenshots');
  final tenInchScreenshotPaths = config.stringList('tenInchScreenshots');
  final localVersionCode =
      int.tryParse(args.value('version-code') ?? '') ??
      _readPubspecVersionCode('pubspec.yaml');
  final dryRun = args.flag('dry-run') || config.boolValue('dryRun');
  final ensureDefaultLanguage = config.boolValue(
    'ensureDefaultLanguage',
    defaultValue: true,
  );
  final skipListing =
      args.flag('skip-listing') || config.boolValue('skipListing');
  final skipAppDetails =
      args.flag('skip-app-details') || config.boolValue('skipAppDetails');
  final forceUpload =
      args.flag('force-upload') || config.boolValue('forceUpload');

  _requireFile(credentialsPath, 'Google Play service account credentials');
  if (!dryRun) {
    _requireFile(aabPath, 'Android App Bundle');
  }

  final listing = skipListing ? null : _readListing(listingDir);
  final releaseNotes = _readOptionalText(releaseNotesPath);
  final appDetailsConfig = skipAppDetails
      ? null
      : legacyAppDetailsPath == null
      ? config.object('appDetails')
      : _readOptionalJson(legacyAppDetailsPath);
  final appDetails = appDetailsConfig == null
      ? null
      : _playAppDetailsFromConfig(appDetailsConfig);
  final testerGroups =
      _testerGroupsFromAppDetails(appDetailsConfig) ??
      (legacyTesterGroupsPath == null
          ? null
          : _readOptionalLines(legacyTesterGroupsPath));
  final dataSafetyCsv = dataSafetyCsvPath == null
      ? null
      : _readOptionalText(dataSafetyCsvPath);
  final listingImages = _readListingImages(
    appIconPath: appIconPath,
    featureGraphicPath: featureGraphicPath,
    phoneScreenshotPaths: phoneScreenshotPaths,
    sevenInchScreenshotPaths: sevenInchScreenshotPaths,
    tenInchScreenshotPaths: tenInchScreenshotPaths,
  );

  _printPlan(
    packageName: packageName,
    track: track,
    language: language,
    aabPath: aabPath,
    credentialsPath: credentialsPath,
    listing: listing,
    ensureDefaultLanguage: ensureDefaultLanguage,
    removeListingLanguages: removeListingLanguages,
    releaseNotes: releaseNotes,
    appDetails: appDetails,
    testerGroups: testerGroups,
    dataSafetyCsvPath: dataSafetyCsvPath,
    dataSafetyCsv: dataSafetyCsv,
    listingImages: listingImages,
    localVersionCode: localVersionCode,
    dryRun: dryRun,
  );

  if (dryRun) {
    return;
  }

  final credentialsJson = jsonDecode(File(credentialsPath).readAsStringSync());
  final credentials = ServiceAccountCredentials.fromJson(credentialsJson);
  final client = await clientViaServiceAccount(credentials, [_publisherScope]);

  try {
    final api = _PlayPublisherApi(client);
    final editId = await api.insertEdit(packageName);
    var changed = false;
    var committed = false;
    final assetCache = _AssetCache.load(_assetCachePath);
    stdout.writeln('Created edit: $editId');
    try {
      if (listing != null) {
        final currentListing = await api.getListing(
          packageName: packageName,
          editId: editId,
          language: language,
        );
        if (listing.matches(currentListing)) {
          stdout.writeln('$language store listing is already up to date.');
        } else {
          await api.updateListing(
            packageName: packageName,
            editId: editId,
            language: language,
            listing: listing,
          );
          changed = true;
          stdout.writeln('Updated $language store listing.');
        }
      }

      if (ensureDefaultLanguage) {
        final currentAppDetails = await api.getAppDetails(
          packageName: packageName,
          editId: editId,
        );
        if (currentAppDetails['defaultLanguage'] == language) {
          stdout.writeln('Default language is already $language.');
        } else {
          await api.patchAppDetails(
            packageName: packageName,
            editId: editId,
            appDetails: {'defaultLanguage': language},
          );
          changed = true;
          stdout.writeln('Updated default language to $language.');
        }
      }

      for (final listingLanguage in removeListingLanguages) {
        final currentListing = await api.getListing(
          packageName: packageName,
          editId: editId,
          language: listingLanguage,
        );
        if (currentListing == null) {
          stdout.writeln('$listingLanguage store listing is already absent.');
          continue;
        }
        await api.deleteListing(
          packageName: packageName,
          editId: editId,
          language: listingLanguage,
        );
        changed = true;
        stdout.writeln('Deleted $listingLanguage store listing.');
      }

      if (appDetails != null) {
        final currentAppDetails = await api.getAppDetails(
          packageName: packageName,
          editId: editId,
        );
        if (_mapContainsAll(currentAppDetails, appDetails)) {
          stdout.writeln('App details are already up to date.');
        } else {
          await api.updateAppDetails(
            packageName: packageName,
            editId: editId,
            appDetails: appDetails,
          );
          changed = true;
          stdout.writeln('Updated app details.');
        }
      }

      if (testerGroups != null && track == 'internal') {
        stdout.writeln(
          'Skipping tester groups: Google Play API cannot set tester groups on the internal track.',
        );
      } else if (testerGroups != null) {
        final currentTesterGroups = await api.getTesterGroups(
          packageName: packageName,
          editId: editId,
          track: track,
        );
        if (_setEquals(currentTesterGroups, testerGroups.toSet())) {
          stdout.writeln('Tester groups are already up to date.');
        } else {
          await api.updateTesterGroups(
            packageName: packageName,
            editId: editId,
            track: track,
            googleGroups: testerGroups,
          );
          changed = true;
          stdout.writeln('Updated tester groups for track $track.');
        }
      }

      if (dataSafetyCsv != null) {
        stdout.writeln(
          'Uploading Data safety declaration from $dataSafetyCsvPath...',
        );
        await api.updateDataSafety(
          packageName: packageName,
          safetyLabelsCsv: dataSafetyCsv,
        );
        stdout.writeln('Uploaded Data safety declaration.');
      }

      for (final imageGroup in _groupListingImages(listingImages)) {
        final cacheKey = imageGroup.cacheKey(
          packageName: packageName,
          language: language,
        );
        if (assetCache.hashFor(cacheKey) == imageGroup.sha256Hash) {
          stdout.writeln(
            '${imageGroup.label} is unchanged since last successful upload; skipping.',
          );
          continue;
        }
        await api.replaceListingImages(
          packageName: packageName,
          editId: editId,
          language: language,
          imageGroup: imageGroup,
        );
        assetCache.setHash(cacheKey, imageGroup.sha256Hash);
        changed = true;
        stdout.writeln('Uploaded ${imageGroup.label}.');
      }

      final versionCode = await _resolveVersionCode(
        api: api,
        packageName: packageName,
        editId: editId,
        track: track,
        aabPath: aabPath,
        localVersionCode: localVersionCode,
        forceUpload: forceUpload,
      );

      final trackIsCurrent = await api.trackReleaseIsCurrent(
        packageName: packageName,
        editId: editId,
        track: track,
        versionCode: versionCode,
        releaseNotes: releaseNotes,
        releaseNotesLanguage: language,
      );
      if (trackIsCurrent) {
        stdout.writeln('Track $track is already up to date.');
      } else {
        stdout.writeln('Updating track $track...');
        await api.updateTrack(
          packageName: packageName,
          editId: editId,
          track: track,
          versionCode: versionCode,
          releaseNotes: releaseNotes,
          releaseNotesLanguage: language,
        );
        changed = true;
        stdout.writeln('Updated track: $track');
      }

      if (changed) {
        stdout.writeln('Committing edit...');
        await api.commitEdit(packageName: packageName, editId: editId);
        committed = true;
        assetCache.save();
        stdout.writeln('Committed edit. Release is submitted to $track.');
      } else {
        stdout.writeln('No Play changes needed; deleting edit.');
        await api.deleteEdit(packageName: packageName, editId: editId);
      }
    } catch (_) {
      if (!committed) {
        stdout.writeln('Deleting uncommitted edit after failure.');
        await api.deleteEdit(packageName: packageName, editId: editId);
      }
      rethrow;
    }
  } finally {
    client.close();
  }
}

void _printPlan({
  required String packageName,
  required String track,
  required String language,
  required String aabPath,
  required String credentialsPath,
  required _Listing? listing,
  required bool ensureDefaultLanguage,
  required List<String> removeListingLanguages,
  required String? releaseNotes,
  required Map<String, Object?>? appDetails,
  required List<String>? testerGroups,
  required String? dataSafetyCsvPath,
  required String? dataSafetyCsv,
  required List<_ListingImage> listingImages,
  required int localVersionCode,
  required bool dryRun,
}) {
  stdout.writeln('Google Play internal release plan');
  stdout.writeln('Package: $packageName');
  stdout.writeln('Track: $track');
  stdout.writeln('Language: $language');
  stdout.writeln(
    'AAB: $aabPath${File(aabPath).existsSync() ? '' : ' (not found yet)'}',
  );
  stdout.writeln('Credentials: $credentialsPath');
  stdout.writeln('Listing: ${listing == null ? 'skipped' : 'included'}');
  stdout.writeln(
    'Ensure default language: ${ensureDefaultLanguage ? language : 'skipped'}',
  );
  stdout.writeln(
    'Remove listing languages: ${removeListingLanguages.isEmpty ? 'none' : removeListingLanguages.join(', ')}',
  );
  stdout.writeln('App details: ${appDetails == null ? 'skipped' : 'included'}');
  stdout.writeln(
    'Tester groups: ${testerGroups == null ? 'skipped' : testerGroups.join(', ')}',
  );
  stdout.writeln(
    'Data safety CSV: ${dataSafetyCsv == null ? 'skipped${dataSafetyCsvPath == null ? '' : ' (missing $dataSafetyCsvPath)'}' : 'included'}',
  );
  stdout.writeln(
    'Manual App content: privacy policy, sign-in details, ads, content rating, target audience, government apps, financial features, and health.',
  );
  stdout.writeln(
    'Listing images: ${listingImages.isEmpty ? 'skipped' : listingImages.map((image) => image.label).join(', ')}',
  );
  stdout.writeln(
    'Release notes: ${releaseNotes == null ? 'none' : 'included'}',
  );
  stdout.writeln('Local versionCode: $localVersionCode');
  if (dryRun) {
    stdout.writeln('Dry run: no Google Play changes will be made.');
  }
}

Future<int> _resolveVersionCode({
  required _PlayPublisherApi api,
  required String packageName,
  required String editId,
  required String track,
  required String aabPath,
  required int localVersionCode,
  required bool forceUpload,
}) async {
  if (!forceUpload) {
    final trackVersionCodes = await api.trackVersionCodes(
      packageName: packageName,
      editId: editId,
      track: track,
    );
    if (trackVersionCodes.contains(localVersionCode)) {
      stdout.writeln(
        'VersionCode $localVersionCode is already on track $track; skipping AAB upload.',
      );
      return localVersionCode;
    }
  }

  stdout.writeln('Uploading AAB...');
  try {
    final versionCode = await api.uploadBundle(
      packageName: packageName,
      editId: editId,
      aabPath: aabPath,
    );
    stdout.writeln('Uploaded AAB versionCode: $versionCode');
    return versionCode;
  } on _GooglePlayApiException catch (error) {
    if (error.statusCode == 403 &&
        error.body.contains(
          'Version code $localVersionCode has already been used',
        )) {
      stdout.writeln(
        'VersionCode $localVersionCode has already been uploaded; skipping AAB upload.',
      );
      return localVersionCode;
    }
    rethrow;
  }
}

int _readPubspecVersionCode(String path) {
  final versionLine = File(path)
      .readAsLinesSync()
      .map((line) => line.trim())
      .firstWhere(
        (line) => line.startsWith('version:'),
        orElse: () => throw StateError('No version: line found in $path'),
      );
  final version = versionLine.substring('version:'.length).trim();
  final plusIndex = version.lastIndexOf('+');
  if (plusIndex == -1 || plusIndex == version.length - 1) {
    throw StateError(
      'Version in $path must include a build number, for example 1.0.0+1.',
    );
  }
  return int.parse(version.substring(plusIndex + 1));
}

_Listing _readListing(String dir) {
  final title = _readRequiredText('$dir/title.txt');
  final shortDescription = _readRequiredText('$dir/short-description.txt');
  final fullDescription = _readRequiredText('$dir/full-description.txt');

  if (title.length > 30) {
    throw StateError('Play title is ${title.length} chars; max is 30.');
  }
  if (shortDescription.length > 80) {
    throw StateError(
      'Play short description is ${shortDescription.length} chars; max is 80.',
    );
  }
  if (fullDescription.length > 4000) {
    throw StateError(
      'Play full description is ${fullDescription.length} chars; max is 4000.',
    );
  }

  return _Listing(
    title: title,
    shortDescription: shortDescription,
    fullDescription: fullDescription,
  );
}

String _readRequiredText(String path) {
  _requireFile(path, path);
  return File(path).readAsStringSync().trim();
}

String? _readOptionalText(String path) {
  final file = File(path);
  if (!file.existsSync()) {
    return null;
  }
  final text = file.readAsStringSync().trim();
  return text.isEmpty ? null : text;
}

Map<String, Object?>? _readOptionalJson(String path) {
  final file = File(path);
  if (!file.existsSync()) {
    return null;
  }
  final decoded = jsonDecode(file.readAsStringSync());
  if (decoded is! Map<String, Object?>) {
    throw FormatException('$path must contain a JSON object.');
  }
  return decoded;
}

Map<String, Object?> _playAppDetailsFromConfig(Map<String, Object?> config) {
  return <String, Object?>{
    for (final MapEntry<String, Object?> entry in config.entries)
      if (entry.key != 'testerGoogleGroups') entry.key: entry.value,
  };
}

List<String>? _testerGroupsFromAppDetails(Map<String, Object?>? config) {
  final Object? value = config?['testerGoogleGroups'];
  if (value == null) {
    return null;
  }
  if (value is! List<Object?>) {
    throw const FormatException(
      'Expected "testerGoogleGroups" in app details to be a list.',
    );
  }
  final List<String> groups = value
      .map((Object? item) => item?.toString().trim() ?? '')
      .where((String item) => item.isNotEmpty)
      .toList();
  return groups.isEmpty ? null : groups;
}

List<String>? _readOptionalLines(String path) {
  final file = File(path);
  if (!file.existsSync()) {
    return null;
  }
  final lines = file
      .readAsLinesSync()
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty && !line.startsWith('#'))
      .toList();
  return lines.isEmpty ? null : lines;
}

List<_ListingImage> _readListingImages({
  required String appIconPath,
  required String featureGraphicPath,
  required List<String> phoneScreenshotPaths,
  required List<String> sevenInchScreenshotPaths,
  required List<String> tenInchScreenshotPaths,
}) {
  return [
    if (File(appIconPath).existsSync())
      _ListingImage.read(
        imageType: 'icon',
        label: 'app icon',
        path: appIconPath,
        requiredWidth: 512,
        requiredHeight: 512,
        maxBytes: 1024 * 1024,
      ),
    if (File(featureGraphicPath).existsSync())
      _ListingImage.read(
        imageType: 'featureGraphic',
        label: 'feature graphic',
        path: featureGraphicPath,
        requiredWidth: 1024,
        requiredHeight: 500,
        maxBytes: 15 * 1024 * 1024,
      ),
    for (var index = 0; index < phoneScreenshotPaths.length; index++)
      _ListingImage.readScreenshot(
        imageType: 'phoneScreenshots',
        label: 'phone screenshot ${index + 1}',
        path: phoneScreenshotPaths[index],
      ),
    for (var index = 0; index < sevenInchScreenshotPaths.length; index++)
      _ListingImage.readScreenshot(
        imageType: 'sevenInchScreenshots',
        label: '7-inch tablet screenshot ${index + 1}',
        path: sevenInchScreenshotPaths[index],
      ),
    for (var index = 0; index < tenInchScreenshotPaths.length; index++)
      _ListingImage.readScreenshot(
        imageType: 'tenInchScreenshots',
        label: '10-inch tablet screenshot ${index + 1}',
        path: tenInchScreenshotPaths[index],
      ),
  ];
}

List<_ListingImageGroup> _groupListingImages(List<_ListingImage> images) {
  final groups = <String, List<_ListingImage>>{};
  for (final image in images) {
    groups.putIfAbsent(image.imageType, () => []).add(image);
  }
  return [
    for (final entry in groups.entries)
      _ListingImageGroup(imageType: entry.key, images: entry.value),
  ];
}

bool _mapContainsAll(
  Map<String, Object?> current,
  Map<String, Object?> desired,
) {
  for (final entry in desired.entries) {
    final desiredValue = entry.value;
    if (desiredValue == null || desiredValue == '') {
      continue;
    }
    if (current[entry.key] != desiredValue) {
      return false;
    }
  }
  return true;
}

bool _setEquals(Set<String> left, Set<String> right) {
  return left.length == right.length && left.containsAll(right);
}

void _requireFile(String path, String label) {
  final file = File(path);
  if (!file.existsSync()) {
    throw StateError('$label not found at $path');
  }
}

class _Listing {
  const _Listing({
    required this.title,
    required this.shortDescription,
    required this.fullDescription,
  });

  final String title;
  final String shortDescription;
  final String fullDescription;

  Map<String, Object?> toJson(String language) {
    return {
      'language': language,
      'title': title,
      'shortDescription': shortDescription,
      'fullDescription': fullDescription,
    };
  }

  bool matches(Map<String, Object?>? current) {
    if (current == null) {
      return false;
    }
    return current['title'] == title &&
        current['shortDescription'] == shortDescription &&
        current['fullDescription'] == fullDescription;
  }
}

class _ListingImage {
  const _ListingImage({
    required this.imageType,
    required this.label,
    required this.path,
    required this.contentType,
    required this.bytes,
    required this.sha256Hash,
  });

  final String imageType;
  final String label;
  final String path;
  final String contentType;
  final List<int> bytes;
  final String sha256Hash;

  static _ListingImage read({
    required String imageType,
    required String label,
    required String path,
    required int requiredWidth,
    required int requiredHeight,
    required int maxBytes,
  }) {
    final file = File(path);
    final bytes = file.readAsBytesSync();
    if (bytes.length > maxBytes) {
      throw StateError(
        '$label at $path is ${bytes.length} bytes; max is $maxBytes bytes.',
      );
    }
    final dimensions = _readPngDimensions(bytes);
    if (dimensions == null) {
      throw StateError('$label at $path must be a PNG file.');
    }
    if (dimensions.width != requiredWidth ||
        dimensions.height != requiredHeight) {
      throw StateError(
        '$label at $path is ${dimensions.width}x${dimensions.height}; expected ${requiredWidth}x$requiredHeight.',
      );
    }
    return _ListingImage(
      imageType: imageType,
      label: label,
      path: path,
      contentType: 'image/png',
      bytes: bytes,
      sha256Hash: sha256.convert(bytes).toString(),
    );
  }

  static _ListingImage readScreenshot({
    required String imageType,
    required String label,
    required String path,
  }) {
    final file = File(path);
    final bytes = file.readAsBytesSync();
    const maxBytes = 8 * 1024 * 1024;
    if (bytes.length > maxBytes) {
      throw StateError(
        '$label at $path is ${bytes.length} bytes; max is $maxBytes bytes.',
      );
    }
    final dimensions = _readPngDimensions(bytes);
    if (dimensions == null) {
      throw StateError('$label at $path must be a PNG file.');
    }
    final shortest = dimensions.width < dimensions.height
        ? dimensions.width
        : dimensions.height;
    final longest = dimensions.width > dimensions.height
        ? dimensions.width
        : dimensions.height;
    if (shortest < 320 || longest > 3840 || longest > shortest * 2) {
      throw StateError(
        '$label at $path is ${dimensions.width}x${dimensions.height}; expected both sides between 320 and 3840 px with longest side at most twice the shortest side.',
      );
    }
    if (_pngHasAlpha(bytes)) {
      throw StateError('$label at $path must be an opaque PNG without alpha.');
    }
    return _ListingImage(
      imageType: imageType,
      label: label,
      path: path,
      contentType: 'image/png',
      bytes: bytes,
      sha256Hash: sha256.convert(bytes).toString(),
    );
  }

  String cacheKey({required String packageName, required String language}) {
    return '$packageName/$language/$imageType';
  }
}

class _ListingImageGroup {
  _ListingImageGroup({required this.imageType, required this.images})
    : assert(images.isNotEmpty);

  final String imageType;
  final List<_ListingImage> images;

  String get label {
    if (images.length == 1) {
      return images.single.label;
    }
    if (imageType == 'phoneScreenshots') {
      return '${images.length} phone screenshots';
    }
    if (imageType == 'sevenInchScreenshots') {
      return '${images.length} 7-inch tablet screenshots';
    }
    if (imageType == 'tenInchScreenshots') {
      return '${images.length} 10-inch tablet screenshots';
    }
    return '${images.length} ${images.first.imageType}';
  }

  String get sha256Hash => sha256.convert([
    for (final image in images) ...[
      ...utf8.encode(image.path),
      0,
      ...utf8.encode(image.sha256Hash),
      0,
    ],
  ]).toString();

  String cacheKey({required String packageName, required String language}) {
    return '$packageName/$language/$imageType';
  }
}

({int width, int height})? _readPngDimensions(List<int> bytes) {
  const signature = [137, 80, 78, 71, 13, 10, 26, 10];
  if (bytes.length < 24) {
    return null;
  }
  for (var index = 0; index < signature.length; index++) {
    if (bytes[index] != signature[index]) {
      return null;
    }
  }
  int readUint32(int offset) {
    return (bytes[offset] << 24) |
        (bytes[offset + 1] << 16) |
        (bytes[offset + 2] << 8) |
        bytes[offset + 3];
  }

  return (width: readUint32(16), height: readUint32(20));
}

bool _pngHasAlpha(List<int> bytes) {
  if (bytes.length < 26) {
    return false;
  }
  final colorType = bytes[25];
  return colorType == 4 || colorType == 6;
}

class _AssetCache {
  _AssetCache(this._path, this._hashes);

  final String _path;
  final Map<String, String> _hashes;

  static _AssetCache load(String path) {
    final file = File(path);
    if (!file.existsSync()) {
      return _AssetCache(path, {});
    }
    final decoded = jsonDecode(file.readAsStringSync());
    if (decoded is! Map<String, Object?>) {
      return _AssetCache(path, {});
    }
    return _AssetCache(
      path,
      decoded.map((key, value) => MapEntry(key, value.toString())),
    );
  }

  String? hashFor(String key) => _hashes[key];

  void setHash(String key, String hash) {
    _hashes[key] = hash;
  }

  void save() {
    final file = File(_path);
    file.parent.createSync(recursive: true);
    final json = const JsonEncoder.withIndent('  ').convert(_hashes);
    file.writeAsStringSync('$json\n');
  }
}

class _Config {
  const _Config(this._values);

  final Map<String, Object?> _values;

  static _Config read(String? path) {
    if (path == null) {
      return const _Config({});
    }

    final file = File(path);
    if (!file.existsSync()) {
      throw FileSystemException('Missing Google Play config file', path);
    }

    final decoded = jsonDecode(file.readAsStringSync());
    if (decoded is! Map<String, Object?>) {
      throw FormatException('Expected a JSON object in $path.');
    }

    return _Config(decoded);
  }

  String? string(String key) {
    final value = _values[key];
    if (value == null) {
      return null;
    }
    if (value is! String) {
      throw FormatException('Expected "$key" in config to be a string.');
    }
    return value;
  }

  Map<String, Object?>? object(String key) {
    final value = _values[key];
    if (value == null) {
      return null;
    }
    if (value is! Map<String, Object?>) {
      throw FormatException('Expected "$key" in config to be an object.');
    }
    return value;
  }

  bool boolValue(String key, {bool defaultValue = false}) {
    final value = _values[key];
    if (value == null) {
      return defaultValue;
    }
    if (value is! bool) {
      throw FormatException('Expected "$key" in config to be a boolean.');
    }
    return value;
  }

  List<String> stringList(String key) {
    final value = _values[key];
    if (value == null) {
      return const [];
    }
    if (value is! List<Object?>) {
      throw FormatException('Expected "$key" in config to be a list.');
    }
    return [
      for (final item in value)
        if (item is String)
          item
        else
          throw FormatException(
            'Expected every item in "$key" config to be a string.',
          ),
    ];
  }
}

class _PlayPublisherApi {
  _PlayPublisherApi(this._client);

  static final _baseUri = Uri.https('androidpublisher.googleapis.com', '');

  final http.Client _client;

  Future<String> insertEdit(String packageName) async {
    final response = await _client.post(
      _baseUri.replace(
        path: '/androidpublisher/v3/applications/$packageName/edits',
      ),
      headers: _jsonHeaders,
    );
    final body = _decode(response);
    return body['id'] as String;
  }

  Future<void> updateListing({
    required String packageName,
    required String editId,
    required String language,
    required _Listing listing,
  }) async {
    await _client
        .put(
          _baseUri.replace(
            path:
                '/androidpublisher/v3/applications/$packageName/edits/$editId/listings/$language',
          ),
          headers: _jsonHeaders,
          body: jsonEncode(listing.toJson(language)),
        )
        .then(_expectSuccess);
  }

  Future<Map<String, Object?>?> getListing({
    required String packageName,
    required String editId,
    required String language,
  }) async {
    final response = await _client.get(
      _baseUri.replace(
        path:
            '/androidpublisher/v3/applications/$packageName/edits/$editId/listings/$language',
      ),
    );
    if (response.statusCode == 404) {
      return null;
    }
    return _decode(response);
  }

  Future<void> deleteListing({
    required String packageName,
    required String editId,
    required String language,
  }) async {
    await _client
        .delete(
          _baseUri.replace(
            path:
                '/androidpublisher/v3/applications/$packageName/edits/$editId/listings/$language',
          ),
        )
        .then(_expectSuccess);
  }

  Future<void> updateAppDetails({
    required String packageName,
    required String editId,
    required Map<String, Object?> appDetails,
  }) async {
    await _client
        .put(
          _baseUri.replace(
            path:
                '/androidpublisher/v3/applications/$packageName/edits/$editId/details',
          ),
          headers: _jsonHeaders,
          body: jsonEncode(appDetails),
        )
        .then(_expectSuccess);
  }

  Future<Map<String, Object?>> getAppDetails({
    required String packageName,
    required String editId,
  }) async {
    final response = await _client.get(
      _baseUri.replace(
        path:
            '/androidpublisher/v3/applications/$packageName/edits/$editId/details',
      ),
    );
    return _decode(response);
  }

  Future<void> patchAppDetails({
    required String packageName,
    required String editId,
    required Map<String, Object?> appDetails,
  }) async {
    await _client
        .patch(
          _baseUri.replace(
            path:
                '/androidpublisher/v3/applications/$packageName/edits/$editId/details',
          ),
          headers: _jsonHeaders,
          body: jsonEncode(appDetails),
        )
        .then(_expectSuccess);
  }

  Future<Set<String>> getTesterGroups({
    required String packageName,
    required String editId,
    required String track,
  }) async {
    final response = await _client.get(
      _baseUri.replace(
        path:
            '/androidpublisher/v3/applications/$packageName/edits/$editId/testers/$track',
      ),
    );
    if (response.statusCode == 404) {
      return {};
    }
    final body = _decode(response);
    final googleGroups = body['googleGroups'];
    if (googleGroups is! List) {
      return {};
    }
    return googleGroups.map((group) => group.toString()).toSet();
  }

  Future<void> updateTesterGroups({
    required String packageName,
    required String editId,
    required String track,
    required List<String> googleGroups,
  }) async {
    await _client
        .put(
          _baseUri.replace(
            path:
                '/androidpublisher/v3/applications/$packageName/edits/$editId/testers/$track',
          ),
          headers: _jsonHeaders,
          body: jsonEncode({'googleGroups': googleGroups}),
        )
        .then(_expectSuccess);
  }

  Future<void> updateDataSafety({
    required String packageName,
    required String safetyLabelsCsv,
  }) async {
    await _client
        .post(
          _baseUri.replace(
            path: '/androidpublisher/v3/applications/$packageName/dataSafety',
          ),
          headers: _jsonHeaders,
          body: jsonEncode({'safetyLabels': safetyLabelsCsv}),
        )
        .then(_expectSuccess);
  }

  Future<void> replaceListingImages({
    required String packageName,
    required String editId,
    required String language,
    required _ListingImageGroup imageGroup,
  }) async {
    stdout.writeln('Replacing ${imageGroup.label}...');
    await _client
        .delete(
          _baseUri.replace(
            path:
                '/androidpublisher/v3/applications/$packageName/edits/$editId/listings/$language/${imageGroup.imageType}',
          ),
        )
        .then(_expectSuccess);

    for (final image in imageGroup.images) {
      stdout.writeln('Uploading ${image.label} from ${image.path}...');
      final response = await _client.post(
        _baseUri.replace(
          path:
              '/upload/androidpublisher/v3/applications/$packageName/edits/$editId/listings/$language/${image.imageType}',
          queryParameters: {'uploadType': 'media'},
        ),
        headers: {'content-type': image.contentType},
        body: image.bytes,
      );
      _expectSuccess(response);
    }
  }

  Future<Set<int>> trackVersionCodes({
    required String packageName,
    required String editId,
    required String track,
  }) async {
    final response = await _client.get(
      _baseUri.replace(
        path:
            '/androidpublisher/v3/applications/$packageName/edits/$editId/tracks/$track',
      ),
    );
    if (response.statusCode == 404) {
      return {};
    }
    final body = _decode(response);
    final releases = body['releases'];
    if (releases is! List) {
      return {};
    }
    return {
      for (final release in releases)
        if (release is Map<String, Object?>)
          for (final versionCode
              in release['versionCodes'] as List? ?? const [])
            int.parse(versionCode.toString()),
    };
  }

  Future<int> uploadBundle({
    required String packageName,
    required String editId,
    required String aabPath,
  }) async {
    final file = File(aabPath);
    final bytes = file.readAsBytesSync();
    stdout.writeln('Read ${bytes.length} bytes from $aabPath.');

    final response = await _client.post(
      _baseUri.replace(
        path:
            '/upload/androidpublisher/v3/applications/$packageName/edits/$editId/bundles',
        queryParameters: {'uploadType': 'media'},
      ),
      headers: {'content-type': 'application/octet-stream'},
      body: bytes,
    );
    stdout.writeln('Bundle upload response: HTTP ${response.statusCode}.');

    final body = _decode(response);
    final versionCode = body['versionCode'];
    if (versionCode is int) {
      return versionCode;
    }
    if (versionCode is String) {
      return int.parse(versionCode);
    }
    throw StateError('Upload response did not contain versionCode: $body');
  }

  Future<void> updateTrack({
    required String packageName,
    required String editId,
    required String track,
    required int versionCode,
    required String? releaseNotes,
    required String releaseNotesLanguage,
  }) async {
    final release = <String, Object?>{
      'name': 'Charge Ledger $versionCode',
      'versionCodes': [versionCode.toString()],
      'status': 'completed',
    };
    if (releaseNotes != null) {
      release['releaseNotes'] = [
        {'language': releaseNotesLanguage, 'text': releaseNotes},
      ];
    }

    await _client
        .put(
          _baseUri.replace(
            path:
                '/androidpublisher/v3/applications/$packageName/edits/$editId/tracks/$track',
          ),
          headers: _jsonHeaders,
          body: jsonEncode({
            'track': track,
            'releases': [release],
          }),
        )
        .then(_expectSuccess);
  }

  Future<bool> trackReleaseIsCurrent({
    required String packageName,
    required String editId,
    required String track,
    required int versionCode,
    required String? releaseNotes,
    required String releaseNotesLanguage,
  }) async {
    final response = await _client.get(
      _baseUri.replace(
        path:
            '/androidpublisher/v3/applications/$packageName/edits/$editId/tracks/$track',
      ),
    );
    if (response.statusCode == 404) {
      return false;
    }
    final body = _decode(response);
    final releases = body['releases'];
    if (releases is! List) {
      return false;
    }
    for (final release in releases) {
      if (release is! Map<String, Object?>) {
        continue;
      }
      final versionCodes = (release['versionCodes'] as List? ?? const [])
          .map((code) => int.parse(code.toString()))
          .toSet();
      if (!versionCodes.contains(versionCode)) {
        continue;
      }
      if (releaseNotes == null) {
        return true;
      }
      final notes = release['releaseNotes'];
      if (notes is! List) {
        return false;
      }
      return notes.any(
        (note) =>
            note is Map<String, Object?> &&
            note['language'] == releaseNotesLanguage &&
            note['text'] == releaseNotes,
      );
    }
    return false;
  }

  Future<void> commitEdit({
    required String packageName,
    required String editId,
  }) async {
    await _client
        .post(
          _baseUri.replace(
            path:
                '/androidpublisher/v3/applications/$packageName/edits/$editId:commit',
          ),
          headers: _jsonHeaders,
        )
        .then(_expectSuccess);
  }

  Future<void> deleteEdit({
    required String packageName,
    required String editId,
  }) async {
    await _client
        .delete(
          _baseUri.replace(
            path:
                '/androidpublisher/v3/applications/$packageName/edits/$editId',
          ),
        )
        .then(_expectSuccess);
  }

  Map<String, Object?> _decode(http.Response response) {
    _expectSuccess(response);
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, Object?>) {
      throw FormatException('Expected JSON object, got: ${response.body}');
    }
    return decoded;
  }

  void _expectSuccess(http.Response response) {
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return;
    }
    throw _GooglePlayApiException(
      statusCode: response.statusCode,
      body: response.body,
      uri: response.request?.url,
    );
  }

  static const _jsonHeaders = {
    'content-type': 'application/json; charset=utf-8',
  };
}

class _GooglePlayApiException implements Exception {
  const _GooglePlayApiException({
    required this.statusCode,
    required this.body,
    required this.uri,
  });

  final int statusCode;
  final String body;
  final Uri? uri;

  @override
  String toString() {
    return 'Google Play API returned $statusCode: $body${uri == null ? '' : ', uri = $uri'}';
  }
}

class _Args {
  _Args(this._values, this._flags);

  final Map<String, String> _values;
  final Set<String> _flags;

  String? value(String name) => _values[name];

  bool flag(String name) => _flags.contains(name);

  static _Args parse(List<String> arguments) {
    final values = <String, String>{};
    final flags = <String>{};

    for (var index = 0; index < arguments.length; index++) {
      final arg = arguments[index];
      if (arg == '--help' || arg == '-h') {
        _printHelp();
        exit(0);
      }
      if (!arg.startsWith('--')) {
        throw FormatException('Unexpected argument: $arg');
      }

      final withoutPrefix = arg.substring(2);
      if (withoutPrefix == 'dry-run' ||
          withoutPrefix == 'verbose' ||
          withoutPrefix == 'skip-listing' ||
          withoutPrefix == 'skip-app-details' ||
          withoutPrefix == 'force-upload') {
        flags.add(withoutPrefix);
        continue;
      }

      final equalsIndex = withoutPrefix.indexOf('=');
      if (equalsIndex != -1) {
        values[withoutPrefix.substring(0, equalsIndex)] = withoutPrefix
            .substring(equalsIndex + 1);
        continue;
      }

      if (index + 1 >= arguments.length) {
        throw FormatException('Missing value for $arg');
      }
      values[withoutPrefix] = arguments[++index];
    }

    return _Args(values, flags);
  }

  static void _printHelp() {
    stdout.writeln('''
Update Google Play listing and upload an AAB to internal testing.

Options:
  --config <path>           Default: built-in defaults only
  --package-name <id>       Default: $_defaultPackageName
  --track <track>           Default: $_defaultTrack
  --language <tag>          Default: $_defaultLanguage
  --aab <path>              Default: $_defaultAabPath
  --credentials <path>      Default: $_defaultCredentialsPath
  --listing-dir <path>      Default: play/listing/<language>
  --release-notes <path>    Default: play/release/release-notes-internal.txt
  --app-details <path>      Legacy override; app details normally come from play-config appDetails.
  --tester-groups <path>    Legacy override; tester groups normally come from play-config appDetails.testerGoogleGroups.
  --skip-listing            Do not update localized store listing text.
  --skip-app-details        Do not update app details.
  --force-upload            Upload even when local versionCode is already on the track.
  --dry-run                 Validate inputs and print the plan only.
  --verbose                 Print stack traces when an error occurs.
''');
  }
}
