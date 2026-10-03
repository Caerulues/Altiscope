# Altiscope 记录格式 v1

## 状态与兼容性

**2026-10-02 实现** 。新记录采用 `altiscope.track` / `schemaVersion: 1`。旧的毫秒日期 JSON 和 `metadata` / `point` / `motion` 事件 JSONL 仍能读取。未知版本、单位和参考系会报错，不尝试猜测转换。

旧日志第一次需要更新时，先留下 `.legacy-backup` 再写入新结构。外部导入不修改源文件，始终创建新本地 UUID；原 ID、导入内容 SHA-256 和原会话状态保存在 `provenance`。导入的 `recording` 状态不会启动录制。取消预览不写盘，多轨迹提交失败会回滚此次新文件。

## 文件组织

| 格式 | 结构 | 用途 |
|---|---|---|
| JSONL | 元数据首行，其后每行一个 `sample`，UTF-8 / LF | 本地持续记录，逐条同步落盘 |
| JSON | 单个根对象，`metadata` 和 `samples` | 完整导出与导入 |
| GPX 1.1 | 标准轨迹点＋`urn:altiscope:track:1` 扩展 | 通用轨迹显示和本应用完整往返 |

元数据首部通过同目录临时文件、同步写盘、原子替换更新。复制后续采样使用分块读写，不原地覆盖变长名称和笔记。中间损坏不跳过；只恢复未换行且 JSON 语法不完整的最后一行，提供行号，本地恢复先备份原文件。外部文件恢复只发生在内存预览中。

## 元数据

`recordType`, `format`, `schemaVersion`, `sessionId`, `travelMode`, `name`, `notes`, `coordinateReference`, `vectorFrame`, `altitudeReference`, `units`, `startedAt`, `endedAt`, `state`, `activeSeconds`, `intervalStartedAt`, `segmentId`, `distanceM`, `isDemo`, `provenance`, `legacyMotion`。

- **参考系** ：原始位置 WGS84；导航向量 ENU（east、north、up）。来源未声明的普通 GPX 高度为 `unknown`，本机 Core Location 高度为 `MSL`。
- **单位** ：高度 m、速度 m/s、加速度 m/s²、角度 deg。显示切换不写回数据。
- **未知时间** ：外部文件确无时间时，`timestamp`、起止时刻或 `activeSeconds` 保留 `null`。界面显示未知；没有时间的点不加入时间曲线；未知时长不计入累计时长。
- **旧运动采样** ：无法与新采样绑定的旧数据完整保存在 `legacyMotion`，不会因迁移丢弃。
- **距离** ：`distanceM` 和采样的 `cumulativeDistanceM` 是持久化检查点。迁移、修改类型不重新计算历史距离。常规录制沿用原定位距离过滤；实验模式统计可显示的估计路径，界面和导出明确来源。

## 逐时刻采样

每条采样有 `recordType: "sample"`、递增 `sequence`、非递减 `segmentId`、UTC 毫秒 `timestamp` 和 UUID `id`。必备可选测量编码为显式 `null`。

| 对象 | 字段 | 含义 |
|---|---|---|
| inertial | coordinate, speedMps, velocityENU, accelerationENU, altitudeM | 有界预测及定位校正后的导航状态 |
| inertial | bearingDeg, bearingSource, bearingReference | 水平前进方向；previous_velocity 优先，compass 后备；真北/磁北分开 |
| inertial | status, lastCorrectionAt, predictionAgeSeconds, horizontalUncertaintyM | uninitialized / corrected / predicted / invalid；不把未知误差写成零 |
| gps | coordinate, speedMps, altitudeM, observedAt | 独立定位观测及其自身时刻；最多关联到后续 2 秒采样 |
| gps | horizontalAccuracyM, verticalAccuracyM, source, courseDeg | 定位质量与来源；core_location 不是独立原始卫星解算声明 |
| gps | deviceHeadingDeg, deviceHeadingReference, usableForRoute | 保留手机朝向；被质量过滤拒绝的观测仍保存，不能用于回放连线 |
| sample | rawMotion, rawLocations, cumulativeDistanceM | 此批原始运动回调、所有定位回调与累计距离检查点 |

运动回调目标 **20 Hz** ，导航采样/落盘目标 **1 Hz** ，定位校正检查目标 **5 秒** 。原始运动数据保存设备轴去重力加速度、单调时间、Core Motion reference-to-device 行主序旋转矩阵、角速度和姿态参考系；批次中的每个运动样本保留自己的时间。系统实际调度可能延迟或停止，不承诺固定后台频率。

暂停、运动中断和预测失效后不能继续积分。地图与统计不跨无坐标采样、暂停和缺失数据连线。地图灰色表示高度未知，虚线表示使用惯导估计。

## GPX 扩展

标准 `trk/name`、`trk/desc`、`trk/type` 对应名称、笔记和记录类型。`trk/extensions` 必须位于 `trkseg` 之前：

- `alt:metadata` 对应完整元数据。
- `alt:unpositionedSamples/alt:sample` 保存没有可用显示坐标的完整采样。
- `trkseg/trkpt/extensions/alt:sample` 保存有坐标的完整采样。
- `alt:positionSource` 明确标准轨迹点来自 `inertial` 或 `observation`。

扩展字段按 JSON 树一一映射：对象 `type="object"`，数组 `type="array"` / `alt:item`，标量为 `string` / `number` / `boolean`，未知值 `missing="true"`。单位、空值、原始采样、分段和顺序都可还原。标准 GPX 的坐标、高度、时间、名称、笔记、类型必须与扩展匹配，否则导入报错。

普通 GPX 仅使用文件中存在的值，位置来源标为 `external_gpx_unknown`；所有惯导字段未知，不将外部路径冒充惯导结果。支持多个 `trk` 及 `rte`，分别预览。独立航点、非 1.1 版本、非法数值/时间不导入。XML 禁止 DTD、实体和网络解析。

**资源边界** ：导入上限 64 MiB、200,000 个导航采样；XML 深度 32、节点 2,000,000；解析任务可取消。仍需用真实长记录评估内存和主线程保存延迟，不能把资源上限当作性能保证。

## 样例与验证

`Formats/synthetic-track.json`、`.jsonl`、`.gpx` 均为虚构样例。它们包括独立观测时间、GPS 缺失、无坐标及无时间采样。生成并执行往返检查：

```sh
swiftc Sources/AltiscopeCore/*.swift Scripts/format_fixtures.swift -o /tmp/altiscope-format-fixtures
/tmp/altiscope-format-fixtures
swift test
```

GPX 通过 Topografix 官方 GPX 1.1 XSD 校验；扩展语义由核心解析器及往返测试校验。第三方软件可能丢弃扩展，本应用不承诺第三方转存无损。

（来源：实现 `TrackDocument.swift`、`TrackImport.swift`、`TrackStore.swift`；[RFC 8259](https://www.rfc-editor.org/rfc/rfc8259)、[RFC 3339](https://www.rfc-editor.org/rfc/rfc3339)、[GPX 1.1 Schema](https://www.topografix.com/GPX/1/1/)、[Apple CLLocation.altitude](https://developer.apple.com/documentation/corelocation/cllocation/altitude)。）
