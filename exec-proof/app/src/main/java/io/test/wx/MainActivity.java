package io.test.wx;

import android.app.Activity;
import android.os.Bundle;
import android.util.Log;
import java.io.File;
import java.io.BufferedReader;
import java.io.InputStreamReader;

/**
 * Minimal harness that answers the one question the SDS treats as load-bearing:
 *
 *   Can an Android app process execve() a binary that shipped as jniLibs/lib*.so
 *   and was extracted to nativeLibraryDir?
 *
 * It runs FOUR experiments and logs the result of each:
 *   T1  exec <nativeLibraryDir>/libprobe.so        (the model the SDS relies on)
 *   T2  exec a copy in filesDir (app-private, writable)  -> expected to FAIL on API 29+
 *   T3  same as T1 but WITHOUT LD_LIBRARY_PATH set      -> does ld resolve DT_NEEDED?
 *   T4  canExecute() check + setExecutable fallback
 */
public class MainActivity extends Activity {

    private static final String TAG = "WXTEST";

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);

        new Thread(() -> {
            try {
                nativeLibraryDir();
                test1_execFromNativeLibDir();
                test2_execFromFilesDir();
                test3_noLibPath();
                test4_canExecute();
            } catch (Throwable t) {
                Log.e(TAG, "harness crashed", t);
            }
            Log.i(TAG, "=== DONE ===");
        }).start();
    }

    private void nativeLibraryDir() {
        File dir = new File(getApplicationInfo().nativeLibraryDir);
        Log.i(TAG, "nativeLibraryDir = " + dir.getAbsolutePath());
        Log.i(TAG, "  exists = " + dir.exists());
        File[] files = dir.listFiles();
        if (files == null) {
            Log.i(TAG, "  listFiles() = null");
            return;
        }
        for (File f : files) {
            Log.i(TAG, "  entry: " + f.getName() + " size=" + f.length() + " canExec=" + f.canExecute());
        }
    }

    private String[] run(File bin, boolean withLibPath) throws Exception {
        ProcessBuilder pb = new ProcessBuilder(bin.getAbsolutePath(), "arg1", "arg2");
        pb.redirectErrorStream(true);
        if (withLibPath) {
            pb.environment().put("LD_LIBRARY_PATH", new File(getApplicationInfo().nativeLibraryDir).getAbsolutePath());
        }
        pb.environment().put("HOME", getFilesDir().getAbsolutePath());
        Process p = pb.start();
        StringBuilder sb = new StringBuilder();
        try (BufferedReader r = new BufferedReader(new InputStreamReader(p.getInputStream()))) {
            String line;
            while ((line = r.readLine()) != null) sb.append(line).append('\n');
        }
        int code = p.waitFor();
        return new String[] { String.valueOf(code), sb.toString().trim() };
    }

    private void test1_execFromNativeLibDir() {
        File bin = new File(getApplicationInfo().nativeLibraryDir, "libprobe.so");
        try {
            String[] r = run(bin, true);
            Log.i(TAG, "T1 exec from nativeLibraryDir -> exit=" + r[0] + " out=[" + r[1] + "]");
        } catch (Throwable t) {
            Log.e(TAG, "T1 FAILED: " + t.getClass().getSimpleName() + ": " + t.getMessage());
        }
    }

    private void test2_execFromFilesDir() {
        File src = new File(getApplicationInfo().nativeLibraryDir, "libprobe.so");
        File dst = new File(getFilesDir(), "probe_copy");
        try {
            copy(src, dst);
            dst.setExecutable(true, false);
            String[] r = run(dst, true);
            Log.i(TAG, "T2 exec from filesDir -> exit=" + r[0] + " out=[" + r[1] + "]");
        } catch (Throwable t) {
            // This FAILURE is the expected/interesting result on API 29+.
            Log.i(TAG, "T2 exec from filesDir -> BLOCKED: " + t.getClass().getSimpleName() + ": " + t.getMessage());
        }
    }

    private void test3_noLibPath() {
        File bin = new File(getApplicationInfo().nativeLibraryDir, "libprobe.so");
        try {
            String[] r = run(bin, false);
            Log.i(TAG, "T3 exec WITHOUT LD_LIBRARY_PATH -> exit=" + r[0] + " out=[" + r[1] + "]");
        } catch (Throwable t) {
            Log.i(TAG, "T3 exec WITHOUT LD_LIBRARY_PATH -> FAILED: "
                    + t.getClass().getSimpleName() + ": " + t.getMessage());
        }
    }
    private void test4_canExecute() {
        File bin = new File(getApplicationInfo().nativeLibraryDir, "libprobe.so");
        Log.i(TAG, "T4 canExecute() before fix = " + bin.canExecute());
        if (!bin.canExecute()) {
            boolean ok = bin.setExecutable(true, false);
            Log.i(TAG, "T4 setExecutable -> " + ok + ", canExecute now = " + bin.canExecute());
        }
    }

    private void copy(File src, File dst) throws Exception {
        try (java.io.InputStream in = new java.io.FileInputStream(src);
             java.io.OutputStream out = new java.io.FileOutputStream(dst)) {
            byte[] buf = new byte[8192];
            int n;
            while ((n = in.read(buf)) > 0) out.write(buf, 0, n);
        }
    }
}
