# DeepTest Guard

**EN** — An Xposed/LSPosed module that keeps the OnePlus/OPPO *深度测试* (Deep Testing) app showing the
**real** bootloader unlock state, while Play Integrity spoofing modules keep faking a locked device.

**中文** — 一个 Xposed/LSPosed 模块：让一加/OPPO「深度测试」App 看到**真实的** Bootloader 解锁状态，
同时不影响 tricky_store / AlwaysStrong 等 Play Integrity 伪装模块。

---

## 背景 / Background

The Deep Testing app decides between “已解锁 / 未解锁” with exactly one value:

```java
// com.coloros.deeptesting.utils.r#d(Context)
((PersistentDataBlockManager) ctx.getSystemService("persistent_data_block"))
        .getFlashLockState();          // 0 = unlocked, 1 = locked
```

which `com.android.server.pdb.PersistentDataBlockService$1` derives from `ro.boot.flash.locked`.

Play Integrity “STRONG” checks want the opposite value, so modules such as **tricky_store (AlwaysStrong)**
do this at boot:

```sh
resetprop_if_diff ro.boot.flash.locked 1
resetprop_if_diff ro.boot.verifiedbootstate green
```

`resetprop` rewrites `/dev/__properties__` directly, so **both Java and native readers** see `1` —
every global workaround (disabling LuckyTool's “disable dm-verity verification”, APatch's exclude-modifications,
etc.) cannot satisfy both consumers at once:

| Consumer | Wants `ro.boot.flash.locked` |
|---|---|
| Play Integrity (`com.android.vending`, `com.google.android.gms`, …) | `1` |
| Deep Testing app | `0` |

## 工作原理 / How it works

The module hooks the *server side* of the binder call inside `system_server`
and only rewrites the result for the Deep Testing caller:

```
com.coloros.deeptesting ──binder──▶ PersistentDataBlockService$1.getFlashLockState()
                                     │
              afterHookedMethod ─────┤ Binder.getCallingUid() → package of caller?
                                     │   ├─ com.coloros.deeptesting → return 0
                                     │   └─ anything else         → return original (1)
```

Caller detection uses `AppGlobals.getPackageManager().getPackagesForUid(uid)`, with a hard-coded
UID fallback (`10291`) if the reflective lookup fails.

## 环境要求 / Requirements

- Android 12–15 (developed and verified on **ColorOS 17.0.1.200, OnePlus Pad 3 Pro / OPPO pad, Android 15**)
- LSPosed (or any Xposed framework exposing the legacy API, `xposedminversion=82`)
- Root manager: APatch / KernelSU / Magisk — anything that can load LSPosed

## 构建 / Build

Requires JDK 17, Android build-tools 34 and `android.jar` (platform-34). Everything is offline, no Gradle.

```powershell
powershell -ExecutionPolicy Bypass -File .\build.ps1 `
  -Bt  "C:\path\to\build-tools\34.0.0" `
  -Jar "C:\path\to\platforms\android-34\android.jar"
```

Convention used by the script:

- `javac` compiles `src/**` against `android.jar` (`-source 8 -target 8`).
- `d8` converts **every** class under `com/dualos/deeptestguard/` — the anonymous inner class
  `MainHook$1` must be included, otherwise LSPosed throws `ClassNotFoundException` at boot.
- `de/robv/android/xposed/**` are compile-only stubs and are **not** put into `classes.dex`;
  the real implementation is provided by the framework at runtime.
- `aapt2 link` → inject `classes.dex` → `zipalign` → `apksigner`.

The output is `DeepTestGuard.apk`.

> Keep `build.ps1` ASCII-only: Windows PowerShell 5.1 decodes non-ASCII scripts as ANSI and fails to parse.

## 安装 / Install

1. Install the APK. On ColorOS the normal `adb install` may hang on the OPPO package-installer dialog;
   installing through root skips it:
   ```sh
   adb push DeepTestGuard.apk /data/local/tmp/
   adb shell su -c 'pm install -r -t /data/local/tmp/DeepTestGuard.apk'
   ```
2. Enable **DeepTest Guard** in LSPosed and set its scope to **System Framework** only.
3. Reboot. The hook lives in `system_server`, so a full reboot is required.

### 验证 / Verify

```sh
# must stay 1 / green: the spoof is still in place for everyone else
adb shell getprop ro.boot.flash.locked
adb shell su -c 'dumpsys persistent_data_block | grep -E "Bootloader|Verified"'

# LSPosed log should contain:
#   DeepTestGuard: hooked getFlashLockState in system_server
```

Then open the Deep Testing app — it must show **已解锁** while the values above still read `1` / `green`.

## 已知限制 / Caveats

- Hook target is `com.android.server.pdb.PersistentDataBlockService$1`. If a ROM build moves or renames it,
  the module logs `PersistentDataBlockService$1 not found` and silently does nothing.
- Only the Deep Testing package is special-cased (`com.coloros.deeptesting`, UID fallback `10291`).
  Other OEM variants may use a different package name — edit `TARGET_PKG` and rebuild.
- The module does not weaken Play Integrity by itself: it only affects the Deep Testing caller.

## 许可证 / License

[Apache-2.0](LICENSE)
