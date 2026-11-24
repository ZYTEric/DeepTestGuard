package com.dualos.deeptestguard;

import de.robv.android.xposed.IXposedHookLoadPackage;
import de.robv.android.xposed.XC_MethodHook;
import de.robv.android.xposed.XposedBridge;
import de.robv.android.xposed.XposedHelpers;
import de.robv.android.xposed.callbacks.XC_LoadPackage;

/**
 * Keep the OnePlus "深度测试" app seeing the real bootloader state.
 *
 * Play Integrity tooling (tricky_store / AlwaysStrong) resetprops
 * ro.boot.flash.locked to "1" so attestation looks like a locked device.
 * That also makes the official deep-test app show "未解锁" and a re-lock
 * countdown. This hook only changes the result for the deep-test caller,
 * leaving every other process with the spoofed value.
 */
public class MainHook implements IXposedHookLoadPackage {

    private static final String TARGET_PKG = "com.coloros.deeptesting";
    private static final int FALLBACK_UID = 10291;

    @Override
    public void handleLoadPackage(XC_LoadPackage.LoadPackageParam lpparam) throws Throwable {
        if (!"android".equals(lpparam.packageName)) return;

        Class<?> stub;
        try {
            stub = XposedHelpers.findClass(
                    "com.android.server.pdb.PersistentDataBlockService$1",
                    lpparam.classLoader);
        } catch (Throwable t) {
            XposedBridge.log("DeepTestGuard: PersistentDataBlockService$1 not found: " + t);
            return;
        }

        XposedBridge.hookAllMethods(stub, "getFlashLockState", new XC_MethodHook() {
            @Override
            protected void afterHookedMethod(MethodHookParam param) {
                try {
                    if (!isTargetCaller()) return;
                    Object r = param.getResult();
                    if (r instanceof Integer && ((Integer) r).intValue() != 0) {
                        param.setResult(Integer.valueOf(0));
                        XposedBridge.log("DeepTestGuard: getFlashLockState -> 0 for deep test");
                    }
                } catch (Throwable ignored) {
                }
            }
        });

        XposedBridge.log("DeepTestGuard: hooked getFlashLockState in system_server");
    }

    /** True when the binder caller is the deep-test app. */
    private static boolean isTargetCaller() {
        try {
            Class<?> binder = Class.forName("android.os.Binder");
            int uid = ((Integer) binder.getMethod("getCallingUid").invoke(null)).intValue();
            if (uid <= 0) return false;

            Class<?> ag = Class.forName("android.app.AppGlobals");
            Object pm = ag.getMethod("getPackageManager").invoke(null);
            if (pm == null) return uid == FALLBACK_UID;

            Class<?> ipm = Class.forName("android.content.pm.IPackageManager");
            String[] pkgs = (String[]) ipm.getMethod("getPackagesForUid", int.class)
                    .invoke(pm, Integer.valueOf(uid));
            if (pkgs != null) {
                for (String p : pkgs) {
                    if (TARGET_PKG.equals(p)) return true;
                }
                return false;
            }
            return uid == FALLBACK_UID;
        } catch (Throwable t) {
            return false;
        }
    }
}
