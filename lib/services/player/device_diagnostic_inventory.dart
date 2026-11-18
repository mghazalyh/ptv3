import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Owner-enabled machine inventory for PlayTorrio's existing private reports.
///
/// A stable per-install ID permits grouping sessions from one installation.
/// Hardware details come from the OS, not inferred from screen dimensions.
/// This never reads environment variables, credential stores, browser data,
/// clipboard contents, files, messages, or streaming authentication URLs.
class DeviceDiagnosticInventory {
  DeviceDiagnosticInventory._({
    Future<Map<String, Object?>> Function()? testSnapshotProvider,
  }) : _testSnapshotProvider = testSnapshotProvider;

  static final DeviceDiagnosticInventory instance =
      DeviceDiagnosticInventory._();

  @visibleForTesting
  factory DeviceDiagnosticInventory.forTesting(
    Future<Map<String, Object?>> Function() provider,
  ) => DeviceDiagnosticInventory._(testSnapshotProvider: provider);

  static const String installIdPreferenceKey =
      'playtorrio_diagnostic_install_id_v1';
  static const MethodChannel _iosChannel =
      MethodChannel('playtorrio/device_diagnostics');
  static const Duration _refreshInterval = Duration(minutes: 5);

  final Future<Map<String, Object?>> Function()? _testSnapshotProvider;
  Future<Map<String, Object?>>? _pending;
  DateTime? _lastCollection;
  Map<String, Object?>? _lastSnapshot;

  /// Refreshes hardware every five minutes rather than spawning a Windows
  /// hardware probe for each periodic playback report.
  Future<Map<String, Object?>> capture() async {
    final cached = _lastSnapshot;
    final last = _lastCollection;
    if (cached != null && last != null &&
        DateTime.now().difference(last) < _refreshInterval) {
      return Map<String, Object?>.from(cached);
    }
    final pending = _pending;
    if (pending != null) return pending;
    final future = _collect();
    _pending = future;
    try {
      final result = await future;
      _lastSnapshot = result;
      _lastCollection = DateTime.now();
      return Map<String, Object?>.from(result);
    } finally {
      _pending = null;
    }
  }

  @visibleForTesting
  void invalidateCache() {
    _lastCollection = null;
    _lastSnapshot = null;
  }

  Future<Map<String, Object?>> _collect() async {
    if (_testSnapshotProvider != null) {
      try {
        return await _testSnapshotProvider();
      } catch (error) {
        return {'collectionError': error.runtimeType.toString()};
      }
    }
    final inventory = <String, Object?>{
      'schema': 1,
      'capturedAtUtc': DateTime.now().toUtc().toIso8601String(),
      'platform': Platform.operatingSystem,
      'operatingSystemVersion': Platform.operatingSystemVersion,
      'dartRuntime': Platform.version,
      'logicalProcessors': Platform.numberOfProcessors,
      'locale': Platform.localeName,
      'timezone': DateTime.now().timeZoneName,
      'timezoneOffsetMinutes': DateTime.now().timeZoneOffset.inMinutes,
      'processResidentBytes': ProcessInfo.currentRss,
      'processMaxResidentBytes': ProcessInfo.maxRss,
    };
    try {
      inventory['installId'] = await _installationId();
    } catch (error) {
      inventory['installIdError'] = error.runtimeType.toString();
    }
    try {
      final package = await PackageInfo.fromPlatform();
      inventory['application'] = <String, Object?>{
        'packageName': package.packageName,
        'appName': package.appName,
        'version': package.version,
        'buildNumber': package.buildNumber,
      };
    } catch (error) {
      inventory['packageInfoError'] = error.runtimeType.toString();
    }
    try {
      inventory['displays'] = ui.PlatformDispatcher.instance.views
          .map((view) => <String, Object?>{
            'viewId': view.viewId,
            'widthPx': view.physicalSize.width.round(),
            'heightPx': view.physicalSize.height.round(),
            'devicePixelRatio': view.devicePixelRatio,
            'viewInsetsBottomPx': view.viewInsets.bottom,
            'paddingTopPx': view.padding.top,
          }).take(8).toList();
      inventory['ui'] = <String, Object?>{
        'platformBrightness':
            ui.PlatformDispatcher.instance.platformBrightness.name,
        'textScaleFactor':
            ui.PlatformDispatcher.instance.textScaleFactor,
        'preferredLocales': ui.PlatformDispatcher.instance.locales
            .take(8).map((locale) => locale.toLanguageTag()).toList(),
      };
    } catch (error) {
      inventory['displayError'] = error.runtimeType.toString();
    }
    try {
      final interfaces = await NetworkInterface.list(
        includeLoopback: false,
        includeLinkLocal: false,
        type: InternetAddressType.any,
      ).timeout(const Duration(seconds: 3));
      inventory['networkInterfaces'] = interfaces.take(32).map(
        (iface) => <String, Object?>{
          'name': iface.name,
          'index': iface.index,
          'addresses': iface.addresses.take(12).map(
            (address) => <String, Object?>{
              'address': address.address,
              'type': address.type.name,
            },
          ).toList(),
        },
      ).toList();
    } catch (error) {
      inventory['networkError'] = error.runtimeType.toString();
    }
    if (Platform.isWindows) {
      inventory['windowsHardware'] = await _windowsHardware();
    } else if (Platform.isIOS) {
      inventory['iosHardware'] = await _iosHardware();
    }
    return inventory;
  }

