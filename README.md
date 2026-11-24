# DeepTest Guard

一个 Xposed / LSPosed 模块：让一加 / OPPO 国行「深度测试」App 看到**真实的** Bootloader 解锁状态，
同时不影响 tricky_store / AlwaysStrong 等 Play Integrity 伪装模块。

---

## 背景

「深度测试」判断"已解锁 / 未解锁"只看一个值：

```java
// com.coloros.deeptesting.utils.r#d(Context)
((PersistentDataBlockManager) ctx.getSystemService("persistent_data_block"))
        .getFlashLockState();          // 0 = 已解锁，1 = 未解锁
```

服务端 `com.android.server.pdb.PersistentDataBlockService$1` 把这个值映射自 `ro.boot.flash.locked`。

而 Play Integrity 的 STRONG 判定要求设备"看起来是锁定的"，于是 **tricky_store（AlwaysStrong）** 会在开机时：

```sh
resetprop_if_diff ro.boot.flash.locked 1
resetprop_if_diff ro.boot.verifiedbootstate green
```

`resetprop` 直接改写 `/dev/__properties__`，**Java 层和 native 层读到的都是 1**。
所以一切全局改法都失效：

| 尝试 | 为什么没用 |
|---|---|
| 关掉 LuckyTool「禁用 dm-verity 校验」 | 那只是 Java 层 hook，管不到 resetprop |
| APatch「排除修改」 | 只对 APatch 自己的模块机制生效，管不到 tricky_store 的 service.sh |
| 卸载 / 禁用 tricky_store | 能恢复显示，但 Play Integrity 伪装同时没了 |

两者诉求正好相反：

| 消费方 | 想要的 `ro.boot.flash.locked` |
|---|---|
| Play Integrity（`com.android.vending`、`com.google.android.gms`、keyattestation …） | `1` |
| 深度测试 App | `0` |

同一个全局属性无法同时满足，所以只能**按调用者分流**。

## 工作原理

模块 hook 的是 `system_server` 里那个 binder 方法的**服务端**，只对被深度测试调用的那一次改返回值：

```
com.coloros.deeptesting ──binder──▶ PersistentDataBlockService$1.getFlashLockState()
                                     │
              afterHookedMethod ─────┤ Binder.getCallingUid() → 调用者是哪个包？
                                     │   ├─ com.coloros.deeptesting → 返回 0
                                     │   └─ 其它任何进程           → 保留原值 1
```

调用者识别用 `AppGlobals.getPackageManager().getPackagesForUid(uid)`；
若反射失败，回退到硬编码 uid `10291`。

## 环境要求

- Android 12–17（实测环境：**ColorOS 17.0.1.200 / 一加平板 3 Pro / Android 15**）
- LSPosed（或任何提供 legacy API 的 Xposed 框架，`xposedminversion=82`）

## 构建

依赖 JDK 17、Android build-tools 34、`android.jar`（platform-34）。不用 Gradle。

```powershell
powershell -ExecutionPolicy Bypass -File .\build.ps1 `
  -Bt  "C:\path\to\build-tools\34.0.0" `
  -Jar "C:\path\to\platforms\android-34\android.jar"
```

脚本做的事：

- `javac` 用 `android.jar` 作 bootclasspath 编译 `src/**`（`-source 8 -target 8`）
- `d8` 必须把 `com/dualos/deeptestguard/` 下**所有** class 都传进去 —— 漏了匿名内部类 `MainHook$1`，
  开机时 LSPosed 会报 `ClassNotFoundException`，hook 静默失败
- `de/robv/android/xposed/**` 只是编译期 stub，**不进 `classes.dex`**，运行时由框架提供真实实现
- `aapt2 link` → 塞入 `classes.dex` → `zipalign` → `apksigner`

产物是 `DeepTestGuard.apk`。

> `build.ps1` 必须保持纯 ASCII：Windows PowerShell 5.1 会按 ANSI 解码非 ASCII 脚本，导致语法错误。

## 安装

1. 安装 APK。
2. 在 LSPosed 里启用 **DeepTest Guard**，作用域**只勾「系统框架」**。
3. 重启整机。hook 在 `system_server` 里，必须整机重启才生效。

### 验证

```sh
# 这两项必须仍是 1 / green，说明对其它进程的伪装完好
adb shell getprop ro.boot.flash.locked
adb shell su -c 'dumpsys persistent_data_block | grep -E "Bootloader|Verified"'

# LSPosed 日志里应出现：
#   DeepTestGuard: hooked getFlashLockState in system_server
```

然后打开「深度测试」：应显示**已解锁**，而上面两项仍是 `1` / `green`。

## 已知限制

- hook 目标是 `com.android.server.pdb.PersistentDataBlockService$1`。如果某个 ROM 把它改名或挪位置，
  模块会打一行 `PersistentDataBlockService$1 not found` 然后什么都不做。
- 只特判了 `com.coloros.deeptesting`（uid 兜底 `10291`）。其它机型若包名不同，改 `TARGET_PKG` 重新编译。
- 模块本身不削弱 Play Integrity：它只影响深度测试这一个调用者。

## 许可证

[Apache-2.0](LICENSE)
