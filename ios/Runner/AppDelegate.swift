import Flutter
import UIKit
import CoreLocation
import ActivityKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  // 后台定位保活：通过持续定位，让 App 在后台保持运行，
  // 从而让签到轮询（Timer）和雨课堂 WebSocket 在后台不被系统冻结。
  private var locationManager: CLLocationManager?
  private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
  private let keepAliveChannel = "com.gongan520.coursehelper/keepalive"
  private let liveActivityChannel = "com.gongan520.coursehelper/liveactivity"

  /// 持有灵动岛通道引用，供「点击灵动岛打开 App」时回调 Flutter。
  private var liveChannelRef: FlutterMethodChannel?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)

    let result = super.application(application, didFinishLaunchingWithOptions: launchOptions)

    // 注册 MethodChannel，接收 Flutter 侧的保活启动指令
    // 在 super 之后注册，确保 rootViewController 已就绪。
    if let controller = self.window?.rootViewController as? FlutterViewController {
      let channel = FlutterMethodChannel(
        name: keepAliveChannel,
        binaryMessenger: controller.binaryMessenger
      )
      channel.setMethodCallHandler { [weak self] (call, result) in
        if call.method == "startBackgroundLocation" {
          self?.startBackgroundLocationKeepAlive()
          result(nil)
        } else {
          result(FlutterMethodNotImplemented)
        }
      }

      // 灵动岛（Live Activity）控制通道
      let laChannel = FlutterMethodChannel(
        name: liveActivityChannel,
        binaryMessenger: controller.binaryMessenger
      )
      laChannel.setMethodCallHandler { [weak self] (call, result) in
        self?.handleLiveActivity(call, result: result)
      }
      liveChannelRef = laChannel
    }

    return result
  }

  /// 点击灵动岛（widgetURL = coursehelper://live）时进入这里。
  override func application(
    _ app: UIApplication,
    open url: URL,
    options: [UIApplication.OpenURLOptionsKey: Any] = [:]
  ) -> Bool {
    if url.scheme == "coursehelper" {
      // 通知 Flutter 侧（UI 已在启动流程中，这里只做事件告知，不做路由跳转，
      // 避免 Flutter 尚未构建完成时导航导致白屏）。
      liveChannelRef?.invokeMethod("openedFromLiveActivity", arguments: [
        "url": url.absoluteString
      ])
      return true
    }
    return super.application(app, open: url, options: options)
  }

  /// 处理灵动岛控制指令。
  private func handleLiveActivity(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard #available(iOS 16.1, *) else {
      result(FlutterError(code: "unsupported", message: "需要 iOS 16.1+", details: nil))
      return
    }

    switch call.method {
    case "start":
      let args = call.arguments as? [String: Any] ?? [:]
      let payload = LiveActivityManager.shared.start(
        statusText: args["statusText"] as? String ?? "蜡笔小新正在守护你的课堂",
        signedAccounts: args["signedAccounts"] as? String ?? "",
        autoCount: args["autoCount"] as? Int ?? 0,
        scheduledCount: args["scheduledCount"] as? Int ?? 0,
        manualCount: args["manualCount"] as? Int ?? 0,
        aiCount: args["aiCount"] as? Int ?? 0,
        mood: args["mood"] as? String ?? "idle",
        signedCount: args["signedCount"] as? Int ?? 0
      )
      result(payload)
    case "update":
      let args = call.arguments as? [String: Any] ?? [:]
      let payload = LiveActivityManager.shared.update(
        statusText: args["statusText"] as? String ?? "蜡笔小新正在守护你的课堂",
        signedAccounts: args["signedAccounts"] as? String ?? "",
        autoCount: args["autoCount"] as? Int ?? 0,
        scheduledCount: args["scheduledCount"] as? Int ?? 0,
        manualCount: args["manualCount"] as? Int ?? 0,
        aiCount: args["aiCount"] as? Int ?? 0,
        mood: args["mood"] as? String ?? "idle",
        signedCount: args["signedCount"] as? Int ?? 0
      )
      result(payload)
    case "stop":
      LiveActivityManager.shared.stop()
      result(nil)
    case "status":
      result(LiveActivityManager.shared.statusPayload())
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  /// 启动后台定位保活（由 Flutter 侧通过 MethodChannel 调用）。
  private func startBackgroundLocationKeepAlive() {
    if locationManager == nil {
      locationManager = CLLocationManager()
      locationManager?.delegate = self
      // 后台定位更新：这是 iOS 允许 App 在后台持续运行的关键开关。
      locationManager?.allowsBackgroundLocationUpdates = true
      locationManager?.pausesLocationUpdatesAutomatically = false
      locationManager?.desiredAccuracy = kCLLocationAccuracyHundredMeters
      locationManager?.distanceFilter = kCLDistanceFilterNone
    }
    // 请求"始终允许"定位权限（后台定位必须）。
    locationManager?.requestAlwaysAuthorization()
    locationManager?.startUpdatingLocation()
  }

  override func applicationDidEnterBackground(_ application: UIApplication) {
    // 进入后台时，开启一个后台任务，给签到轮询争取额外执行时间，
    // 并确保后台定位持续运行。
    backgroundTask = application.beginBackgroundTask(withName: "KeepAlive") { [weak self] in
      self?.endBackgroundTask()
    }
    locationManager?.startUpdatingLocation()
  }

  override func applicationWillEnterForeground(_ application: UIApplication) {
    endBackgroundTask()
  }

  private func endBackgroundTask() {
    if backgroundTask != .invalid {
      UIApplication.shared.endBackgroundTask(backgroundTask)
      backgroundTask = .invalid
    }
  }
}

extension AppDelegate: CLLocationManagerDelegate {
  func locationManager(_ manager: CLLocationManager,
                       didChangeAuthorization status: CLAuthorizationStatus) {
    // 权限变为"始终允许"后，确保开始后台定位。
    if status == .authorizedAlways || status == .authorizedWhenInUse {
      manager.allowsBackgroundLocationUpdates = true
      manager.startUpdatingLocation()
    }
  }

  func locationManager(_ manager: CLLocationManager,
                       didUpdateLocations locations: [CLLocation]) {
    // 持续定位回调，保持后台存活（无需处理坐标）。
  }

  func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
    // 定位失败不影响签到主流程。
  }
}
