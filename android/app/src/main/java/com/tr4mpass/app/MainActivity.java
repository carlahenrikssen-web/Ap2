package com.tr4mpass.app;

import android.app.Activity;
import android.graphics.Typeface;
import android.os.Bundle;
import android.widget.Button;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;
import java.io.BufferedReader;
import java.io.InputStreamReader;

public class MainActivity extends Activity {
    private TextView out;

    @Override public void onCreate(Bundle b) {
        super.onCreate(b);
        LinearLayout l = new LinearLayout(this);
        l.setOrientation(LinearLayout.VERTICAL);
        int p = (int)(12 * getResources().getDisplayMetrics().density);
        l.setPadding(p, p, p, p);
        Button btn = new Button(this);
        btn.setText("Run tr4mpass");
        out = new TextView(this);
        out.setTypeface(Typeface.MONOSPACE);
        out.setTextIsSelectable(true);
        out.setText("Tap the button. Output appears here.\n");
        btn.setOnClickListener(v -> run());
        ScrollView sv = new ScrollView(this);
        l.addView(btn); l.addView(sv); sv.addView(out);
        setContentView(l);
    }

    private void run() {
        out.setText("Running as root...\n");
        new Thread(() -> {
            String r;
            try {
                String bin = getApplicationInfo().nativeLibraryDir + "/libtr4mpass.so";
                Process pr = new ProcessBuilder("su", "-c", bin + " --help")
                        .redirectErrorStream(true).start();
                BufferedReader br = new BufferedReader(new InputStreamReader(pr.getInputStream()));
                StringBuilder sb = new StringBuilder();
                String ln;
                while ((ln = br.readLine()) != null) sb.append(ln).append('\n');
                pr.waitFor();
                r = sb.toString();
            } catch (Exception e) { r = "ERROR: " + e; }
            final String f = r;
            runOnUiThread(() -> out.setText(f));
        }).start();
    }
}
