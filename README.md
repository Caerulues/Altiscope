<img src="App/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png" width="160" alt="Altiscope app icon" align="right" />

# Altiscope

A local-first journey recorder for iPhone and iPad. Your journey, recorded.

## 功能

- **旅程记录** ：步行、骑行、驾车、飞行；开始、暂停、继续、结束；本地存储，无需账号。
- **地图** ：Apple MapKit 与离线画布。进入实时页面即可请求当前位置；预览不创建日志。手动浏览退出跟随，定位按钮恢复跟随，保存后显示全览。
- **界面** ：iPhone 可折叠信息面板；iPad 仅显示图标的窄侧栏、悬停名称提示与可折叠移动浮窗；顶部实际应用图标、当地时间/UTC 切换。
- **三维轨迹** ：按真实记录高度绘制主线和半透明幕帘，零平面固定为 0 m；支持点选高度、与图表共享单位，未知高度/暂停处断开。相机不能可靠对齐时回退二维；系统全览限制倾角时，进入三维自动查看局部航段。详见[三维实现与验证](Documentation/THREE-D-ROUTE.md)及[真实航线修正记录](Documentation/THREE-D-REAL-FLIGHT-2026-10-03.md)。
- **回看** ：按海拔着色、海拔与地速共享 UTC 时间轴的双轴图、在设置页切换公制 m / km/h 与航空 ft / kts，选择自动保存。
- **日志管理** ：名称/笔记搜索、日志内修改名称/类型/笔记、删除确认；GPX / JSON / JSONL 导入预览、重复检测、多个轨迹分别导入。
- **格式** ：版本化 JSONL 元数据首行和逐时刻采样；JSON 与 GPX 保留惯导、定位观测、原始运动、空值和分段。旧格式兼容读取，迁移前备份。
- **实验惯导** ：默认关闭，在设置中为下一段旅程启用。20 Hz 运动预测、约 5 秒检查新定位；保留独立来源与误差状态。纯软件回放已经测试，未完成真机标定。

## 构建

需要 Xcode；应用最低 iOS / iPadOS 17.6，核心包支持 macOS 13 / iOS 17。此次验证使用 Xcode 26.3。

```sh
python3 Scripts/generate_project.py
swift test
xcodebuild -project Altiscope.xcodeproj -scheme Altiscope \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO build
```

打开 `Altiscope.xcodeproj` 运行应用；模拟器构建无需个人签名团队。真机安装时，复制 `Config/Secrets.example.xcconfig` 为 `Config/Secrets.xcconfig` 并填写自己的 `DEVELOPMENT_TEAM`；这个本地文件被 Git 忽略，现有签名设置保留在其中。

## 记录与验证边界

**原始数据使用 WGS 84** 。MapKit 使用系统定义的坐标输入，没有未经测量的附加偏移。大陆偏移反馈仍需在实机对比系统位置标记与已知参考点，不能凭底图提供方推断转换需求。（[Apple CLLocationCoordinate2D](https://developer.apple.com/documentation/corelocation/cllocationcoordinate2d)。）

显示转换组件等价移植 **wandergis/coordtransform 2.1.2** 的 WGS84 / GCJ02 函数，固定 commit `606c6f3b57b6f1d60458793fea39928d2b11b637`。参考系标签防止二次转换；适用区域必须由已核实的区域信息明确指定，港澳台、境外及边界不明时不转换。当前 MapKit 路径要求 WGS84，因此没有启用 GCJ02 转换；矩形判断不充当大陆地理边界。详见实施记录。

**惯导仍为实验功能** 。当前预测时长、误差阈值和偏置约束是原型设计值，不能视为设备校准结果；运动中断或状态失效保留缺口。没有完成真实携带姿态、城市/隧道、飞行、长时间后台和能耗验收。应用不能用作航空导航或测绘仪器。

- [2026-10-02 实施与验证记录](Documentation/IMPLEMENTATION-2026-10-02.md)
- [文件格式、迁移及 GPX 扩展规范](Documentation/TRACK-FORMAT.md)
- [此前的历史验收记录](Documentation/VALIDATION.md)（旧版功能和结果，不代表当前版本）

## LICENSE

[MIT License](LICENSE) © 2026 Caeruvis

设计参考 Volanta 的地图、日志和统计布局。

坐标转换部分源自 [wandergis/coordtransform](https://github.com/wandergis/coordtransform/tree/606c6f3b57b6f1d60458793fea39928d2b11b637)，© 2015 记忆的残骸，遵循 [MIT 许可](App/Resources/CoordTransform-LICENSE.txt)。版权与授权文本随应用资源打包。
