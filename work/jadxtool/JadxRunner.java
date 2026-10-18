import jadx.api.JadxArgs;
import jadx.api.JadxDecompiler;
import jadx.api.JavaClass;
import java.io.File;
import java.util.ArrayList;
import java.util.List;
import java.util.regex.Pattern;

/**
 * usage: JadxRunner <input dex/apk/jar> <outDir> [nameFilterRegex] [--list]
 */
public class JadxRunner {
    public static void main(String[] argv) throws Exception {
        File in = new File(argv[0]);
        File out = new File(argv[1]);
        String filter = argv.length > 2 ? argv[2] : null;
        boolean listOnly = false;
        for (String a : argv) {
            if (a.equals("--list")) listOnly = true;
        }

        JadxArgs args = new JadxArgs();
        args.setInputFile(in);
        args.setOutDir(out);
        args.setSkipResources(true);
        args.setShowInconsistentCode(true);
        args.setThreadsCount(Runtime.getRuntime().availableProcessors());
        args.setDecompilationMode(jadx.api.DecompilationMode.FALLBACK);

        JadxDecompiler jadx = new JadxDecompiler(args);
        jadx.load();
        List<JavaClass> classes = jadx.getClassesWithInners();

        Pattern p = filter == null ? null : Pattern.compile(filter);
        List<JavaClass> sel = new ArrayList<>();
        for (JavaClass c : classes) {
            if (p == null || p.matcher(c.getFullName()).find()) sel.add(c);
        }
        System.err.println("total classes=" + classes.size() + " selected=" + sel.size());

        if (listOnly) {
            for (JavaClass c : sel) System.out.println(c.getFullName());
            jadx.close();
            return;
        }

        int n = 0;
        for (JavaClass c : sel) {
            try {
                String code = c.getCode();
                if (code == null) continue;
                String fn = c.getFullName().replace('.', '/') + ".java";
                File f = new File(out, fn);
                File parent = f.getParentFile();
                if (parent != null) parent.mkdirs();
                java.nio.file.Files.write(f.toPath(), code.getBytes("UTF-8"));
                n++;
            } catch (Throwable t) {
                System.err.println("fail " + c.getFullName() + " : " + t);
            }
        }
        System.err.println("written=" + n);
        jadx.close();
    }
}