  Future<String> _installationId() async {
    final prefs = await SharedPreferences.getInstance();
    final previous = prefs.getString(installIdPreferenceKey);
    if (previous != null && RegExp(r'^[0-9a-f]{32}$').hasMatch(previous)) {
      return previous;
    }
    final random = Random.secure();
    final id = List<int>.generate(16, (_) => random.nextInt(256))
        .map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
    await prefs.setString(installIdPreferenceKey, id);
    return id;
  }

  Future<Map<String, Object?>> _iosHardware() async {
    try {
      final response = await _iosChannel.invokeMapMethod<String, dynamic>(
        'snapshot',
      ).timeout(const Duration(seconds: 4));
      return response == null
          ? <String, Object?>{'available': false}
          : Map<String, Object?>.from(response);
    } catch (error) {
      return <String, Object?>{
        'available': false,
        'error': error.runtimeType.toString(),
      };
    }
  }

  Future<Map<String, Object?>> _windowsHardware() async {
    // PowerShell is available on supported Windows builds. Every WMI class
    // has independent error handling; limited arrays bound report size.
    const script = r'''
$ErrorActionPreference = 'Stop'
function Read-Cim([string]$class, [string[]]$fields, [int]$limit = 8) {
  try {
    @(Get-CimInstance -ClassName $class -ErrorAction Stop |
      Select-Object -Property $fields -First $limit)
  } catch { @() }
}
$report = [ordered]@{
  computerSystem = @(Read-Cim 'Win32_ComputerSystem' @('Name','Manufacturer','Model','SystemType','TotalPhysicalMemory','NumberOfLogicalProcessors','NumberOfProcessors','Domain','HypervisorPresent') 1)
  operatingSystem = @(Read-Cim 'Win32_OperatingSystem' @('Caption','Version','BuildNumber','OSArchitecture','InstallDate','LastBootUpTime','TotalVisibleMemorySize','FreePhysicalMemory','FreeVirtualMemory','TotalVirtualMemorySize') 1)
  processor = @(Read-Cim 'Win32_Processor' @('Name','Manufacturer','NumberOfCores','NumberOfLogicalProcessors','MaxClockSpeed','CurrentClockSpeed','LoadPercentage','ProcessorId','Architecture') 8)
  graphicsAdapters = @(Read-Cim 'Win32_VideoController' @('Name','AdapterCompatibility','AdapterRAM','DriverVersion','DriverDate','VideoProcessor','CurrentHorizontalResolution','CurrentVerticalResolution','CurrentRefreshRate','Status') 12)
  memoryModules = @(Read-Cim 'Win32_PhysicalMemory' @('Manufacturer','PartNumber','Capacity','Speed','ConfiguredClockSpeed','SMBIOSMemoryType','BankLabel','DeviceLocator') 24)
  disks = @(Read-Cim 'Win32_DiskDrive' @('Model','Manufacturer','MediaType','Size','InterfaceType','FirmwareRevision','Status','SerialNumber') 16)
  volumes = @(Read-Cim 'Win32_LogicalDisk' @('DeviceID','DriveType','FileSystem','Size','FreeSpace','VolumeName') 24)
  networkAdapters = @(Read-Cim 'Win32_NetworkAdapter' @('Name','Manufacturer','MACAddress','Speed','NetEnabled','AdapterType','PhysicalAdapter') 32)
  networkConfiguration = @(Read-Cim 'Win32_NetworkAdapterConfiguration' @('Description','IPAddress','IPSubnet','DefaultIPGateway','DHCPEnabled','DHCPServer','DNSServerSearchOrder','MACAddress') 24)
  soundDevices = @(Read-Cim 'Win32_SoundDevice' @('Name','Manufacturer','ProductName','Status') 16)
  monitors = @(Read-Cim 'Win32_DesktopMonitor' @('Name','MonitorType','ScreenHeight','ScreenWidth','Status') 12)
  battery = @(Read-Cim 'Win32_Battery' @('Name','BatteryStatus','EstimatedChargeRemaining','EstimatedRunTime') 8)
  bios = @(Read-Cim 'Win32_BIOS' @('Manufacturer','SMBIOSBIOSVersion','ReleaseDate','SerialNumber') 1)
  baseboard = @(Read-Cim 'Win32_BaseBoard' @('Manufacturer','Product','Version','SerialNumber') 1)
}
try {
  $report.topMemoryProcesses = @(Get-Process -ErrorAction Stop |
    Sort-Object -Property WorkingSet64 -Descending |
    Select-Object -First 15 -Property ProcessName,Id,CPU,WorkingSet64)
} catch { $report.topMemoryProcesses = @() }
$report | ConvertTo-Json -Depth 7 -Compress
''';
    try {
      final result = await Process.run(
        'powershell.exe',
        ['-NoProfile', '-NonInteractive', '-ExecutionPolicy',
          'Bypass', '-Command', script],
        runInShell: false,
        stdoutEncoding: utf8,
        stderrEncoding: utf8,
      ).timeout(const Duration(seconds: 15));
      if (result.exitCode != 0) {
        return {'available': false, 'exitCode': result.exitCode};
      }
      final output = result.stdout.toString().trim();
      if (output.isEmpty || output.length > 200000) {
        return {'available': false, 'reason': 'invalid-response-size'};
      }
      final decoded = jsonDecode(output);
      if (decoded is! Map) {
        return {'available': false, 'reason': 'invalid-response'};
      }
      return Map<String, Object?>.from(decoded);
    } catch (error) {
      return {
        'available': false,
        'error': error.runtimeType.toString(),
      };
    }
  }
}
